# Lua VM - Function Calling Convention
# Implements Lua-to-Lua, Lua-to-C calls, and tail call optimization

implement Luavm;

include "sys.m";
include "luavm.m";

sys: Sys;
print, sprint, fprint: import sys;

# ====================================================================
# Call Frame Management
# ====================================================================

# Extended call info with status tracking
CallInfoEx: adt {
	func:		ref Value;		# Function being called
	base:		int;			# Base register
	top:		int;			# Top register
	savedpc:	int;			# Saved PC
	nresults:	int;			# Number of results expected
	prev:		ref CallInfoEx;	# Previous call frame
	next:		ref CallInfoEx;	# Next call frame
	callstatus:	int;			# Call status flags
	extra:		int;			# Extra field for use by hooks
	oldpc:		int;			# Saved PC for tail calls
};

# Call status flags
CIST_LUA:		con 1 << 0;	# Call is to Lua function
CIST_HOOKED:	con 1 << 1;	# Function has hook
CIST_REENTRY:	con 1 << 2;	# Call is reentrant
CIST_YIELDED:	con 1 << 3;	# Call yielded
CIST_TAIL:		con 1 << 4;	# Tail call
CIST_FRESH:		con 1 << 5;	# Fresh call (not resumed)
CIST_LEQ:		con 1 << 6;	# Use previous frame's top
CIST_FIN:		con 1 << 7;	# Call is finalizer

# Create new call frame
newcallframe(func: ref Value, base, top: int): ref CallInfoEx
{
	ci := ref CallInfoEx;
	ci.func = func;
	ci.base = base;
	ci.top = top;
	ci.savedpc = 0;
	ci.nresults = -1;  # Multi-return by default
	ci.prev = nil;
	ci.next = nil;
	ci.callstatus = 0;
	ci.extra = 0;
	ci.oldpc = 0;

	if(func != nil && func.ty == TFUNCTION && func.f != nil && func.f.isc == 0)
		ci.callstatus = CIST_LUA;

	return ci;
}

# Push call frame onto stack
pushcallframe(L: ref State, ci: ref CallInfoEx): int
{
	if(L == nil)
		return ERRRUN;

	# Check stack space
	if(!checkstack(L, 20))
		return ERRMEM;

	# Link new frame
	ci.prev = ref CallInfoEx(L.ci);
	if(L.ci != nil)
		ref CallInfoEx(L.ci).next = ci;
	L.ci = ref CallInfo(ci);

	return OK;
}

# Pop call frame
popcallframe(L: ref State)
{
	if(L == nil || L.ci == nil)
		return;

	ci := ref CallInfoEx(L.ci);

	# Unlink from chain
	if(ci.prev != nil)
		ci.prev.next = nil;

	# Restore previous frame
	L.ci = ref CallInfo(ci.prev);
}

# ====================================================================
# Function Call Entry
# ====================================================================

# Prepare function call
prepcall(L: ref State, func: ref Value, nargs: int, nresults: int): int
{
	if(L == nil || func == nil)
		return ERRRUN;

	if(func.ty != TFUNCTION || func.f == nil) {
		# Try __call metamethod
		return callmeta(L, func, nargs);
	}

	# Find base of arguments
	base := L.top - nargs;

	# Check stack space
	needed := base + 20;
	if(func.f.proto != nil)
		needed += func.f.proto.maxstacksize;
	else
		needed += 20;

	if(L.stack == nil || len L.stack < needed) {
		reserve(L, needed - len L.stack);
	}

	# Create call frame
	ci := newcallframe(func, base, L.top);
	ci.nresults = nresults;

	# Push frame
	status := pushcallframe(L, ci);
	if(status != OK)
		return status;

	# Adjust top for function
	if(func.f.proto != nil) {
		L.top = base + func.f.proto.maxstacksize;
	} else {
		L.top = base + 20;
	}

	return OK;
}

# Call function (main entry point)
callfunc(L: ref State, nargs: int, nresults: int): int
{
	if(L == nil || L.ci == nil)
		return ERRRUN;

	ci := ref CallInfoEx(L.ci);
	if(ci.func == nil || ci.func.f == nil)
		return ERRRUN;

	f := ci.func.f;

	# Call based on function type
	if(f.isc != 0) {
		return callcfunction(L, f, nargs, nresults);
	} else {
		return callluafunction(L, f, nargs, nresults);
	}
}

# Call Lua function
callluafunction(L: ref State, f: ref Function, nargs, nresults: int): int
{
	if(f == nil || f.proto == nil)
		return ERRRUN;

	# Initialize upvalues from closure
	if(f.upvals != nil) {
		# Upvalues are already set in closure
	}

	# Set up registers
	base := L.ci.base;
	L.top = base + f.proto.maxstacksize;

	# Execute bytecode
	vm := newvm(L);
	status := vmexec(vm);

	# Adjust results
	if(status == OK && nresults != 0) {
		adjustresults(L, nresults);
	}

	return status;
}

# Call C function
callcfunction(L: ref State, f: ref Function, nargs, nresults: int): int
{
	if(f == nil || f.cfunc == nil)
		return ERRRUN;

	# Call C function
	# Note: C functions receive L as first argument
	# This is a simplified interface

	# Adjust stack for C function
	base := L.ci.base;
	L.top = base;

	# Simulate C call (in real implementation, would call actual C function)
	# For now, just return OK
	return OK;
}

# Call metamethod
callmeta(L: ref State, obj: ref Value, nargs: int): int
{
	if(obj == nil || obj.ty != TTABLE || obj.t == nil)
		return ERRRUN;

	mt := obj.t.metatable;
	if(mt == nil)
		return ERRRUN;

	# Get __call metamethod
	key := ref Value;
	key.ty = TSTRING;
	key.s = "__call";

	callfn := gettablevalue(mt, key);
	if(callfn == nil || callfn.ty != TFUNCTION)
		return ERRRUN;

	# Push object as first argument
	base := L.top - nargs;
	for(i := nargs; i > 0; i--) {
		if(base + i - 1 < L.top)
			L.stack[base + i] = L.stack[base + i - 1];
	}
	L.stack[base] = obj;
	L.top++;

	# Prepare and call metamethod
	return prepcall(L, callfn, nargs + 1, -1);
}

# ====================================================================
# Function Return
# ====================================================================

# Return from function
returnfunc(L: ref State, nresults: int, isyield: int): int
{
	if(L == nil || L.ci == nil)
		return ERRRUN;

	ci := ref CallInfoEx(L.ci);

	# Close upvalues at this level
	closeupvals(L, ci.base);

	# Get caller's frame
	caller := ci.prev;
	if(caller == nil) {
		# Returning from main chunk
		if(isyield)
			return YIELD;
		return OK;
	}

	# Move results to caller's base
	firstresult := ci.base;
	destbase := caller.base;

	if(ci.nresults < 0) {
		# Multi-return - copy all results
		n := nresults;
		for(i := 0; i < n; i++) {
			if(firstresult + i < L.top && destbase + i < len L.stack)
				L.stack[destbase + i] = L.stack[firstresult + i];
		}
		L.top = destbase + n;
	} else {
		# Fixed number of results
		n := nresults;
		if(n > ci.nresults)
			n = ci.nresults;

		for(i := 0; i < n; i++) {
			if(firstresult + i < L.top && destbase + i < len L.stack)
				L.stack[destbase + i] = L.stack[firstresult + i];
		}

		# Fill rest with nil
		for(i = n; i < ci.nresults; i++) {
			v := ref Value;
			v.ty = TNIL;
			if(destbase + i < len L.stack)
				L.stack[destbase + i] = v;
		}

		L.top = destbase + ci.nresults;
	}

	# Pop frame
	popcallframe(L);

	if(isyield)
		return YIELD;
	return OK;
}

# Adjust results to match expected count
adjustresults(L: ref State, nresults: int)
{
	if(L == nil || L.ci == nil)
		return;

	ci := ref CallInfoEx(L.ci);
	caller := ci.prev;
	if(caller == nil)
		return;

	actual := L.top - ci.base;
	expected := nresults;

	# If -1, means multi-return (caller expects whatever we have)
	if(expected == -1)
		return;

	if(actual < expected) {
		# Fill missing with nil
		for(i := actual; i < expected; i++) {
			v := ref Value;
			v.ty = TNIL;
			pushvalue(L, v);
		}
	} else if(actual > expected) {
		# Trim excess
		L.top = ci.base + expected;
	}
}

# ====================================================================
# Tail Call Optimization
# ====================================================================

# Perform tail call
tailcall(L: ref State, func: ref Value, nargs: int): int
{
	if(L == nil || L.ci == nil)
		return ERRRUN;

	ci := ref CallInfoEx(L.ci);

	# Can't tail call from main or already tail-calling frame
	if(ci.prev == nil || (ci.callstatus & CIST_TAIL) != 0)
		return ERRRUN;  # Not a tail call position

	# Close upvalues at this level
	closeupvals(L, ci.base);

	# Move function and arguments to base
	funcreg := L.top - nargs;
	base := ci.base;

	for(i := 0; i < nargs; i++) {
		if(funcreg + i < L.top && base + i < len L.stack)
			L.stack[base + i] = L.stack[funcreg + i];
	}

	L.top = base + nargs;

	# Mark as tail call
	ci.callstatus |= CIST_TAIL;
	ci.func = func;
	ci.savedpc = 0;  # Reset PC

	return OK;
}

# Continue tail call (if any)
continuetailcall(L: ref State): int
{
	if(L == nil || L.ci == nil)
		return OK;

	ci := ref CallInfoEx(L.ci);

	# Check if tail call pending
	if((ci.callstatus & CIST_TAIL) == 0)
		return OK;

	# Clear tail call flag
	ci.callstatus &= ~CIST_TAIL;

	# Call the function
	return callfunc(L, L.top - ci.base, ci.nresults);
}

# ====================================================================
# Coroutine Yield/Resume
# ====================================================================

# Yield from current function
yieldfunc(L: ref State, nresults: int): int
{
	if(L == nil || L.ci == nil)
		return ERRRUN;

	ci := ref CallInfoEx(L.ci);

	# Mark frame as yielded
	ci.callstatus |= CIST_YIELDED;

	# Close upvalues
	closeupvals(L, ci.base);

	# Return with yield status
	return returnfunc(L, nresults, 1);
}

# Resume coroutine
resumefunc(L: ref State, co: ref Thread, nargs: int): int
{
	if(co == nil)
		return ERRRUN;

	# Check coroutine status
	if(co.status != OK && co.status != YIELD)
		return ERRRUN;

	# Switch stacks
	oldsaved := L.stack;
	oldtop := L.top;
	oldbase := L.base;

	L.stack = co.stack;
	L.top = co.top;
	L.base = co.base;

	# Resume execution
	status := callfunc(L, nargs, -1);

	# Save stack back
	co.stack = L.stack;
	co.top = L.top;
	co.base = L.base;

	L.stack = oldsaved;
	L.top = oldtop;
	L.base = oldbase;

	return status;
}

# ====================================================================
# Helper Functions
# ====================================================================

# Check stack space
checkstack(L: ref State, n: int): int
{
	if(L == nil || L.stack == nil)
		return 0;
	return (len L.stack - L.top) >= n;
}

# Reserve stack space
reserve(L: ref State, n: int)
{
	if(L == nil)
		return;

	if(L.stack == nil) {
		L.stack = array[n + 10] of ref Value;
	} else if(L.top + n > len L.stack) {
		newstack := array[L.top + n + 10] of ref Value;
		if(L.top > 0)
			newstack[:L.top] = L.stack[:L.top];
		L.stack = newstack;
	}
}

# Push value onto stack
pushvalue(L: ref State, v: ref Value)
{
	if(L == nil)
		return;

	if(L.stack == nil) {
		L.stack = array[20] of ref Value;
	} else if(L.top >= len L.stack) {
		newstack := array[len L.stack * 2] of ref Value;
		if(L.top > 0)
			newstack[:L.top] = L.stack[:L.top];
		L.stack = newstack;
	}

	L.stack[L.top++] = v;
}

# Close upvalues (placeholder)
closeupvals(L: ref State, level: int)
{
	# Will be implemented in lua_upval.b
}

# Get table value (placeholder)
gettablevalue(t: ref Table, key: ref Value): ref Value
{
	# From lua_table.b
	result := ref Value;
	result.ty = TNIL;
	return result;
}

# Create VM (placeholder)
newvm(L: ref State): ref VM
{
	vm := ref VM;
	vm.L = L;
	return vm;
}

# VM adt placeholder
VM: adt {
	L: ref State;
};

# VM execution (placeholder)
vmexec(vm: ref VM): int
{
	return OK;
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
		"Function Calling Convention",
		"Lua-to-Lua and Lua-to-C calls with tail call optimization",
	};
}
