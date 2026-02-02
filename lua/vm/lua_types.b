# Lua VM - Value Type System
# Implements TValue tagged union for Lua 5.4 compatibility

implement Luavm;

include "sys.m";
include "luavm.m";

sys: Sys;
print, sprint, fprint: import sys;

# Module initialization
init(): string
{
	sys = load Sys Sys;
	return nil;
}

# Value constructors and helpers

# Create nil value
mknil(): ref Value
{
	v := ref Value;
	v.ty = TNIL;
	return v;
}

# Create boolean value
mkbool(b: int): ref Value
{
	v := ref Value;
	v.ty = TBOOLEAN;
	v.b = b;
	return v;
}

# Create number value
mknumber(n: real): ref Value
{
	v := ref Value;
	v.ty = TNUMBER;
	v.n = n;
	return v;
}

# Create string value
mkstring(s: string): ref Value
{
	v := ref Value;
	v.ty = TSTRING;
	v.s = s;
	return v;
}

# Create table value
mktable(t: ref Table): ref Value
{
	v := ref Value;
	v.ty = TTABLE;
	v.t = t;
	return v;
}

# Create function value
mkfunction(f: ref Function): ref Value
{
	v := ref Value;
	v.ty = TFUNCTION;
	v.f = f;
	return v;
}

# Create userdata value
mkuserdata(u: ref Userdata): ref Value
{
	v := ref Value;
	v.ty = TUSERDATA;
	v.u = u;
	return v;
}

# Create thread value
mkthread(th: ref Thread): ref Value
{
	v := ref Value;
	v.ty = TTHREAD;
	v.th = th;
	return v;
}

# Type checking functions

isnil(v: ref Value): int
{
	if(v == nil)
		return 1;
	return v.ty == TNIL;
}

isboolean(v: ref Value): int
{
	if(v == nil)
		return 0;
	return v.ty == TBOOLEAN;
}

isnumber(v: ref Value): int
{
	if(v == nil)
		return 0;
	return v.ty == TNUMBER;
}

isstring(v: ref Value): int
{
	if(v == nil)
		return 0;
	return v.ty == TSTRING;
}

istable(v: ref Value): int
{
	if(v == nil)
		return 0;
	return v.ty == TTABLE;
}

isfunction(v: ref Value): int
{
	if(v == nil)
		return 0;
	return v.ty == TFUNCTION;
}

isuserdata(v: ref Value): int
{
	if(v == nil)
		return 0;
	return v.ty == TUSERDATA;
}

isthread(v: ref Value): int
{
	if(v == nil)
		return 0;
	return v.ty == TTHREAD;
}

# Type conversion functions

# Convert value to boolean
# Lua rules: nil and false are false, everything else is true
toboolean(v: ref Value): int
{
	if(v == nil)
		return 0;
	if(v.ty == TNIL)
		return 0;
	if(v.ty == TBOOLEAN && v.b == 0)
		return 0;
	return 1;
}

# Convert value to number
tonumber(v: ref Value): real
{
	if(v == nil)
		return 0.0;

	case(v.ty) {
	TNUMBER =>
		return v.n;
	TBOOLEAN =>
		if(v.b)
			return 1.0;
		else
			return 0.0;
	TSTRING =>
		# Try to convert string to number
		return strtonumber(v.s);
	* =>
		return 0.0;
	}
}

# Convert string to number (helper)
strtonumber(s: string): real
{
	# Simple implementation - just parse basic numbers
	# In a full implementation, this would handle hex, scientific notation, etc.
	n := 0.0;
	sign := 1.0;
	i := 0;
	len := len s;

	# Skip leading whitespace
	while(i < len && (s[i] == ' ' || s[i] == '\t' || s[i] == '\n' || s[i] == '\r'))
		i++;

	# Check for sign
	if(i < len && s[i] == '-') {
		sign = -1.0;
		i++;
	} else if(i < len && s[i] == '+') {
		i++;
	}

	# Parse digits
	have_digits := 0;
	while(i < len && s[i] >= '0' && s[i] <= '9') {
		n = n * 10.0 + real(s[i] - '0');
		i++;
		have_digits = 1;
	}

	# Parse decimal part
	if(i < len && s[i] == '.') {
		i++;
		dec := 0.1;
		while(i < len && s[i] >= '0' && s[i] <= '9') {
			n = n + dec * real(s[i] - '0');
			dec = dec / 10.0;
			i++;
			have_digits = 1;
		}
	}

	# Parse exponent
	if(i < len && (s[i] == 'e' || s[i] == 'E')) {
		i++;
		exp_sign := 1;
		if(i < len && s[i] == '-') {
			exp_sign = -1;
			i++;
		} else if(i < len && s[i] == '+') {
			i++;
		}
		exp := 0;
		while(i < len && s[i] >= '0' && s[i] <= '9') {
			exp = exp * 10 + (s[i] - '0');
			i++;
		}
		if(exp_sign > 0) {
			while(exp > 0) {
				n = n * 10.0;
				exp--;
			}
		} else {
			while(exp > 0) {
				n = n / 10.0;
				exp--;
			}
		}
	}

	if(!have_digits)
		return 0.0;

	return n * sign;
}

# Convert value to string
tostring(v: ref Value): string
{
	if(v == nil)
		return "nil";

	case(v.ty) {
	TNIL =>
		return "nil";
	TBOOLEAN =>
		if(v.b)
			return "true";
		else
			return "false";
	TNUMBER =>
		# Format number appropriately
		if(v.n != v.n)  # NaN
			return "nan";
		if(v.n == 1.0/0.0)  # Inf
			return "inf";
		if(v.n == -1.0/0.0)  # -Inf
			return "-inf";
		# Simple format - in full implementation would handle formatting better
		return sprint("%g", v.n);
	TSTRING =>
		return v.s;
	TTABLE =>
		return "table: " + sprint("%p", v.t);
	TFUNCTION =>
		if(v.f.isc)
			return "function: C";
		else
			return "function: Lua";
	TUSERDATA =>
		return "userdata: " + sprint("%p", v.u);
	TTHREAD =>
		return "thread: " + sprint("%p", v.th);
	* =>
		return "unknown";
	}
}

# Get type name
typeName(v: ref Value): string
{
	if(v == nil)
		return "no value";

	case(v.ty) {
	TNIL =>
		return "nil";
	TBOOLEAN =>
		return "boolean";
	TNUMBER =>
		return "number";
	TSTRING =>
		return "string";
	TTABLE =>
		return "table";
	TFUNCTION =>
		return "function";
	TUSERDATA =>
		return "userdata";
	TTHREAD =>
		return "thread";
	* =>
		return "unknown";
	}
}

# Get string length (fast)
objlen(v: ref Value): int
{
	if(v == nil || v.ty != TSTRING)
		return 0;
	return len v.s;
}

# Stack operations for Lua State

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

# Push value onto stack
pushvalue(L: ref State, v: ref Value)
{
	if(L == nil)
		return;

	# Grow stack if needed
	if(L.stack == nil) {
		L.stack = array[20] of ref Value;
	} else if(L.top >= len L.stack) {
		newstack := array[len L.stack * 2] of ref Value;
		newstack[:] = L.stack;
		L.stack = newstack;
	}

	L.stack[L.top++] = v;
}

# Push nil
pushnil(L: ref State)
{
	pushvalue(L, mknil());
}

# Push boolean
pushboolean(L: ref State, b: int)
{
	pushvalue(L, mkbool(b));
}

# Push number
pushnumber(L: ref State, n: real)
{
	pushvalue(L, mknumber(n));
}

# Push string
pushstring(L: ref State, s: string)
{
	pushvalue(L, mkstring(s));
}

# Pop n values from stack
pop(L: ref State, n: int)
{
	if(L == nil)
		return;

	if(n > L.top)
		L.top = 0;
	else
		L.top -= n;
}

# Get top of stack (number of elements)
gettop(L: ref State): int
{
	if(L == nil)
		return 0;
	return L.top;
}

# Set top of stack
settop(L: ref State, idx: int)
{
	if(L == nil)
		return;

	if(idx < 0) {
		idx = L.top + idx + 1;
	}

	if(idx < 0)
		idx = 0;

	# Grow stack if needed
	if(L.stack == nil) {
		L.stack = array[idx + 10] of ref Value;
	} else if(idx > len L.stack) {
		newstack := array[idx + 10] of ref Value;
		if(L.top > 0)
			newstack[:L.top] = L.stack[:L.top];
		L.stack = newstack;
	}

	# Fill with nils if growing
	if(idx > L.top) {
		for(i := L.top; i < idx; i++)
			L.stack[i] = mknil();
	}

	L.top = idx;
}

# Create new Lua state
newstate(): ref State
{
	L := ref State;

	L.stack = array[20] of ref Value;
	L.top = 0;
	L.base = 0;
	L.global = createtable(0, 32);  # Preallocate space for globals
	L.registry = createtable(0, 0);
	L.upvalhead = nil;
	L.ci = nil;  # Will be set on first function call

	return L;
}

# Close Lua state
close(L: ref State)
{
	if(L == nil)
		return;

	# Free stack
	L.stack = nil;
	# GC will collect tables and other objects
	L.global = nil;
	L.registry = nil;
	L.ci = nil;
}

# Load Lua string (placeholder - implemented in parser)
loadstring(L: ref State, s: string): int
{
	# Placeholder - this will be implemented in the parser phase
	return ERRSYNTAX;
}

# Load Lua file (placeholder)
loadfile(L: ref State, filename: string): int
{
	# Placeholder - this will be implemented in the parser phase
	return ERRFILE;
}

# Protected call (placeholder - needs full VM)
pcall(L: ref State, nargs: int, nresults: int): int
{
	# Placeholder - this will be implemented in the VM phase
	return ERRRUN;
}

# Create new table
newtable(L: ref State): ref Table
{
	t := createtable(0, 0);
	pushvalue(L, mktable(t));
	return t;
}

# Create table with preallocated sizes
createtable(narr: int, nrec: int): ref Table
{
	t := ref Table;
	t.arr = nil;
	t.hash = nil;
	t.sizearray = 0;
	t.metatable = nil;

	# Preallocate array part if needed
	if(narr > 0) {
		t.arr = array[narr] of ref Value;
		t.sizearray = narr;
		for(i := 0; i < narr; i++)
			t.arr[i] = mknil();
	}

	# Preallocate hash table if needed
	if(nrec > 0) {
		# Create hash table with appropriate size
		# This will be implemented in lua_table.b
	}

	return t;
}

# Get table field by string key
getfield(L: ref State, idx: int, k: string)
{
	t := getvalue(L, idx);
	if(t == nil || t.ty != TTABLE || t.t == nil) {
		pushnil(L);
		return;
	}

	key := mkstring(k);
	v := gettablevalue(t.t, key);
	pushvalue(L, v);
}

# Set table field by string key
setfield(L: ref State, idx: int, k: string)
{
	t := getvalue(L, idx);
	if(t == nil || t.ty != TTABLE || t.t == nil)
		return;

	if(L.top < 1)
		return;

	v := L.stack[L.top - 1];  # Get value from top of stack
	key := mkstring(k);
	settablevalue(t.t, key, v);
}

# Get table value (key at top-1, table at top-2)
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

# Set table value (table at top-2, key at top-1, value at top)
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

# Get value from table
gettablevalue(t: ref Table, key: ref Value): ref Value
{
	if(t == nil || key == nil)
		return mknil();

	# Check metatable __index metamethod
	if(t.metatable != nil) {
		# This will be implemented later
	}

	# Try array part first for integer keys
	if(key.ty == TNUMBER) {
		n := int(key.n);
		if(n > 0 && n <= t.sizearray) {
			v := t.arr[n - 1];
			if(v != nil)
				return v;
		}
	}

	# Check hash part
	if(t.hash != nil) {
		hashidx := strhash(sprint("%g", key.n)) % 1024;  # Simple hash
		node := t.hash;
		while(node != nil) {
			if(node.key != nil && values_equal(node.key, key))
				return node.val;
			node = node.next;
		}
	}

	return mknil();
}

# Set value in table
settablevalue(t: ref Table, key: ref Value, val: ref Value)
{
	if(t == nil || key == nil)
		return;

	# Check metatable __newindex metamethod
	if(t.metatable != nil) {
		# This will be implemented later
	}

	# Try array part first for integer keys
	if(key.ty == TNUMBER) {
		n := int(key.n);
		if(n > 0 && n <= t.sizearray) {
			t.arr[n - 1] = val;
			return;
		}
		# Grow array if appropriate
		if(n == t.sizearray + 1) {
			newsize := t.sizearray * 2;
			if(newsize < 8)
				newsize = 8;
			newarray := array[newsize] of ref Value;
			if(t.arr != nil)
				newarray[:t.sizearray] = t.arr[:t.sizearray];
			for(i := t.sizearray; i < newsize; i++)
				newarray[i] = mknil();
			t.arr = newarray;
			t.sizearray = newsize;
			t.arr[n - 1] = val;
			return;
		}
	}

	# Set in hash part
	if(t.hash == nil) {
		t.hash = ref Hashnode;
		t.hash.key = key;
		t.hash.val = val;
		t.hash.next = nil;
	} else {
		hashidx := strhash(sprint("%g", key.n)) % 1024;
		node := t.hash;
		prev: ref Hashnode;
		while(node != nil) {
			if(node.key != nil && values_equal(node.key, key)) {
				node.val = val;
				return;
			}
			prev = node;
			node = node.next;
		}
		# Add new node
		newnode := ref Hashnode;
		newnode.key = key;
		newnode.val = val;
		newnode.next = nil;
		if(prev != nil)
			prev.next = newnode;
	}
}

# Compare two values for equality (for table lookup)
values_equal(a, b: ref Value): int
{
	if(a == nil && b == nil)
		return 1;
	if(a == nil || b == nil)
		return 0;
	if(a.ty != b.ty)
		return 0;

	case(a.ty) {
	TNIL =>
		return 1;
	TBOOLEAN =>
		return a.b == b.b;
	TNUMBER =>
		return a.n == b.n;
	TSTRING =>
		return a.s == b.s;
	TTABLE =>
		return a.t == b.t;
	TFUNCTION =>
		return a.f == b.f;
	TUSERDATA =>
		return a.u == b.u;
	TTHREAD =>
		return a.th == b.th;
	* =>
		return 0;
	}
}

# String hashing (djb2 algorithm)
strhash(s: string): int
{
	h := 5381;
	for(i := 0; i < len s; i++) {
		h = ((h << 5) + h) + int s[i];
	}
	if(h < 0)
		h = -h;
	return h;
}

# Intern string (placeholder)
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

# Allocate GC object (placeholder)
allocobj(sz: int): ref Value
{
	return mknil();  # Placeholder
}

# Garbage collection (placeholder)
gc(L: ref State, what: int, data: real): real
{
	# Placeholder - this will be implemented in the GC phase
	return 0.0;
}

# Create new thread
newthread(L: ref State): ref Thread
{
	th := ref Thread;
	th.status = OK;
	th.stack = array[20] of ref Value;
	th.ci = nil;
	th.base = 0;
	th.top = 0;
	pushvalue(L, mkthread(th));
	return th;
}

# Resume coroutine (placeholder)
resume(L: ref State, co: ref Thread, nargs: int): int
{
	# Placeholder - this will be implemented in the coroutine phase
	return ERRRUN;
}

# Yield from coroutine (placeholder)
yield(L: ref State, nresults: int): int
{
	# Placeholder - this will be implemented in the coroutine phase
	return YIELD;
}

# About this implementation
about(): array of string
{
	return array[] of {
		"Lua VM for Inferno/Limbo",
		"Targeting Lua 5.4 compatibility",
		"Copyright (c) 2025 TaijiOS Project",
	};
}
