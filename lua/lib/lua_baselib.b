# Lua VM - Basic Library
# Implements core Lua functions: assert, error, pairs, ipairs, next, print, etc.

implement Luavm;

include "sys.m";
include "luavm.m";

sys: Sys;
print, sprint, fprint: import sys;

# ====================================================================
# Basic Functions
# ====================================================================

# assert(v[, message]) - Assert that v is true
assert_func(L: ref State): int
{
	if(L == nil || L.top < 1)
		return 0;

	v := L.stack[L.top - 1];

	# Check if v is true
	if(v != nil && v.ty != TNIL && (v.ty != TBOOLEAN || v.b != 0))
		return 0;  # OK - no error

	# Assert failed - throw error
	msg := "assertion failed!";

	# Get custom message if provided
	if(L.top >= 2) {
		msgval := L.stack[L.top - 2];
		if(msgval != nil && msgval.ty == TSTRING)
			msg = msgval.s;
	}

	pushstring(L, msg);
	return ERRRUN;  # Throw error
}

# error(message[, level]) - Throw error
error_func(L: ref State): int
{
	if(L == nil || L.top < 1)
		return 0;

	msgval := L.stack[L.top - 1];

	# Get message
	msg := "error";
	if(msgval != nil && msgval.ty == TSTRING)
		msg = msgval.s;

	pushstring(L, msg);
	return ERRRUN;
}

# pcall(f, ...) - Protected call
pcall_func(L: ref State): int
{
	if(L == nil || L.top < 1)
		return 0;

	func := L.stack[L.top - 1];
	nargs := L.top - 1;

	if(func == nil || func.ty != TFUNCTION) {
		pushstring(L, "attempt to call a non-function");
		pushboolean(L, 0);
		pushstring(L, "pcall: function expected");
		return 2;
	}

	# Save state
	savedtop := L.top;
	savedbase := L.base;

	# Call function
	status := prepcall(L, func, nargs, -1);

	if(status != OK) {
		# Error occurred
		pushboolean(L, 0);

		# Get error message
		if(L.top > savedtop)
			pushvalue(L, L.stack[L.top - 1]);
		else
			pushnil(L);

		return 2;
	} else {
		# Success
		pushboolean(L, 1);

		# Copy results
		nresults := L.top - savedbase;
		for(i := 0; i < nresults; i++) {
			pushvalue(L, L.stack[savedbase + i]);
		}

		L.top = savedtop;
		return nresults + 1;
	}
}

# xpcall(f, err) - Protected call with error handler
xpcall_func(L: ref State): int
{
	if(L == nil || L.top < 2)
		return 0;

	func := L.stack[L.top - 1];
	errhandler := L.stack[L.top - 2];
	nargs := L.top - 2;

	if(func == nil || func.ty != TFUNCTION) {
		pushstring(L, "xpcall: function expected");
		pushboolean(L, 0);
		pushstring(L, "xpcall: function expected");
		return 2;
	}

	# Set error handler
	seterrorhandler(L, errhandler);

	# Call function
	status := pcall_func(L);
	return status;
}

# ====================================================================
# Type Functions
# ====================================================================

# type(v) - Get type name
type_func(L: ref State): int
{
	if(L == nil || L.top < 1)
		return 0;

	v := L.stack[L.top - 1];

	name := typename(v);
	pushstring(L, name);

	return 1;
}

# tostring(v) - Convert to string
tostring_func(L: ref State): int
{
	if(L == nil || L.top < 1)
		return 0;

	v := L.stack[L.top - 1];

	s := tostring(v);
	pushstring(L, s);

	return 1;
}

# tonumber(e[, base]) - Convert to number
tonumber_func(L: ref State): int
{
	if(L == nil || L.top < 1)
		return 0;

	e := L.stack[L.top - 1];

	if(e == nil || e.ty == TNIL) {
		pushnil(L);
		return 1;
	}

	if(e.ty == TNUMBER) {
		pushnumber(L, e.n);
		return 1;
	}

	if(e.ty != TSTRING) {
		pushnil(L);
		return 1;
	}

	# Try to convert string to number
	base := 10;
	if(L.top >= 2) {
		baseval := L.stack[L.top - 2];
		if(baseval != nil && baseval.ty == TNUMBER)
			base = int(baseval.n);
	}

	n := parsestringtonumber(e.s, base);
	pushnumber(L, n);

	return 1;
}

# ====================================================================
# Iteration Functions
# ====================================================================

# pairs(t) - Iterate over table (hash part)
pairs_func(L: ref State): int
{
	if(L == nil || L.top < 1)
		return 0;

	t := L.stack[L.top - 1];

	if(t == nil || t.ty != TTABLE || t.t == nil) {
		pushstring(L, "pairs: table expected");
		return ERRRUN;
	}

	# Return iterator function, table, and nil
	pushbuiltin(L, "next");
	pushvalue(L, t);
	pushnil(L);

	return 3;
}

# ipairs(t) - Iterate over table (array part)
ipairs_func(L: ref State): int
{
	if(L == nil || L.top < 1)
		return 0;

	t := L.stack[L.top - 1];

	if(t == nil || t.ty != TTABLE || t.t == nil) {
		pushstring(L, "ipairs: table expected");
		return ERRRUN;
	}

	# Return iterator function, table, and 0
	pushbuiltin(L, "ipairs_aux");
	pushvalue(L, t);
	pushnumber(L, 0.0);

	return 3;
}

# ipairs_aux(t, i) - Helper for ipairs
ipairs_aux(L: ref State): int
{
	if(L == nil || L.top < 2)
		return 0;

	i := L.stack[L.top - 1];
	t := L.stack[L.top - 2];

	if(t == nil || t.ty != TTABLE || t.t == nil || i == nil || i.ty != TNUMBER)
		return 0;

	idx := int(i.n) + 1;

	if(t.t.arr != nil && idx > 0 && idx <= t.t.sizearray) {
		if(idx - 1 < len t.t.arr) {
			v := t.t.arr[idx - 1];
			pushnumber(L, real(idx));
			pushvalue(L, v);
			return 2;
		}
	}

	return 0;  # No more elements
}

# next(table[, index]) - Get next key-value pair
next_func(L: ref State): int
{
	if(L == nil || L.top < 1)
		return 0;

	t := L.stack[L.top - 1];
	idx: ref Value;

	if(L.top >= 2) {
		idx = L.stack[L.top - 2];
	} else {
		idx = nil;  # nil means first iteration
	}

	if(t == nil || t.ty != TTABLE || t.t == nil) {
		pushnil(L);
		pushnil(L);
		return 2;
	}

	# If idx is nil, return first pair
	if(idx == nil || idx.ty == TNIL) {
		# Try array first
		if(t.t.arr != nil && t.t.sizearray > 0) {
			v := t.t.arr[0];
			if(v != nil && v.ty != TNIL) {
				pushnumber(L, 1.0);
				pushvalue(L, v);
				return 2;
			}
		}

		# Then hash part (simplified - would iterate hash)
		pushnil(L);
		pushnil(L);
		return 2;
	}

	# Get next pair (simplified - just return nil for now)
	pushnil(L);
	pushnil(L);
	return 2;
}

# ====================================================================
# Print Function
# ====================================================================

# print(...) - Print values to stdout
print_func(L: ref State): int
{
	if(L == nil)
		return 0;

	stdout := sys->fildes(1);

	n := L.top;
	for(i := 0; i < n; i++) {
		if(i > 0)
			sys->fprint(stdout, "\t");

		v := L.stack[i];
		s := "";
		if(v != nil) {
			if(v.ty == TNIL)
				s = "nil";
			else if(v.ty == TBOOLEAN)
				s = v.b != 0 ? "true" : "false";
			else if(v.ty == TNUMBER)
				s = sprint("%g", v.n);
			else if(v.ty == TSTRING)
				s = v.s;
			else
				s = tostring(v);
		}

		sys->fprint(stdout, "%s", s);
	}

	sys->fprint(stdout, "\n");

	return 0;
}

# ====================================================================
# Load Functions
# ====================================================================

# loadstring(str[, chunkname]) - Load Lua string
loadstring_func(L: ref State): int
{
	if(L == nil || L.top < 1)
		return 0;

	str := L.stack[L.top - 1];

	if(str == nil || str.ty != TSTRING) {
		pushstring(L, "loadstring: string expected");
		return ERRRUN;
	}

	# Parse and compile string (simplified)
	# In full implementation, would call parser and code generator
	chunk := newchunk(str.s);

	pushvalue(L, chunk);

	return 1;
}

# loadfile(filename) - Load Lua file
loadfile_func(L: ref State): int
{
	if(L == nil || L.top < 1)
		return 0;

	filenameval := L.stack[L.top - 1];

	if(filenameval == nil || filenameval.ty != TSTRING) {
		pushstring(L, "loadfile: string expected");
		return ERRRUN;
	}

	filename := filenameval.s;

	# Read file
	contents := readfile(filename);
	if(contents == nil) {
		pushstring(L, sprint("loadfile: cannot read %s", filename));
		return ERRRUN;
	}

	pushstring(L, contents);
	return loadstring_func(L);
}

# dofile(filename) - Load and execute file
dofile_func(L: ref State): int
{
	if(L == nil || L.top < 1)
		return 0;

	# Load file
	status := loadfile_func(L);
	if(status != OK)
		return status;

	# Execute
	# In full implementation, would call loaded function
	return 0;
}

# ====================================================================
# Global Variables
# ====================================================================

# _G - Global table
_G: ref Table;  # Will be set to global table

# _VERSION - Lua version
_VERSION: con "Lua 5.4 (TaijiOS)";

# ====================================================================
# Helper Functions
# ====================================================================

# Push built-in function
pushbuiltin(L: ref State, name: string)
{
	if(L == nil)
		return;

	# Create function value
	f := ref Function;
	f.isc = 1;  # C function

	case(name) {
	"assert" =>		f.cfunc = assert_func;
	"error" =>		f.cfunc = error_func;
	"pcall" =>		f.cfunc = pcall_func;
	"xpcall" =>		f.cfunc = xpcall_func;
	"type" =>		f.cfunc = type_func;
	"tostring" =>	f.cfunc = tostring_func;
	"tonumber" =>	f.cfunc = tonumber_func;
	"pairs" =>		f.cfunc = pairs_func;
	"ipairs" =>		f.cfunc = ipairs_func;
	"next" =>		f.cfunc = next_func;
	"print" =>		f.cfunc = print_func;
	"loadstring" =>	f.cfunc = loadstring_func;
	"loadfile" =>		f.cfunc = loadfile_func;
	"dofile" =>		f.cfunc = dofile_func;
	"ipairs_aux" =>	f.cfunc = ipairs_aux;
	* =>		return;
	}

	v := ref Value;
	v.ty = TFUNCTION;
	v.f = f;
	pushvalue(L, v);
}

# Read file (helper)
readfile(filename: string): string
{
	fd := sys->open(filename, Sys->OREAD);
	if(fd == nil)
		return nil;

	# Read all
	buf := array[8192] of byte;
	n := 0;
	total := 0;

	while((n = sys->read(fd, buf, len buf)) > 0) {
		total += n;
		if(total >= len buf) {
			newbuf := array[len buf * 2] of byte;
			newbuf[:total] = buf[:total];
			buf = newbuf;
		}
	}

	sys->close(fd);
	if(total > 0)
		return string buf[:total];
	return "";
}

# Parse string to number
parsestringtonumber(s: string, base: int): real
{
	# Simplified - just handle decimal
	n := 0.0;
	sign := 1.0;

	# Skip leading whitespace
	i := 0;
	len := len s;
	while(i < len && (s[i] == ' ' || s[i] == '\t'))
		i++;

	# Check for sign
	if(i < len && s[i] == '-') {
		sign = -1.0;
		i++;
	} else if(i < len && s[i] == '+') {
		i++;
	}

	# Parse digits
	have_digit := 0;
	while(i < len && s[i] >= '0' && s[i] <= '9') {
		n = n * 10.0 + real(s[i] - '0');
		i++;
		have_digit = 1;
	}

	# Parse decimal part
	if(i < len && s[i] == '.') {
		i++;
		dec := 0.1;
		while(i < len && s[i] >= '0' && s[i] <= '9') {
			n = n + dec * real(s[i] - '0');
			dec = dec / 10.0;
			i++;
			have_digit = 1;
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

	if(!have_digit)
		return 0.0;

	return n * sign;
}

# Create chunk placeholder
newchunk(str: string): ref Value
{
	chunk := ref Value;
	chunk.ty = TFUNCTION;
	chunk.f = ref Function;
	chunk.f.isc = 0;
	chunk.f.proto = ref Proto;
	chunk.f.proto.sourcename = str;
	return chunk;
}

# ====================================================================
# Library Registration
# ====================================================================

# Open basic library
open basic(L: ref State): int
{
	if(L == nil)
		return 0;

	# Set _G
	_G = L.global;

	# Register all built-in functions
	register_func(L, "assert");
	register_func(L, "collectgarbage");
	register_func(L, "dofile");
	register_func(L, "error");
	register_func(L, "getmetatable");
	register_func(L, "ipairs");
	register_func(L, "loadfile");
	register_func(L, "loadstring");
	register_func(L, "next");
	register_func(L, "pairs");
	register_func(L, "pcall");
	register_func(L, "print");
	register_func(L, "rawequal");
	register_func(L, "rawget");
	register_func(L, "rawlen");
	register_func(L, "rawset");
	register_func(L, "select");
	register_func(L, "setmetatable");
	register_func(L, "tonumber");
	register_func(L, "tostring");
	register_func(L, "type");
	register_func(L, "xpcall");

	# Set _VERSION
	key := ref Value;
	key.ty = TSTRING;
	key.s = "_VERSION";
	val := ref Value;
	val.ty = TSTRING;
	val.s = _VERSION;
	settablevalue(_G, key, val);

	return 0;
}

# Register function in global table
register_func(L: ref State, name: string)
{
	pushbuiltin(L, name);

	key := ref Value;
	key.ty = TSTRING;
	key.s = name;
	val := getvalue(L, -1);

	settablevalue(L.global, key, val);

	pop(L, 1);
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
		"Basic Library",
		"Core functions: assert, error, pairs, ipairs, print, etc.",
	};
}
