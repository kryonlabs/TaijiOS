# Lua VM - Incremental Garbage Collector
# Implements step-based incremental GC to avoid long pauses

implement Luavm;

include "sys.m";
include "luavm.m";
include "lua_gc.m";

sys: Sys;
print, sprint, fprint: import sys;

# ====================================================================
# GC State Machine
# ====================================================================

# GC states
GCSpause:		con 0;	# Paused/not running
GCSpropagate:	con 1;	# Propagating marks
GCSatomic:		con 2;	# Atomic propagation
GCSsweepstring:	con 3;	# Sweeping strings
GCSsweepudata:	con 4;	# Sweeping userdata
GCSsweep:		con 5;	# Sweeping other objects

# GC parameters
GENMINORMUL:	con 20;	# Multiplier for young collection
GENMAJORMUL:	con 100;	# Multiplier for old collection
WORKPERTHREAD:	con 100;	# Work units per thread

# Incremental GC state
IGC: adt {
	gcstate:		int;		# Current GC state
	currentwhite:	int;		# Current white color
	otherwhite:		int;		# Other white color
	gray:			ref GCheader;	# List of gray objects
	grayagain:		ref GCheader;	# List of grays (atomic)
	old:			ref GCheader;	# Old generation
	sweepstr:		ref GCheader;	# Sweeping position (strings)
	sweepudata:		ref GCheader;	# Sweeping position (userdata)
	sweeplast:		ref GCheader;	# Last sweep position
	totalbytes:		big;		# Total bytes
	gcpause:		int;		# Pause between collections
	gcmajorinc:		int;		# Major collection increment
	gctrigger:		big;		# Trigger for next collection
 debt:			big;		# Memory debt
	estimate:		big;		# Estimate of work
	work:			big;		# Work done in this cycle
};

# ====================================================================
# Incremental GC Step
# ====================================================================

# Perform one incremental GC step
incstep(L: ref State, igc: ref IGC, gsize: int): big
{
	if(L == nil || igc == nil)
		return 0big;

	# Calculate work to do
	work := big(igc.estimate / WORKPERTHREAD);
	if(work < 1big)
		work = 1big;

	# Execute based on state
	while(work > 0big) {
		case(igc.gcstate) {
		GCSpause =>
			# Start new cycle
			restartcollection(igc);
			igc.gcstate = GCSpropagate;
			work--;

		GCSpropagate =>
			# Propagate marks
			did := propagatestep(igc, L);
			work -= big(did);

			if(igc.gray == nil && igc.grayagain == nil) {
				# No more gray objects, go to atomic
				igc.gcstate = GCSatomic;
				atomicstart(igc);
			}

		GCSatomic =>
			# Atomic phase
			did := atomicstep(igc, L);
			work -= big(did);

			if(igc.gray == nil && igc.grayagain == nil) {
				# Atomic done, start sweeping
				igc.gcstate = GCSsweepstring;
				igc.sweepstr = igc.old;
			}

		GCSsweepstring =>
			# Sweep strings
			did := sweepstep(igc, TSTRING);
			work -= big(did);

			if(igc.sweepstr == nil) {
				# Strings done, sweep userdata
				igc.gcstate = GCSsweepudata;
				igc.sweepudata = igc.old;
			}

		GCSsweepudata =>
			# Sweep userdata (with finalizers)
			did := sweepstep(igc, TUSERDATA);
			work -= big(did);

			if(igc.sweepudata == nil) {
				# Userdata done, sweep rest
				igc.gcstate = GCSsweep;
				igc.sweeplast = igc.old;
			}

		GCSsweep =>
			# Sweep remaining objects
			did := sweepstep(igc, -1);  # All types
			work -= big(did);

			if(igc.sweeplast == nil) {
				# All done, back to pause
				igc.gcstate = GCSpause;
				finishsweep(igc);
				work = 0big;
			}
		}
	}

	# Update estimate
	igc.estimate = igc.totalbytes;

	return work;
}

# ====================================================================
# State Operations
# ====================================================================

# Restart collection cycle
restartcollection(igc: ref IGC)
{
	if(igc == nil)
		return;

	# Flip white colors
	temp := igc.currentwhite;
	igc.currentwhite = igc.otherwhite;
	igc.otherwhite = temp;

	# Clear gray lists
	igc.gray = nil;
	igc.grayagain = nil;

	# Start from old generation
	igc.old = nil;
}

# Start atomic phase
atomicstart(igc: ref IGC)
{
	if(igc == nil)
		return;

	# Mark weak tables
	markweak(igc);

	# Clear old generation
	igc.old = nil;

	# Separate objects to be finalized
	separatetofinalize(igc);

	# Propagate again
	repropagate(igc);
}

# Finish sweep phase
finishsweep(igc: ref IGC)
{
	if(igc == nil)
		return;

	# Call finalizers
	callpendingfinalizers(igc);

	# Check if need major collection
	if(shouldgomajor(igc)) {
		# Major collection
		majorcollection(igc);
	}

	# Calculate next trigger
	igc.gctrigger = igc.totalbytes + big(igc.gcpause * igc.totalbytes / 100);
}

# ====================================================================
# Propagation Step
# ====================================================================

# Propagate marks (one step)
propagatestep(igc: ref IGC, L: ref State): int
{
	if(igc == nil || L == nil)
		return 0;

	count := 0;

	# Process gray list
	while(igc.gray != nil && count < WORKPERTHREAD) {
		# Get first gray object
		gray := igc.gray;
		igc.gray = gray.next;

		# Mark its children
		markchildren(igc, gray, L);

		# Mark as black
		gray.marked = BLACK;

		count++;
	}

	# If gray list empty, process grayagain
	if(igc.gray == nil) {
		while(igc.grayagain != nil && count < WORKPERTHREAD) {
			gray := igc.grayagain;
			igc.grayagain = gray.next;

			markchildren(igc, gray, L);
			gray.marked = BLACK;

			count++;
		}
	}

	return count;
}

# Mark children of object
markchildren(igc: ref IGC, obj: ref GCheader, L: ref State)
{
	if(obj == nil)
		return;

	case(obj.tt) {
	TTABLE =>
		t := ref Table(obj - 4);
		if(t != nil) {
			if(t.metatable != nil)
				markobjectg(igc, t.metatable);
			if(t.arr != nil) {
				for(i := 0; i < t.sizearray; i++)
					markvalueg(igc, t.arr[i]);
			}
		}

	TFUNCTION =>
		f := ref Function(obj - 4);
		if(f != nil) {
			if(f.proto != nil)
				markobjectg(igc, f.proto);
			if(f.env != nil)
				markobjectg(igc, f.env);
		}

	TUSERDATA =>
		u := ref Userdata(obj - 4);
		if(u != nil) {
			if(u.env != nil)
				markobjectg(igc, u.env);
			if(u.metatable != nil)
				markobjectg(igc, u.metatable);
		}

	TTHREAD =>
		th := ref Thread(obj - 4);
		if(th != nil && th.stack != nil) {
			for(i := 0; i < th.top; i++)
				markvalueg(igc, th.stack[i]);
		}
	}
}

# Mark object (add to gray list)
markobjectg(igc: ref IGC, obj: ref Value)
{
	if(obj == nil || igc == nil)
		return;

	case(obj.ty) {
	TTABLE =>
		if(obj.t != nil)
			markobjectg(igc, obj.t);
	TFUNCTION =>
		if(obj.f != nil)
			markobjectg(igc, obj.f);
	}
}

# Mark value
markvalueg(igc: ref IGC, v: ref Value)
{
	if(v == nil || igc == nil)
		return;

	case(v.ty) {
	TTABLE =>
		if(v.t != nil)
			marktableg(igc, v.t);
	TFUNCTION =>
		if(v.f != nil)
			markfunctiong(igc, v.f);
	TUSERDATA =>
		if(v.u != nil)
			markuserdatag(igc, v.u);
	TTHREAD =>
		if(v.th != nil)
			markthreadg(igc, v.th);
	}
}

# Type-specific mark functions
marktableg(igc: ref IGC, t: ref Table)
{
	if(t == nil || igc == nil)
		return;

	# Get header and add to gray
	hdr := ref GCheader(t);
	if(hdr.marked != WHITE0 && hdr.marked != WHITE1)
		return;  # Already marked

	hdr.marked = GRAY;
	hdr.next = igc.gray;
	igc.gray = hdr;

	# Mark metatable
	if(t.metatable != nil)
		marktableg(igc, t.metatable);
}

markfunctiong(igc: ref IGC, f: ref Function)
{
	if(f == nil || igc == nil)
		return;

	hdr := ref GCheader(f);
	if(hdr.marked != WHITE0 && hdr.marked != WHITE1)
		return;

	hdr.marked = GRAY;
	hdr.next = igc.gray;
	igc.gray = hdr;
}

markuserdatag(igc: ref IGC, u: ref Userdata)
{
	if(u == nil || igc == nil)
		return;

	hdr := ref GCheader(u);
	if(hdr.marked != WHITE0 && hdr.marked != WHITE1)
		return;

	hdr.marked = GRAY;
	hdr.next = igc.gray;
	igc.gray = hdr;
}

markthreadg(igc: ref IGC, th: ref Thread)
{
	if(th == nil || igc == nil)
		return;

	hdr := ref GCheader(th);
	if(hdr.marked != WHITE0 && hdr.marked != WHITE1)
		return;

	hdr.marked = GRAY;
	hdr.next = igc.gray;
	igc.gray = hdr;
}

# ====================================================================
# Atomic Phase
# ====================================================================

# Atomic propagation step
atomicstep(igc: ref IGC, L: ref State): int
{
	if(igc == nil || L == nil)
		return 0;

	count := 0;

	# Propagate all remaining grays
	while(igc.gray != nil && count < WORKPERTHREAD) {
		gray := igc.gray;
		igc.gray = gray.next;

		markchildren(igc, gray, L);
		gray.marked = BLACK;

		count++;
	}

	while(igc.grayagain != nil && count < WORKPERTHREAD) {
		gray := igc.grayagain;
		igc.grayagain = gray.next;

		markchildren(igc, gray, L);
		gray.marked = BLACK;

		count++;
	}

	return count;
}

# Mark weak tables
markweak(igc: ref IGC)
{
	if(igc == nil)
		return;

	# Mark keys/values in weak tables
	# (simplified - would iterate over all tables)
}

# Separate objects needing finalization
separatetofinalize(igc: ref IGC)
{
	if(igc == nil)
		return;

	# Check all objects for __gc metamethod
	# Move them to separate list
}

# Re-propagate after atomic
repropagate(igc: ref IGC)
{
	# Propagate marks again for correctness
}

# ====================================================================
# Sweep Step
# ====================================================================

# Sweep objects (one step)
sweepstep(igc: ref IGC, type: int): int
{
	if(igc == nil)
		return 0;

	count := 0;
	swept := 0;
	list := igc.sweeplast;

	if(list == nil)
		return 0;

	while(list != nil && swept < WORKPERTHREAD) {
		nextobj := list.next;

		# Check if object is white (dead)
		if(list.marked == igc.otherwhite) {
			# Free object
			freeobjectg(igc, list);
			swept++;
		} else {
			# Make current white
			list.marked = igc.currentwhite;
		}

		list = nextobj;
		count++;
	}

	igc.sweeplast = list;
	return count;
}

# Free object during sweep
freeobjectg(igc: ref IGC, obj: ref GCheader)
{
	if(obj == nil || igc == nil)
		return;

	# Calculate size
	sz := 0;
	case(obj.tt) {
	TSTRING =>	sz = 32;
	TTABLE =>	sz = 64;
	TFUNCTION =>	sz = 48;
	TUSERDATA =>	sz = 32;
	TTHREAD =>	sz = 128;
	TPROTO =>	sz = 64;
	}

	igc.totalbytes -= big(sz);
}

# ====================================================================
# Generational Support
# ====================================================================

# Check if should do major collection
shouldgomajor(igc: ref IGC): int
{
	if(igc == nil)
		return 0;

	# Heuristic: if old generation is too large
	return igc.old != nil && getsize(igc.old) > 1000;
}

# Major collection (full GC)
majorcollection(igc: ref IGC)
{
	if(igc == nil)
		return;

	# Mark all objects
	obj := igc.old;
	while(obj != nil) {
		if(obj.marked == igc.currentwhite)
			obj.marked = BLACK;
		obj = obj.next;
	}

	# Sweep old generation
	igc.sweeplast = igc.old;
	while(igc.sweeplast != nil) {
		sweepstep(igc, -1);
	}

	# Clear old generation
	igc.old = nil;
}

# Get size of object list
getsize(head: ref GCheader): int
{
	count := 0;
	obj := head;
	while(obj != nil) {
		count++;
		obj = obj.next;
	}
	return count;
}

# ====================================================================
# Weak Tables
# ====================================================================

# Mark weak tables (called during atomic)
markweak(igc: ref IGC)
{
	if(igc == nil)
		return;

	# Iterate over all tables
	# Mark keys/values in non-weak mode
	# Clear dead entries from weak tables
}

# Clear weak tables
clearweak(igc: ref IGC)
{
	if(igc == nil)
		return;

	# Clear entries with dead keys/values
}

# ====================================================================
# Finalization
# ====================================================================

# Separate objects with finalizers
separateofinalize(igc: ref IGC): int
{
	if(igc == nil)
		return 0;

	count := 0;
	obj := igc.old;

	while(obj != nil) {
		nextobj := obj.next;

		if(obj.marked == igc.otherwhite && hasfinalizer(obj)) {
			# Resurrect for finalization
			obj.marked = GRAY;

			# Add to finalization list
			obj.next = igc.tobefnz;
			igc.tobefnz = obj;

			count++;
		}

		obj = nextobj;
	}

	return count;
}

# Call pending finalizers
callpendingfinalizers(igc: ref IGC)
{
	if(igc == nil)
		return;

	while(igc.tobefnz != nil) {
		obj := igc.tobefnz;
		igc.tobefnz = obj.next;

		# Call __gc metamethod
		callfinalizer(obj);

		# Mark as black (keep for now)
		obj.marked = BLACK;
		obj.next = igc.old;
		igc.old = obj;
	}
}

# Check if object has finalizer
hasfinalizer(obj: ref GCheader): int
{
	if(obj == nil)
		return 0;

	# Check for __gc metamethod
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

# Call finalizer
callfinalizer(obj: ref GCheader)
{
	# Would call __gc metamethod
	# For now, placeholder
}

# ====================================================================
# Control Interface
# ====================================================================

# Start incremental GC
startincgc(igc: ref IGC)
{
	if(igc == nil)
		return;

	igc.gcstate = GCSpropagate;
	igc.gcpause = 200;  # Default: wait until memory is 200% of last collection
	igc.gcmajorinc = 200;  # Default: do major collection at 200%
}

# Stop incremental GC
stopincgc(igc: ref IGC)
{
	if(igc == nil)
		return;

	igc.gcstate = GCSpause;
}

# Set GC pause
setgcpause(igc: ref IGC, pause: int)
{
	if(igc == nil || pause < 50 || pause > 500)
		return;
	igc.gcpause = pause;
}

# Set GC major increment
setgcmajorinc(igc: ref IGC, inc: int)
{
	if(igc == nil || inc < 0 || inc > 5000)
		return;
	igc.gcmajorinc = inc;
}

# Get GC state
getgcstate(igc: ref IGC): string
{
	if(igc == nil)
		return "unknown";

	case(igc.gcstate) {
	GCSpause =>		return "pause";
	GCSpropagate =>	return "propagate";
	GCSatomic =>		return "atomic";
	GCSsweepstring =>	return "sweepstring";
	GCSsweepudata =>	return "sweepudata";
	GCSsweep =>		return "sweep";
	* =>				return "unknown";
	}
}

# ====================================================================
# Module Interface
# ====================================================================

init(): string
{
	sys = load Sys Sys;
	return nil;
}

about(): array of string
{
	return array[] of {
		"Lua VM for Inferno/Limbo",
		"Incremental Garbage Collector",
		"Step-based GC to avoid long pauses",
	};
}
