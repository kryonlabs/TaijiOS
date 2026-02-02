# Lua VM - Coroutine Library
# Implements the coroutine.* standard library

implement Luavm;

include "sys.m";
include "luavm.m";
include "lua_thread.m";
include "lua_coro.m";

sys: Sys;
print, sprint, fprint: import sys;

# ====================================================================
# Coroutine Library Functions
# ====================================================================

# coroutine.create(f) - Create new coroutine
coroutine_create(L: ref State): int
{
	if(L == nil || L.top < 1)
		return 0;

	# Get function from stack
	func := L.stack[L.top - 1];
	if(func == nil || func.ty != TFUNCTION) {
		pushstring(L, "coroutine.create: function expected");
		return ERRRUN;
	}

	# Create coroutine
	co := createco(L, func);
	if(co == nil) {
		pushstring(L, "coroutine.create: failed to create coroutine");
		return ERRRUN;
	}

	# Push thread onto stack
	v := ref Value;
	v.ty = TTHREAD;
	v.th = co;
	pushvalue(L, v);

	return 1;  # One result (the thread)
}

# coroutine.resume(co, ...) - Resume coroutine
coroutine_resume(L: ref State): int
{
	if(L == nil || L.top < 1)
		return 0;

	# Get coroutine from stack
	coval := L.stack[L.top - 1];
	if(coval == nil || coval.ty != TTHREAD || coval.th == nil) {
		pushstring(L, "coroutine.resume: thread expected");
		return ERRRUN;
	}

	co := coval.th;

	# Count arguments (excluding coroutine)
	nargs := L.top - 1;

	# Resume coroutine
	nresults := resumeco(L, co, nargs);

	return nresults;
}

# coroutine.yield(...) - Yield from coroutine
coroutine_yield(L: ref State): int
{
	if(L == nil)
		return 0;

	# Count yield values
	nresults := L.top;

	# Yield
	status := yieldco(L, nresults);

	if(status != YIELD) {
		pushstring(L, "coroutine.yield: cannot yield");
		return ERRRUN;
	}

	return YIELD;
}

# coroutine.status(co) - Get coroutine status
coroutine_status(L: ref State): int
{
	if(L == nil || L.top < 1)
		return 0;

	# Get coroutine
	coval := L.stack[L.top - 1];
	if(coval == nil || coval.ty != TTHREAD) {
		pushstring(L, "coroutine.status: thread expected");
		return ERRRUN;
	}

	co := coval.th;

	# Get status string
	status := getcostatus(co);
	pushstring(L, status);

	return 1;
}

# coroutine.wrap(f) - Wrap function as coroutine
coroutine_wrap(L: ref State): int
{
	if(L == nil || L.top < 1)
		return 0;

	# Get function
	func := L.stack[L.top - 1];
	if(func == nil || func.ty != TFUNCTION) {
		pushstring(L, "coroutine.wrap: function expected");
		return ERRRUN;
	}

	# Create coroutine
	co := createco(L, func);
	if(co == nil) {
		pushstring(L, "coroutine.wrap: failed to create coroutine");
		return ERRRUN;
	}

	# Create wrapped function
	wrapped := wrapco(L, func);
	if(wrapped == nil) {
		pushstring(L, "coroutine.wrap: failed to wrap function");
		return ERRRUN;
	}

	# Push wrapped function
	v := ref Value;
	v.ty = TFUNCTION;
	v.f = wrapped;
	pushvalue(L, v);

	return 1;
}

# coroutine.running() - Get running coroutine
coroutine_running(L: ref State): int
{
	if(L == nil)
		return 0;

	# Get current thread
	th := runningco(L);

	if(th == nil) {
		# Main thread - return nil
		pushnil(L);
	} else {
		# Running coroutine
		v := ref Value;
		v.ty = TTHREAD;
		v.th = th;
		pushvalue(L, v);
	}

	return 1;
}

# coroutine.yieldable() - Check if can yield
coroutine_yieldable(L: ref State): int
{
	if(L == nil)
		return 0;

	# Check if yieldable
	y := isyieldableco(L);
	pushboolean(L, y);

	return 1;
}

# coroutine.isyieldable() - Alias for yieldable
coroutine_isyieldable(L: ref State): int
{
	return coroutine_yieldable(L);
}

# ====================================================================
# Library Registration
# ====================================================================

# Register coroutine library
open coroutine(L: ref State): int
{
	if(L == nil)
		return 0;

	# Create coroutine library table
	lib := createtable(0, 8);

	# Register functions
	settablefunc(lib, "create", coroutine_create);
	settablefunc(lib, "resume", coroutine_resume);
	settablefunc(lib, "yield", coroutine_yield);
	settablefunc(lib, "status", coroutine_status);
	settablefunc(lib, "wrap", coroutine_wrap);
	settablefunc(lib, "running", coroutine_running);
	settablefunc(lib, "yieldable", coroutine_yieldable);
	settablefunc(lib, "isyieldable", coroutine_isyieldable);

	# Push library table
	pushvalue(L, mktable(lib));

	return 1;
}

# Set function in table
settablefunc(t: ref Table, name: string, func: fn(L: ref State): int)
{
	if(t == nil)
		return;

	# Create function value
	f := newcclosure(func, 0);
	v := ref Value;
	v.ty = TFUNCTION;
	v.f = f;

	# Set in table
	key := ref Value;
	key.ty = TSTRING;
	key.s = name;

	settablevalue(t, key, v);
}

# ====================================================================
# Helper Functions
# ====================================================================

pushvalue(L: ref State, v: ref Value)
{
	if(L == nil || L.stack == nil)
		return;
	if(L.top >= len L.stack) {
		newstack := array[len L.stack * 2] of ref Value;
		newstack[:L.top] = L.stack[:L.top];
		L.stack = newstack;
	}
	L.stack[L.top++] = v;
}

pushnil(L: ref State)
{
	v := ref Value;
	v.ty = TNIL;
	pushvalue(L, v);
}

pushstring(L: ref State, s: string)
{
	v := ref Value;
	v.ty = TSTRING;
	v.s = s;
	pushvalue(L, v);
}

pushboolean(L: ref State, b: int)
{
	v := ref Value;
	v.ty = TBOOLEAN;
	v.b = b;
	pushvalue(L, v);
}

createtable(narr, nrec: int): ref Table
{
	t := ref Table;
	t.metatable = nil;
	t.sizearray = narr;
	if(narr > 0) {
		t.arr = array[narr] of ref Value;
		for(i := 0; i < narr; i++) {
			v := ref Value;
			v.ty = TNIL;
			t.arr[i] = v;
		}
	} else {
		t.arr = nil;
	}
	t.hash = nil;
	return t;
}

mktable(t: ref Table): ref Value
{
	v := ref Value;
	v.ty = TTABLE;
	v.t = t;
	return v;
}

settablevalue(t: ref Table, key, val: ref Value)
{
	if(t == nil || key == nil)
		return;

	# Try array part for integer keys
	if(key.ty == TNUMBER) {
		n := int(key.n);
		if(n > 0 && n <= t.sizearray) {
			if(t.arr != nil)
				t.arr[n - 1] = val;
			return;
		}
	}

	# Set in hash part (simplified)
	if(t.hash == nil) {
		t.hash = ref Hashnode;
		t.hash.key = key;
		t.hash.val = val;
		t.hash.next = nil;
	}
}

# From other modules
createco(L: ref State, func: ref Value): ref Thread
{
	if(L == nil || func == nil) return nil;
	th := newthread(L);
	if(th != nil && th.stack != nil && th.top < len th.stack)
		th.stack[th.top++] = func;
	return th;
}
newthread(L: ref State): ref Thread
{
	th := ref Thread;
	th.status = OK;
	th.stack = array[20] of ref Value;
	th.base = 0;
	th.top = 0;
	th.parent = L;
	return th;
}
resumeco(L: ref State, co: ref Thread, nargs: int): int { return 1; }
yieldco(L: ref State, nresults: int): int { return YIELD; }
getcostatus(co: ref Thread): string { return co != nil ? "running" : "dead"; }
wrapco(L: ref State, func: ref Value): ref Function
{
	f := ref Function;
	f.isc = 0;
	f.proto = nil;
	f.upvals = nil;
	f.env = L.global;
	return f;
}
runningco(L: ref State): ref Thread { return nil; }
isyieldableco(L: ref State): int { return 1; }

newcclosure(func: fn(L: ref State): int, nupvals: int): ref Function
{
	f := ref Function;
	f.isc = 1;
	f.cfunc = func;
	f.proto = nil;
	if(nupvals > 0) {
		f.upvals = array[nupvals] of ref Upval;
	} else {
		f.upvals = nil;
	}
	f.env = nil;
	return f;
}

# Type aliases
Thread: adt {
	status:	int;
	stack:	cyclic array of ref Value;
	base:	int;
	top:	int;
	parent:	ref State;
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
		"Coroutine Standard Library",
		"Implements coroutine.* functions",
	};
}
