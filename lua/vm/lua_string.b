# Lua VM - String Interning System
# Implements string pool with hash table for efficient string storage

implement Luavm;

include "sys.m";
include "luavm.m";

sys: Sys;
print, sprint, fprint: import sys;

# String table for global state
stringtable: ref Stringtable;

# Initialize string table
initstrings()
{
	stringtable = ref Stringtable;
	stringtable.size = 64;  # Initial hash table size
	stringtable.nuse = 0;
	stringtable.hash = array[stringtable.size] of ref TString;
	for(i := 0; i < stringtable.size; i++)
		stringtable.hash[i] = nil;
}

# String hashing - djb2 algorithm
strhash(s: string): int
{
	h := 5381;
	len := len s;
	for(i := 0; i < len; i++) {
		c := s[i];
		if(c < 0)
			c += 256;
		h = ((h << 5) + h) + c;  # h * 33 + c
	}
	if(h < 0)
		h = -h;
	return h;
}

# Intern a string - returns existing TString if already interned
internstring(s: string): ref TString
{
	if(s == nil)
		return nil;

	if(stringtable == nil)
		initstrings();

	h := strhash(s);
	idx := h % stringtable.size;

	# Search for existing string
	node := stringtable.hash[idx];
	while(node != nil) {
		if(node.hash == h && node.s == s)
			return node;  # Found existing string
		node = node.next;
	}

	# Create new string node
	ts := ref TString;
	ts.s = s;
	ts.length = len s;
	ts.hash = h;
	ts.next = stringtable.hash[idx];
	ts.reserved = 0;

	stringtable.hash[idx] = ts;
	stringtable.nuse++;

	# Resize hash table if needed
	if(stringtable.nuse > stringtable.size)
		resizestringtable();

	return ts;
}

# Resize string table when it gets too full
resizestringtable()
{
	oldsize := stringtable.size;
	oldhash := stringtable.hash;

	# Double the size
	newsize := oldsize * 2;
	stringtable.size = newsize;
	stringtable.hash = array[newsize] of ref TString;
	stringtable.nuse = 0;

	# Rehash all strings
	for(i := 0; i < oldsize; i++) {
		node := oldhash[i];
		while(node != nil) {
			next := node.next;
			idx := node.hash % newsize;
			node.next = stringtable.hash[idx];
			stringtable.hash[idx] = node;
			stringtable.nuse++;
			node = next;
		}
	}
}

# Create a new string value (interned)
newstringvalue(s: string): ref Value
{
	if(s == nil)
		return mknil();

	ts := internstring(s);
	v := ref Value;
	v.ty = TSTRING;
	v.s = ts.s;  # Use the interned string
	return v;
}

# Concatenate two strings
stringconcat(a, b: ref Value): ref Value
{
	if(a == nil || a.ty != TSTRING)
		return mknil();
	if(b == nil || b.ty != TSTRING)
		return mknil();

	result := a.s + b.s;
	return newstringvalue(result);
}

# Compare two strings
stringcompare(a, b: ref Value): int
{
	if(a == nil || a.ty != TSTRING)
		return -1;
	if(b == nil || b.ty != TSTRING)
		return 1;

	if(a.s < b.s)
		return -1;
	if(a.s > b.s)
		return 1;
	return 0;
}

# Get string length
strlen(s: ref Value): int
{
	if(s == nil || s.ty != TSTRING)
		return 0;
	return len s.s;
}

# Substring
substring(s: ref Value, start, end: int): ref Value
{
	if(s == nil || s.ty != TSTRING)
		return mknil();

	len := len s.s;
	if(start < 0)
		start = 0;
	if(end > len)
		end = len;
	if(start >= end)
		return newstringvalue("");

	result := s.s[start:end];
	return newstringvalue(result);
}

# String to upper case
strtoupper(s: ref Value): ref Value
{
	if(s == nil || s.ty != TSTRING)
		return mknil();

	result := "";
	for(i := 0; i < len s.s; i++) {
		c := s.s[i];
		if(c >= 'a' && c <= 'z')
			c -= 'a' - 'A';
		result[len result] = c;
	}
	return newstringvalue(result);
}

# String to lower case
strtolower(s: ref Value): ref Value
{
	if(s == nil || s.ty != TSTRING)
		return mknil();

	result := "";
	for(i := 0; i < len s.s; i++) {
		c := s.s[i];
		if(c >= 'A' && c <= 'Z')
			c += 'a' - 'A';
		result[len result] = c;
	}
	return newstringvalue(result);
}

# Reverse string
strreverse(s: ref Value): ref Value
{
	if(s == nil || s.ty != TSTRING)
		return mknil();

	result := "";
	len := len s.s;
	for(i := len - 1; i >= 0; i--)
		result[len result] = s.s[i];
	return newstringvalue(result);
}

# Repeat string
strrepeat(s: ref Value, count: int): ref Value
{
	if(s == nil || s.ty != TSTRING)
		return mknil();

	if(count <= 0)
		return newstringvalue("");

	result := "";
	for(i := 0; i < count; i++)
		result += s.s;
	return newstringvalue(result);
}

# Strip whitespace from left
lstrip(s: ref Value): ref Value
{
	if(s == nil || s.ty != TSTRING)
		return mknil();

	start := 0;
	len := len s.s;
	while(start < len) {
		c := s.s[start];
		if(c != ' ' && c != '\t' && c != '\n' && c != '\r')
			break;
		start++;
	}
	return newstringvalue(s.s[start:]);
}

# Strip whitespace from right
rstrip(s: ref Value): ref Value
{
	if(s == nil || s.ty != TSTRING)
		return mknil();

	end := len s.s;
	while(end > 0) {
		c := s.s[end - 1];
		if(c != ' ' && c != '\t' && c != '\n' && c != '\r')
			break;
		end--;
	}
	return newstringvalue(s.s[:end]);
}

# Strip whitespace from both ends
strip(s: ref Value): ref Value
{
	if(s == nil || s.ty != TSTRING)
		return mknil();

	# First strip left
	temp := lstrip(s);
	# Then strip right
	return rstrip(temp);
}

# Find substring (returns 1-based index or 0)
strfind(s, pattern: ref Value, start: int): int
{
	if(s == nil || s.ty != TSTRING)
		return 0;
	if(pattern == nil || pattern.ty != TSTRING)
		return 0;

	len := len s.s;
	patlen := len pattern.s;

	if(start < 1)
		start = 1;
	if(start > len)
		return 0;

	# Simple search
	for(i := start - 1; i <= len - patlen; i++) {
		match := 1;
		for(j := 0; j < patlen; j++) {
			if(s.s[i + j] != pattern.s[j]) {
				match = 0;
				break;
			}
		}
		if(match)
			return i + 1;  # Return 1-based index
	}

	return 0;
}

# Get character code at position
strbyte(s: ref Value, idx: int): int
{
	if(s == nil || s.ty != TSTRING)
		return -1;

	len := len s.s;
	if(idx < 1)
		idx = 1;
	if(idx > len)
		return -1;

	c := s.s[idx - 1];
	if(c < 0)
		c += 256;
	return c;
}

# Create string from character codes
strchar(codes: array of int): ref Value
{
	s := "";
	for(i := 0; i < len codes; i++) {
		c := codes[i];
		if(c >= 0 && c < 256)
			s[len s] = byte c;
	}
	return newstringvalue(s);
}

# Format string (simple implementation)
strformat(fmt: string, args: array of ref Value): ref Value
{
	result := "";
	argidx := 0;
	len := len fmt;

	i := 0;
	while(i < len) {
		c := fmt[i];
		if(c == '%') {
			i++;
			if(i >= len) {
				result[len result] = '%';
				break;
			}
			c = fmt[i];
			case(c) {
			'%' or 'd' or 'i' =>
				# Integer
				if(argidx < len args && args[argidx] != nil) {
					n := int(tonumber(args[argidx]));
					result += sprint("%d", n);
				}
				argidx++;
			'f' =>
				# Float
				if(argidx < len args && args[argidx] != nil) {
					n := tonumber(args[argidx]);
					result += sprint("%g", n);
				}
				argidx++;
			's' =>
				# String
				if(argidx < len args && args[argidx] != nil) {
					result += tostring(args[argidx]);
				}
				argidx++;
			'g' =>
				# Generic (try number then string)
				if(argidx < len args && args[argidx] != nil) {
					v := args[argidx];
					if(v.ty == TNUMBER)
						result += sprint("%g", v.n);
					else
						result += tostring(v);
				}
				argidx++;
			'x' =>
				# Hexadecimal
				if(argidx < len args && args[argidx] != nil) {
					n := int(tonumber(args[argidx]));
					result += sprint("%x", n);
				}
				argidx++;
			'X' =>
				# Uppercase hexadecimal
				if(argidx < len args && args[argidx] != nil) {
					n := int(tonumber(args[argidx]));
					result += sprint("%X", n);
				}
				argidx++;
			'c' =>
				# Character
				if(argidx < len args && args[argidx] != nil) {
					n := int(tonumber(args[argidx]));
					if(n >= 0 && n < 256)
						result[len result] = byte n;
				}
				argidx++;
			* =>
				# Unknown format
				result[len result] = '%';
				result[len result] = c;
			}
		} else {
			result[len result] = c;
		}
		i++;
	}

	return newstringvalue(result);
}

# Split string by delimiter
strsplit(s, delim: ref Value): ref Table
{
	result := createtable(0, 0);

	if(s == nil || s.ty != TSTRING || delim == nil || delim.ty != TSTRING)
		return result;

	input := s.s;
	sep := delim.s;
	idx := 1;

	while(len input > 0) {
		pos := 0;
		found := 0;
		for(i := 0; i <= len input - len sep; i++) {
			match := 1;
			for(j := 0; j < len sep; j++) {
				if(input[i + j] != sep[j]) {
					match = 0;
					break;
				}
			}
			if(match) {
				pos = i;
				found = 1;
				break;
			}
		}

		if(found) {
			part := input[:pos];
			key := mknumber(real idx);
			val := newstringvalue(part);
			settablevalue(result, key, val);
			idx++;
			input = input[pos + len sep:];
		} else {
			key := mknumber(real idx);
			val := newstringvalue(input);
			settablevalue(result, key, val);
			break;
		}
	}

	return result;
}

# Get string table statistics
stringtablestats(): (int, int)
{
	if(stringtable == nil)
		return (0, 0);
	return (stringtable.size, stringtable.nuse);
}
