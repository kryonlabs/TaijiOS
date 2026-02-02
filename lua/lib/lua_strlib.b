# Lua VM - String Library
# Implements string.* functions

implement Luavm;

include "sys.m";
include "luavm.m";
include "lua_baselib.m";

sys: Sys;
print, sprint, fprint: import sys;

# ====================================================================
# String Operations
# ====================================================================

# string.byte(s[, i[, j]]) - Get character codes
string_byte(L: ref State): int
{
	if(L == nil || L.top < 1)
		return 0;

	sval := L.stack[L.top - 1];

	if(sval == nil || sval.ty != TSTRING) {
		pushnil(L);
		return 1;
	}

	s := sval.s;
	len := len s;

	# Get indices
	i := 1;
	j := i;
	if(L.top >= 2) {
		ival := L.stack[L.top - 2];
		if(ival != nil && ival.ty == TNUMBER)
			i = int(ival.n);
	}
	if(L.top >= 3) {
		jval := L.stack[L.top - 3];
		if(jval != nil && jval.ty == TNUMBER)
			j = int(jval.n);
	}

	# Default j to end
	if(j < 0)
		j = len + j + 1;
	if(j > len)
		j = len;

	# Return character codes
	if(i < 1)
		i = 1;
	if(j < i || i > len) {
		return 0;
	}

	count := j - i + 1;
	for(idx := i; idx <= j; idx++) {
		c := s[idx - 1];
		if(c < 0)
			c += 256;
		pushnumber(L, real(c));
	}

	return count;
}

# string.char(...) - Create string from character codes
string_char(L: ref State): int
{
	if(L == nil)
		return 0;

	n := L.top;

	if(n == 0) {
		pushstring(L, "");
		return 1;
	}

	s := "";
	for(i := 0; i < n; i++) {
		val := L.stack[i];
		if(val == nil || val.ty != TNUMBER)
			return 0;

		c := int(val.n);
		if(c < 0 || c > 255) {
			pushstring(L, "char: value out of range");
			return ERRRUN;
		}

		s[len s] = byte c;
	}

	pushstring(L, s);
	return 1;
}

# string.length(s) - Get string length
string_len(L: ref State): int
{
	if(L == nil || L.top < 1)
		return 0;

	sval := L.stack[L.top - 1];

	if(sval == nil || sval.ty != TSTRING) {
		pushnumber(L, 0.0);
		return 1;
	}

	pushnumber(L, real(len sval.s));
	return 1;
}

# string.sub(s, i[, j]) - Get substring
string_sub(L: ref State): int
{
	if(L == nil || L.top < 2)
		return 0;

	sval := L.stack[L.top - 1];
	ival := L.stack[L.top - 2];

	if(sval == nil || sval.ty != TSTRING || ival == nil || ival.ty != TNUMBER) {
		pushnil(L);
		return 1;
	}

	s := sval.s;
	len := len s;
	i := int(ival.n);

	# Get j (default to end)
	j := len;
	if(L.top >= 3) {
		jval := L.stack[L.top - 3];
		if(jval != nil && jval.ty == TNUMBER)
			j = int(jval.n);
	}

	# Adjust negative indices
	if(i < 0)
		i = len + i + 1;
	if(j < 0)
		j = len + j + 1;

	# Clamp to range
	if(i < 1)
		i = 1;
	if(j > len)
		j = len;
	if(i > j) {
		pushstring(L, "");
		return 1;
	}

	result := s[i-1:j];
	pushstring(L, result);

	return 1;
}

# string.upper(s) - Convert to uppercase
string_upper(L: ref State): int
{
	if(L == nil || L.top < 1)
		return 0;

	sval := L.stack[L.top - 1];

	if(sval == nil || sval.ty != TSTRING) {
		pushnil(L);
		return 1;
	}

	s := sval.s;
	result := "";

	for(i := 0; i < len s; i++) {
		c := s[i];
		if(c >= 'a' && c <= 'z')
			c -= 'a' - 'A';
		result[len result] = c;
	}

	pushstring(L, result);
	return 1;
}

# string.lower(s) - Convert to lowercase
string_lower(L: ref State): int
{
	if(L == nil || L.top < 1)
		return 0;

	sval := L.stack[L.top - 1];

	if(sval == nil || sval.ty != TSTRING) {
		pushnil(L);
		return 1;
	}

	s := sval.s;
	result := "";

	for(i := 0; i < len s; i++) {
		c := s[i];
		if(c >= 'A' && c <= 'Z')
			c += 'a' - 'A';
		result[len result] = c;
	}

	pushstring(L, result);
	return 1;
}

# string.reverse(s) - Reverse string
string_reverse(L: ref State): int
{
	if(L == nil || L.top < 1)
		return 0;

	sval := L.stack[L.top - 1];

	if(sval == nil || sval.ty != TSTRING) {
		pushnil(L);
		return 1;
	}

	s := sval.s;
	result := "";

	for(i := len s - 1; i >= 0; i--)
		result[len result] = s[i];

	pushstring(L, result);
	return 1;
}

# string.rep(s, n) - Repeat string
string_rep(L: ref State): int
{
	if(L == nil || L.top < 2)
		return 0;

	sval := L.stack[L.top - 1];
	nval := L.stack[L.top - 2];

	if(sval == nil || sval.ty != TSTRING || nval == nil || nval.ty != TNUMBER) {
		pushnil(L);
		return 1;
	}

	s := sval.s;
	n := int(nval.n);

	if(n < 0) {
		pushstring(L, "rep: negative count");
		return ERRRUN;
	}

	if(n == 0) {
		pushstring(L, "");
		return 1;
	}

	result := "";
	for(i := 0; i < n; i++)
		result += s;

	pushstring(L, result);
	return 1;
}

# string.find(s, pattern[, init[, plain]) - Find pattern
string_find(L: ref State): int
{
	if(L == nil || L.top < 2)
		return 0;

	sval := L.stack[L.top - 1];
	pval := L.stack[L.top - 2];

	if(sval == nil || sval.ty != TSTRING || pval == nil || pval.ty != TSTRING) {
		pushnil(L);
		return 1;
	}

	s := sval.s;
	pattern := pval.s;

	init := 1;
	if(L.top >= 3) {
		ival := L.stack[L.top - 3];
		if(ival != nil && ival.ty == TNUMBER)
			init = int(ival.n);
	}

	# Simple string search
	idx := findstring(s, pattern, init);
	if(idx == 0) {
		pushnil(L);
	} else {
		pushnumber(L, real(idx));
		pushstring(L, s[idx-1:idx+len pattern-1]);
	}

	return idx != 0 ? 2 : 1;
}

# string.format(fmt, ...) - Format string
string_format(L: ref State): int
{
	if(L == nil || L.top < 1)
		return 0;

	fmtval := L.stack[L.top - 1];

	if(fmtval == nil || fmtval.ty != TSTRING) {
		pushstring(L, "format: string expected");
		return ERRRUN;
	}

	fmt := fmtval.s;
	args := L.top - 1;

	# Format string
	result := "";
	argidx := 0;
	i := 0;

	while(i < len fmt) {
		c := fmt[i];
		i++;

		if(c == '%') {
			if(i >= len fmt)
				break;

			c = fmt[i];
			i++;

			case(c) {
			'%' =>
				result[len result] = '%';
			'd' or 'i' =>
				if(argidx < args) {
					arg := L.stack[argidx++];
					n := 0;
					if(arg != nil && arg.ty == TNUMBER)
						n = int(arg.n);
					result += sprint("%d", n);
				}
			'f' =>
				if(argidx < args) {
					arg := L.stack[argidx++];
					r := 0.0;
					if(arg != nil && arg.ty == TNUMBER)
						r = arg.n;
					result += sprint("%g", r);
				}
			's' =>
				if(argidx < args) {
					arg := L.stack[argidx++];
					s := "";
					if(arg != nil)
						s = tostring(arg);
					result += s;
				}
			'g' =>
				if(argidx < args) {
					arg := L.stack[argidx++];
					v := "";
					if(arg != nil) {
						if(arg.ty == TNUMBER)
							v = sprint("%g", arg.n);
						else
							v = tostring(arg);
					}
					result += v;
				}
			'q' =>
				if(argidx < args) {
					arg := L.stack[argidx++];
					s := "";
					if(arg != nil)
						s = tostring(arg);
					result += sprint("%q", s);
				}
			* =>
				result[len result] = '%';
				result[len result] = c;
			}
		} else {
			result[len result] = c;
		}
	}

	pushstring(L, result);
	return 1;
}

# string.dump(function) - Convert function to string
string_dump(L: ref State): int
{
	if(L == nil || L.top < 1)
		return 0;

	# For now, just return a placeholder
	pushstring(L, "-- bytecode --");
	return 1;
}

# ====================================================================
# Helper Functions
# ====================================================================

# Find string in string (simple implementation)
findstring(s, pattern, init: int): int
{
	len := len s;
	patlen := len pattern;

	if(init < 1)
		init = 1;
	if(init > len)
		return 0;

	# Simple search
	for(i := init; i <= len - patlen + 1; i++) {
		match := 1;
		for(j := 0; j < patlen; j++) {
			if(s[i + j - 1] != pattern[j]) {
				match = 0;
				break;
			}
		}
		if(match)
			return i;
	}

	return 0;
}

# ====================================================================
# Library Registration
# ====================================================================

# Open string library
open string(L: ref State): int
{
	if(L == nil)
		return 0;

	# Create string library table
	lib := createtable(0, 20);

	# Register functions
	setlibfunc(lib, "byte", string_byte);
	setlibfunc(lib, "char", string_char);
	setlibfunc(lib, "dump", string_dump);
	setlibfunc(lib, "find", string_find);
	setlibfunc(lib, "format", string_format);
	setlibfunc(lib, "len", string_len);
	setlibfunc(lib, "lower", string_lower);
	setlibfunc(lib, "rep", string_rep);
	setlibfunc(lib, "reverse", string_reverse);
	setlibfunc(lib, "sub", string_sub);
	setlibfunc(lib, "upper", string_upper);

	# Add metatable with __tostring
	meta := createtable(0, 1);
	key := ref Value;
	key.ty = TSTRING;
	key.s = "__tostring";
	val := ref Value;
	val.ty = TSTRING;
	val.s = "string";
	settablevalue(meta, key, val);

	# Set metatable
	key.s = "__metatable";
	settablevalue(lib, key, mktable(meta));

	pushvalue(L, mktable(lib));
	return 1;
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
		"String Library",
		"String manipulation functions",
	};
}
