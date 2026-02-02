# Lua VM - State Management
# Implements LuaState with stack, global state, and error handling

implement Luavm;

include "sys.m";
include "luavm.m";

sys: Sys;
print, sprint, fprint: import sys;

# Error codes
OK, YIELD, ERRRUN, ERRSYNTAX, ERRMEM, ERRERR, ERRFILE: con iota;

# GC constants
GCSTOP, GCRESTART, GCCOLLECT, GCCOUNT: con iota;
GCCOUNTB, GCSTEP, GCSETPAUSE, GCSETSTEPMUL: con iota;

# Global state
globalstate: ref Global;

# Initialize global state
initglobal(): string
{
	if(globalstate != nil)
		return nil;

	globalstate = ref Global;
	globalstate.strings = nil;  # Will be initialized by string module
	globalstate.registry = nil;
	globalstate.malloc = 0;
	globalstate.gcthreshold = 1024 * 1024;  # 1MB initial threshold

	return nil;
}

# Create new Lua state
newstate(): ref State
{
	if(globalstate == nil)
		initglobal();

	L := ref State;

	# Initialize stack
	L.stack = array[20] of ref Value;
	L.top = 0;
	L.base = 0;

	# Initialize call info
	L.ci = nil;

	# Create global table
	L.global = createtable(0, 32);

	# Create registry
	L.registry = createtable(0, 16);

	# Initialize upvalue list
	L.upvalhead = nil;

	# Initialize error handling
	L.errorjmp = nil;

	return L;
}

# Close Lua state
close(L: ref State)
{
	if(L == nil)
		return;

	# Close all upvalues
	closeallupvalues(L);

	# Clear stack
	L.stack = nil;
	L.top = 0;
	L.base = 0;

	# Clear tables
	L.global = nil;
	L.registry = nil;

	# Clear call info chain
	while(L.ci != nil) {
		ci := L.ci;
		L.ci = ci.next;
		ci.next = nil;
	}

	L.upvalhead = nil;
}

# Push value onto stack with growth
pushvalue(L: ref State, v: ref Value)
{
	if(L == nil)
		return;

	# Check stack space
	if(L.stack == nil) {
		L.stack = array[20] of ref Value;
		L.top = 0;
	}

	# Grow stack if needed (exponential growth)
	if(L.top >= len L.stack) {
		newsize := len L.stack * 2;
		if(newsize < 40)
			newsize = 40;
		newstack := array[newsize] of ref Value;
		if(L.top > 0)
			newstack[:L.top] = L.stack[:L.top];
		L.stack = newstack;
	}

	L.stack[L.top++] = v;
}

# Push nil
pushnil(L: ref State)
{
	v := ref Value;
	v.ty = TNIL;
	pushvalue(L, v);
}

# Push boolean
pushboolean(L: ref State, b: int)
{
	v := ref Value;
	v.ty = TBOOLEAN;
	v.b = b;
	pushvalue(L, v);
}

# Push number
pushnumber(L: ref State, n: real)
{
	v := ref Value;
	v.ty = TNUMBER;
	v.n = n;
	pushvalue(L, v);
}

# Push string
pushstring(L: ref State, s: string)
{
	v := ref Value;
	v.ty = TSTRING;
	v.s = s;
	pushvalue(L, v);
}

# Push table
pushtable(L: ref State, t: ref Table)
{
	v := ref Value;
	v.ty = TTABLE;
	v.t = t;
	pushvalue(L, v);
}

# Push function
pushfunction(L: ref State, f: ref Function)
{
	v := ref Value;
	v.ty = TFUNCTION;
	v.f = f;
	pushvalue(L, v);
}

# Pop n values from stack
pop(L: ref State, n: int)
{
	if(L == nil)
		return;

	if(n < 0)
		n = 0;

	if(n >= L.top) {
		L.top = 0;
	} else {
		L.top -= n;
	}
}

# Remove element at index
remove(L: ref State, idx: int)
{
	if(L == nil || L.stack == nil)
		return;

	# Convert negative index
	if(idx < 0) {
		idx = L.top + idx + 1;
	}

	if(idx < 0 || idx >= L.top)
		return;

	# Shift elements down
	for(i := idx; i < L.top - 1; i++)
		L.stack[i] = L.stack[i + 1];

	L.top--;
}

# Insert value at index
insert(L: ref State, idx: int)
{
	if(L == nil || L.stack == nil || L.top < 1)
		return;

	# Convert negative index
	if(idx < 0) {
		idx = L.top + idx + 1;
	}

	if(idx < 0 || idx > L.top)
		return;

	# Get value from top
	v := L.stack[L.top - 1];

	# Shift elements up
	for(i := L.top - 1; i > idx; i--)
		L.stack[i] = L.stack[i - 1];

	L.stack[idx] = v;
}

# Replace value at index with top value
replace(L: ref State, idx: int)
{
	if(L == nil || L.stack == nil || L.top < 1)
		return;

	# Convert negative index
	if(idx < 0) {
		idx = L.top + idx + 1;
	}

	if(idx < 0 || idx >= L.top)
		return;

	L.stack[idx] = L.stack[L.top - 1];
	pop(L, 1);
}

# Copy value from srcidx to destidx
copy(L: ref State, srcidx, destidx: int)
{
	if(L == nil || L.stack == nil)
		return;

	# Convert negative indices
	if(srcidx < 0) {
		srcidx = L.top + srcidx + 1;
	}
	if(destidx < 0) {
		destidx = L.top + destidx + 1;
	}

	if(srcidx < 0 || srcidx >= L.top || destidx < 0 || destidx >= L.top)
		return;

	L.stack[destidx] = L.stack[srcidx];
}

# Get top of stack
gettop(L: ref State): int
{
	if(L == nil)
		return 0;
	return L.top;
}

# Set top of stack (absolute or relative)
settop(L: ref State, idx: int)
{
	if(L == nil)
		return;

	# Convert negative index
	if(idx < 0) {
		idx = L.top + idx + 1;
	}

	if(idx < 0)
		idx = 0;

	# Grow stack if needed
	if(L.stack == nil) {
		L.stack = array[idx + 10] of ref Value;
	} else if(idx > len L.stack) {
		newsize := idx + 10;
		newstack := array[newsize] of ref Value;
		if(L.top > 0)
			newstack[:L.top] = L.stack[:L.top];
		L.stack = newstack;
	}

	# Fill new slots with nil
	if(idx > L.top) {
		for(i := L.top; i < idx; i++) {
			v := ref Value;
			v.ty = TNIL;
			L.stack[i] = v;
		}
	}

	L.top = idx;
}

# Get value at index (handling absolute and negative indices)
getvalue(L: ref State, idx: int): ref Value
{
	if(L == nil || L.stack == nil)
		return nil;

	# Convert negative index to positive
	if(idx < 0) {
		idx = L.top + idx + 1;
	}

	if(idx < 0 || idx >= L.top)
		return nil;

	return L.stack[idx];
}

# Check stack space
checkstack(L: ref State, sz: int): int
{
	if(L == nil)
		return 0;

	if(L.stack == nil)
		return 0;

	return (len L.stack - L.top) >= sz;
}

# Reserve stack space
reserve(L: ref State, sz: int)
{
	if(L == nil)
		return;

	while(L.stack == nil || (len L.stack - L.top) < sz) {
		newsize := len L.stack * 2;
		if(newsize < L.top + sz)
			newsize = L.top + sz + 10;
		newstack := array[newsize] of ref Value;
		if(L.top > 0)
			newstack[:L.top] = L.stack[:L.top];
		L.stack = newstack;
	}
}

# Upvalue management

# Create new upvalue
newupvalue(L: ref State, val: ref Value): ref Upval
{
	uv := ref Upval;
	uv.v = val;
	uv.refcount = 1;

	# Add to head of upvalue list
	uv.next = L.upvalhead;  # Note: need to add next field to Upval adt
	L.upvalhead = uv;

	return uv;
}

# Find upvalue for stack position
findupvalue(L: ref State, pos: int): ref Upval
{
	uv := L.upvalhead;
	while(uv != nil) {
		# Check if upvalue points to this stack position
		if(uv.v != nil && uv.v == L.stack[pos])
			return uv;
		uv = uv.next;  # Note: need next field
	}

	# Create new upvalue
	return newupvalue(L, L.stack[pos]);
}

# Close all upvalues at or above stack level
closeallupvalues(L: ref State)
{
	# This will be implemented when we add upvalue chaining
	L.upvalhead = nil;
}

# Error handling

# Set error handler
seterrorhandler(L: ref State, idx: int)
{
	if(L == nil)
		return;

	handler := getvalue(L, idx);
	# Store handler in registry
	setfield(L, -10002, "_ERRORHANDLER");  # LUA_REGISTRYINDEX
}

# Get error handler
geterrorhandler(L: ref State): ref Value
{
	if(L == nil)
		return nil;

	# Get from registry
	getfield(L, -10002, "_ERRORHANDLER");
	return getvalue(L, -1);
}

# Raise error
raiseerror(L: ref State, msg: string)
{
	if(L == nil)
		return;

	pushstring(L, msg);

	# Longjmp to error handler (placeholder)
	# In full implementation, this would use setjmp/longjmp
}

# Protected call wrapper
pcall(L: ref State, nargs: int, nresults: int): int
{
	# Placeholder - needs full VM implementation
	return ERRRUN;
}

# Load string (placeholder)
loadstring(L: ref State, s: string): int
{
	# This will be implemented in the parser phase
	return ERRSYNTAX;
}

# Load file (placeholder)
loadfile(L: ref State, filename: string): int
{
	# This will be implemented in the parser phase
	return ERRFILE;
}

# Do file (load and execute)
dofile(L: ref State, filename: string): int
{
	status := loadfile(L, filename);
	if(status != OK)
		return status;

	# Execute (placeholder)
	return ERRRUN;
}

# Do string (load and execute)
dostring(L: ref State, s: string): int
{
	status := loadstring(L, s);
	if(status != OK)
		return status;

	# Execute (placeholder)
	return ERRRUN;
}

# Get global
getglobal(L: ref State, name: string)
{
	getfield(L, -10001, name);  # LUA_GLOBALSINDEX
}

# Set global
setglobal(L: ref State, name: string)
{
	if(L == nil || L.top < 1)
		return;

	v := L.stack[L.top - 1];
	setfield(L, -10001, name);
}

# Registry operations
getregistry(L: ref State)
{
	pushvalue(L, mktable(L.registry));
}

# Table operations
newtable(L: ref State): ref Table
{
	t := createtable(0, 0);
	pushtable(L, t);
	return t;
}

createtable(narr, nrec: int): ref Table
{
	t := ref Table;
	t.metatable = nil;
	t.sizearray = narr;

	# Preallocate array
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

	# Hash table (will be lazy-allocated)
	t.hash = nil;

	return t;
}

getfield(L: ref State, idx: int, k: string)
{
	t := getvalue(L, idx);
	if(t == nil || t.ty != TTABLE || t.t == nil) {
		pushnil(L);
		return;
	}

	key := ref Value;
	key.ty = TSTRING;
	key.s = k;

	v := gettablevalue(t.t, key);
	pushvalue(L, v);
}

setfield(L: ref State, idx: int, k: string)
{
	t := getvalue(L, idx);
	if(t == nil || t.ty != TTABLE || t.t == nil)
		return;

	if(L.top < 1)
		return;

	v := L.stack[L.top - 1];

	key := ref Value;
	key.ty = TSTRING;
	key.s = k;

	settablevalue(t.t, key, v);
}

gettable(L: ref State, idx: int)
{
	t := getvalue(L, idx);
	if(t == nil || t.ty != TTABLE || t.t == nil) {
		pushnil(L);
		return;
	}

	if(L.top < 1)
		return;

	key := L.stack[L.top - 1];
	pop(L, 1);

	v := gettablevalue(t.t, key);
	pushvalue(L, v);
}

settable(L: ref State, idx: int)
{
	t := getvalue(L, idx);
	if(t == nil || t.ty != TTABLE || t.t == nil)
		return;

	if(L.top < 2)
		return;

	v := L.stack[L.top - 1];
	key := L.stack[L.top - 2];
	pop(L, 2);

	settablevalue(t.t, key, v);
}

gettablevalue(t: ref Table, key: ref Value): ref Value
{
	if(t == nil || key == nil)
		return nil;

	result := ref Value;
	result.ty = TNIL;
	return result;
}

settablevalue(t: ref Table, key: ref Value, val: ref Value)
{
	# Placeholder - implemented in lua_table.b
}

# Type checking
typeName(v: ref Value): string
{
	if(v == nil)
		return "no value";

	case(v.ty) {
	TNIL => return "nil";
	TBOOLEAN => return "boolean";
	TNUMBER => return "number";
	TSTRING => return "string";
	TTABLE => return "table";
	TFUNCTION => return "function";
	TUSERDATA => return "userdata";
	TTHREAD => return "thread";
	* => return "unknown";
	}
}

isnil(v: ref Value): int
{
	return v != nil && v.ty == TNIL;
}

isboolean(v: ref Value): int
{
	return v != nil && v.ty == TBOOLEAN;
}

isnumber(v: ref Value): int
{
	return v != nil && v.ty == TNUMBER;
}

isstring(v: ref Value): int
{
	return v != nil && v.ty == TSTRING;
}

istable(v: ref Value): int
{
	return v != nil && v.ty == TTABLE;
}

isfunction(v: ref Value): int
{
	return v != nil && v.ty == TFUNCTION;
}

isuserdata(v: ref Value): int
{
	return v != nil && v.ty == TUSERDATA;
}

isthread(v: ref Value): int
{
	return v != nil && v.ty == TTHREAD;
}

toboolean(v: ref Value): int
{
	if(v == nil || v.ty == TNIL)
		return 0;
	if(v.ty == TBOOLEAN)
		return v.b;
	return 1;
}

tonumber(v: ref Value): real
{
	if(v == nil)
		return 0.0;
	if(v.ty == TNUMBER)
		return v.n;
	return 0.0;
}

tostring(v: ref Value): string
{
	if(v == nil)
		return "nil";

	case(v.ty) {
	TNIL => return "nil";
	TBOOLEAN => return (v.b != 0) ? "true" : "false";
	TNUMBER => return sprint("%g", v.n);
	TSTRING => return v.s;
	* => return sprint("%p", v);
	}
}

objlen(v: ref Value): int
{
	if(v == nil)
		return 0;
	if(v.ty == TSTRING)
		return len v.s;
	if(v.ty == TTABLE) {
		# Return array length
		if(v.t != nil)
			return v.t.sizearray;
	}
	return 0;
}

# Garbage collection (placeholder)
gc(L: ref State, what: int, data: real): real
{
	case(what) {
	GCSTOP =>
		# Stop GC
		return 0.0;
	GCRESTART =>
		# Restart GC
		return 0.0;
	GCCOLLECT =>
		# Full collection
		return 0.0;
	GCCOUNT =>
		# Return memory in use
		if(globalstate != nil)
			return real(globalstate.malloc / 1024);
		return 0.0;
	GCCOUNTB =>
		# Return remainder of memory/1024
		if(globalstate != nil)
			return real(globalstate.malloc % 1024);
		return 0.0;
	GCSTEP =>
		# Incremental step
		return 0.0;
	GCSETPAUSE =>
		# Set pause
		return 0.0;
	GCSETSTEPMUL =>
		# Set step multiplier
		return 0.0;
	}
	return 0.0;
}

# Coroutine operations (placeholder)
newthread(L: ref State): ref Thread
{
	th := ref Thread;
	th.status = OK;
	th.stack = array[20] of ref Value;
	th.ci = nil;
	th.base = 0;
	th.top = 0;

	v := ref Value;
	v.ty = TTHREAD;
	v.th = th;
	pushvalue(L, v);

	return th;
}

resume(L: ref State, co: ref Thread, nargs: int): int
{
	return ERRRUN;
}

yield(L: ref State, nresults: int): int
{
	return YIELD;
}

# String operations
strhash(s: string): int
{
	h := 5381;
	for(i := 0; i < len s; i++) {
		c := s[i];
		if(c < 0)
			c += 256;
		h = ((h << 5) + h) + c;
	}
	if(h < 0)
		h = -h;
	return h;
}

internstring(s: string): ref TString
{
	ts := ref TString;
	ts.s = s;
	ts.length = len s;
	ts.hash = strhash(s);
	ts.next = nil;
	ts.reserved = 0;
	return ts;
}

allocobj(sz: int): ref Value
{
	return nil;
}

# Module initialization
init(): string
{
	sys = load Sys Sys;
	initglobal();
	return nil;
}

about(): array of string
{
	return array[] of {
		"Lua VM for Inferno/Limbo",
		"State Management Module",
		"Targeting Lua 5.4 compatibility",
	};
}
