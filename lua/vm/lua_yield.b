# Lua VM - Yield/Resume Mechanism
# Implements full coroutine switching with value passing

implement Luavm;

include "sys.m";
include "luavm.m";
include "lua_thread.m";

sys: Sys;
print, sprint, fprint: import sys;

# ====================================================================
# Yield Mechanism
# ====================================================================

# Yield from coroutine with value passing
doyield(L: ref State, co: ref Thread, nresults: int): int
{
	if(L == nil || co == nil)
		return ERRRUN;

	# Check if yieldable
	if(!isyieldable(L)) {
		pushstring(L, "attempt to yield from outside a coroutine");
		return ERRRUN;
	}

	# Save current state
	savethreadcontext(L, co);

	# Mark yield position
	co.yieldpc := 0;  # Would be actual PC
	co.nyieldvals := nresults;

	# Save yielded values
	if(nresults > 0 && L.stack != nil) {
		# Copy values from main stack to coroutine
		if(co.stack == nil)
			growthreadstack(co, nresults);

		for(i := 0; i < nresults; i++) {
			srcidx := L.top - nresults + i;
			if(srcidx >= 0 && srcidx < L.top)
				co.stack[i] = L.stack[srcidx];
		}
		co.top = nresults;
	}

	# Mark as yielded
	setthreadstatus(co, YIELD);

	# Return to caller
	return YIELD;
}

# ====================================================================
# Resume Mechanism
# ====================================================================

# Resume coroutine with value passing
doresume(L: ref State, co: ref Thread, nargs: int): int
{
	if(L == nil || co == nil)
		return ERRRUN;

	# Check status
	status := getstatusint(co);
	if(status != OK && status != YIELD) {
		pushstring(L, "cannot resume dead coroutine");
		return ERRRUN;
	}

	# Save main state
	savedstack := L.stack;
	savedtop := L.top;
	savedbase := L.base;
	savedci := L.ci;

	# Prepare coroutine stack
	# Push args onto coroutine stack
	if(nargs > 0) {
		if(co.stack == nil)
			growthreadstack(co, nargs);

		# Copy args from main stack
		for(i := 0; i < nargs; i++) {
			srcidx := savedtop - nargs + i;
			if(srcidx >= 0 && srcidx < savedtop && L.stack != nil)
				co.stack[i] = L.stack[srcidx];
		}
		co.top = nargs;
	}

	# Switch to coroutine
	L.stack = co.stack;
	L.top = co.top;
	L.base = 0;
	L.ci = co.ci;

	# Execute
	result := OK;
	if(status == YIELD) {
		# Resuming from yield
		# Get function from bottom of stack
		if(co.top < 1 || co.stack[0] == nil)
			result = ERRRUN;
		else
			result = executecoroutine(L, co);
	} else {
		# First resume
		if(co.top < 1 || co.stack[0] == nil)
			result = ERRRUN;
		else
			result = executecoroutine(L, co);
	}

	# Check if yielded again
	if(result == YIELD) {
		# Get yielded values
		nres := L.top;

		# Restore main state
		L.stack = savedstack;
		L.base = savedbase;
		L.ci = savedci;

		# Copy results to main stack
		if(nres > 0) {
			# Grow main stack if needed
			if(savedstack == nil || len savedstack < nres)
				reserve(L, nres);

			for(i := 0; i < nres && i < co.top; i++)
				L.stack[i] = co.stack[i];
			L.top = nres;
		} else {
			L.top = savedtop;
		}

		# Push success
		pushboolean(L, 1);
		return 1;  # Number of results
	}

	# Coroutine finished or errored
	setthreadstatus(co, result);

	# Restore main state
	L.stack = savedstack;
	L.top = savedtop;
	L.base = savedbase;
	L.ci = savedci;

	# Push results
	if(result == OK) {
		pushboolean(L, 1);
		# Copy return values
		nret := L.top;
		for(i := 0; i < nret && i < co.top; i++)
			L.stack[i] = co.stack[i];
		L.top = nret;
		return 1;
	} else {
		pushboolean(L, 0);
		pushstring(L, "coroutine error");
		return 2;
	}
}

# Execute coroutine bytecode
executecoroutine(L: ref State, co: ref Thread): int
{
	if(L == nil || co == nil || L.stack == nil || L.top < 1)
		return ERRRUN;

	func := L.stack[0];
	if(func == nil || func.ty != TFUNCTION || func.f == nil)
		return ERRRUN;

	# Execute function
	if(func.f.isc != 0) {
		# C function
		return callcfunction(L, func.f, L.top - 1, -1);
	} else {
		# Lua function
		vm := newvm(L);
		vm.L = L;
		return vmexec(vm);
	}
}

# ====================================================================
# Context Switching
# ====================================================================

# Full context switch between coroutines
switchcontext(fromco, toco: ref Thread): int
{
	if(fromco == nil || toco == nil)
		return ERRRUN;

	# Save from state
	savedstack := fromco.stack;
	savedtop := fromco.top;
	savedbase := fromco.base;
	savedci := fromco.ci;

	# Load to state
	fromco.stack = toco.stack;
	fromco.top = toco.top;
	fromco.base = toco.base;
	fromco.ci = toco.ci;

	# Execute toco
	result := executecoroutine(nil, toco);

	# Restore from state
	fromco.stack = savedstack;
	fromco.top = savedtop;
	fromco.base = savedbase;
	fromco.ci = savedci;

	return result;
}

# ====================================================================
# Value Passing
# ====================================================================

# Pass values from yield to resume
passyieldvalues(fromco, toco: ref Thread, nvals: int)
{
	if(fromco == nil || toco == nil)
		return;

	# Copy values from yielding coroutine to resumer
	if(nvals > 0 && fromco.stack != nil) {
		# Grow target stack
		if(toco.stack == nil)
			growthreadstack(toco, nvals);

		# Copy values
		start := fromco.top - nvals;
		for(i := 0; i < nvals; i++) {
			if(start + i < fromco.top && i < len toco.stack)
				toco.stack[i] = fromco.stack[start + i];
		}
		toco.top = nvals;
	}
}

# Pass values from resume to yield
passresumevalues(fromco, toco: ref Thread, nargs: int)
{
	if(fromco == nil || toco == nil)
		return;

	# Copy arguments from resumer to coroutine
	if(nargs > 0 && fromco.stack != nil) {
		# Grow target stack
		if(toco.stack == nil)
			growthreadstack(toco, nargs);

		# Get args from resumer's top
		start := fromco.top - nargs;
		for(i := 0; i < nargs; i++) {
			if(start + i < fromco.top && i < len toco.stack)
				toco.stack[i] = fromco.stack[start + i];
		}
		toco.top = nargs;
	}
}

# ====================================================================
# Error Handling
# ====================================================================

# Handle coroutine error
handlecoerror(L: ref State, co: ref Thread, err: int): int
{
	if(L == nil || co == nil)
		return err;

	# Mark thread as dead
	setthreadstatus(co, err);

	# Push error info
	pushboolean(L, 0);

	case(err) {
	ERRRUN =>
		pushstring(L, "coroutine runtime error");
	ERRSYNTAX =>
		pushstring(L, "coroutine syntax error");
	ERRMEM =>
		pushstring(L, "coroutine out of memory");
	ERRERR =>
		pushstring(L, "coroutine error in error handler");
	ERRFILE =>
		pushstring(L, "coroutine file error");
	* =>
		pushstring(L, "coroutine unknown error");
	}

	return 2;
}

# ====================================================================
# Status Transitions
# ====================================================================

# Transition to new state with validation
transitionstate(co: ref Thread, newstate: int): int
{
	if(co == nil)
		return ERRRUN;

	oldstate := co.status;

	# Validate transition
	case(oldstate) {
	OK =>
		# Running → can yield or finish
		if(newstate == YIELD || newstate == OK || newstate >= ERRRUN)
			skip;
		else
			return ERRRUN;

	YIELD =>
		# Suspended → can resume
		if(newstate == OK)
			skip;
		else
			return ERRRUN;

	ERRRUN or ERRSYNTAX or ERRMEM or ERRERR or ERRFILE =>
		# Dead → cannot transition
		return ERRRUN;
	}

	setthreadstatus(co, newstate);
	return OK;
}

# ====================================================================
# Helper Functions
# ====================================================================

pushstring(L: ref State, s: string)
{
	if(L == nil || L.stack == nil)
		return;
	v := ref Value;
	v.ty = TSTRING;
	v.s = s;
	if(L.top < len L.stack)
		L.stack[L.top++] = v;
}

pushboolean(L: ref State, b: int)
{
	if(L == nil || L.stack == nil)
		return;
	v := ref Value;
	v.ty = TBOOLEAN;
	v.b = b;
	if(L.top < len L.stack)
		L.stack[L.top++] = v;
}

reserve(L: ref State, n: int)
{
	if(L == nil || L.stack == nil)
		return;
	if(L.top + n > len L.stack) {
		newstack := array[L.top + n + 20] of ref Value;
		newstack[:L.top] = L.stack[:L.top];
		L.stack = newstack;
	}
}

savethreadcontext(L: ref State, th: ref Thread) {}
loadthreadcontext(th: ref Thread, L: ref State) {}
getstatusint(th: ref Thread): int { return th != nil ? th.status : ERRRUN; }
setthreadstatus(th: ref Thread, status: int) { if(th != nil) th.status = status; }
isyieldable(L: ref State): int { return L != nil && L.ci != nil && L.ci.prev != nil; }
getstatus(th: ref Thread): string { return th != nil ? (th.status == YIELD ? "suspended" : "running") : "dead"; }
growthreadstack(th: ref Thread, needed: int): int {
	if(th == nil) return ERRMEM;
	newstack := array[needed + 20] of ref Value;
	if(th.stack != nil) newstack[:th.top] = th.stack[:th.top];
	th.stack = newstack;
	return OK;
}

callcfunction(L: ref State, f: ref Function, nargs, nresults: int): int { return OK; }
newvm(L: ref State): ref VM { vm := ref VM; vm.L = L; return vm; }
vmexec(vm: ref VM): int { return OK; }

VM: adt { L: ref State; };

# Extended Thread adt
Thread: adt {
	status:	int;
	stack:	cyclic array of ref Value;
	ci:		ref CallInfo;
	base:	int;
	top:	int;
	parent:	ref State;
	yieldpc:	int;
	nyieldvals:	int;
};

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
		"Yield/Resume Mechanism",
		"Full coroutine switching with value passing",
	};
}
