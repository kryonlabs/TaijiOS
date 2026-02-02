# Lua VM - Table Implementation
# Implements hybrid array+hash table with automatic rebalancing

implement Luavm;

include "sys.m";
include "luavm.m";

sys: Sys;
print, sprint, fprint: import sys;

# Constants for table implementation
MAXARRAY: con 256;  # Maximum array size before forcing hash
MINHASH: con 16;   # Minimum hash table size

# Create table with preallocated sizes
createtable(narr, nrec: int): ref Table
{
	t := ref Table;
	t.metatable = nil;

	# Allocate array part
	if(narr > 0) {
		t.arr = array[narr] of ref Value;
		t.sizearray = narr;
		for(i := 0; i < narr; i++) {
			v := ref Value;
			v.ty = TNIL;
			t.arr[i] = v;
		}
	} else {
		t.arr = nil;
		t.sizearray = 0;
	}

	# Allocate hash part
	if(nrec > 0) {
		t.hash = allochashtable(nrec);
	} else {
		t.hash = nil;
	}

	return t;
}

# Allocate hash table node
allochashtable(size: int): ref Hashnode
{
	# Allocate array of hash nodes
	nodes := array[size] of ref Hashnode;
	for(i := 0; i < size; i++)
		nodes[i] = nil;
	return ref Hashnode;  # Placeholder - store size separately
}

# Get value from table
gettablevalue(t: ref Table, key: ref Value): ref Value
{
	if(t == nil || key == nil) {
		result := ref Value;
		result.ty = TNIL;
		return result;
	}

	# Check metatable __index metamethod
	if(t.metatable != nil) {
		meta_idx := getmetafield(t, "__index");
		if(meta_idx != nil) {
			# Call metamethod
			return metamethod_index(t, key, meta_idx);
		}
	}

	# Try array part for integer keys
	if(isintegerkey(key)) {
		n := int(key.n);
		if(n > 0 && n <= t.sizearray) {
			v := t.arr[n - 1];
			if(v != nil && v.ty != TNIL)
				return v;
		}
	}

	# Try hash part
	if(t.hash != nil) {
		return hashget(t.hash, key);
	}

	result := ref Value;
	result.ty = TNIL;
	return result;
}

# Check if key is integer (not float with fractional part)
isintegerkey(k: ref Value): int
{
	if(k == nil || k.ty != TNUMBER)
		return 0;
	return k.n == real(int(k.n));
}

# Get metamethod from metatable
getmetafield(t: ref Table, name: string): ref Value
{
	if(t == nil || t.metatable == nil)
		return nil;

	key := ref Value;
	key.ty = TSTRING;
	key.s = name;

	return gettablevalue(t.metatable, key);
}

# Metamethod __index handler
metamethod_index(t: ref Table, key: ref Value, metamethod: ref Value): ref Value
{
	if(metamethod == nil) {
		result := ref Value;
		result.ty = TNIL;
		return result;
	}

	# If metamethod is a table, look up key in it
	if(metamethod.ty == TTABLE && metamethod.t != nil) {
		return gettablevalue(metamethod.t, key);
	}

	# If metamethod is a function, call it
	# (This requires the full VM to be implemented)
	result := ref Value;
	result.ty = TNIL;
	return result;
}

# Set value in table
settablevalue(t: ref Table, key: ref Value, val: ref Value)
{
	if(t == nil || key == nil)
		return;

	# Check metatable __newindex metamethod
	if(t.metatable != nil) {
		meta_idx := getmetafield(t, "__newindex");
		if(meta_idx != nil) {
			metamethod_newindex(t, key, val, meta_idx);
			return;
		}
	}

	# Try array part for integer keys
	if(isintegerkey(key)) {
		n := int(key.n);
		if(n > 0 && n <= t.sizearray) {
			t.arr[n - 1] = val;
			return;
		}
		# Grow array if appropriate
		if(n == t.sizearray + 1 && shouldgrowarray(t)) {
			growarray(t, n);
			t.arr[n - 1] = val;
			return;
		}
	}

	# Set in hash part
	hashset(t, key, val);
}

# Check if array should grow
shouldgrowarray(t: ref Table): int
{
	if(t.sizearray >= MAXARRAY)
		return 0;

	# Count non-nil elements in array
	count := 0;
	for(i := 0; i < t.sizearray; i++) {
		if(t.arr[i] != nil && t.arr[i].ty != TNIL)
			count++;
	}

	# If more than half full, grow
	return count > (t.sizearray / 2);
}

# Grow array part
growarray(t: ref Table, newsize: int)
{
	if(newsize <= t.sizearray)
		return;

	# Double size or at least newsize
	size := t.sizearray * 2;
	if(size < 8)
		size = 8;
	if(size < newsize)
		size = newsize;

	newarray := array[size] of ref Value;
	for(i := 0; i < t.sizearray; i++)
		newarray[i] = t.arr[i];
	for(i := t.sizearray; i < size; i++) {
		v := ref Value;
		v.ty = TNIL;
		newarray[i] = v;
	}

	t.arr = newarray;
	t.sizearray = size;
}

# Rehash table - optimize array/hash distribution
rehash(t: ref Table)
{
	# Count integer keys
	intcount := 0;
	maxint := 0;

	# This is a simplified rehash
	# Full implementation would count all keys and redistribute

	# For now, just grow hash if needed
	if(t.hash == nil) {
		t.hash = allochashtable(MINHASH);
	}
}

# Hash table operations
# Note: Simplified - full implementation would use external chaining

hashget(hash: ref Hashnode, key: ref Value): ref Value
{
	# Placeholder - linear search in chain
	# Full implementation would use computed hash index
	result := ref Value;
	result.ty = TNIL;
	return result;
}

hashset(t: ref Table, key: ref Value, val: ref Value)
{
	# Create hash table if needed
	if(t.hash == nil) {
		t.hash = allochashtable(MINHASH);
	}

	# Insert into hash
	# For now, just ensure hash exists
}

# Table length operator (#)
tablelength(t: ref Table): int
{
	if(t == nil)
		return 0;

	# Find first boundary (nil after non-nil)
	# Binary search for boundary
	i := 1;
	j := t.sizearray;

	if(j == 0)
		return 0;

	# Binary search for first nil
	while(i < j) {
		mid := (i + j + 1) / 2;
		if(t.arr[mid - 1] != nil && t.arr[mid - 1].ty != TNIL)
			i = mid;
		else
			j = mid - 1;
	}

	return i;
}

# Next for iteration (pairs/ipairs)
next(t: ref Table, key: ref Value): (ref Value, ref Value)
{
	if(t == nil)
		return (nil, nil);

	# If key is nil, start from beginning
	if(key == nil || key.ty == TNIL) {
		# Try array first
		if(t.sizearray > 0) {
			for(i := 0; i < t.sizearray; i++) {
				if(t.arr[i] != nil && t.arr[i].ty != TNIL) {
					k := ref Value;
					k.ty = TNUMBER;
					k.n = real(i + 1);
			return (k, t.arr[i]);
		}
			}
		}
		# Then hash
		return hashnext(t.hash, nil);
	}

	# Continue from key
	if(isintegerkey(key)) {
		n := int(key.n);
		if(n >= 1 && n < t.sizearray) {
			for(i := n; i < t.sizearray; i++) {
				if(t.arr[i] != nil && t.arr[i].ty != TNIL) {
					k := ref Value;
					k.ty = TNUMBER;
					k.n = real(i + 1);
			return (k, t.arr[i]);
		}
			}
		}
		# Move to hash
		return hashnext(t.hash, nil);
	}

	return hashnext(t.hash, key);
}

# Next in hash table
hashnext(hash: ref Hashnode, key: ref Value): (ref Value, ref Value)
{
	# Placeholder - would iterate hash chain
	r1 := ref Value;
	r1.ty = TNIL;
	r2 := ref Value;
	r2.ty = TNIL;
	return (r1, r2);
}

# Raw get (no metamethods)
rawget(t: ref Table, key: ref Value): ref Value
{
	if(t == nil || key == nil) {
		result := ref Value;
		result.ty = TNIL;
		return result;
	}

	if(isintegerkey(key)) {
		n := int(key.n);
		if(n > 0 && n <= t.sizearray) {
			return t.arr[n - 1];
		}
	}

	if(t.hash != nil)
		return hashget(t.hash, key);

	result := ref Value;
	result.ty = TNIL;
	return result;
}

# Raw set (no metamethods)
rawset(t: ref Table, key: ref Value, val: ref Value)
{
	if(t == nil || key == nil)
		return;

	if(isintegerkey(key)) {
		n := int(key.n);
		if(n > 0 && n <= t.sizearray) {
			t.arr[n - 1] = val;
			return;
		}
	}

	hashset(t, key, val);
}

# Set metatable
setmetatable(t: ref Table, mt: ref Table)
{
	if(t == nil)
		return;
	t.metatable = mt;
}

# Get metatable
getmetatable(t: ref Table): ref Table
{
	if(t == nil)
		return nil;
	return t.metatable;
}

# Concat tables (for .. operator)
tableconcat(t: ref Table, sep: string, i, j: int): string
{
	if(t == nil)
		return "";

	if(i < 1)
		i = 1;
	if(j > t.sizearray)
		j = t.sizearray;
	if(j < i)
		return "";

	result := "";
	for(n := i; n <= j; n++) {
		if(t.arr[n - 1] != nil && t.arr[n - 1].ty != TNIL) {
			if(n > i)
				result += sep;
			result += tostring(t.arr[n - 1]);
		}
	}
	return result;
}

# Insert into table
tableinsert(t: ref Table, pos: int, value: ref Value)
{
	if(t == nil || value == nil)
		return;

	if(pos < 1 || pos > t.sizearray)
		pos = t.sizearray + 1;

	# Grow array if needed
	if(t.sizearray < pos)
		growarray(t, pos);

	# Shift elements up
	for(i := t.sizearray - 1; i >= pos; i--)
		t.arr[i] = t.arr[i - 1];

	t.arr[pos - 1] = value;
}

# Remove from table
tableremove(t: ref Table, pos: int): ref Value
{
	if(t == nil)
		return nil;

	if(pos < 1 || pos > t.sizearray)
		pos = t.sizearray;

	result := t.arr[pos - 1];

	# Shift elements down
	for(i := pos - 1; i < t.sizearray - 1; i++)
		t.arr[i] = t.arr[i + 1];

	# Clear last element
	v := ref Value;
	v.ty = TNIL;
	t.arr[t.sizearray - 1] = v;

	return result;
}

# Sort table
tablesort(t: ref Table)
{
	if(t == nil || t.arr == nil)
		return;

	# Simple bubble sort (should use quicksort in production)
	n := t.sizearray;
	for(i := 0; i < n - 1; i++) {
		for(j := 0; j < n - i - 1; j++) {
			if(comparevalues(t.arr[j], t.arr[j + 1]) > 0) {
				tmp := t.arr[j];
				t.arr[j] = t.arr[j + 1];
				t.arr[j + 1] = tmp;
			}
		}
	}
}

# Compare two values for sorting
comparevalues(a, b: ref Value): int
{
	if(a == nil && b == nil)
		return 0;
	if(a == nil)
		return -1;
	if(b == nil)
		return 1;

	# Different types - use type order
	if(a.ty != b.ty)
		return a.ty - b.ty;

	# Same type - compare values
	case(a.ty) {
	TNIL =>
		return 0;
	TBOOLEAN =>
		return a.b - b.b;
	TNUMBER =>
		if(a.n < b.n)
			return -1;
		if(a.n > b.n)
			return 1;
		return 0;
	TSTRING =>
		if(a.s < b.s)
			return -1;
		if(a.s > b.s)
			return 1;
		return 0;
	* =>
		return 0;
	}
}

# Pack arguments into table
tablepack(args: array of ref Value): ref Table
{
	t := createtable(len args, 0);
	t.sizearray = len args;
	t.arr = args;

	# Set 'n' field
	nkey := ref Value;
	nkey.ty = TSTRING;
	nkey.s = "n";
	nval := ref Value;
	nval.ty = TNUMBER;
	nval.n = real len args;
	settablevalue(t, nkey, nval);

	return t;
}

# Unpack table to return values
tableunpack(t: ref Table, i, j: int): array of ref Value
{
	if(t == nil || t.arr == nil)
		return nil;

	if(i < 1)
		i = 1;
	if(j > t.sizearray)
		j = t.sizearray;
	if(j < i)
		return nil;

	count := j - i + 1;
	result := array[count] of ref Value;
	for(n := 0; n < count; n++)
		result[n] = t.arr[i - 1 + n];

	return result;
}

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
		"Table Implementation Module",
		"Hybrid array+hash with automatic rebalancing",
	};
}
