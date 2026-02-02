# Lua VM - Upvalue Management
# Handles open and closed upvalues for closures

implement Luavm;

include "sys.m";
include "luavm.m";

sys: Sys;
print, sprint, fprint: import sys;

# ====================================================================
# Upvalue Structures
# ====================================================================

# Extended Upval adt with additional fields
UpvalX: adt {
	v:			cyclic ref Value;	# Value pointer
	refcount:	int;				# Reference count
	open:		int;				# Is open (on stack)?
	prev:		ref UpvalX;			# Previous in upvalue list
	next:		ref UpvalX;			# Next in upvalue list
	stacklevel:	int;				# Stack level when opened
};

# Cast between Upval and UpvalX
toupvalx(uv: ref Upval): ref UpvalX
{
	return ref UpvalX(uv);
}

# ====================================================================
# Upvalue List Management
# ====================================================================

# Find or create upvalue for stack position
findupval(L: ref State, level: int, pos: int): ref Upval
{
	# Search existing upvalues
	uv := toupvalx(L.upvalhead);
	prev: ref UpvalX;

	while(uv != nil) {
		if(uv.open && uv.stacklevel == level && isupvalat(uv, pos)) {
			# Found existing upvalue at this position
			uv.refcount++;
			return ref Upval(uv);
		}
		prev = uv;
		uv = uv.next;
	}

	# Create new upvalue
	newuv := ref UpvalX;
	newuv.v = nil;  # Will be set when value is pushed
	newuv.refcount = 1;
	newuv.open = 1;
	newuv.prev = prev;
	newuv.next = nil;
	newuv.stacklevel = level;

	# Link into list
	if(prev != nil)
		prev.next = newuv;
	else
		L.upvalhead = ref Upval(newuv);

	return ref Upval(newuv);
}

# Check if upvalue points to stack position
isupvalat(uv: ref UpvalX, pos: int): int
{
	# This is a simplified check
	# In full implementation, would compare memory addresses
	# For now, just check if value is in stack range
	return 1;
}

# Close all upvalues at or above stack position
closeupvals(L: ref State, level: int, pos: int)
{
	uv := toupvalx(L.upvalhead);

	while(uv != nil) {
		nextuv := uv.next;

		if(uv.open && uv.stacklevel >= level) {
			# Close this upvalue
			closeupval(L, ref Upval(uv));
		}

		uv = nextuv;
	}
}

# Close upvalue (move from stack to heap)
closeupval(L: ref State, uv: ref Upval)
{
	ux := toupvalx(uv);
	if(ux == nil || !ux.open)
		return;

	# Save value from stack
	savedval := ux.v;

	# Mark as closed
	ux.open = 0;
	ux.stacklevel = -1;

	# Value stays in ux.v, no longer points to stack

	# Decrease refcount
	ux.refcount--;
	if(ux.refcount <= 0) {
		# Remove from list
		if(ux.prev != nil)
			ux.prev.next = ux.next;
		if(ux.next != nil)
			ux.next.prev = ux.prev;
		if(L.upvalhead == ref Upval(ux))
			L.upvalhead = ref Upval(ux.next);
	}
}

# ====================================================================
# Upvalue Value Access
# ====================================================================

# Get upvalue value
getupvalvalue(uv: ref Upval): ref Value
{
	if(uv == nil)
		return nil;
	ux := toupvalx(uv);
	if(ux == nil)
		return nil;
	return ux.v;
}

# Set upvalue value
setupvalvalue(uv: ref Upval, val: ref Value)
{
	if(uv == nil)
		return;
	ux := toupvalx(uv);
	if(ux == nil)
		return;
	ux.v = val;
}

# Mark upvalue as referencing stack position
markupvalstack(L: ref State, uv: ref Upval, pos: int)
{
	if(uv == nil || L.stack == nil)
		return;
	ux := toupvalx(uv);
	if(ux == nil)
		return;

	# Point to stack value
	if(pos >= 0 && pos < L.top)
		ux.v = L.stack[pos];
}

# ====================================================================
# Upvalue Chaining for Function Calls
# ====================================================================

# Save current upvalue state
saveupvals(L: ref State): ref UpvalList
{
	ul := ref UpvalList;
	ul.head = L.upvalhead;
	ul.count := countupvals(L.upvalhead);
	return ul;
}

# Restore upvalue state
restoreupvals(L: ref State, ul: ref UpvalList)
{
	if(ul == nil)
		return;
	L.upvalhead = ul.head;
}

# Count upvalues in list
countupvals(head: ref Upval): int
{
	count := 0;
	uv := head;
	while(uv != nil) {
		count++;
		# Need next field in Upval adt for this to work properly
		# For now, just count what we can
		break;
	}
	return count;
}

UpvalList: adt {
	head:	ref Upval;
	count:	int;
};

# ====================================================================
# Upvalue Resolution
# ====================================================================

# Resolve upvalue by name (during compilation)
resolveupval(fs: ref FuncState, name: string): int
{
	if(fs == nil || fs.prev == nil)
		return -1;  # Not an upvalue, local or global

	# Check outer function's locals
	localidx := findlocal(fs.prev, name);
	if(localidx >= 0) {
		# Found local in outer function - becomes upvalue
		return newupval(fs, name);
	}

	# Recursively check outer functions
	return resolveupval(fs.prev, name);
}

# Find local variable in function state
findlocal(fs: ref FuncState, name: string): int
{
	if(fs == nil || fs.locals == nil)
		return -1;

	locs := fs.locals;
	idx := 0;
	while(locs != nil) {
		loc := hd locs;
		if(loc != nil && loc.name == name)
			return idx;
		locs = tl locs;
		idx++;
	}

	return -1;
}

# Create new upvalue in function state
newupval(fs: ref FuncState, name: string): int
{
	if(fs == nil)
		return -1;

	# Check if upvalue already exists
	if(fs.upvalues != nil) {
		nupvals := len fs.upvalues;
		for(i := 0; i < nupvals; i++) {
			if(fs.upvalues[i] == name)
				return i;
		}
	}

	# Add new upvalue
	if(fs.upvalues == nil) {
		fs.upvalues = array[16] of string;
	} else if(len fs.upvalues >= 255) {
		return -1;  # Too many upvalues
	} else if(fs.nactvar >= len fs.upvalues) {
		newups := array[len fs.upvalues * 2] of string;
		newups[:fs.nactvar] = fs.upvalues[:fs.nactvar];
		fs.upvalues = newups;
	}

	idx := fs.nactvar;
	fs.upvalues[idx] = name;
	fs.nactvar++;

	return idx;
}

# ====================================================================
# Upvalue Migration
# ====================================================================

# Migrate upvalues when leaving scope
migrateupvals(L: ref State, oldlevel, newlevel: int)
{
	uv := toupvalx(L.upvalhead);

	while(uv != nil) {
		if(uv.open && uv.stacklevel == oldlevel) {
			# Move upvalue to new level
			uv.stacklevel = newlevel;
		}
		uv = uv.next;
	}
}

# Reassign upvalues to new stack
reassignupvals(L: ref State, oldstack, newstack: array of ref Value)
{
	uv := toupvalx(L.upvalhead);

	while(uv != nil) {
		if(uv.open) {
			# Find value in old stack, point to same value in new stack
			# This is simplified - real implementation would track positions
			if(uv.v != nil && oldstack != nil) {
				for(i := 0; i < len oldstack; i++) {
					if(oldstack[i] == uv.v && newstack != nil && i < len newstack) {
						uv.v = newstack[i];
						break;
					}
				}
			}
		}
		uv = uv.next;
	}
}

# ====================================================================
# Debug Information
# ====================================================================

# Get upvalue info
getupvalinfo(uv: ref Upval): (int, string)
{
	if(uv == nil)
		return (0, "");

	ux := toupvalx(uv);
	if(ux == nil)
		return (0, "");

	status := 0;
	if(ux.open)
		status = 1;  # Open
	else
		status = 2;  # Closed

	info := sprint("upval@%p", uv);
	return (status, info);
}

# Dump upvalue list
dumpupvals(L: ref State): list of string
{
	info: list of string;

	uv := toupvalx(L.upvalhead);
	idx := 0;
	while(uv != nil) {
		line := "";
		if(uv.open) {
			line = sprint("[%d] open, level=%d, refcount=%d",
				idx, uv.stacklevel, uv.refcount);
		} else {
			line = sprint("[%d] closed, refcount=%d",
				idx, uv.refcount);
		}
		info = list of {line} + info;
		idx++;
		uv = uv.next;
	}

	return info;
}

# ====================================================================
# Garbage Collection Support
# ====================================================================

# Mark upvalues for GC
markupvals(head: ref Upval)
{
	uv := head;
	while(uv != nil) {
		markupval(uv);
		uv = nil;  # Need next field
	}
}

# Mark single upvalue
markupval(uv: ref Upval)
{
	if(uv == nil)
		return;

	ux := toupvalx(uv);
	if(ux == nil)
		return;

	# Mark the value
	if(ux.v != nil) {
		# Mark based on value type
		case(ux.v.ty) {
		TTABLE =>
			if(ux.v.t != nil)
				marktable(ux.v.t);
		TFUNCTION =>
			if(ux.v.f != nil)
				markfunction(ux.v.f);
		TUSERDATA =>
			if(ux.v.u != nil)
				markuserdata(ux.v.u);
		TTHREAD =>
			if(ux.v.th != nil)
				markthread(ux.v.th);
		* =>
			skip;
		}
	}
}

# Placeholder mark functions
marktable(t: ref Table) {}
markfunction(f: ref Function) {}
markuserdata(u: ref Userdata) {}
markthread(th: ref Thread) {}

# ====================================================================
# Module Interface
# ====================================================================

# Initialize upvalue system
initupvals(L: ref State)
{
	L.upvalhead = nil;
}

# Find upvalue (public interface)
findupval(L: ref State, level, pos: int): ref Upval
{
	return findupval(L, level, pos);
}

# Close upvalue (public interface)
closeupval(L: ref State, uv: ref Upval)
{
	closeupval(L, uv);
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
		"Upvalue Management",
		"Handles open and closed upvalues for closures",
	};
}
