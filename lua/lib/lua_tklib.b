# Lua VM - Tk Library
# Implements tk.* functions for Inferno
# Provides Tk widget control and event handling

implement Lua_tklib;

include "sys.m";
include "draw.m";
include "tk.m";
include "tkclient.m";
include "luavm.m";
include "lua_tklib.m";

sys: Sys;
print, sprint, fprint, pctl: import sys;

tk: Tk;
Toplevel: import tk;

luavm: Luavm;
State, Value, Table, TNIL, TNUMBER, TSTRING, TFUNCTION, TUSERDATA, TTABLE: import luavm;

# ====================================================================
# Module State
# ====================================================================

tkctxt: ref Toplevel;           # Tk toplevel context
callbacks: ref Table;           # Callback registry: "widget:event" -> TkCallback
timers: list of ref TkTimer;    # Active timers

# ====================================================================
# Helper Functions
# ====================================================================

# Check if argument is a string
checkstring(L: ref State; idx: int): (string, int)
{
	if(L == nil || idx < 0 || idx >= L.top)
		return (nil, 0);

	val := L.stack[L.top - idx];
	if(val == nil || val.ty != TSTRING)
		return (nil, 0);

	return (val.s, 1);
}

# Check if argument is a number
checknumber(L: ref State; idx: int): (real, int)
{
	if(L == nil || idx < 0 || idx >= L.top)
		return (0.0, 0);

	val := L.stack[L.top - idx];
	if(val == nil || val.ty != TNUMBER)
		return (0.0, 0);

	return (val.n, 1);
}

# Check if argument is a function
checkfunction(L: ref State; idx: int): (ref Value, int)
{
	if(L == nil || idx < 0 || idx >= L.top)
		return (nil, 0);

	val := L.stack[L.top - idx];
	if(val == nil || val.ty != TFUNCTION)
		return (nil, 0);

	return (val, 1);
}

# Register callback in registry
registercallback(widget: string; event: string; func: ref Value; L: ref State)
{
	if(callbacks == nil)
		callbacks = luavm->createtable(0, 10);

	# Create callback
	cb := ref TkCallback;
	cb.lua_func = func;
	cb.L = L;
	cb.widget = widget;
	cb.event = event;

	# Store in registry
	key := ref Value;
	key.ty = TSTRING;
	key.s = widget + ":" + event;

	val := ref Value;
	val.ty = TUSERDATA;
	val.u = cb;

	luavm->settablevalue(callbacks, key, val);
}

# Lookup callback in registry
lookupcallback(widget: string; event: string): ref TkCallback
{
	if(callbacks == nil)
		return nil;

	key := ref Value;
	key.ty = TSTRING;
	key.s = widget + ":" + event;

	val := luavm->gettablevalue(callbacks, key);
	if(val == nil || val.ty != TUSERDATA)
		return nil;

	cb := val.u;
	if(cb == nil)
		return nil;

	return cb;
}

# ====================================================================
# Tk Functions
# ====================================================================

# tk.cmd(command) -> string
tk_cmd(L: ref State): int
{
	if(L == nil || L.top < 1)
		return 0;

	(cmd, ok) := checkstring(L, 1);
	if(!ok) {
		luavm->pushstring(L, "cmd: command must be string");
		return luavm->ERRRUN;
	}

	if(tkctxt == nil) {
		luavm->pushstring(L, "cmd: Tk context not set");
		return luavm->ERRRUN;
	}

	# Execute Tk command
	result := tk->cmd(tkctxt, cmd);

	# Return result
	if(result != nil)
		luavm->pushstring(L, result);
	else
		luavm->pushstring(L, "");

	return 1;
}

# tk.getvar(name) -> string
tk_getvar(L: ref State): int
{
	if(L == nil || L.top < 1)
		return 0;

	(name, ok) := checkstring(L, 1);
	if(!ok) {
		luavm->pushstring(L, "getvar: name must be string");
		return luavm->ERRRUN;
	}

	if(tkctxt == nil) {
		luavm->pushstring(L, "getvar: Tk context not set");
		return luavm->ERRRUN;
	}

	# Get Tk variable
	result := tk->cmd(tkctxt, "set " + name);

	if(result != nil)
		luavm->pushstring(L, result);
	else
		luavm->pushstring(L, "");

	return 1;
}

# tk.setvar(name, value)
tk_setvar(L: ref State): int
{
	if(L == nil || L.top < 2)
		return 0;

	(name, okn) := checkstring(L, 2);
	(val, okv) := checkstring(L, 1);

	if(!okn || !okv) {
		luavm->pushstring(L, "setvar: name and value must be strings");
		return luavm->ERRRUN;
	}

	if(tkctxt == nil) {
		luavm->pushstring(L, "setvar: Tk context not set");
		return luavm->ERRRUN;
	}

	# Set Tk variable
	tk->cmd(tkctxt, "set " + name + " " + val);

	return 0;
}

# tk.bind(widget, event, func)
tk_bind(L: ref State): int
{
	if(L == nil || L.top < 3)
		return 0;

	(widget, okw) := checkstring(L, 3);
	(event, oke) := checkstring(L, 2);
	(func, okf) := checkfunction(L, 1);

	if(!okw || !oke || !okf) {
		luavm->pushstring(L, "bind: widget (string), event (string), and function required");
		return luavm->ERRRUN;
	}

	if(tkctxt == nil) {
		luavm->pushstring(L, "bind: Tk context not set");
		return luavm->ERRRUN;
	}

	# Register callback
	registercallback(widget, event, func, L);

	# Create Tk binding
	# The binding sends: lua_bind:widget:event %s
	bindcmd := sprint("bind %s %s {send cmd lua_bind:%s:%s %%s}", widget, event, widget, event);
	tk->cmd(tkctxt, bindcmd);

	return 0;
}

# tk.after(ms, func)
tk_after(L: ref State): int
{
	if(L == nil || L.top < 2)
		return 0;

	(ms, okm) := checknumber(L, 2);
	(func, okf) := checkfunction(L, 1);

	if(!okm || !okf) {
		luavm->pushstring(L, "after: delay (number) and function required");
		return luavm->ERRRUN;
	}

	delay := int ms;

	# Get current time
	(now, _) := sys->millisec();

	# Create timer
	timer := ref TkTimer;
	timer.lua_func = func;
	timer.L = L;
	timer.delay = delay;
	timer.due = now + delay;

	# Add to timer list
	timers = timer :: timers;

	return 0;
}

# ====================================================================
# Callback Dispatch
# ====================================================================

# Dispatch a callback from Tk to Lua
dispatchcallback(widget: string; event: string; data: string)
{
	if(callbacks == nil)
		return;

	# Lookup callback
	cb := lookupcallback(widget, event);
	if(cb == nil)
		return;

	L := cb.L;
	if(L == nil)
		return;

	# Push function
	luavm->pushvalue(L, cb.lua_func);

	# Push data argument
	if(data != nil)
		luavm->pushstring(L, data);
	else
		luavm->pushstring(L, "");

	# Call function (protected)
	status := luavm->pcall(L, 1, 0);

	if(status != luavm->OK) {
		# Error in callback
		if(L.top > 0) {
			val := L.stack[L.top - 1];
			if(val != nil && val.ty == TSTRING) {
				sys->fprint(sys->fildes(2), "tk callback error: %s\n", val.s);
			}
		}
	}
}

# Process and fire due timers
processtimers()
{
	if(timers == nil)
		return;

	# Get current time
	(now, _) := sys->millisec();

	# Check each timer
	fired: list of ref TkTimer = nil;
	remaining: list of ref TkTimer = nil;

	while(timers != nil) {
		timer := hd timers;
		timers = tl timers;

		if(timer.due <= now) {
			# Timer is due - fire it
			fired = timer :: fired;
		} else {
			# Timer not due yet - keep it
			remaining = timer :: remaining;
		}
	}

	# Update timer list
	timers = remaining;

	# Fire all due timers
	while(fired != nil) {
		timer := hd fired;
		fired = tl fired;

		L := timer.L;
		if(L != nil) {
			# Push function
			luavm->pushvalue(L, timer.lua_func);

			# Call function (no arguments)
			status := luavm->pcall(L, 0, 0);

			if(status != luavm->OK) {
				# Error in timer callback
				if(L.top > 0) {
					val := L.stack[L.top - 1];
					if(val != nil && val.ty == TSTRING) {
						sys->fprint(sys->fildes(2), "tk timer error: %s\n", val.s);
					}
				}
			}
		}
	}
}

# ====================================================================
# Library Registration
# ====================================================================

# Set library function
setlibfunc(lib: ref Table; name: string; func: fn(L: ref State): int)
{
	if(lib == nil)
		return;

	f := ref luavm->Function;
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

	luavm->settablevalue(lib, key, val);
}

# Open tk library
opentk(L: ref State): int
{
	if(L == nil)
		return 0;

	# Initialize callback registry
	if(callbacks == nil)
		callbacks = luavm->createtable(0, 20);

	# Create tk library table
	lib := luavm->createtable(0, 5);

	# Register functions
	setlibfunc(lib, "cmd", tk_cmd);
	setlibfunc(lib, "getvar", tk_getvar);
	setlibfunc(lib, "setvar", tk_setvar);
	setlibfunc(lib, "bind", tk_bind);
	setlibfunc(lib, "after", tk_after);

	# Set global 'tk'
	val := ref Value;
	val.ty = TTABLE;
	val.t = lib;

	key := ref Value;
	key.ty = TSTRING;
	key.s = "tk";

	luavm->settablevalue(L.global, key, val);

	return 0;
}

# Set Tk context
setctxt(top: ref Toplevel; wlua: ref WluaContext)
{
	tkctxt = top;
	# wlua is stored but not directly used yet
}

# ====================================================================
# Module Interface
# ====================================================================

init(): string
{
	sys = load Sys Sys;
	tk = load Tk Tk;
	luavm = load Luavm Luavm;

	if(luavm == nil)
		return "cannot load Luavm";

	return nil;
}

about(): array of string
{
	return array[] of {
		"Lua VM for Inferno/Limbo",
		"Tk Library",
		"Tk widget control and event handling for Inferno",
	};
}
