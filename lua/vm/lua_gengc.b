# Lua VM - Generational Garbage Collector
# Implements Lua 5.4 generational GC with young/old generations

implement Luavm;

include "sys.m";
include "luavm.m";

sys: Sys;
print, sprint, fprint: import sys;

# ====================================================================
# Generational GC Types
# ====================================================================

# Generation types
YOUNG_GEN:	con 0;	# Young generation (newly created)
OLD_GEN:		con 1;	# Old generation (survived collections)
TENURED_GEN:	con 2;	# Tenured generation (very old)

# Remember set for old-to-young pointers
RememberSet: adt {
	nodes:	list of ref RememberEntry;	# Remembered pointers
	count:	int;						# Number of entries
};

# Remember entry (old object pointing to young object)
RememberEntry: adt {
	oldobj:	ref GCheader;	# Old object
	key:	ref Value;		# Key (if table entry)
	val:	ref Value;		# Value (if table entry)
	next:	ref RememberEntry;	# Next entry
};

# Generational GC state
GGC: adt {
	young:			ref GCheader;	# Young generation list
	old:			ref GCheader;	# Old generation list
	tenured:		ref GCheader;	# Tenured list
	remember:		ref RememberSet;	# Remember set
	majorgc:		big;			# Bytes allocated since last major GC
	minorgc:		big;			# Bytes allocated since last minor GC
	youngsize:		big;			# Size of young generation
	oldsize:		big;			# Size of old generation
	lastmajor:		big;			# Timestamp of last major GC
	lastminor:		big;			# Timestamp of last minor GC
	minorgcmul:		int;			# Minor GC multiplier
	majorgcmul:		int;			# Major GC multiplier
};

# ====================================================================
# Allocation and Generations
# ====================================================================

# Allocate object in young generation
allocyoung(ggc: ref GGC, size: int, type: int): ref GCheader
{
	if(ggc == nil)
		return nil;

	# Create object
	obj := ref GCheader;
	obj.marked = WHITE0;  # Start white
	obj.tt = type;
	obj.next = ggc.young;
	obj.refcount = 1;

	# Add to young generation
	ggc.young = obj;

	# Track allocation
	ggc.minorgc += big(size);
	ggc.majorgc += big(size);
	ggc.youngsize += big(size);

	return obj;
}

# Promote object from young to old generation
promote(ggc: ref GGC, obj: ref GCheader)
{
	if(ggc == nil || obj == nil)
		return;

	# Check if already old
	if(objgeneration(ggc, obj) != YOUNG_GEN)
		return;

	# Remove from young list
	removefromlist(ggc.young, obj);

	# Add to old list
	obj.next = ggc.old;
	ggc.old = obj;

	# Adjust sizes
	sz := getobjsize(obj);
	ggc.youngsize -= sz;
	ggc.oldsize += sz;
}

# Get object generation
objgeneration(ggc: ref GGC, obj: ref GCheader): int
{
	if(ggc == nil || obj == nil)
		return YOUNG_GEN;

	# Check which list it's in
	list := ggc.young;
	while(list != nil) {
		if(list == obj)
			return YOUNG_GEN;
		list = list.next;
	}

	list = ggc.old;
	while(list != nil) {
		if(list == obj)
			return OLD_GEN;
		list = list.next;
	}

	return TENURED_GEN;  # Not found - assume tenured
}

# Get object size (estimate)
getobjsize(obj: ref GCheader): big
{
	if(obj == nil)
		return 0big;

	case(obj.tt) {
	TSTRING =>	return 32big;
	TTABLE =>	return 64big;
	TFUNCTION =>	return 48big;
	TUSERDATA =>	return 32big;
	TTHREAD =>	return 128big;
	TPROTO =>	return 64big;
	* =>		return 0big;
	}
}

# Remove from list
removefromlist(list: ref GCheader, obj: ref GCheader)
{
	if(list == nil || obj == nil)
		return;

	prev := ref GCheader;
	curr := list;

	while(curr != nil) {
		if(curr == obj) {
			# Found it, remove
			if(prev != nil)
				prev.next = curr.next;
			else
				list = curr.next;
			return;
		}
		prev = curr;
		curr = curr.next;
	}
}

# ====================================================================
# Remember Set (Write Barrier)
# ====================================================================

# Add to remember set (old object has new reference to young object)
remember(ggc: ref GGC, oldobj: ref GCheader, key, val: ref Value)
{
	if(ggc == nil || oldobj == nil)
		return;

	# Check if old object is actually old
	if(objgeneration(ggc, oldobj) == YOUNG_GEN)
		return;  # Not old, no need to remember

	# Create remember entry
	entry := ref RememberEntry;
	entry.oldobj = oldobj;
	entry.key = key;
	entry.val = val;
	entry.next = nil;

	# Add to remember set
	if(ggc.remember == nil) {
		ggc.remember = ref RememberSet;
		ggc.remember.nodes = list of {entry};
		ggc.remember.count = 1;
	} else {
		entry.next = hd ggc.remember.nodes;
		ggc.remember.nodes = list of {entry} + ggc.remember.nodes;
		ggc.remember.count++;
	}

	# Limit remember set size
	if(ggc.remember.count > 10000) {
		triggermajor(ggc);
	}
}

# Clear remember set
clearremember(ggc: ref GGC)
{
	if(ggc == nil)
		return;

	if(ggc.remember != nil) {
		ggc.remember.nodes = nil;
		ggc.remember.count = 0;
	}
}

# ====================================================================
# Minor Collection (Young Generation)
# ====================================================================

# Perform minor GC (collect young only)
minorgc(ggc: ref GGC, L: ref State): big
{
	if(ggc == nil)
		return 0big;

	before := ggc.youngsize;

	# Mark roots
	markyoungroots(ggc, L);

	# Propagate within young generation
	propagateyoung(ggc);

	# Sweep young generation
	sweepyoung(ggc);

	# Promote survivors to old
	promotesurvivors(ggc);

	# Process remember set
	processremember(ggc);

	# Reset counters
	ggc.minorgc = 0big;

	after := ggc.youngsize;
	return before - after;
}

# Mark young generation roots
markyoungroots(ggc: ref GGC, L: ref State)
{
	if(ggc == nil || L == nil)
		return;

	# Mark stack values (pointing to young)
	if(L.stack != nil) {
		for(i := 0; i < L.top; i++) {
			v := L.stack[i];
			if(isyoung(ggc, v))
				markyoung(ggc, v);
		}
	}

	# Mark global table
	if(L.global != nil && isyoungobj(ggc, L.global))
		markyoungtable(ggc, L.global);

	# Mark registry
	if(L.registry != nil && isyoungobj(ggc, L.registry))
		markyoungtable(ggc, L.registry);
}

# Propagate marks in young generation
propagateyoung(ggc: ref GGC)
{
	if(ggc == nil)
		return;

	# Process gray objects
	gray := ref GCheader;

	# Collect all gray objects in young generation
	obj := ggc.young;
	while(obj != nil) {
		if(obj.marked == GRAY) {
			obj.next = gray;
			gray = obj;
		}
		obj = obj.next;
	}

	# Propagate
	while(gray != nil) {
		nextobj := gray.next;

		# Mark children
		markchildrenyoung(ggc, gray);

		# Mark as black
		gray.marked = BLACK;

		gray = nextobj;
	}
}

# Mark object as gray (young generation)
markyoung(ggc: ref GGC, v: ref Value)
{
	if(v == nil || ggc == nil)
		return;

	case(v.ty) {
	TTABLE =>
		if(v.t != nil && isyoungobj(ggc, v.t))
			markyoungtable(ggc, v.t);
	TFUNCTION =>
		if(v.f != nil && isyoungobj(ggc, v.f))
			markyoungfunction(ggc, v.f);
	TUSERDATA =>
		if(v.u != nil && isyoungobj(ggc, v.u))
			markyounguserdata(ggc, v.u);
	}
}

# Check if value is in young generation
isyoung(ggc: ref GGC, v: ref Value): int
{
	if(v == nil || ggc == nil)
		return 0;

	case(v.ty) {
	TTABLE =>	return isyoungobj(ggc, v.t);
	TFUNCTION =>	return isyoungobj(ggc, v.f);
	TUSERDATA =>	return isyoungobj(ggc, v.u);
	TTHREAD =>	return isyoungobj(ggc, v.th);
	* =>		return 0;
	}
}

# Check if object is in young generation
isyoungobj(ggc: ref GGC, obj: ref GCheader): int
{
	if(obj == nil || ggc == nil)
		return 0;

	list := ggc.young;
	while(list != nil) {
		if(list == obj)
			return 1;
		list = list.next;
	}
	return 0;
}

# Mark children in young generation
markchildrenyoung(ggc: ref GGC, obj: ref GCheader)
{
	if(obj == nil)
		return;

	case(obj.tt) {
	TTABLE =>
		t := ref Table(obj - 4);
		if(t != nil) {
			# Mark array part
			if(t.arr != nil) {
				for(i := 0; i < t.sizearray; i++) {
					if(isyoung(ggc, t.arr[i])) {
						# Mark young, remember if in old
						markyoung(ggc, t.arr[i]);
					}
				}
			}
		}
	}
}

# Sweep young generation
sweepyoung(ggc: ref GGC)
{
	if(ggc == nil)
		return;

	prev := ref GCheader;
	obj := ggc.young;

	while(obj != nil) {
		nextobj := obj.next;

		if(obj.marked == WHITE0 || obj.marked == WHITE1) {
			# Dead object - free it
			freeyoungobj(ggc, obj);

			# Unlink
			if(prev != nil)
				prev.next = nextobj;
			else
				ggc.young = nextobj;
		} else {
			# Survived - will be promoted
			obj.marked = WHITE0;  # Reset to white
			prev = obj;
		}

		obj = nextobj;
	}
}

# Free young object
freeyoungobj(ggc: ref GGC, obj: ref GCheader)
{
	if(obj == nil || ggc == nil)
		return;

	sz := getobjsize(obj);
	ggc.youngsize -= sz;
	ggc.totalbytes -= sz;
}

# Promote survivors to old generation
promotesurvivors(ggc: ref GGC)
{
	if(ggc == nil)
		return;

	obj := ggc.young;
	while(obj != nil) {
		nextobj := obj.next;

		# Promote if survived
		if(obj.marked != WHITE0 && obj.marked != WHITE1) {
			promote(ggc, obj);
		}

		obj = nextobj;
	}
}

# ====================================================================
# Major Collection
# ====================================================================

# Perform major GC (full collection)
majorgc(ggc: ref GGC, L: ref State): big
{
	if(ggc == nil)
		return 0big;

	before := ggc.youngsize + ggc.oldsize;

	# Mark all objects from roots
	markallroots(ggc, L);

	# Propagate marks
	propagateall(ggc);

	# Sweep all generations
	sweeppromote(ggc);

	# Clear remember set
	clearremember(ggc);

	# Reset counter
	ggc.majorgc = 0big;

	after := ggc.youngsize + ggc.oldsize;
	return before - after;
}

# Mark all roots (all generations)
markallroots(ggc: ref GGC, L: ref State)
{
	if(ggc == nil || L == nil)
		return;

	# Mark stack
	if(L.stack != nil) {
		for(i := 0; i < L.top; i++) {
			markvalueall(ggc, L.stack[i]);
		}
	}

	# Mark globals and registry
	markvalueall(ggc, mktable(L.global));
	markvalueall(ggc, mktable(L.registry));

	# Mark remember set
	markrememberset(ggc);
}

# Mark value (all generations)
markvalueall(ggc: ref GGC, v: ref Value)
{
	if(v == nil || ggc == nil)
		return;

	case(v.ty) {
	TTABLE =>
		if(v.t != nil)
			marktableall(ggc, v.t);
	TFUNCTION =>
		if(v.f != nil)
			markfunctionall(ggc, v.f);
	TUSERDATA =>
		if(v.u != nil)
			markuserdataall(ggc, v.u);
	TTHREAD =>
		if(v.th != nil)
			markthreadall(ggc, v.th);
	}
}

# Propagate all marks
propagateall(ggc: ref GGC)
{
	if(ggc == nil)
		return;

	# Combine all object lists
	all := concatlists(ggc.young, ggc.old, ggc.tenured);

	while(all != nil) {
		if(all.marked == GRAY) {
			markchildrenall(ggc, all);
			all.marked = BLACK;
		}
		all = all.next;
	}
}

# Sweep all and promote
sweeppromote(ggc: ref GGC)
{
	if(ggc == nil)
		return;

	# Sweep young, promote to old
	obj := ggc.young;
	while(obj != nil) {
		nextobj := obj.next;

		if(obj.marked == WHITE0 || obj.marked == WHITE1) {
			freeyoungobj(ggc, obj);
		} else {
			promote(ggc, obj);
		}

		obj = nextobj;
	}

	# Sweep old
	obj := ggc.old;
	while(obj != nil) {
		nextobj := obj.next;

		if(obj.marked == WHITE0 || obj.marked == WHITE1) {
			freeoldobj(ggc, obj);
		} else {
			obj.marked = WHITE0;
		}

		obj = nextobj;
	}
}

# ====================================================================
# Remember Set Processing
# ====================================================================

# Process remember set (during major GC)
processremember(ggc: ref GGC)
{
	if(ggc == nil || ggc.remember == nil)
		return;

	entries := ggc.remember.nodes;
	while(entries != nil) {
		entry := hd entries;

		# Mark young object referenced by old object
		if(entry.val != nil && isyoung(ggc, entry.val))
			markyoung(ggc, entry.val);

		entries = tl entries;
	}
}

# Mark remember set
markrememberset(ggc: ref GGC)
{
	if(ggc == nil || ggc.remember == nil)
		return;

	entries := ggc.remember.nodes;
	while(entries != nil) {
		entry := hd entries;

		# Mark old object
		markoldobj(ggc, entry.oldobj);

		entries = tl entries;
	}
}

# Mark old object
markoldobj(ggc: ref GGC, obj: ref GCheader)
{
	if(obj == nil)
		return;

	obj.marked = BLACK;
}

# ====================================================================
# GC Control
# ====================================================================

# Check if should do minor GC
shouldminorgc(ggc: ref GGC): int
{
	if(ggc == nil)
		return 0;

	# Trigger if allocated enough
	return ggc.minorgc > (ggc.youngsize / big(ggc.minorgcmul) * 100big);
}

# Check if should do major GC
shouldmajorgc(ggc: ref GGC): int
{
	if(ggc == nil)
		return 0;

	# Trigger if remember set too large
	if(ggc.remember != nil && ggc.remember.count > 1000)
		return 1;

	# Or allocated enough
	return ggc.majorgc > (ggc.oldsize / big(ggc.majorgcmul) * 100big);
}

# Trigger major GC
triggermajor(ggc: ref GGC)
{
	if(ggc == nil)
		return;

	# Force major GC soon
	ggc.majorgc = 99999999big;
}

# ====================================================================
# Helper Functions
# ====================================================================

# Type-specific mark functions (all generations)
marktableall(ggc: ref GGC, t: ref Table)
{
	if(t == nil || ggc == nil)
		return;

	hdr := ref GCheader(t);
	if(hdr.marked == WHITE0 || hdr.marked == WHITE1)
		hdr.marked = GRAY;

	# Mark children
	if(t.arr != nil) {
		for(i := 0; i < t.sizearray; i++)
			markvalueall(ggc, t.arr[i]);
	}
}

markfunctionall(ggc: ref GGC, f: ref Function)
{
	if(f == nil || ggc == nil)
		return;

	hdr := ref GCheader(f);
	if(hdr.marked == WHITE0 || hdr.marked == WHITE1)
		hdr.marked = GRAY;

	if(f.proto != nil)
		markprotoall(ggc, f.proto);
	if(f.env != nil)
		marktableall(ggc, f.env);
}

markuserdataall(ggc: ref GGC, u: ref Userdata)
{
	if(u == nil || ggc == nil)
		return;

	hdr := ref GCheader(u);
	if(hdr.marked == WHITE0 || hdr.marked == WHITE1)
		hdr.marked = GRAY;

	if(u.env != nil)
		marktableall(ggc, u.env);
	if(u.metatable != nil)
		marktableall(ggc, u.metatable);
}

markthreadall(ggc: ref GGC, th: ref Thread)
{
	if(th == nil || ggc == nil)
		return;

	hdr := ref GCheader(th);
	if(hdr.marked == WHITE0 || hdr.marked == WHITE1)
		hdr.marked = GRAY;

	if(th.stack != nil) {
		for(i := 0; i < th.top; i++)
			markvalueall(ggc, th.stack[i]);
	}
}

markprotoall(ggc: ref GGC, p: ref Proto)
{
	if(p == nil || ggc == nil)
		return;

	hdr := ref GCheader(p);
	if(hdr.marked == WHITE0 || hdr.marked == WHITE1)
		hdr.marked = GRAY;

	if(p.k != nil) {
		for(i := 0; i < len p.k; i++)
			markvalueall(ggc, p.k[i]);
	}
}

# Mark children (all)
markchildrenall(ggc: ref GGC, obj: ref GCheader)
{
	if(obj == nil)
		return;

	case(obj.tt) {
	TTABLE =>
		t := ref Table(obj - 4);
		if(t != nil) {
			if(t.metatable != nil)
				marktableall(ggc, t.metatable);
			if(t.arr != nil) {
				for(i := 0; i < t.sizearray; i++)
					markvalueall(ggc, t.arr[i]);
			}
		}
	TFUNCTION =>
		f := ref Function(obj - 4);
		if(f != nil) {
			if(f.proto != nil)
				markprotoall(ggc, f.proto);
			if(f.env != nil)
				marktableall(ggc, f.env);
		}
	}
}

# Free old object
freeoldobj(ggc: ref GGC, obj: ref GCheader)
{
	if(obj == nil || ggc == nil)
		return;

	sz := getobjsize(obj);
	ggc.oldsize -= sz;
	ggc.totalbytes -= sz;
}

# Concatenate lists
concatlists(a, b, c: ref GCheader): ref GCheader
{
	# Simple concatenation
	result := a;
	last := a;

	if(a != nil) {
		while(a.next != nil)
			a = a.next;
		last = a;
	}

	if(last != nil)
		last.next = b;
	else
		result = b;

	if(b != nil) {
		while(b.next != nil)
			b = b.next;
		b.next = c;
	} else if(last != nil) {
		last.next = c;
	} else {
		result = c;
	}

	return result;
}

# Module initialization
init(): string
{
	sys = load Sys Sys;
	return nil;
}

about(): array of string
{
	return array[] of {
		"Lua VM for Inferno/Limbo",
		"Generational Garbage Collector",
		"Young/old generations with remember set",
	};
}
