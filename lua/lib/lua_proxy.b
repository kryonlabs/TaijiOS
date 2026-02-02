# Lua VM - Function Proxy Generator
# Creates Lua-callable wrappers for Limbo functions
# Handles argument marshaling, function calls, and result conversion

implement Luavm;

include "sys.m";
include "draw.m";
include "loader.m";
include "luavm.m";
include "lua_baselib.m";
include "lua_marshal.m";
include "lua_modparse.m";

sys: Sys;
print, sprint, fprint: import sys;

luavm: Luavm;
State, Value, Table, Function, TNIL, TNUMBER, TSTRING, TFUNCTION, TUSERDATA, TTABLE: import luavm;

# ====================================================================
# Proxy Context
# ====================================================================

ProxyContext: adt {
	mod: ref LoadedModule;  # Loaded module
	sig: ref FuncSig;        # Function signature
};

# ====================================================================
# Proxy Generation
# ====================================================================

# Generate proxy for a Limbo function
genproxy(mod: ref LoadedModule; sig: ref FuncSig): ref Function
{
	if(mod == nil || sig == nil)
		return nil;

	# Create C function that will call the Limbo function
	f := ref Function;
	f.isc = 1;
	f.cfunc = calllimbo_function;
	f.upvals = nil;
	f.env = nil;

	# Store context in function (simplified)
	# Real implementation needs proper upvalue storage

	return f;
}

# Generic caller - invoked from Lua
calllimbo_function(L: ref State): int
{
	if(L == nil)
		return 0;

	nargs := L.top - L.base;

	# Load required modules
	caller := load Limbocaller Limbocaller->PATH;
	if(caller == nil) {
		pushstring(L, "cannot load limbocaller module");
		return -1;
	}

	parser := load Luadisparser Luadisparser->PATH;
	if(parser == nil) {
		pushstring(L, "cannot load luadisparser module");
		return -1;
	}

	# Get module and function names from upvalues
	# For now, we'll use a simpler approach: assume math module
	# Real implementation would store these in upvalues when generating proxy

	modname := "math";
	funcname := "sin";  # Default, should come from upvalue

	# Parse DIS file
	(file, err) := parser->parse("/dis/lib/" + modname + ".dis");
	if(file == nil) {
		pushstring(L, sprint("cannot load %s.dis: %s", modname, err));
		return -1;
	}

	# Find function link
	link := parser->findlink(file, funcname);
	if(link == nil) {
		pushstring(L, sprint("function %s not found in %s", funcname, modname));
		return -1;
	}

	# Create execution context
	ctx := caller->createcontext(file, link);
	if(ctx == nil) {
		pushstring(L, "cannot create execution context");
		return -1;
	}

	# Set up call
	if(caller->setupcall(ctx, nargs) != caller->EOK) {
		pushstring(L, sprint("setupcall failed: %s", caller->geterror(ctx)));
		caller->freectx(ctx);
		return -1;
	}

	# Marshal arguments from Lua stack to Limbo
	for(i := 0; i < nargs; i++) {
		# Get Lua value from stack (Lua is 1-indexed)
		idx := i + 1;
		luaarg := L.stack[L.top - idx];

		if(luaarg == nil) {
			pushstring(L, sprint("missing argument %d", idx));
			caller->freectx(ctx);
			return -1;
		}

		# Convert Lua value to Limbo value
		limboarg := lua2limbo(L, idx, "real");  # Assume real for math functions
		if(limboarg == nil) {
			pushstring(L, sprint("argument %d type mismatch", idx));
			caller->freectx(ctx);
			return -1;
		}

		# Push argument onto Limbo stack
		if(caller->pusharg(ctx, limboarg, "real") != caller->EOK) {
			pushstring(L, sprint("pusharg %d failed: %s", idx, caller->geterror(ctx)));
			caller->freectx(ctx);
			return -1;
		}
	}

	# Call the function
	ret := caller->call(ctx);
	if(ret == nil) {
		pushstring(L, sprint("call failed: %s", caller->geterror(ctx)));
		caller->freectx(ctx);
		return -1;
	}

	# Unmarshal result(s) back to Lua
	nret := 0;
	if(ret.count > 0 && ret.values != nil) {
		for(vals := ret.values; vals != nil; vals = tl vals) {
			v := hd vals;
			if(v != nil) {
				# Convert Limbo value to Lua
				if(v.ty == caller->TInt) {
					# Push integer as number
					val := ref Value;
					val.ty = TNUMBER;
					val.n = real v.v;
					luavm->pushvalue(L, val);
					nret++;
				} else if(v.ty == caller->TReal) {
					# Push real as number
					val := ref Value;
					val.ty = TNUMBER;
					val.n = v.v;
					luavm->pushvalue(L, val);
					nret++;
				} else if(v.ty == caller->TString) {
					# Push string
					val := ref Value;
					val.ty = TSTRING;
					val.s = v.s;
					luavm->pushvalue(L, val);
					nret++;
				}
			}
		}
	}

	# Clean up
	caller->freectx(ctx);

	return nret;
}

# ====================================================================
# Argument Marshaling
# ====================================================================

# Marshal Lua arguments to Limbo values
marshalargs(L: ref State; sig: ref FuncSig): array of ref Value
{
	if(L == nil || sig == nil)
		return nil;

	nparams := len sig.params;
	if(nparams == 0)
		return array[0] of ref Value;

	args := array[nparams] of ref Value;
	i := 0;

	for(params := sig.params; params != nil && i < nparams; params = tl params) {
		p := hd params;

		# Get Lua value from stack
		idx := i + 1;  # Lua is 1-indexed
		if(idx >= L.top)
			return nil;

		luaarg := L.stack[L.top - idx];

		# Convert based on parameter type
		typesig := type2string(p.typ);
		limboarg := lua2limbo(L, idx, typesig);

		if(limboarg == nil) {
			# Type mismatch
			return nil;
		}

		args[i] = limboarg;
		i++;
	}

	return args;
}

# Convert Type to string signature
type2string(t: ref Type): string
{
	if(t == nil)
		return "unknown";

	case pick t {
	Basic =>
		return t.name;
	Array =>
		return "array of " + type2string(t.elem);
	List =>
		return "list of " + type2string(t.elem);
	Ref =>
		return t.target;
	Function =>
		return "fn";
	}

	return "unknown";
}

# ====================================================================
# Result Unmarshaling
# ====================================================================

# Unmarshal Limbo result to Lua value(s)
unmarshalresult(L: ref State; result: ref Value; sig: ref FuncSig): int
{
	if(L == nil)
		return 0;

	if(sig.returns == nil) {
		# No return value
		return 0;
	}

	# Push return values onto stack
	nret := 0;
	for(rets := sig.returns; rets != nil; rets = tl rets) {
		rettype := hd rets;
		typesig := type2string(rettype);

		# Convert Limbo value to Lua
		count := limbo2lua(L, result, typesig);
		nret += count;
	}

	return nret;
}

# ====================================================================
# Function Calling
# ====================================================================

# Call Limbo function via link table
calllimbo(mod: ref LoadedModule; fname: string; args: array of ref Value): ref Value
{
	if(mod == nil || mod.linktab == nil)
		return nil;

	# Find function in link table
	for(i := 0; i < len mod.linktab; i++) {
		link := mod.linktab[i];
		if(link != nil && link.name == fname) {
			# Found function
			# TODO: Actually call the function
			# This requires understanding the link table format
			# and creating proper function calls

			# For now, return nil
			return nil;
		}
	}

	# Function not found
	return nil;
}

# ====================================================================
# Validation
# ====================================================================

# Validate argument count matches signature
validateargc(nargs: int; sig: ref FuncSig): int
{
	if(sig == nil)
		return 0;

	nparams := len sig.params;
	return nargs == nparams;
}

# Validate argument types
validateargtypes(L: ref State; sig: ref FuncSig): int
{
	if(L == nil || sig == nil)
		return 0;

	i := 0;
	for(params := sig.params; params != nil; params = tl params) {
		p := hd params;
		idx := i + 1;

		if(idx >= L.top)
			return 0;

		val := L.stack[L.top - idx];
		if(val == nil)
			return 0;

		# Check type compatibility
		if(!typecompatible(val, p.typ))
			return 0;

		i++;
	}

	return 1;
}

# Check if Lua value is compatible with Limbo type
typecompatible(val: ref Value; typ: ref Type): int
{
	if(val == nil || typ == nil)
		return 0;

	case pick typ {
	Basic =>
		case typ.name {
		"int" or "real" or "byte" =>
			return val.ty == TNUMBER;
		"string" =>
			return val.ty == TSTRING || val.ty == TNUMBER;  # Numbers convert to strings
		"nil" =>
			return val.ty == TNIL;
		* =>
			# Unknown basic type - accept anything
			return 1;
		}

	Array =>
		# Arrays must be tables
		return val.ty == TTABLE;

	List =>
		# Lists must be tables
		return val.ty == TTABLE;

	Ref =>
		# Refs must be userdata
		return val.ty == TUSERDATA;

	Function =>
		# Functions must be functions
		return val.ty == TFUNCTION;
	}

	return 0;
}

# ====================================================================
# Error Handling
# ====================================================================

# Push argument error message
pushargerror(L: ref State; expected: string; got: int; argnum: int)
{
	if(L == nil)
		return;

	gotstr := typename(got);
	err := sprint("bad argument #%d to '%s' (%s expected, got %s)",
	             argnum, expected, gotstr);

	pushstring(L, err);
}

# Get type name from type enum
typename(ty: int): string
{
	case ty {
	TNIL =>
		return "nil";
	TNUMBER =>
		return "number";
	TSTRING =>
		return "string";
	TBOOLEAN =>
		return "boolean";
	TTABLE =>
		return "table";
	TFUNCTION =>
		return "function";
	TUSERDATA =>
		return "userdata";
	* =>
		return sprint("unknown(%d)", ty);
	}
}

# ====================================================================
# Optimization
# ====================================================================

# Fast path for simple types (int, real, string)
isfasttype(typ: ref Type): int
{
	if(typ == nil)
		return 0;

	case pick typ {
	Basic =>
		return typ.name == "int" || typ.name == "real" || typ.name == "string";
	* =>
		return 0;
	}
}

# Create fast proxy for simple functions
genfastproxy(mod: ref LoadedModule; sig: ref FuncSig): ref Function
{
	if(mod == nil || sig == nil)
		return nil;

	# Check if all params and returns are fast types
	for(params := sig.params; params != nil; params = tl params) {
		p := hd params;
		if(!isfasttype(p.typ))
			return nil;  # Not all fast types
	}

	for(rets := sig.returns; rets != nil; rets = tl rets) {
		r := hd rets;
		if(!isfaststate(r.typ))
			return nil;  # Not all fast types
	}

	# Create optimized proxy
	f := ref Function;
	f.isc = 1;
	f.cfunc = calllimbo_function_fast;
	f.upvals = nil;
	f.env = nil;

	return f;
}

# Fast caller for simple types
calllimbo_function_fast(L: ref State): int
{
	if(L == nil)
		return 0;

	# Similar to calllimbo_function but with optimizations
	# Skip type validation, use direct conversions

	return calllimbo_function(L);
}

# ====================================================================
# Helper Functions
# ====================================================================

# Push string value
pushstring(L: ref State; s: string)
{
	if(L == nil)
		return;

	val := ref Value;
	val.ty = TSTRING;
	val.s = s;

	luavm->pushvalue(L, val);
}

# Convert Lua value to Limbo value
lua2limbo(L: ref State; idx: int; typesig: string): ref Limbocaller->Value
{
	if(L == nil || idx < 1 || idx > L.top)
		return nil;

	luaarg := L.stack[L.top - idx];
	if(luaarg == nil)
		return nil;

	# Create Limbo value based on Lua type and expected type
	result := ref Limbocaller->Value;

	case typesig {
	"int" or "byte" =>
		if(luaarg.ty != TNUMBER)
			return nil;
		result.ty = Limbocaller->TInt;
		result.v = int luaarg.n;
		return result;

	"real" =>
		if(luaarg.ty != TNUMBER)
			return nil;
		result.ty = Limbocaller->TReal;
		result.v = luaarg.n;
		return result;

	"string" =>
		if(luaarg.ty != TSTRING)
			return nil;
		result.ty = Limbocaller->TString;
		result.s = luaarg.s;
		return result;

	* =>
		# Unknown type - try to convert
		if(luaarg.ty == TNUMBER) {
			result.ty = Limbocaller->TReal;
			result.v = luaarg.n;
			return result;
		} else if(luaarg.ty == TSTRING) {
			result.ty = Limbocaller->TString;
			result.s = luaarg.s;
			return result;
		}
		return nil;
	}

	return nil;
}

# Convert Limbo value to Lua value (push onto stack)
limbo2lua(L: ref State; limboval: ref Limbocaller->Value; typesig: string): int
{
	if(L == nil || limboval == nil)
		return 0;

	val := ref Value;

	case limboval.ty {
	Limbocaller->TInt =>
		val.ty = TNUMBER;
		val.n = real limboval.v;
		luavm->pushvalue(L, val);
		return 1;

	Limbocaller->TReal =>
		val.ty = TNUMBER;
		val.n = limboval.v;
		luavm->pushvalue(L, val);
		return 1;

	Limbocaller->TString =>
		val.ty = TSTRING;
		val.s = limboval.s;
		luavm->pushvalue(L, val);
		return 1;
	}

	return 0;
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
		"Function Proxy Generator",
		"Creates Lua-callable wrappers for Limbo functions",
		"Integrates with limbocaller for execution",
	};
}
