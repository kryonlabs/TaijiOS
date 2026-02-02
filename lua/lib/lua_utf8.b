# Lua VM - UTF-8 Library
# Implements utf8.* functions
# Provides UTF-8 string manipulation

implement Luavm;

include "sys.m";
include "draw.m";
include "luavm.m";
include "lua_baselib.m";

sys: Sys;
print, sprint, fprint: import sys;

# ====================================================================
# UTF-8 Constants
# ====================================================================

UTF8_MAXBYTES: con 6;  # Max bytes per UTF-8 char

# ====================================================================
# UTF-8 Functions
# ====================================================================

# utf8.offset(s, n[, i]) - Get byte offset of character
utf8_offset(L: ref State): int
{
	if(L == nil || L.top < 2)
		return 0;

	sval := L.stack[L.top - 1];
	nval := L.stack[L.top - 2];

	if(sval == nil || sval.ty != TSTRING ||
	   nval == nil || nval.ty != TNUMBER) {
		pushnil(L);
		return 1;
	}

	s := sval.s;
	n := int(nval.n);

	# Get starting position (default 1, meaning first character)
	i := 1;
	if(L.top >= 3) {
		ival := L.stack[L.top - 3];
		if(ival != nil && ival.ty == TNUMBER)
			i = int(ival.n);
	}

	# Convert to 0-based
	if(i < 0)
		i = len s + i + 1;

	if(i < 1)
		i = 1;

	if(i > len s)
		i = len s;

	# Find nth character starting from position i
	bytepos := i - 1;
	charpos := 0;

	# Count characters from start
	for(j := 0; j < i - 1; j++) {
		if(isutf8startbyte(s[j]))
			charpos++;
	}

	# Find nth character
	targetchar := charpos + n;
	currentchar := charpos;

	while(bytepos < len s && currentchar < targetchar) {
		if(isutf8startbyte(s[bytepos]))
			currentchar++;

		if(currentchar >= targetchar)
			break;

		bytepos++;
	}

	if(currentchar < targetchar) {
		pushnil(L);
		return 1;
	}

	pushnumber(L, real(bytepos + 1));  # 1-based
	return 1;
}

# utf8.codepoint(s[, i[, j]]) - Get codepoints
utf8_codepoint(L: ref State): int
{
	if(L == nil || L.top < 1)
		return 0;

	sval := L.stack[L.top - 1];
	if(sval == nil || sval.ty != TSTRING) {
		pushstring(L, "codepoint: string expected");
		return ERRRUN;
	}

	s := sval.s;

	# Get range
	i := 1;
	if(L.top >= 2) {
		ival := L.stack[L.top - 2];
		if(ival != nil && ival.ty == TNUMBER)
			i = int(ival.n);
	}

	j := i;
	if(L.top >= 3) {
		jval := L.stack[L.top - 3];
		if(jval != nil && jval.ty == TNUMBER)
			j = int(jval.n);
	}

	# Convert to 0-based
	if(i < 0)
		i = len s + i + 1;
	if(j < 0)
		j = len s + j + 1;

	if(i < 1)
		i = 1;
	if(j > len s)
		j = len s;

	if(i > j) {
		pushstring(L, "codepoint: invalid range");
		return ERRRUN;
	}

	# Find codepoints
	bytepos := i - 1;
	nresults := 0;

	while(bytepos < len s && bytepos < j) {
		if(!isutf8startbyte(s[bytepos])) {
			bytepos++;
			continue;
		}

		(codepoint, nbytes) := utf8decode(s, bytepos);
		if(codepoint >= 0) {
			pushnumber(L, real(codepoint));
			nresults++;
		}

		bytepos += nbytes;
	}

	return nresults;
}

# utf8.char(...) - Create string from codepoints
utf8_char(L: ref State): int
{
	if(L == nil)
		return 0;

	n := L.top;
	if(n == 0)
		return 0;

	result := "";

	for(i := 0; i < n; i++) {
		val := L.stack[i];
		if(val == nil || val.ty != TNUMBER)
			continue;

		codepoint := int(val.n);

		# Encode codepoint to UTF-8
		bytes := encodeutf8(codepoint);
		if(bytes != nil)
			result += bytes;
	}

	pushstring(L, result);
	return 1;
}

# utf8.length(s[, i[, j]]) - Get string length in characters
utf8_len(L: ref State): int
{
	if(L == nil || L.top < 1)
		return 0;

	sval := L.stack[L.top - 1];
	if(sval == nil || sval.ty != TSTRING) {
		pushnil(L);
		pushstring(L, "len: string expected");
		return 2;
	}

	s := sval.s;

	# Get range
	i := 1;
	if(L.top >= 2) {
		ival := L.stack[L.top - 2];
		if(ival != nil && ival.ty == TNUMBER)
			i = int(ival.n);
	}

	j := len s;
	if(L.top >= 3) {
		jval := L.stack[L.top - 3];
		if(jval != nil && jval.ty == TNUMBER)
			j = int(jval.n);
	}

	# Convert to 0-based
	if(i < 0)
		i = len s + i + 1;
	if(j < 0)
		j = len s + j + 1;

	if(i < 1)
		i = 1;
	if(j > len s)
		j = len s;

	if(i > j) {
		pushnil(L);
		pushstring(L, "len: invalid range");
		return 2;
	}

	# Count characters
	charcount := 0;
	for(k := i - 1; k < j; k++) {
		if(isutf8startbyte(s[k]))
			charcount++;
	}

	pushnumber(L, real(charcount));
	return 1;
}

# utf8.codes(s) - Iterator for codepoints
utf8_codes(L: ref State): int
{
	if(L == nil || L.top < 1)
		return 0;

	sval := L.stack[L.top - 1];
	if(sval == nil || sval.ty != TSTRING) {
		pushstring(L, "codes: string expected");
		return ERRRUN;
	}

	# Return iterator function, state, initial value
	pushcfunction(L, codes_iterator);
	pushvalue(L, sval);  # State is the string
	pushnumber(L, 0.0);  # Start at position 0

	return 3;
}

# codes iterator
codes_iterator(L: ref State): int
{
	if(L == nil || L.top < 2)
		return 0;

	sval := L.stack[L.top - 2];
	posval := L.stack[L.top - 1];

	if(sval == nil || sval.ty != TSTRING ||
	   posval == nil || posval.ty != TNUMBER) {
		pushnil(L);
		return 1;
	}

	s := sval.s;
	pos := int(posval.n);

	# Find next character
	while(pos < len s && !isutf8startbyte(s[pos])) {
		pos++;
	}

	if(pos >= len s) {
		pushnil(L);
		return 1;
	}

	# Decode character
	(codepoint, nbytes) := utf8decode(s, pos);

	if(codepoint < 0) {
		pushnil(L);
		return 1;
	}

	# Return position and codepoint
	pushnumber(L, real(pos + 1));  # 1-based
	pushnumber(L, real(codepoint));

	# Update position for next iteration
	newpos := pos + nbytes;
	pushnumber(L, real(newpos));

	return 3;
}

# utf8.charpattern - Pattern for UTF-8 character
utf8_charpattern(L: ref State): int
{
	if(L == nil)
		return 0;

	# Pattern matching UTF-8 character
	# [\0-\x7F\xC2-\xF4][\x80-\xBF]*
	pattern := "[\\0-\\x7F\\xC2-\\xF4][\\x80-\\xBF]*";

	pushstring(L, pattern);
	return 1;
}

# utf8.code(s) - Validate UTF-8 string
utf8_code(L: ref State): int
{
	if(L == nil || L.top < 1)
		return 0;

	sval := L.stack[L.top - 1];
	if(sval == nil || sval.ty != TSTRING) {
		pushnil(L);
		pushstring(L, "code: string expected");
		return 2;
	}

	s := sval.s;

	# Validate UTF-8
	(valid, pos) := validateutf8(s);

	if(valid) {
		pushnumber(L, 0.0);  # Success
		return 1;
	} else {
		pushnil(L);
		pushnumber(L, real(pos));  # Invalid position
		return 2;
	}
}

# ====================================================================
# Helper Functions
# ====================================================================

# Check if byte is UTF-8 start byte
isutf8startbyte(b: int): int
{
	# Start bytes: 0xxxxxxx, 110xxxxx, 1110xxxx, 11110xxx
	return ((b & 0xC0) != 0x80);
}

# Decode UTF-8 character
utf8decode(s: string, pos: int): (int, int)
{
	if(pos < 0 || pos >= len s)
		return (-1, 0);

	b1 := int(s[pos]);

	# 1-byte sequence: 0xxxxxxx
	if(b1 < 0x80)
		return (b1, 1);

	# 2-byte sequence: 110xxxxx 10xxxxxx
	if((b1 & 0xE0) == 0xC0) {
		if(pos + 1 >= len s)
			return (-1, 0);

		b2 := int(s[pos + 1]);
		if((b2 & 0xC0) != 0x80)
			return (-1, 0);

		codepoint := ((b1 & 0x1F) << 6) | (b2 & 0x3F);
		return (codepoint, 2);
	}

	# 3-byte sequence: 1110xxxx 10xxxxxx 10xxxxxx
	if((b1 & 0xF0) == 0xE0) {
		if(pos + 2 >= len s)
			return (-1, 0);

		b2 := int(s[pos + 1]);
		b3 := int(s[pos + 2]);

		if((b2 & 0xC0) != 0x80 || (b3 & 0xC0) != 0x80)
			return (-1, 0);

		codepoint := ((b1 & 0x0F) << 12) | ((b2 & 0x3F) << 6) | (b3 & 0x3F);
		return (codepoint, 3);
	}

	# 4-byte sequence: 11110xxx 10xxxxxx 10xxxxxx 10xxxxxx
	if((b1 & 0xF8) == 0xF0) {
		if(pos + 3 >= len s)
			return (-1, 0);

		b2 := int(s[pos + 1]);
		b3 := int(s[pos + 2]);
		b4 := int(s[pos + 3]);

		if((b2 & 0xC0) != 0x80 || (b3 & 0xC0) != 0x80 || (b4 & 0xC0) != 0x80)
			return (-1, 0);

		codepoint := ((b1 & 0x07) << 18) | ((b2 & 0x3F) << 12) |
		            ((b3 & 0x3F) << 6) | (b4 & 0x3F);
		return (codepoint, 4);
	}

	return (-1, 0);
}

# Encode codepoint to UTF-8
encodeutf8(codepoint: int): string
{
	if(codepoint < 0)
		return nil;

	# 1-byte sequence
	if(codepoint < 0x80) {
		return string array[] of {byte codepoint};
	}

	# 2-byte sequence
	if(codepoint < 0x800) {
		return string array[] of {
			byte (0xC0 | (codepoint >> 6)),
			byte (0x80 | (codepoint & 0x3F))
		};
	}

	# 3-byte sequence
	if(codepoint < 0x10000) {
		return string array[] of {
			byte (0xE0 | (codepoint >> 12)),
			byte (0x80 | ((codepoint >> 6) & 0x3F)),
			byte (0x80 | (codepoint & 0x3F))
		};
	}

	# 4-byte sequence
	if(codepoint < 0x110000) {
		return string array[] of {
			byte (0xF0 | (codepoint >> 18)),
			byte (0x80 | ((codepoint >> 12) & 0x3F)),
			byte (0x80 | ((codepoint >> 6) & 0x3F)),
			byte (0x80 | (codepoint & 0x3F))
		};
	}

	return nil;  # Invalid codepoint
}

# Validate UTF-8 string
validateutf8(s: string): (int, int)
{
	pos := 0;

	while(pos < len s) {
		if(!isutf8startbyte(s[pos])) {
			return (0, pos + 1);  # Invalid, return 1-based position
		}

		(codepoint, nbytes) := utf8decode(s, pos);

		if(codepoint < 0) {
			return (0, pos + 1);  # Invalid
		}

		pos += nbytes;
	}

	return (1, 0);  # Valid
}

# ====================================================================
# Library Registration
# ====================================================================

# Open utf8 library
open utf8(L: ref State): int
{
	if(L == nil)
		return 0;

	# Create utf8 library table
	lib := createtable(0, 10);

	# Register functions
	setlibfunc(lib, "offset", utf8_offset);
	setlibfunc(lib, "codepoint", utf8_codepoint);
	setlibfunc(lib, "char", utf8_char);
	setlibfunc(lib, "len", utf8_len);
	setlibfunc(lib, "codes", utf8_codes);
	setlibfunc(lib, "charpattern", utf8_charpattern);

	# Set charpattern
	key := ref Value;
	val := ref Value;

	key.ty = TSTRING;
	key.s = "charpattern";

	val.ty = TSTRING;
	val.s = "[\\0-\\x7F\\xC2-\\xF4][\\x80-\\xBF]*";

	settablevalue(lib, key, val);

	pushvalue(L, mktable(lib));
	return 1;
}

# Set library function
setlibfunc(lib: ref Table, name: string, func: fn(L: ref State): int)
{
	if(lib == nil)
		return;

	f := ref Function;
	f.isc = 1;
	f.cfunc = func;
	f.upvals = nil;
	f.env = nil;

	key := ref Value;
	key.ty = TSTRING;
	key.s = name;

	val := ref Value;
	val.ty = TFUNCTION;
	val.f = f;

	settablevalue(lib, key, val);
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
		"UTF-8 Library",
		"UTF-8 string manipulation",
	};
}
