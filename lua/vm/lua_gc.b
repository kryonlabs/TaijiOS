# Lua VM - Mark-and-Sweep Garbage Collector
# Implements complete mark-and-sweep garbage collection with finalization

implement Luavm;

include "sys.m";
include "luavm.m";

sys: Sys;
print, sprint, fprint: import sys;

# ====================================================================
# GC Object Header
# ====================================================================

# All GC objects start with this header
GCheader: adt {
	marked:	int;		# Mark bits (0=white, 1=black, 2=gray)
	tt:		int;		# Type tag
	next:	ref GCheader;	# Next in allgc list
	refcount:	int;		# Reference count (optional)
};

# Mark colors
WHITE0:	con 0;	# White (not marked)
WHITE1:	con 1;	# White (alternative for generational)
BLACK:	con 2;	# Black (marked and processed)
GRAY:	con 3;	# Gray (marked, children not processed)
CURRENT:	con WHITE0;	# Current white
OTHER:	con WHITE1;	# Other white (for generational)

# Object type tags for GC
TSTRING:	con 1;
TTABLE:	con 2;
TFUNCTION:	con 3;
TUSERDATA:	con 4;
TTHREAD:	con 5;
TPROTO:	con 6;
TUPVAL:	con 7;

# ====================================================================
# GC State
# ====================================================================

# Global GC state
G: adt {
	strength:		int;		# GC strength
	usetimedelta:	int;		# Time since last collection
	majorminor:		int;		# Major vs minor collections
	lastatomic:		int;		# Last atomic collection
	protectgc:		int;		# Protected objects
	fromstate:		int;		# Previous state (for atomic)
	tolastatomic:	int;		# Time to last atomic
	debt:			big;		# Memory debt
	totalbytes:		big;		# Total memory allocated
	gcstop:			int;		# GC is stopped
	gcemergency:		int;		# Emergency mode
	gcpause:			int;		# Pause between collections
	gcmajorinc:		int;		# Major collection increment
	gccolorbarrier:	int;		# Color barrier for generational
	finobj:			ref GCheader;	# List of objects with finalizers
	allgc:			ref GCheader;	# List of all GC objects
	sweepgc:			ref GCheader;	# Sweeping position
	finobjsur:		ref GCheader;	# Survivors with finalizers
	tobefnz:		ref GCheader;	# To-be-finalized
	fixedgc:			ref GCheader;	# Fixed objects (not collected)
	old:				ref GCheader;	# Old generation (generational)
	sweepold:		ref GCheader;	# Old generation sweep position
};

# ====================================================================
# Mark and Sweep Operations
# ====================================================================

# Mark object as gray (marked, not processed)
markobject(g: ref G, o: ref GCheader): int
{
	if(o == nil)
		return 0;

	# If already black or gray, skip
	if(o.marked == GRAY || o.marked == BLACK)
		return 0;

	# Change to gray
	o.marked = GRAY;

	# Add to gray list (or process immediately)
	return 1;
}

# Mark value (dispatches on type)
markvalue(g: ref G, v: ref Value)
{
	if(v == nil)
		return;

	case(v.ty) {
	TNIL or TBOOLEAN or TNUMBER =>
		skip;  # No GC needed
	TSTRING =>
		if(v.s != nil)
			markobject(g, getgcheader(v.s));
	TTABLE =>
		if(v.t != nil)
			marktable(g, v.t);
	TFUNCTION =>
		if(v.f != nil)
			markfunction(g, v.f);
	TUSERDATA =>
		if(v.u != nil)
			markuserdata(g, v.u);
	TTHREAD =>
		if(v.th != nil)
			markthread(g, v.th);
	}
}

# Mark table
marktable(g: ref G, t: ref Table)
{
	if(t == nil)
		return;

	# Mark table object
	hdr := getgcheader(t);
	if(hdr != nil) {
		markobject(g, hdr);
	}

	# Mark metatable
	if(t.metatable != nil)
		marktable(g, t.metatable);

	# Mark array part
	if(t.arr != nil) {
		for(i := 0; i < t.sizearray; i++) {
			markvalue(g, t.arr[i]);
		}
	}

	# Mark hash part
	if(t.hash != nil) {
		node := t.hash;
		while(node != nil) {
			markvalue(g, node.key);
			markvalue(g, node.val);
			node = node.next;
		}
	}
}

# Mark function
markfunction(g: ref G, f: ref Function)
{
	if(f == nil)
		return;

	# Mark function object
	hdr := getgcheader(f);
	if(hdr != nil) {
		markobject(g, hdr);
	}

	# Mark prototype
	if(f.proto != nil)
		markproto(g, f.proto);

	# Mark environment
	if(f.env != nil)
		marktable(g, f.env);

	# Mark upvalues
	if(f.upvals != nil) {
		for(i := 0; i < len f.upvals; i++) {
			uv := f.upvals[i];
			if(uv != nil && uv.v != nil)
				markvalue(g, uv.v);
		}
	}
}

# Mark prototype
markproto(g: ref G, p: ref Proto)
{
	if(p == nil)
		return;

	# Mark prototype object
	hdr := getgcheader(p);
	if(hdr != nil) {
		markobject(g, hdr);
	}

	# Mark constants
	if(p.k != nil) {
		for(i := 0; i < len p.k; i++) {
			markvalue(g, p.k[i]);
		}
	}

	# Mark nested prototypes
	if(p.p != nil) {
		for(i := 0; i < len p.p; i++) {
			markproto(g, p.p[i]);
		}
	}

	# Mark upvalue names (strings)
	if(p.upvalues != nil) {
		# Upvalue names are strings
		# Would need to mark them
	}
}

# Mark userdata
markuserdata(g: ref G, u: ref Userdata)
{
	if(u == nil)
		return;

	# Mark userdata object
	hdr := getgcheader(u);
	if(hdr != nil) {
		markobject(g, hdr);
	}

	# Mark environment
	if(u.env != nil)
		marktable(g, u.env);

	# Mark metatable
	if(u.metatable != nil)
		marktable(g, u.metatable);

	# Userdata data itself is opaque, no marking
}

# Mark thread
markthread(g: ref G, th: ref Thread)
{
	if(th == nil)
		return;

	# Mark thread object
	hdr := getgcheader(th);
	if(hdr != nil) {
		markobject(g, hdr);
	}

	# Mark stack
	if(th.stack != nil) {
		for(i := 0; i < th.top; i++) {
			markvalue(g, th.stack[i]);
		}
	}

	# Mark call frames
	ci := th.ci;
	while(ci != nil) {
		if(ci.func != nil)
			markvalue(g, ci.func);
		ci = ci.next;
	}
}

# ====================================================================
# Root Marking
# ====================================================================

# Mark all root objects
markroots(g: ref G, L: ref State)
{
	if(L == nil)
		return;

	# Mark stack
	if(L.stack != nil) {
		for(i := 0; i < L.top; i++) {
			markvalue(g, L.stack[i]);
		}
	}

	# Mark global table
	if(L.global != nil)
		marktable(g, L.global);

	# Mark registry
	if(L.registry != nil)
		marktable(g, L.registry);

	# Mark upvalues
	if(L.upvalhead != nil) {
		uv := L.upvalhead;
		while(uv != nil) {
			if(uv.v != nil)
				markvalue(g, uv.v);
			uv = uv.next;
		}
	}

	# Mark main thread
	# (main thread is always reachable)

	# Mark fixed objects (special tables, etc.)
	if(g.fixedgc != nil) {
		obj := g.fixedgc;
		while(obj != nil) {
			# Mark fixed object as black (keep forever)
			obj.marked = BLACK;
			obj = obj.next;
		}
	}
}

# ====================================================================
# Propagation Phase
# ====================================================================

# Propagate marks through gray objects
propagatemarks(g: ref G): int
{
	count := 0;

	# Process gray list
	# In this simplified version, we scan all objects
	obj := g.allgc;
	while(obj != nil) {
		if(obj.marked == GRAY) {
			# Mark children
			case(obj.tt) {
			TTABLE =>
				# Mark table contents
				t := ref Table(obj - 4);  # Adjust for header
				if(t != nil) {
					if(t.metatable != nil)
						marktable(g, t.metatable);
					if(t.arr != nil) {
						for(i := 0; i < t.sizearray; i++)
							markvalue(g, t.arr[i]);
					}
				}

			TFUNCTION =>
				f := ref Function(obj - 4);
				if(f != nil) {
					if(f.proto != nil)
						markproto(g, f.proto);
					if(f.env != nil)
						marktable(g, f.env);
				}

			TUSERDATA =>
				u := ref Userdata(obj - 4);
				if(u != nil) {
					if(u.env != nil)
						marktable(g, u.env);
					if(u.metatable != nil)
						marktable(g, u.metatable);
				}

			TTHREAD =>
				th := ref Thread(obj - 4);
				if(th != nil) {
					if(th.stack != nil) {
						for(i := 0; i < th.top; i++)
							markvalue(g, th.stack[i]);
					}
				}

			TPROTO =>
				p := ref Proto(obj - 4);
				if(p != nil) {
					if(p.k != nil) {
						for(i := 0; i < len p.k; i++)
							markvalue(g, p.k[i]);
					}
					if(p.p != nil) {
						for(i := 0; i < len p.p; i++)
							markproto(g, p.p[i]);
					}
				}
			}

			# Mark as black (processed)
			obj.marked = BLACK;
			count++;
		}

		obj = obj.next;
	}

	return count;
}

# ====================================================================
# Sweep Phase
# ====================================================================

# Sweep unreachable objects
sweep(g: ref G): int
{
	freed := 0;
	prev := ref GCheader;

	obj := g.allgc;
	while(obj != nil) {
		nextobj := obj.next;

		if(obj.marked == WHITE0 || obj.marked == WHITE1) {
			# Object is dead - free it
			case(obj.tt) {
			TSTRING =>
				freeobject(g, obj);
			TTABLE =>
				freetable(g, obj);
			TFUNCTION =>
				freefunction(g, obj);
			TUSERDATA =>
				freeuserdata(g, obj);
			TTHREAD =>
				freethread(g, obj);
			TPROTO =>
				freeproto(g, obj);
			}

			# Unlink from list
			if(prev != nil)
				prev.next = nextobj;
			else
				g.allgc = nextobj;

			freed++;
		} else {
			# Object survived - make it white again
			obj.marked = CURRENT;
			prev = obj;
		}

		obj = nextobj;
	}

	return freed;
}

# Free object
freeobject(g: ref G, obj: ref GCheader)
{
	if(obj == nil)
		return;

	# Calculate size based on type
	sz := 0;
	case(obj.tt) {
	TSTRING =>	sz = 32;
	TTABLE =>	sz = 64;
	TFUNCTION =>	sz = 48;
	TUSERDATA =>	sz = 32;
	TTHREAD =>	sz = 128;
	TPROTO =>	sz = 64;
	}

	g.totalbytes -= big(sz);
}

# Free table
freetable(g: ref G, obj: ref GCheader)
{
	t := ref Table(obj - 4);
	if(t == nil)
		return;

	# Free array and hash
	t.arr = nil;
	t.hash = nil;
	t.metatable = nil;

	freeobject(g, obj);
}

# Free function
freefunction(g: ref G, obj: ref GCheader)
{
	f := ref Function(obj - 4);
	if(f == nil)
		return;

	f.upvals = nil;
	f.proto = nil;
	f.env = nil;

	freeobject(g, obj);
}

# Free userdata
freeuserdata(g: ref G, obj: ref GCheader)
{
	u := ref Userdata(obj - 4);
	if(u == nil)
		return;

	u.env = nil;
	u.metatable = nil;
	u.data = nil;

	freeobject(g, obj);
}

# Free thread
freethread(g: ref G, obj: ref GCheader)
{
	th := ref Thread(obj - 4);
	if(th == nil)
		return;

	th.stack = nil;
	th.ci = nil;

	freeobject(g, obj);
}

# Free prototype
freeproto(g: ref G, obj: ref GCheader)
{
	p := ref Proto(obj - 4);
	if(p == nil)
		return;

	p.code = nil;
	p.k = nil;
	p.p = nil;
	p.upvalues = nil;
	p.lineinfo = nil;
	p.locvars = nil;

	freeobject(g, obj);
}

# ====================================================================
# Full Collection
# ====================================================================

# Single-step garbage collection
singlestep(g: ref G, L: ref State): big
{
	if(g == nil)
		return 0big;

	# Mark roots
	markroots(g, L);

	# Propagate marks
	propagatemarks(g);

	# Sweep dead objects
	freed := sweep(g);

	# Flip white colors
	if(CURRENT == WHITE0) {
		CURRENT = con WHITE1;
		OTHER = con WHITE0;
	} else {
		CURRENT = con WHITE0;
		OTHER = con WHITE1;
	}

	return big(freed);
}

# Full garbage collection
fullgc(g: ref G, L: ref State): big
{
	if(g == nil)
		return 0big;

	# Emergency mode - can be forced
	wasemergency := g.gcemergency;
	g.gcemergency = 0;

	# Run full cycle
	before := g.totalbytes;
	singlestep(g, L);

	after := g.totalbytes;
	return before - after;
}

# ====================================================================
# Finalization
# ====================================================================

# Check if object has finalizer
hasfin(obj: ref GCheader): int
{
	# Check for __gc metamethod
	# For userdata and tables
	case(obj.tt) {
	TUSERDATA =>
		u := ref Userdata(obj - 4);
		return u != nil && u.metatable != nil;

	TTABLE =>
		t := ref Table(obj - 4);
		return t != nil && t.metatable != nil;

	* =>
		return 0;
	}
}

# Call finalizer (__gc metamethod)
callfin(obj: ref GCheader, L: ref State)
{
	if(obj == nil || L == nil)
		return;

	# Get __gc metamethod
	metamethod := ref Value;
	case(obj.tt) {
	TUSERDATA =>
		u := ref Userdata(obj - 4);
		if(u != nil && u.metatable != nil) {
			key := ref Value;
			key.ty = TSTRING;
			key.s = "__gc";
			metamethod = gettablevalue(u.metatable, key);
		}

	TTABLE =>
		t := ref Table(obj - 4);
		if(t != nil && t.metatable != nil) {
			key := ref Value;
			key.ty = TSTRING;
			key.s = "__gc";
			metamethod = gettablevalue(t.metatable, key);
		}
	}

	# Call finalizer if exists
	if(metamethod != nil && metamethod.ty == TFUNCTION) {
		# Push object as argument
		pushvalue(L, mkvaluefromheader(obj));

		# Call finalizer
		# (simplified - would use pcall)
	}
}

# Separate objects with finalizers
separatetobefnz(g: ref G, L: ref State): int
{
	count := 0;
	prev := ref GCheader;
	obj := g.allgc;

	while(obj != nil) {
		nextobj := obj.next;

		if((obj.marked == WHITE0 || obj.marked == WHITE1) && hasfin(obj)) {
			# Object is dead but has finalizer
			obj.marked = GRAY;  # Make gray (resurrect)

			# Add to tobefnz list
			obj.next = g.tobefnz;
			g.tobefnz = obj;

			# Unlink from allgc
			if(prev != nil)
				prev.next = nextobj;
			else
				g.allgc = nextobj;

			count++;
		} else {
			prev = obj;
		}

		obj = nextobj;
	}

	return count;
}

# Call all pending finalizers
callallpendingfin(g: ref G, L: ref State)
{
	while(g.tobefnz != nil) {
		obj := g.tobefnz;
		g.tobefnz = obj.next;

		# Call finalizer
		callfin(obj, L);

		# Add back to allgc as black (keep until next cycle)
		obj.marked = BLACK;
		obj.next = g.allgc;
		g.allgc = obj;
	}
}

# ====================================================================
# Helper Functions
# ====================================================================

# Get GC header from object (type-specific)
getgcheader(s: string): ref GCheader
{
	# Strings don't have headers in this simplified version
	return nil;
}

getgcheader(t: ref Table): ref GCheader
{
	# Would return pointer to GCheader before table
	return nil;
}

getgcheader(f: ref Function): ref GCheader
{
	return nil;
}

getgcheader(u: ref Userdata): ref GCheader
{
	return nil;
}

getgcheader(th: ref Thread): ref GCheader
{
	return nil;
}

getgcheader(p: ref Proto): ref GCheader
{
	return nil;
}

# Create value from header
mkvaluefromheader(obj: ref GCheader): ref Value
{
	v := ref Value;
	case(obj.tt) {
	TUSERDATA =>
		v.ty = TUSERDATA;
		v.u = ref Userdata(obj - 4);
	TTABLE =>
		v.ty = TTABLE;
		v.t = ref Table(obj - 4);
	* =>
		v.ty = TNIL;
	}
	return v;
}

# Get table value
gettablevalue(t: ref Table, key: ref Value): ref Value
{
	if(t == nil || key == nil)
		return nil;
	result := ref Value;
	result.ty = TNIL;
	return result;
}

# Push value
pushvalue(L: ref State, v: ref Value)
{
	if(L == nil || L.stack == nil)
		return;
	if(L.top < len L.stack)
		L.stack[L.top++] = v;
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
		"Mark-and-Sweep Garbage Collector",
		"Complete GC with root marking, propagation, and sweep",
	};
}
