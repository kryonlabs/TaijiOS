# Lua VM - Thread (Coroutine) States
# Implements separate stacks and status tracking for coroutines

implement Luavm;

include "sys.m";
include "luavm.m";

sys: Sys;
print, sprint, fprint: import sys;

# ====================================================================
# Thread States
# ====================================================================

# Coroutine status codes (from luavm.m)
# OK, YIELD, ERRRUN, ERRSYNTAX, ERRMEM, ERRERR, ERRFILE

# Thread status strings
statusstring(status: int): string
{
	case(status) {
	OK =>
		return "running";
	YIELD =>
		return "suspended";
	ERRRUN or ERRSYNTAX or ERRMEM or ERRERR or ERRFILE =>
		return "dead";
	* =>
		return "unknown";
	}
}

# Get status from thread
getstatus(th: ref Thread): string
{
	if(th == nil)
		return "dead";

	# Check if thread is the current running one
	if(th == runningthread())
		return "running";

	return statusstring(th.status);
}

# Check if thread is alive
isalive(th: ref Thread): int
{
	if(th == nil)
		return 0;
	return th.status == OK || th.status == YIELD;
}

# Check if thread is yieldable at current position
isyieldable(L: ref State): int
{
	if(L == nil || L.ci == nil)
		return 0;

	# Can't yield from main thread
	if(L.ci.prev == nil)
		return 0;

	return 1;
}

# Get currently running thread
runningthread(): ref Thread
{
	# In a full implementation, would track current thread
	# For now, return nil (main thread)
	return nil;
}

# ====================================================================
# Thread Creation
# ====================================================================

# Create new thread
newthread(L: ref State): ref Thread
{
	if(L == nil)
		return nil;

	th := ref Thread;

	# Set initial status
	th.status = OK;

	# Allocate separate stack for thread
	th.stack = array[20] of ref Value;
	th.base = 0;
	th.top = 0;

	# Initialize call info
	th.ci = nil;

	# Link to parent state
	th.parent = L;

	return th;
}

# Reset thread for reuse
resetthread(th: ref Thread)
{
	if(th == nil)
		return;

	th.status = OK;
	th.base = 0;
	th.top = 0;

	# Clear stack
	if(th.stack != nil) {
		for(i := 0; i < len th.stack; i++)
			th.stack[i] = nil;
	}

	th.ci = nil;
}

# ====================================================================
# Thread Stack Management
# ====================================================================

# Grow thread stack
growthreadstack(th: ref Thread, needed: int): int
{
	if(th == nil)
		return ERRMEM;

	current := len th.stack;
	if(current >= needed)
		return OK;

	# Double size or accommodate needed
	newsize := current * 2;
	if(newsize < needed)
		newsize = needed + 20;

	newstack := array[newsize] of ref Value;

	# Copy old stack
	if(th.top > 0)
		newstack[:th.top] = th.stack[:th.top];

	# Initialize new slots
	for(i := th.top; i < newsize; i++) {
		v := ref Value;
		v.ty = TNIL;
		newstack[i] = v;
	}

	th.stack = newstack;
	return OK;
}

# Push value onto thread stack
pushthreadvalue(th: ref Thread, v: ref Value): int
{
	if(th == nil)
		return ERRRUN;

	# Grow stack if needed
	if(th.top >= len th.stack) {
		status := growthreadstack(th, th.top + 1);
		if(status != OK)
			return status;
	}

	th.stack[th.top++] = v;
	return OK;
}

# Pop values from thread stack
popthreadvalues(th: ref Thread, n: int)
{
	if(th == nil)
		return;

	if(n >= th.top)
		th.top = 0;
	else
		th.top -= n;
}

# Get value from thread stack
getthreadvalue(th: ref Thread, idx: int): ref Value
{
	if(th == nil || th.stack == nil)
		return nil;

	# Handle negative indices
	if(idx < 0)
		idx = th.top + idx + 1;

	if(idx < 0 || idx >= th.top)
		return nil;

	return th.stack[idx];
}

# Set thread stack top
setthreadtop(th: ref Thread, top: int)
{
	if(th == nil)
		return;

	if(top < 0)
		top = 0;

	if(top > len th.stack)
		growthreadstack(th, top);

	if(top > th.top) {
		# Fill new slots with nil
		for(i := th.top; i < top; i++) {
			v := ref Value;
			v.ty = TNIL;
			th.stack[i] = v;
		}
	}

	th.top = top;
}

# Get thread stack top
getthreadtop(th: ref Thread): int
{
	if(th == nil)
		return 0;
	return th.top;
}

# ====================================================================
# Thread Status Management
# ====================================================================

# Set thread status
setthreadstatus(th: ref Thread, status: int)
{
	if(th == nil)
		return;

	# If thread dies, clean up
	if(status != OK && status != YIELD) {
		# Thread is dead, can close resources
		closeallupvalues(th);
	}

	th.status = status;
}

# Check thread status
checkthreadstatus(th: ref Thread, expected: int): int
{
	if(th == nil)
		return 0;

	if(expected == OK || expected == YIELD)
		return isalive(th);

	return th.status == expected;
}

# ====================================================================
# Thread Context Switching
# ====================================================================

# Save current context to thread
savethreadcontext(L: ref State, th: ref Thread)
{
	if(L == nil || th == nil)
		return;

	# Save stack
	if(L.stack != nil && L.top > 0) {
		if(th.stack == nil || len th.stack < L.top) {
			growthreadstack(th, L.top);
		}
		th.stack[:L.top] = L.stack[:L.top];
	}
	th.top = L.top;
	th.base = L.base;

	# Save call info chain
	th.ci = L.ci;
}

# Restore context from thread
loadthreadcontext(th: ref Thread, L: ref State)
{
	if(L == nil || th == nil)
		return;

	# Restore stack
	if(th.stack != nil && th.top > 0) {
		if(L.stack == nil || len L.stack < th.top) {
			# Grow main stack
			newstack := array[th.top + 20] of ref Value;
			if(L.stack != nil && L.top > 0)
				newstack[:L.top] = L.stack[:L.top];
			L.stack = newstack;
		}
		L.stack[:th.top] = th.stack[:th.top];
	}
	L.top = th.top;
	L.base = th.base;

	# Restore call info
	L.ci = th.ci;
}

# Swap thread contexts
swapthreadcontext(from, to: ref Thread): int
{
	if(from == nil || to == nil)
		return ERRRUN;

	# Save current context
	savethreadcontext(nil, from);

	# Load new context
	loadthreadcontext(to, nil);

	return OK;
}

# ====================================================================
# Thread Cleanup
# ====================================================================

# Free thread resources
freethread(th: ref Thread)
{
	if(th == nil)
		return;

	# Close all upvalues
	closeallupvalues(th);

	# Clear stack
	th.stack = nil;
	th.base = 0;
	th.top = 0;

	# Clear call info
	th.ci = nil;

	# Mark as dead
	th.status = ERRRUN;  # Any error status means dead
}

# Close all upvalues in thread
closeallupvalues(th: ref Thread)
{
	if(th == nil || th.stack == nil)
		return;

	# Close upvalues at all stack levels
	for(level := 0; level < th.top; level++) {
		# Would call closeupvals for each level
		# This requires upval list tracking per level
	}
}

# ====================================================================
# Thread Debugging
# ====================================================================

# Get thread call stack
getthreadcallstack(th: ref Thread): list of string
{
	if(th == nil)
		return nil;

	stack: list of string;

	# Walk call info chain
	ci := th.ci;
	level := 0;
	while(ci != nil) {
		info := sprint("%d: %s", level, "function");
		stack = list of {info} + stack;
		ci = ci.next;
		level++;
	}

	return stack;
}

# Dump thread state
dumpthreadstate(th: ref Thread): string
{
	if(th == nil)
		return "nil";

	s := sprint("Thread@%p\n", th);
	s += sprint("  Status: %s\n", getstatus(th));
	s += sprint("  Stack: %d/%d\n", th.top, len th.stack);
	s += sprint("  Base: %d\n", th.base);
	s += sprint("  Alive: %s\n", isalive(th) ? "yes" : "no");

	return s;
}

# Dump thread stack
dumpthreadstack(th: ref Thread): string
{
	if(th == nil || th.stack == nil)
		return "empty";

	s := "";
	for(i := 0; i < th.top; i++) {
		v := th.stack[i];
		s += sprint("  [%d] %s: %s\n", i, typename(v), tostring(v));
	}

	return s;
}

# ====================================================================
# Parent Thread (for main thread)
# ====================================================================

# Parent thread reference
Thread: adt {
	status:		int;			# Thread status
	stack:		cyclic array of ref Value;	# Stack
	ci:			ref CallInfo;	# Call info chain
	base:		int;			# Stack base
	top:		int;			# Stack top
	parent:		ref State;		# Parent state
};

# Get parent state from thread
getparentstate(th: ref Thread): ref State
{
	if(th == nil)
		return nil;
	return th.parent;
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
		"Thread (Coroutine) States",
		"Separate stacks and status tracking for coroutines",
	};
}
