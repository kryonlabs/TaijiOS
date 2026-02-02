# Lua VM - Table Library
# Implements table.* functions

implement Luavm;

include "sys.m";
include "luavm.m";
include "lua_baselib.m";

sys: Sys;
print, sprint, fprint: import sys;

# ====================================================================
# Table Operations
# ====================================================================

# table.concat(list[, sep[, i[, j]]) - Concatenate table elements
table_concat(L: ref State): int
{
	if(L == nil || L.top < 1)
		return 0;

	listval := L.stack[L.top - 1];

	if(listval == nil || listval.ty != TTABLE || listval.t == nil) {
		pushstring(L, "concat: table expected");
		return ERRRUN;
	}

	t := listval.t;

	# Get separator (default "")
	sep := "";
	if(L.top >= 2) {
		sepval := L.stack[L.top - 2];
		if(sepval != nil && sepval.ty == TSTRING)
			sep = sepval.s;
	}

	# Get range
	i := 1;
	j := tablelength(t);

	if(L.top >= 3) {
		ival := L.stack[L.top - 3];
		if(ival != nil && ival.ty == TNUMBER)
			i = int(ival.n);
	}
	if(L.top >= 4) {
		jval := L.stack[L.top - 4];
		if(jval != nil && jval.ty == TNUMBER)
			j = int(jval.n);
	}

	# Clamp indices
	len := tablelength(t);
	if(i < 1)
		i = 1;
	if(j > len)
		j = len;
	if(i > j) {
		pushstring(L, "");
		return 1;
	}

	# Concatenate elements
	result := "";
	for(n := i; n <= j; n++) {
		if(n > i)
			result += sep;

		# Get element at position n
		key := mknumber(real(n));
		val := gettablevalue(t, key);

		if(val != nil && val.ty == TSTRING)
			result += val.s;
		else if(val != nil)
			result += tostring(val);
	}

	pushstring(L, result);
	return 1;
}

# table.insert(list, pos[, value]) - Insert element
table_insert(L: ref State): int
{
	if(L == nil || L.top < 1)
		return 0;

	listval := L.stack[L.top - 1];

	if(listval == nil || listval.ty != TTABLE || listval.t == nil) {
		pushstring(L, "insert: table expected");
		return ERRRUN;
	}

	t := listval.t;

	# Get position
	pos := tablelength(t) + 1;  # Default: insert at end
	value := nil;  # Default: insert nil

	if(L.top >= 2) {
		posval := L.stack[L.top - 2];
		if(posval != nil && posval.ty == TNUMBER)
			pos = int(posval.n);

		if(L.top >= 3) {
			value = L.stack[L.top - 3];
		}
	} else {
		# Only table provided
		return 0;
	}

	# Check bounds
	if(pos < 1)
		pos = 1;
	if(pos > tablelength(t) + 1)
		pos = tablelength(t) + 1;

	# Shift elements to make room
	oldlen := tablelength(t);
	if(pos <= oldlen) {
		# Grow array if needed
		if(t.arr == nil || t.sizearray < oldlen + 1) {
			newsize := oldlen * 2;
			if(newsize < 8)
				newsize = 8;

			newarray := array[newsize] of ref Value;
			if(t.arr != nil && oldlen > 0)
				newarray[:oldlen] = t.arr[:oldlen];
			for(i := oldlen; i < newsize; i++) {
				v := ref Value;
				v.ty = TNIL;
				newarray[i] = v;
			}
			t.arr = newarray;
			t.sizearray = newsize;
		}

		# Shift elements
		for(i := oldlen; i >= pos; i--) {
			if(i + 1 <= t.sizearray && t.arr != nil) {
				if(i > 0)
					t.arr[i] = t.arr[i - 1];
				else
					t.arr[i] = value;
			}
		}
	}

	# Insert value
	if(pos <= t.sizearray && t.arr != nil) {
		t.arr[pos - 1] = value;
	}

	return 0;
}

# table.remove(list[, pos]) - Remove element
table_remove(L: ref State): int
{
	if(L == nil || L.top < 1)
		return 0;

	listval := L.stack[L.top - 1];

	if(listval == nil || listval.ty != TTABLE || listval.t == nil) {
		pushstring(L, "remove: table expected");
		return ERRRUN;
	}

	t := listval.t;

	# Get position
	pos := tablelength(t);  # Default: remove last
	if(L.top >= 2) {
		posval := L.stack[L.top - 2];
		if(posval != nil && posval.ty == TNUMBER)
			pos = int(posval.n);
	}

	# Check bounds
	len := tablelength(t);
	if(pos < 1 || pos > len) {
		pushnil(L);
		return 1;
	}

	# Get removed value
	key := mknumber(real(pos));
	retval := gettablevalue(t, key);

	# Shift elements down
	if(t.arr != nil && pos < len) {
		for(i := pos; i < len; i++) {
			t.arr[i - 1] = t.arr[i];
		}
	}

	# Clear last slot
	if(t.arr != nil && len > 0) {
		v := ref Value;
		v.ty = TNIL;
		t.arr[len - 1] = v;
	}

	pushvalue(L, retval);
	return 1;
}

# table.sort(list[, comp]) - Sort table
table_sort(L: ref State): int
{
	if(L == nil || L.top < 1)
		return 0;

	listval := L.stack[L.top - 1];

	if(listval == nil || listval.ty != TTABLE || listval.t == nil) {
		pushstring(L, "sort: table expected");
		return ERRRUN;
	}

	t := listval.t;

	# Get comparator
	comp: ref Value = nil;
	ascending := 1;

	if(L.top >= 2) {
		comp = L.stack[L.top - 2];
		if(comp != nil && comp.ty == TNIL || comp.ty == TFUNCTION)
			comp = nil;
	}

	# Simple bubble sort for array part
	if(t.arr != nil) {
		n := t.sizearray;

		for(i := 0; i < n - 1; i++) {
			for(j := 0; j < n - i - 1; j++) {
				ij := i + j + 1;
				ij1 := ij - 1;

				compare := -1;
				if(comp != nil) {
					# Use custom comparator
					# Would call comp(t.arr[ij1], t.arr[ij])
				}

				if(compare > 0) {
					# Swap
					tmp := t.arr[ij1];
					t.arr[ij1] = t.arr[ij];
					t.arr[ij] = tmp;
				}
			}
		}
	}

	return 0;
}

# table.pack(...) - Pack arguments into table
table_pack(L: ref State): int
{
	if(L == nil)
		return 0;

	n := L.top;
	t := createtable(n, 0);
	t.sizearray = n;
	t.arr = array[n] of ref Value;

	for(i := 0; i < n; i++) {
		if(L.stack[i] != nil)
			t.arr[i] = L.stack[i];
		else {
			v := ref Value;
			v.ty = TNIL;
			t.arr[i] = v;
		}
	}

	# Set 'n' field
	nkey := ref Value;
	nkey.ty = TSTRING;
	nkey.s = "n";

	nval := ref Value;
	nval.ty = TNUMBER;
	nval.n = real(n);

	settablevalue(t, nkey, nval);

	pushvalue(L, mktable(t));
	return 1;
}

# table.unpack(list[, i[, j]]) - Unpack table
table_unpack(L: ref State): int
{
	if(L == nil || L.top < 1)
		return 0;

	listval := L.stack[L.top - 1];

	if(listval == nil || listval.ty != TTABLE || listval.t == nil) {
		pushnil(L);
		return 1;
	}

	t := listval.t;

	# Get range
	i := 1;
	j := tablelength(t);

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

	# Clamp
	len := tablelength(t);
	if(i < 1)
		i = 1;
	if(j > len)
		j = len;
	if(i > j) {
		return 0;  # No results
	}

	# Unpack elements
	nresults := j - i + 1;
	for(n := i; n <= j; n++) {
		key := mknumber(real(n));
		val := gettablevalue(t, key);
		pushvalue(L, val);
	}

	return nresults;
}

# table.move(a1, f, e, t[, a2]) - Move elements
table_move(L: ref State): int
{
	if(L == nil || L.top < 3)
		return 0;

	a1 := L.stack[L.top - 1];
	f := L.stack[L.top - 2];
	e := L.stack[L.top - 3];
	t := L.stack[L.top - 4];
	a2: ref Value = nil;

	if(L.top >= 5)
		a2 = L.stack[L.top - 5];

	# Validate parameters
	if(a1 == nil || a1.ty != TTABLE || a1.t == nil)
		return 0;

	if(f == nil || f.ty != TNUMBER || t == nil || t.ty != TTABLE || t.t == nil)
		return 0;

	# Get indices
	from := int(f.n);
	to := int(t.n);

	# Implementation would move elements from a1[from:e] to t
	# Simplified placeholder

	return 0;
}

# table.foreachi(table, f) - Apply function to array
table_foreachi(L: ref State): int
{
	if(L == nil || L.top < 2)
		return 0;

	tableval := L.stack[L.top - 1];
	funcval := L.stack[L.top - 2];

	if(tableval == nil || tableval.ty != TTABLE || tableval.t == nil)
		return 0;

	if(funcval == nil || funcval.ty != TFUNCTION)
		return 0;

	t := tableval.t;

	# Iterate over array part
	if(t.arr != nil) {
		for(i := 0; i < t.sizearray; i++) {
			val := t.arr[i];
			if(val != nil && val.ty != TNIL) {
				# Call function(index, value)
				# Would push i and val, call func, pop results
			}
		}
	}

	return 0;
}

# table.maxn(table) - Get maximum numeric index
table_maxn(L: ref State): int
{
	if(L == nil || L.top < 1)
		return 0;

	tableval := L.stack[L.top - 1];

	if(tableval == nil || tableval.ty != TTABLE || tableval.t == nil) {
		pushnumber(L, 0.0);
		return 1;
	}

	t := tableval.t;

	# Find maximum integer key in array part
	maxn := 0;
	if(t.arr != nil) {
		for(i := t.sizearray - 1; i >= 0; i--) {
			if(t.arr[i] != nil && t.arr[i].ty != TNIL) {
				maxn = i + 1;
				break;
			}
		}
	}

	# Check hash part for larger integer keys
	# (simplified)

	pushnumber(L, real(maxn));
	return 1;
}

# table.getn(table) - Get table length
table_getn(L: ref State): int
{
	if(L == nil || L.top < 1)
		return 0;

	tableval := L.stack[L.top - 1];

	if(tableval == nil || tableval.ty != TTABLE || tableval.t == nil) {
		pushnumber(L, 0.0);
		return 1;
	}

	pushnumber(L, real(tablelength(tableval.t)));
	return 1;
}

# ====================================================================
# Helper Functions
# ====================================================================

# Get table length (border in array part)
tablelength(t: ref Table): int
{
	if(t == nil)
		return 0;

	# Find first nil in array
	if(t.arr != nil) {
		for(i := t.sizearray - 1; i >= 0; i--) {
			if(t.arr[i] == nil || t.arr[i].ty == TNIL)
				return i;
		}
		return t.sizearray;
	}
	return 0;
}

# ====================================================================
# Library Registration
# ====================================================================

# Open table library
open table(L: ref State): int
{
	if(L == nil)
		return 0;

	# Create table library table
	lib := createtable(0, 20);

	# Register functions
	setlibfunc(lib, "concat", table_concat);
	setlibfunc(lib, "insert", table_insert);
	setlibfunc(lib, "remove", table_remove);
	setlibfunc(lib, "sort", table_sort);
	setlibfunc(lib, "pack", table_pack);
	setlibfunc(lib, "unpack", table_unpack);
	setlibfunc(lib, "move", table_move);
	setlibfunc(lib, "foreachi", table_foreachi);
	setlibfunc(lib, "maxn", table_maxn);
	setlibfunc(lib, "getn", table_getn);

	pushvalue(L, mktable(lib));
	return 1;
}

# Set library function
setlibfunc(lib: ref Table, name: string, func: fn(L: ref State): int)
{
	if(lib == nil)
		return;

	# Create C function wrapper
	f := ref Function;
	f.isc = 1;
	f.cfunc = func;
	f.upvals = nil;
	f.env = nil;

	# Set in library table
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
		"Table Library",
		"Table manipulation functions",
	};
}
