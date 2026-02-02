# Lua VM - Functions and Closures
# Implements LClosure (Lua functions) and CClosure (C functions)

implement Luavm;

include "sys.m";
include "luavm.m";

sys: Sys;
print, sprint, fprint: import sys;

# ====================================================================
# Closure Types
# ====================================================================

# Create new Lua closure (with prototype)
newluaclosure(proto: ref Proto, env: ref Table): ref Function
{
	f := ref Function;
	f.isc = 0;  # Lua closure
	f.proto = proto;
	f.cfunc = nil;

	# Allocate upvalue array
	if(proto != nil && proto.upvalues != nil) {
		nupvals := len proto.upvalues;
		if(nupvals > 0) {
			f.upvals = array[nupvals] of ref Upval;
			for(i := 0; i < nupvals; i++)
				f.upvals[i] = nil;
		} else {
			f.upvals = nil;
		}
	} else {
		f.upvals = nil;
	}

	# Set environment
	f.env = env;
	if(f.env == nil)
		f.env = getglobalenv();

	return f;
}

# Create new C closure (for host integration)
newcclosure(func: fn(nil, pointer): int, nupvals: int): ref Function
{
	f := ref Function;
	f.isc = 1;  # C closure
	f.proto = nil;
	f.cfunc = func;

	# Allocate upvalue array
	if(nupvals > 0) {
		f.upvals = array[nupvals] of ref Upval;
		for(i := 0; i < nupvals; i++)
			f.upvals[i] = nil;
	} else {
		f.upvals = nil;
	}

	# C closures use global environment
	f.env = getglobalenv();

	return f;
}

# Get closure environment
getfenv(f: ref Function): ref Table
{
	if(f == nil)
		return nil;
	return f.env;
}

# Set closure environment
setfenv(f: ref Function, env: ref Table)
{
	if(f == nil)
		return;
	f.env = env;
}

# Check if function is Lua closure
isluaclosure(f: ref Function): int
{
	if(f == nil)
		return 0;
	return f.isc == 0;
}

# Check if function is C closure
iscclosure(f: ref Function): int
{
	if(f == nil)
		return 0;
	return f.isc == 1;
}

# Get function prototype (for Lua closures)
getproto(f: ref Function): ref Proto
{
	if(f == nil || f.isc != 0)
		return nil;
	return f.proto;
}

# Get number of upvalues
getnupvals(f: ref Function): int
{
	if(f == nil || f.upvals == nil)
		return 0;
	return len f.upvals;
}

# Get upvalue from closure
getupval(f: ref Function, idx: int): ref Upval
{
	if(f == nil || f.upvals == nil)
		return nil;
	if(idx < 0 || idx >= len f.upvals)
		return nil;
	return f.upvals[idx];
}

# Set upvalue in closure
setupval(f: ref Function, idx: int, uv: ref Upval)
{
	if(f == nil || f.upvals == nil)
		return;
	if(idx < 0 || idx >= len f.upvals)
		return;
	f.upvals[idx] = uv;
}

# ====================================================================
# Function Call Protocol
# ====================================================================

# Call frame structure (extends CallInfo)
CallInfo: adt {
	func:		ref Value;		# Function being called
	base:		int;			# Base register
	top:		int;			# Top register
	savedpc:	int;			# Saved PC
	nresults:	int;			# Number of results expected
	prev:		ref CallInfo;	# Previous call frame
	callstatus:	int;			# Call status flags
};

# Call status flags
CISTLua:		con 1 << 0;	# Call is to Lua function
CIST hooked:	con 1 << 1;	# Function has hook
CIST_REENTRY:	con 1 << 2;	# Call is reentrant
CIST_YIELDED:	con 1 << 3;	# Call yielded
CIST_TAIL:	con 1 << 4;	# Tail call
CIST_FRESH:	con 1 << 5;	# Fresh call (not resumed)

# Prepare function call
prepcall(L: ref State, func: ref Value, nargs: int): int
{
	if(func == nil || func.ty != TFUNCTION)
		return ERRRUN;

	# Check stack space
	if(!checkstack(L, nargs + 20))  # Extra space for call frame
		return ERRMEM;

	# Create new call info frame
	ci := ref CallInfo;
	ci.func = func;
	ci.base = L.top - nargs;
	ci.top = L.top;
	ci.savedpc = 0;
	ci.nresults = -1;  # Multi-return by default
	ci.prev = L.ci;
	ci.callstatus = 0;

	if(func.f.isc != 0) {
		# C function
		ci.callstatus |= CISTLua;
	}

	# Link new frame
	L.ci = ci;

	return OK;
}

# Finish function call
finishcall(L: ref State, nresults: int)
{
	ci := L.ci;
	if(ci == nil)
		return;

	# Move results to caller's base if needed
	if(ci.nresults >= 0 && ci.prev != nil) {
		# Adjust results
		firstresult := ci.base;
		if(nresults > ci.nresults)
			nresults = ci.nresults;

		# Copy results to previous frame's base
		destbase := ci.prev.base;
		for(i := 0; i < nresults; i++) {
			if(firstresult + i < L.top)
				L.stack[destbase + i] = L.stack[firstresult + i];
		}
	}

	# Restore previous frame
	L.ci = ci.prev;
	L.top = ci.base;
}

# Call Lua function
callluafunc(L: ref State, nargs: int): int
{
	ci := L.ci;
	if(ci == nil || ci.func == nil || ci.func.f == nil)
		return ERRRUN;

	f := ci.func.f;
	if(f.proto == nil)
		return ERRRUN;

	# Adjust stack size for function
	needed := f.proto.maxstacksize;
	if(L.top - ci.base < needed) {
		# Grow stack
		settop(L, ci.base + needed);
	}

	# Execute function bytecode
	vm := newvm(L);
	vm.base = ci.base;
	vm.top = L.top;
	vm.ci = ci;
	vm.pc = 0;

	status := vmexec(vm);

	return status;
}

# Call C function
callcfunc(L: ref State, nargs: int): int
{
	ci := L.ci;
	if(ci == nil || ci.func == nil || ci.func.f == nil)
		return ERRRUN;

	f := ci.func.f;
	if(f.cfunc == nil)
		return ERRRUN;

	# Call C function
	nresults := f.cfunc(nil, pointer 0);

	# Adjust stack
	L.top = ci.base + nresults;

	return OK;
}

# Tail call optimization
tailcall(L: ref State, func: ref Value, nargs: int): int
{
	ci := L.ci;
	if(ci == nil)
		return ERRRUN;

	# Check if we can do tail call
	if(ci.prev == nil || (ci.callstatus & CIST_FRESH) != 0)
		return ERRRUN;  # Can't tail call from main or fresh frame

	# Close upvalues at current level
	closeupvals(L, ci.base);

	# Move new function and arguments to current base
	funcreg := L.top - nargs;
	for(i := 0; i < nargs; i++) {
		if(funcreg + i < L.top)
			L.stack[ci.base + i] = L.stack[funcreg + i];
	}

	# Mark as tail call
	ci.callstatus |= CIST_TAIL;

	# Set new function
	ci.func = func;

	return OK;
}

# Return from function
returnfromfunc(L: ref State, nresults: int): int
{
	ci := L.ci;
	if(ci == nil)
		return ERRRUN;

	# If tail call, continue with tail-called function
	if((ci.callstatus & CIST_TAIL) != 0) {
		# Tail call - don't return yet
		return OK;
	}

	# Close upvalues
	closeupvals(L, ci.base);

	# Finish call
	finishcall(L, nresults);

	return OK;
}

# Yield from coroutine
yieldfunc(L: ref State, nresults: int): int
{
	ci := L.ci;
	if(ci == nil)
		return ERRRUN;

	# Mark as yielded
	ci.callstatus |= CIST_YIELDED;

	return YIELD;
}

# ====================================================================
# Upvalue Access from Closures
# ====================================================================

# Get upvalue value from closure
getupvalvalue(f: ref Function, idx: int): ref Value
{
	uv := getupval(f, idx);
	if(uv == nil || uv.v == nil)
		return nil;
	return uv.v;
}

# Set upvalue value in closure
setupvalvalue(f: ref Function, idx: int, val: ref Value)
{
	uv := getupval(f, idx);
	if(uv == nil)
		return;
	uv.v = val;
}

# Clone upvalue (for closing)
cloneupval(uv: ref Upval): ref Upval
{
	if(uv == nil)
		return nil;

	newuv := ref Upval;
	newuv.v = uv.v;
	newuv.refcount = 1;
	return newuv;
}

# Close all upvalues at stack level
closeupvals(L: ref State, level: int)
{
	uv := L.upvalhead;
	prev: ref Upval;

	while(uv != nil) {
		# Check if upvalue points to stack at or above level
		if(isupvalopenat(uv, L.stack, level)) {
			# Close upvalue - move to heap
			closed := closeupval(uv);

			if(prev != nil)
				prev.next = closed;
			else
				L.upvalhead = closed;

			uv = closed.next;
		} else {
			prev = uv;
			uv = uv.next;  # Need next field in Upval adt
		}
	}
}

# Check if upvalue is open and points to stack at level
isupvalopenat(uv: ref Upval, stack: array of ref Value, level: int): int
{
	if(uv == nil || uv.v == nil)
		return 0;

	# Check if value points into stack
	addr := 0;
	# In Limbo, can't directly get address
	# Use heuristic: if value is in stack array

	return 0;  # Placeholder
}

# Close upvalue (move to heap)
closeupval(uv: ref Upval): ref Upval
{
	if(uv == nil)
		return nil;

	# Copy value to heap
	val := uv.v;
	uv.v = val;  # Keep reference

	return uv;
}

# ====================================================================
# Function Metamethods
# ====================================================================

# __call metamethod support
callmetamethod(L: ref State, func: ref Value, nargs: int): int
{
	if(func == nil || func.ty != TTABLE || func.t == nil)
		return ERRRUN;

	# Get __call metamethod
	metatable := func.t.metatable;
	if(metatable == nil)
		return ERRRUN;

	key := ref Value;
	key.ty = TSTRING;
	key.s = "__call";

	callmt := gettablevalue(metatable, key);
	if(callmt == nil || callmt.ty != TFUNCTION)
		return ERRRUN;

	# Call metamethod with function as first argument
	# Move function to make room
	base := L.top - nargs;
	for(i := 0; i < nargs; i++) {
		if(base + i + 1 < L.top)
			L.stack[base + i + 1] = L.stack[base + i];
	}
	L.stack[base] = callmt;
	L.top++;

	# Call the metamethod
	return prepcall(L, callmt, nargs + 1);
}

# ====================================================================
# Helper Functions
# ====================================================================

# Get global environment
getglobalenv(): ref Table
{
	# Return default global environment
	return createtable(0, 32);
}

# Check if there's stack space
checkstack(L: ref State, n: int): int
{
	if(L == nil || L.stack == nil)
		return 0;
	return (len L.stack - L.top) >= n;
}

# Set top of stack (adjusted)
settop(L: ref State, idx: int)
{
	if(L == nil)
		return;

	if(idx < 0)
		idx = L.top + idx + 1;

	if(idx < 0)
		idx = 0;

	if(L.stack == nil) {
		L.stack = array[idx + 10] of ref Value;
	} else if(idx > len L.stack) {
		newstack := array[idx + 10] of ref Value;
		if(L.top > 0)
			newstack[:L.top] = L.stack[:L.top];
		L.stack = newstack;
	}

	if(idx > L.top) {
		for(i := L.top; i < idx; i++) {
			v := ref Value;
			v.ty = TNIL;
			L.stack[i] = v;
		}
	}

	L.top = idx;
}

# VM execution placeholder (will be in lua_vm.b)
vmexec(vm: ref VM): int
{
	return OK;
}

# VM creation placeholder
newvm(L: ref State): ref VM
{
	vm := ref VM;  # VM adt from lua_vm.b
	vm.L = L;
	vm.base = 0;
	vm.top = L.top;
	vm.ci = L.ci;
	vm.pc = 0;
	return vm;
}

# VM adt placeholder
VM: adt {
	L:		ref State;
	base:	int;
	top:	int;
	ci:		ref CallInfo;
	pc:		int;
};

# ====================================================================
# Module Interface Functions
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
		"Functions and Closures",
		"Implements LClosure and CClosure types",
	};
}
