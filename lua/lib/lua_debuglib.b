# Lua VM - Debug Library
# Implements debug.* functions
# Provides debugging and introspection capabilities

implement Luavm;

include "sys.m";
include "draw.m";
include "luavm.m";
include "lua_baselib.m";

sys: Sys;
print, sprint, fprint: import sys;

# ====================================================================
# Debug Functions
# ====================================================================

# debug.debug() - Enter debug mode
debug_debug(L: ref State): int
{
	if(L == nil)
		return 0;

	# Enter interactive debug mode
	# This is a simplified implementation

	pushstring(L, "Enter Lua debug mode (type 'cont' to continue)\n");

	# In a real implementation, this would start a REPL
	# For now, just return

	return 0;
}

# debug.getfcontent([f]) - Get function environment
debug_getfenv(L: ref State): int
{
	if(L == nil)
		return 0;

	# Get function from stack or level 1
	fval: ref Value;

	if(L.top >= 1) {
		fval = L.stack[L.top - 1];
		if(fval == nil || fval.ty != TFUNCTION) {
			pushnil(L);
			return 1;
		}
	} else {
		pushnil(L);
		return 1;
	}

	f := fval.f;
	if(f == nil) {
		pushnil(L);
		return 1;
	}

	# Return function's environment table
	if(f.env != nil)
		pushvalue(L, mktable(f.env));
	else
		pushnil(L);

	return 1;
}

# debug.gethook([thread]) - Get hook settings
debug_gethook(L: ref State): int
{
	if(L == nil)
		return 0;

	# Get hook settings from state
	if(L.hookmask != nil)
		pushstring(L, L.hookmask);
	else
		pushnil(L);

	if(L.hookcount != nil)
		pushnumber(L, real L.hookcount);
	else
		pushnil(L);

	if(L.hookfunc != nil)
		pushvalue(L, mkfunction(L.hookfunc));
	else
		pushnil(L);

	return 3;
}

# debug.getinfo([thread,] f[, what]) - Get function info
debug_getinfo(L: ref State): int
{
	if(L == nil)
		return 0;

	# Get function
	fval: ref Value;

	if(L.top >= 1) {
		fval = L.stack[L.top - 1];
		if(fval == nil)
			fval = L.stack[0];  # Try level 1
	} else {
		pushnil(L);
		return 1;
	}

	if(fval == nil) {
		pushnil(L);
		return 1;
	}

	# Get what string (default "flnStu")
	what := "flnStu";
	if(L.top >= 2) {
		whatval := L.stack[L.top - 2];
		if(whatval != nil && whatval.ty == TSTRING)
			what = whatval.s;
	}

	# Create info table
	info := createtable(0, 10);

	# Fill in requested info
	key := ref Value;
	val := ref Value;
	key.ty = TSTRING;

	# Source
	if(contains(what, "S")) {
		key.s = "source";
		val.ty = TSTRING;
		if(fval.ty == TFUNCTION && fval.f != nil && fval.f.proto != nil)
			val.s = fval.f.proto.source;
		else
			val.s = "=[C]";
		settablevalue(info, key, val);

		# what
		key.s = "what";
		if(fval.ty == TFUNCTION && fval.f != nil && fval.f.isc == 0)
			val.s = "Lua";
		else
			val.s = "C";
		settablevalue(info, key, val);
	}

	# Line info
	if(contains(what, "l")) {
		key.s = "currentline";
		val.ty = TNUMBER;
		if(fval.ty == TFUNCTION && fval.f != nil && fval.f.proto != nil)
			val.n = real(fval.f.proto.linedefined);
		else
			val.n = -1.0;
		settablevalue(info, key, val);
	}

	# Name
	if(contains(what, "n")) {
		key.s = "name";
		val.ty = TSTRING;
		if(fval.ty == TFUNCTION && fval.f != nil && fval.f.proto != nil)
			val.s = fval.f.proto.name;
		else
			val.s = "";
		settablevalue(info, key, val);
	}

	# Function type
	if(contains(what, "t")) {
		key.s = "what";
		val.ty = TSTRING;
		if(fval.ty == TFUNCTION && fval.f != nil && fval.f.isc == 0)
			val.s = "Lua";
		else
			val.s = "C";
		settablevalue(info, key, val);
	}

	pushvalue(L, mktable(info));
	return 1;
}

# debug.getlocal([thread,] f, i) - Get local variable
debug_getlocal(L: ref State): int
{
	if(L == nil || L.top < 2)
		return 0;

	# Get function and index
	fval := L.stack[L.top - 1];
	ival := L.stack[L.top - 2];

	if(fval == nil || ival == nil || ival.ty != TNUMBER) {
		pushnil(L);
		return 1;
	}

	i := int(ival.n);

	# Get local from function
	if(fval.ty == TFUNCTION && fval.f != nil && fval.f.proto != nil) {
		proto := fval.f.proto;

		if(i >= 0 && i < proto.nlocvars) {
			locvar := proto.locvars[i];

			# Get value from stack or upvalue
			# This is simplified

			pushstring(L, locvar.name);
			pushnil(L);  # Value would be retrieved from stack

			return 2;
		}
	}

	pushnil(L);
	return 1;
}

# debug.getmetatable(value) - Get metatable
debug_getmetatable(L: ref State): int
{
	if(L == nil || L.top < 1)
		return 0;

	val := L.stack[L.top - 1];
	if(val == nil)
		return 0;

	case val.ty {
	TTABLE =>
		if(val.t != nil && val.t.meta != nil)
			pushvalue(L, mktable(val.t.meta));
		else
			pushnil(L);

	TUSERDATA =>
		if(val.u_meta != nil)
			pushvalue(L, mktable(val.u_meta));
		else
			pushnil(L);

	* =>
		pushnil(L);
	}

	return 1;
}

# debug.getregistry() - Get registry table
debug_getregistry(L: ref State): int
{
	if(L == nil)
		return 0;

	if(L.registry != nil)
		pushvalue(L, mktable(L.registry));
	else
		pushnil(L);

	return 1;
}

# debug.getupvalue(f, i) - Get upvalue
debug_getupvalue(L: ref State): int
{
	if(L == nil || L.top < 2)
		return 0;

	fval := L.stack[L.top - 1];
	ival := L.stack[L.top - 2];

	if(fval == nil || fval.ty != TFUNCTION ||
	   ival == nil || ival.ty != TNUMBER) {
		pushnil(L);
		return 1;
	}

	i := int(ival.n);

	f := fval.f;
	if(f == nil || f.isc != 0 || f.upvals == nil) {
		pushnil(L);
		return 1;
	}

	if(i < 0 || i >= f.nupvals)
		return 0;

	# Get upvalue
	upval := f.upvals[i];
	if(upval == nil || upval.v == nil) {
		pushnil(L);
		return 1;
	}

	# Get upvalue name from prototype
	name := "";
	if(f.proto != nil && f.proto.upvalues != nil && i < len f.proto.upvalues)
		name = f.proto.upvalues[i];

	pushstring(L, name);
	pushvalue(L, upval.v^);

	return 2;
}

# debug.setfcontent(f, table) - Set function environment
debug_setfenv(L: ref State): int
{
	if(L == nil || L.top < 2)
		return 0;

	fval := L.stack[L.top - 1];
	tabval := L.stack[L.top - 2];

	if(fval == nil || fval.ty != TFUNCTION)
		return 0;

	if(tabval == nil || tabval.ty != TTABLE)
		return 0;

	f := fval.f;
	if(f == nil)
		return 0;

	# Set environment
	f.env = tabval.t;

	pushvalue(L, fval);
	return 1;
}

# debug.sethook([thread,] hook, mask[, count]) - Set hook
debug_sethook(L: ref State): int
{
	if(L == nil)
		return 0;

	# Get hook function
	hookval: ref Value = nil;

	if(L.top >= 1) {
		hookval = L.stack[L.top - 1];
	}

	# Get mask
	mask := "";
	if(L.top >= 2) {
		maskval := L.stack[L.top - 2];
		if(maskval != nil && maskval.ty == TSTRING)
			mask = maskval.s;
	}

	# Get count
	count := 0;
	if(L.top >= 3) {
		countval := L.stack[L.top - 3];
		if(countval != nil && countval.ty == TNUMBER)
			count = int(countval.n);
	}

	# Set hook
	if(hookval != nil && hookval.ty == TFUNCTION) {
		L.hookfunc = hookval.f;
		L.hookmask = mask;
		L.hookcount = count;
	} else {
		# Clear hook
		L.hookfunc = nil;
		L.hookmask = nil;
		L.hookcount = 0;
	}

	return 0;
}

# debug.setlocal([thread,] f, i, value) - Set local variable
debug_setlocal(L: ref State): int
{
	if(L == nil || L.top < 3)
		return 0;

	fval := L.stack[L.top - 1];
	ival := L.stack[L.top - 2];
	valval := L.stack[L.top - 3];

	if(fval == nil || ival == nil || ival.ty != TNUMBER)
		return 0;

	i := int(ival.n);

	# Set local in function
	if(fval.ty == TFUNCTION && fval.f != nil) {
		# This would modify the stack or upvalue
		# Simplified implementation

		pushstring(L, sprint("local_%d", i));
		return 1;
	}

	return 0;
}

# debug.setmetatable(value, table) - Set metatable
debug_setmetatable(L: ref State): int
{
	if(L == nil || L.top < 2)
		return 0;

	val := L.stack[L.top - 1];
	tabval := L.stack[L.top - 2];

	if(tabval == nil || tabval.ty != TTABLE)
		return 0;

	case val.ty {
	TTABLE =>
		if(val.t != nil)
			val.t.meta = tabval.t;
		pushvalue(L, val);

	TUSERDATA =>
		val.u_meta = tabval.t;
		pushvalue(L, val);

	* =>
		pushnil(L);
	}

	return 1;
}

# debug.setupvalue(f, i, value) - Set upvalue
debug_setupvalue(L: ref State): int
{
	if(L == nil || L.top < 3)
		return 0;

	fval := L.stack[L.top - 1];
	ival := L.stack[L.top - 2];
	valval := L.stack[L.top - 3];

	if(fval == nil || fval.ty != TFUNCTION ||
	   ival == nil || ival.ty != TNUMBER)
		return 0;

	i := int(ival.n);

	f := fval.f;
	if(f == nil || f.isc != 0 || f.upvals == nil)
		return 0;

	if(i < 0 || i >= f.nupvals)
		return 0;

	# Set upvalue
	upval := f.upvals[i];
	if(upval != nil && upval.v != nil) {
		upval.v^ = valval;
	}

	# Return upvalue name
	name := "";
	if(f.proto != nil && f.proto.upvalues != nil && i < len f.proto.upvalues)
		name = f.proto.upvalues[i];

	pushstring(L, name);
	return 1;
}

# debug.traceback([thread,] [message[, level]]) - Get stack trace
debug_traceback(L: ref State): int
{
	if(L == nil)
		return 0;

	# Get message
	message := "";
	if(L.top >= 1) {
		msgval := L.stack[L.top - 1];
		if(msgval != nil && msgval.ty == TSTRING)
			message = msgval.s;
	}

	# Get level
	level := 1;
	if(L.top >= 2) {
		levelval := L.stack[L.top - 2];
		if(levelval != nil && levelval.ty == TNUMBER)
			level = int(levelval.n);
	}

	# Generate traceback
	trace := "";

	if(len message > 0)
		trace += message + "\n";

	trace += "stack traceback:\n";

	# Walk the call stack
	if(L.ci != nil) {
		frame := L.ci;
		lev := 1;

		while(frame != nil) {
			if(lev >= level) {
				trace += sprint("\t[%d]: ", lev);

				if(frame.func != nil && frame.func.proto != nil) {
					proto := frame.func.proto;
					if(len proto.name > 0)
						trace += sprint("function '%s'", proto.name);
					else
						trace += "function";

					if(len proto.source > 0)
						trace += sprint(" at %s:%d", proto.source, proto.linedefined);
				} else {
					trace += "C function";
				}

				trace += "\n";
			}

			frame = frame.previous;
			lev++;
		}
	}

	pushstring(L, trace);
	return 1;
}

# ====================================================================
# Helper Functions
# ====================================================================

# Check if string contains character
contains(s: string, c: int): int
{
	if(s == nil)
		return 0;

	for(i := 0; i < len s; i++) {
		if(s[i] == c)
			return 1;
	}
	return 0;
}

# ====================================================================
# Library Registration
# ====================================================================

# Open debug library
open debug(L: ref State): int
{
	if(L == nil)
		return 0;

	# Create debug library table
	lib := createtable(0, 15);

	# Register functions
	setlibfunc(lib, "debug", debug_debug);
	setlibfunc(lib, "getfenv", debug_getfenv);
	setlibfunc(lib, "gethook", debug_gethook);
	setlibfunc(lib, "getinfo", debug_getinfo);
	setlibfunc(lib, "getlocal", debug_getlocal);
	setlibfunc(lib, "getmetatable", debug_getmetatable);
	setlibfunc(lib, "getregistry", debug_getregistry);
	setlibfunc(lib, "getupvalue", debug_getupvalue);
	setlibfunc(lib, "setfenv", debug_setfenv);
	setlibfunc(lib, "sethook", debug_sethook);
	setlibfunc(lib, "setlocal", debug_setlocal);
	setlibfunc(lib, "setmetatable", debug_setmetatable);
	setlibfunc(lib, "setupvalue", debug_setupvalue);
	setlibfunc(lib, "traceback", debug_traceback);

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
		"Debug Library",
		"Debugging and introspection",
	};
}
