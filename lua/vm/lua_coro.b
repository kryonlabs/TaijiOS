# Lua VM - Coroutine Operations
# Implements coroutine.create, resume, yield, status, wrap, etc.

implement Luavm;

include "sys.m";
include "luavm.m";
include "lua_thread.m";

sys: Sys;
print, sprint, fprint: import sys;

# ====================================================================
# Coroutine Creation
# ====================================================================

# Create new coroutine
createco(L: ref State, func: ref Value): ref Thread
{
	if(L == nil || func == nil || func.ty != TFUNCTION)
		return nil;

	# Create new thread
	th := newthread(L);
	if(th == nil)
		return nil;

	# Push function onto thread stack
	pushthreadvalue(th, func);

	# Initialize first call frame
	th.ci = ref CallInfo;
	th.ci.func = func;
	th.ci.base = 0;
	th.ci.top = 1;
	th.ci.savedpc = 0;
	th.ci.nresults = -1;
	th.ci.prev = nil;
	th.ci.next = nil;

	return th;
}

# ====================================================================
# Coroutine Resume
# ====================================================================

# Resume coroutine execution
resumeco(L: ref State, co: ref Thread, nargs: int): int
{
	if(L == nil || co == nil)
		return ERRRUN;

	# Check coroutine status
	if(!isalive(co)) {
		# Cannot resume dead coroutine
		pushstring(L, "cannot resume dead coroutine");
		return ERRRUN;
	}

	# Check if resuming self
	if(co == runningthread()) {
		pushstring(L, "cannot resume non-suspended coroutine");
		return ERRRUN;
	}

	# Save current state (main thread)
	savedstack := L.stack;
	savedtop := L.top;
	savedbase := L.base;
	savedci := L.ci;

	# Get function from coroutine stack
	if(co.top < 1) {
		setthreadstatus(co, ERRRUN);
		return ERRRUN;
	}

	func := co.stack[0];

	# Push arguments onto coroutine stack
	argstart := 1;
	for(i := 0; i < nargs; i++) {
		# Get argument from main stack
		if(L.top > nargs - i) {
			arg := L.stack[L.top - nargs + i];
			pushthreadvalue(co, arg);
		}
	}

	# Set coroutine base
	co.base = 0;

	# Set coroutine top
	if(func.f != nil && func.f.proto != nil)
		co.top = func.f.proto.maxstacksize;
	else
		co.top = 20;

	# Switch to coroutine
	L.stack = co.stack;
	L.top = co.top;
	L.base = co.base;
	L.ci = co.ci;

	# Execute coroutine
	status := OK;
	if(func.f.isc != 0) {
		# C function
		status = callcfunc(L, nargs + 1, -1);
	} else {
		# Lua function
		vm := newvm(L);
		status = vmexec(vm);
	}

	# Check if coroutine yielded
	if(status == YIELD) {
		# Coroutine yielded
		co.status = YIELD;
		setthreadstatus(co, YIELD);
	} else {
		# Coroutine finished or errored
		co.status = status;
		setthreadstatus(co, status);
	}

	# Restore main thread state
	L.stack = savedstack;
	L.top = savedtop;
	L.base = savedbase;
	L.ci = savedci;

	# Push results onto main stack
	# Count results from coroutine
	nresults := 0;
	if(co.stack != nil && co.top > 0) {
		# Results are at top of coroutine stack
		# For now, just push status
		if(status == OK) {
			pushboolean(L, 1);
			nresults = 1;

			# Push any return values
			# (simplified - would copy from co.stack)
		} else {
			pushboolean(L, 0);
			pushstring(L, "coroutine error");
			nresults = 2;
		}
	} else {
		pushboolean(L, 0);
		nresults = 1;
	}

	return nresults;
}

# ====================================================================
# Coroutine Yield
# ====================================================================

# Yield from coroutine
yieldco(L: ref State, nresults: int): int
{
	if(L == nil)
		return ERRRUN;

	# Check if we can yield
	if(!isyieldable(L)) {
		pushstring(L, "attempt to yield from outside a coroutine");
		return ERRRUN;
	}

	# Get current thread (would be tracked in full implementation)
	th := runningthread();
	if(th == nil) {
		pushstring(L, "attempt to yield from outside a coroutine");
		return ERRRUN;
	}

	# Save yield results
	# In full implementation, would copy to parent thread

	# Mark as yielded
	setthreadstatus(th, YIELD);

	return YIELD;
}

# ====================================================================
# Coroutine Status
# ====================================================================

# Get coroutine status string
getcostatus(co: ref Thread): string
{
	if(co == nil)
		return "dead";

	return getstatus(co);
}

# ====================================================================
# Coroutine Wrap
# ====================================================================

# Wrap coroutine (returns function that resumes coroutine)
wrapco(L: ref State, func: ref Value): ref Function
{
	if(L == nil || func == nil)
		return nil;

	# Create wrapped function
	wrapped := ref Function;
	wrapped.isc = 0;
	wrapped.proto = nil;
	wrapped.env = L.global;
	wrapped.upvals = nil;

	# Store coroutine reference
	# In full implementation, would create closure with coroutine as upvalue

	return wrapped;
}

# Call wrapped function
callwrapped(L: ref State, co: ref Thread, nargs: int): int
{
	if(L == nil || co == nil)
		return ERRRUN;

	# Just resume the coroutine
	return resumeco(L, co, nargs);
}

# ====================================================================
# Coroutine Running
# ====================================================================

# Get currently running coroutine
runningco(L: ref State): ref Thread
{
	if(L == nil)
		return nil;

	# In full implementation, would track current thread
	# For now, nil indicates main thread
	return nil;
}

# ====================================================================
# Coroutine Auxiliary Functions
# ====================================================================

# Check if coroutine is yieldable
isyieldableco(L: ref State): int
{
	return isyieldable(L);
}

# Get main coroutine
mainco(L: ref State): ref Thread
{
	# Main thread is not a real coroutine
	return nil;
}

# ====================================================================
# Coroutine Error Handling
# ====================================================================

# Wrap coroutine call with error handling
resumecoprotected(L: ref State, co: ref Thread, nargs: int): int
{
	if(L == nil || co == nil)
		return ERRRUN;

	# Try to resume
	status := resumeco(L, co, nargs);

	# Handle errors
	if(status != OK && status != YIELD) {
		# Error occurred
		pushboolean(L, 0);

		# Error message already pushed by resumeco
		return 2;
	}

	return status;
}

# ====================================================================
# Coroutine Utilities
# ====================================================================

# Copy coroutine
copyco(src: ref Thread): ref Thread
{
	if(src == nil)
		return nil;

	dst := newthread(src.parent);

	# Copy status
	dst.status = src.status;

	# Copy stack (simplified)
	if(src.stack != nil) {
		dst.stack = array[len src.stack] of ref Value;
		dst.stack[:src.top] = src.stack[:src.top];
		dst.top = src.top;
		dst.base = src.base;
	}

	# Copy call info (shallow copy)
	dst.ci = src.ci;

	return dst;
}

# Merge coroutine state
mergeco(dst, src: ref Thread)
{
	if(dst == nil || src == nil)
		return;

	dst.status = src.status;
	dst.base = src.base;
	dst.top = src.top;
	dst.ci = src.ci;

	# Copy stack
	if(src.stack != nil) {
		if(dst.stack == nil || len dst.stack < src.top)
			growthreadstack(dst, src.top);
		dst.stack[:src.top] = src.stack[:src.top];
	}
}

# ====================================================================
# Coroutine Debugging
# ====================================================================

# Get coroutine info
getcoinfo(co: ref Thread): list of string
{
	if(co == nil)
		return nil;

	info: list of string;

	info = list of {sprint("Status: %s", getcostatus(co))} + info;
	info = list of {sprint("Stack size: %d", co.top)} + info;
	info = list of {sprint("Alive: %s", isalive(co) ? "yes" : "no")} + info;

	if(co.ci != nil) {
		info = list of {"Has call info"} + info;
	}

	return info;
}

# Compare coroutines
equalco(a, b: ref Thread): int
{
	if(a == nil && b == nil)
		return 1;
	if(a == nil || b == nil)
		return 0;
	return a == b;
}

# ====================================================================
# Helper Functions (from other modules)
# ====================================================================

# Push values
pushstring(L: ref State, s: string)
{
	if(L == nil)
		return;
	v := ref Value;
	v.ty = TSTRING;
	v.s = s;
	if(L.stack != nil && L.top < len L.stack)
		L.stack[L.top++] = v;
}

pushboolean(L: ref State, b: int)
{
	if(L == nil)
		return;
	v := ref Value;
	v.ty = TBOOLEAN;
	v.b = b;
	if(L.stack != nil && L.top < len L.stack)
		L.stack[L.top++] = v;
}

# Value operations
typename(v: ref Value): string
{
	if(v == nil)
		return "no value";
	case(v.ty) {
	TNIL =>	return "nil";
	TBOOLEAN =>	return "boolean";
	TNUMBER =>	return "number";
	TSTRING =>	return "string";
	TTABLE =>	return "table";
	TFUNCTION =>	return "function";
	TUSERDATA =>	return "userdata";
	TTHREAD =>	return "thread";
	* =>	return "unknown";
	}
}

tostring(v: ref Value): string
{
	if(v == nil)
		return "nil";
	case(v.ty) {
	TNIL =>	return "nil";
	TBOOLEAN =>	return v.b != 0 ? "true" : "false";
	TNUMBER =>	return sprint("%g", v.n);
	TSTRING =>	return v.s;
	* =>	return sprint("%p", v);
	}
}

# Thread operations from lua_thread.b
newthread(L: ref State): ref Thread
{
	th := ref Thread;
	th.status = OK;
	th.stack = array[20] of ref Value;
	th.ci = nil;
	th.base = 0;
	th.top = 0;
	th.parent = L;
	return th;
}

growthreadstack(th: ref Thread, needed: int): int
{
	if(th == nil)
		return ERRMEM;
	newsize := len th.stack * 2;
	if(newsize < needed)
		newsize = needed + 20;
	newstack := array[newsize] of ref Value;
	newstack[:th.top] = th.stack[:th.top];
	th.stack = newstack;
	return OK;
}

pushthreadvalue(th: ref Thread, v: ref Value)
{
	if(th == nil || th.stack == nil)
		return;
	if(th.top >= len th.stack)
		growthreadstack(th, th.top + 1);
	th.stack[th.top++] = v;
}

savethreadcontext(L: ref State, th: ref Thread) {}
loadthreadcontext(th: ref Thread, L: ref State) {}
getstatus(th: ref Thread): string { return "unknown"; }
isalive(th: ref Thread): int { return th != nil && (th.status == OK || th.status == YIELD); }
setthreadstatus(th: ref Thread, status: int) { if(th != nil) th.status = status; }
isyieldable(L: ref State): int { return L != nil && L.ci != nil && L.ci.prev != nil; }
runningthread(): ref Thread { return nil; }

# C function call
callcfunc(L: ref State, nargs, nresults: int): int { return OK; }

# VM execution
newvm(L: ref State): ref VM
{
	vm := ref VM;
	vm.L = L;
	return vm;
}

vmexec(vm: ref VM): int { return OK; }

VM: adt { L: ref State; };

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
		"Coroutine Operations",
		"Implements create, resume, yield, status, wrap",
	};
}
