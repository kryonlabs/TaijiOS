# Lua VM - Type Marshaling System
# Converts between Lua values and Limbo types
# Supports basic types, arrays, lists, ADTs, and functions

implement Luavm;

include "sys.m";
include "draw.m";
include "luavm.m";
include "lua_baselib.m";

sys: Sys;
print, sprint, fprint: import sys;

luavm: Luavm;
State, Value, Table, Function, TNIL, TNUMBER, TSTRING, TFUNCTION, TUSERDATA, TTABLE, TBOOLEAN: import luavm;

# ====================================================================
# Type Converter Registry
# ====================================================================

TypeConverter: adt {
	typestr: string;          # Type signature (e.g., "array of int")
	tolimbo: fn(val: ref Value): ref Value;  # Lua to Limbo
	tolua: fn(limboval: ref Value, L: ref State): int;  # Limbo to Lua
};

converters: list of ref TypeConverter;

# Register custom type converter
registerconverter(typestr: string; conv: ref TypeConverter)
{
	conv.typestr = typestr;
	converters = conv :: converters;
}

# Find converter for type
findconverter(typestr: string): ref TypeConverter
{
	for(c := converters; c != nil; c = tl c) {
		conv := hd c;
		if(conv.typestr == typestr)
			return conv;
	}
	return nil;
}

# ====================================================================
# Basic Type Marshaling
# ====================================================================

# Convert Lua value to Limbo value based on type signature
lua2limbo(L: ref State; idx: int; typesig: string): ref Value
{
	if(L == nil || idx < 0 || idx >= L.top)
		return nil;

	val := L.stack[L.top - idx];
	if(val == nil)
		return nil;

	# Parse type signature
	return lua2limbo_typed(L, val, typesig);
}

# Internal converter with type dispatch
lua2limbo_typed(L: ref State; val: ref Value; typesig: string): ref Value
{
	if(val == nil)
		return nil;

	# Handle basic types
	case typesig {
	"int" or "int" =>
		return lua2int(L, val);

	"real" =>
		return lua2real(L, val);

	"string" =>
		return lua2string(L, val);

	"byte" =>
		return lua2byte(L, val);

	"nil" =>
		if(val.ty == TNIL)
			return mklimbonil();
		return nil;

	* =>
		# Check for array types
		if(len typesig > 10 && typesig[0:10] == "array of ") {
			elemtype := typesig[10:];
			return lua2array(L, val, elemtype);
		}

		# Check for list types
		if(len typesig > 8 && typesig[0:8] == "list of ") {
			elemtype := typesig[8:];
			return lua2list(L, val, elemtype);
		}

		# Check for custom converter
		conv := findconverter(typesig);
		if(conv != nil)
			return conv.tolimbo(val);

		# Unknown type - treat as ADT/ref
		return lua2ref(L, val, typesig);
	}
}

# Convert Lua value to int
lua2int(L: ref State; val: ref Value): ref Value
{
	if(val == nil || val.ty != TNUMBER)
		return nil;

	# Range check for 32-bit int
	if(val.n < -2.147e9 || val.n > 2.147e9)
		return nil;

	result := ref Value;
	result.ty = TNUMBER;  # Store as number, consumer converts to int
	result.n = val.n;
	return result;
}

# Convert Lua value to real
lua2real(L: ref State; val: ref Value): ref Value
{
	if(val == nil || val.ty != TNUMBER)
		return nil;

	result := ref Value;
	result.ty = TNUMBER;
	result.n = val.n;
	return result;
}

# Convert Lua value to string
lua2string(L: ref State; val: ref Value): ref Value
{
	if(val == nil)
		return nil;

	if(val.ty == TSTRING) {
		result := ref Value;
		result.ty = TSTRING;
		result.s = val.s;
		return result;
	}

	if(val.ty == TNUMBER) {
		# Convert number to string
		result := ref Value;
		result.ty = TSTRING;
		result.s = sprint("%g", val.n);
		return result;
	}

	if(val.ty == TBOOLEAN) {
		result := ref Value;
		result.ty = TSTRING;
		result.s = (val.b != 0) ? "true" : "false";
		return result;
	}

	return nil;
}

# Convert Lua value to byte
lua2byte(L: ref State; val: ref Value): ref Value
{
	if(val == nil)
		return nil;

	if(val.ty == TNUMBER) {
		i := int val.n;
		if(i < 0 || i > 255)
			return nil;

		result := ref Value;
		result.ty = TNUMBER;
		result.n = real(i);
		return result;
	}

	if(val.ty == TSTRING && len val.s == 1) {
		result := ref Value;
		result.ty = TNUMBER;
		result.n = real(int val.s[0]);
		return result;
	}

	return nil;
}

# Convert Lua table to Limbo array
lua2array(L: ref State; val: ref Value; elemtype: string): ref Value
{
	if(val == nil || val.ty != TTABLE)
		return nil;

	tab := val.t;
	if(tab == nil)
		return nil;

	# Count elements
	n := 0;
	for(i := 1; i <= 10000; i++) {  # Max array size limit
		key := ref Value;
		key.ty = TNUMBER;
		key.n = real(i);

		elem := luavm->gettablevalue(tab, key);
		if(elem == nil || elem.ty == TNIL)
			break;

		n++;
	}

	if(n == 0)
		return nil;

	# Create array value (store as Lua table for now)
	result := ref Value;
	result.ty = TTABLE;
	result.t = tab;

	return result;
}

# Convert Lua table to Limbo list
lua2list(L: ref State; val: ref Value; elemtype: string): ref Value
{
	if(val == nil || val.ty != TTABLE)
		return nil;

	# Lists are represented as tables with integer keys
	tab := val.t;
	if(tab == nil)
		return nil;

	result := ref Value;
	result.ty = TTABLE;
	result.t = tab;

	return result;
}

# Convert Lua userdata to Limbo ref (ADT)
lua2ref(L: ref State; val: ref Value; typestr: string): ref Value
{
	if(val == nil || val.ty != TUSERDATA)
		return nil;

	# Userdata should already be a Limbo object reference
	result := ref Value;
	result.ty = TUSERDATA;
	result.u = val.u;

	return result;
}

# Create Limbo nil value
mklimbonil(): ref Value
{
	result := ref Value;
	result.ty = TNIL;
	return result;
}

# ====================================================================
# Limbo to Lua Conversion
# ====================================================================

# Convert Limbo value to Lua value based on type signature
limbo2lua(L: ref State; limboval: ref Value; typesig: string): int
{
	if(L == nil || limboval == nil)
		return 0;

	# Parse type signature
	return limbo2lua_typed(L, limboval, typesig);
}

# Internal converter with type dispatch
limbo2lua_typed(L: ref State; val: ref Value; typesig: string): int
{
	if(val == nil) {
		luavm->pushnil(L);
		return 1;
	}

	# Handle basic types
	case typesig {
	"int" or "int" =>
		return int2lua(L, val);

	"real" =>
		return real2lua(L, val);

	"string" =>
		return string2lua(L, val);

	"byte" =>
		return byte2lua(L, val);

	"nil" =>
		luavm->pushnil(L);
		return 1;

	* =>
		# Check for array types
		if(len typesig > 10 && typesig[0:10] == "array of ") {
			elemtype := typesig[10:];
			return array2lua(L, val, elemtype);
		}

		# Check for list types
		if(len typesig > 8 && typesig[0:8] == "list of ") {
			elemtype := typesig[8:];
			return list2lua(L, val, elemtype);
		}

		# Check for custom converter
		conv := findconverter(typesig);
		if(conv != nil)
			return conv.tolua(val, L);

		# Unknown type - treat as ADT/ref
		return ref2lua(L, val, typesig);
	}
}

# Convert int to Lua
int2lua(L: ref State; val: ref Value): int
{
	if(val == nil) {
		luavm->pushnil(L);
		return 1;
	}

	result := ref Value;
	result.ty = TNUMBER;
	if(val.ty == TNUMBER)
		result.n = val.n;
	else
		result.n = 0.0;

	luavm->pushvalue(L, result);
	return 1;
}

# Convert real to Lua
real2lua(L: ref State; val: ref Value): int
{
	if(val == nil) {
		luavm->pushnil(L);
		return 1;
	}

	result := ref Value;
	result.ty = TNUMBER;
	if(val.ty == TNUMBER)
		result.n = val.n;
	else
		result.n = 0.0;

	luavm->pushvalue(L, result);
	return 1;
}

# Convert string to Lua
string2lua(L: ref State; val: ref Value): int
{
	if(val == nil) {
		luavm->pushnil(L);
		return 1;
	}

	result := ref Value;
	result.ty = TSTRING;
	if(val.ty == TSTRING)
		result.s = val.s;
	else
		result.s = "";

	luavm->pushvalue(L, result);
	return 1;
}

# Convert byte to Lua
byte2lua(L: ref State; val: ref Value): int
{
	if(val == nil) {
		luavm->pushnil(L);
		return 1;
	}

	result := ref Value;
	result.ty = TNUMBER;
	if(val.ty == TNUMBER)
		result.n = val.n;
	else
		result.n = 0.0;

	luavm->pushvalue(L, result);
	return 1;
}

# Convert array to Lua table
array2lua(L: ref State; val: ref Value; elemtype: string): int
{
	if(val == nil || val.ty != TTABLE) {
		luavm->pushnil(L);
		return 1;
	}

	# Already a table - just push it
	luavm->pushvalue(L, val);
	return 1;
}

# Convert list to Lua table
list2lua(L: ref State; val: ref Value; elemtype: string): int
{
	if(val == nil) {
		luavm->pushnil(L);
		return 1;
	}

	# If already a table, push it
	if(val.ty == TTABLE) {
		luavm->pushvalue(L, val);
		return 1;
	}

	# Otherwise create table from list
	tab := luavm->createtable(0, 10);
	luavm->pushvalue(L, mktable(tab));
	return 1;
}

# Convert ref (ADT) to Lua userdata
ref2lua(L: ref State; val: ref Value; typestr: string): int
{
	if(val == nil) {
		luavm->pushnil(L);
		return 1;
	}

	# Wrap in userdata
	result := ref Value;
	result.ty = TUSERDATA;
	result.u = val.u;

	luavm->pushvalue(L, result);
	return 1;
}

# ====================================================================
# Helper Functions
# ====================================================================

# Make table value
mktable(t: ref Table): ref Value
{
	val := ref Value;
	val.ty = TTABLE;
	val.t = t;
	return val;
}

# Make nil value
mknil(): ref Value
{
	val := ref Value;
	val.ty = TNIL;
	return val;
}

# Make boolean value
mkbool(b: int): ref Value
{
	val := ref Value;
	val.ty = TBOOLEAN;
	val.b = b;
	return val;
}

# ====================================================================
# Complex Type Support
# ====================================================================

# Parse type signature to extract component types
parsetypesig(sig: string): (string, string)
{
	# Returns (base_type, element_type) for arrays/lists
	if(len sig > 10 && sig[0:10] == "array of ") {
		return ("array", sig[10:]);
	}

	if(len sig > 8 && sig[0:8] == "list of ") {
		return ("list", sig[8:]);
	}

	return (sig, "");
}

# Check if type is numeric
isnumeric(typestr: string): int
{
	return typestr == "int" || typestr == "real" || typestr == "byte";
}

# Check if type is a reference type
isref(typestr: string): int
{
	# Arrays, lists, and ADTs are reference types
	return (len typestr > 10 && typestr[0:10] == "array of ") ||
	       (len typestr > 8 && typestr[0:8] == "list of ") ||
	       (!isnumeric(typestr) && typestr != "string" && typestr != "nil");
}

# ====================================================================
# Error Handling
# ====================================================================

typeerror(expected: string; got: int): string
{
	gotstr := "unknown";
	case got {
	TNIL =>
		gotstr = "nil";
	TNUMBER =>
		gotstr = "number";
	TSTRING =>
		gotstr = "string";
	TBOOLEAN =>
		gotstr = "boolean";
	TTABLE =>
		gotstr = "table";
	TFUNCTION =>
		gotstr = "function";
	TUSERDATA =>
		gotstr = "userdata";
	}

	return sprint("type error: expected %s, got %s", expected, gotstr);
}

# ====================================================================
# Module Interface
# ====================================================================

init(): string
{
	sys = load Sys Sys;
	converters = nil;
	return nil;
}

about(): array of string
{
	return array[] of {
		"Lua VM for Inferno/Limbo",
		"Type Marshaling System",
		"Converts between Lua and Limbo types",
		"Supports: int, real, string, byte, arrays, lists, ADTs",
	};
}
