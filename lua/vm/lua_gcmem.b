# Lua VM - GC Interface and collectgarbage()
# Implements memory allocation and GC control interface

implement Luavm;

include "sys.m";
include "luavm.m";
include "lua_gc.m";
include "lua_incrementalgc.m";

sys: Sys;
print, sprint, fprint: import sys;

# ====================================================================
# Memory Allocation
# ====================================================================

# Allocate GC object
allocluaobj(sz: int, type: int, L: ref State): ref GCheader
{
	if(L == nil)
		return nil;

	g := getglobalgc(L);
	if(g == nil)
		return nil;

	# Update total bytes
	g.totalbytes += big(sz);

	# Check if GC needed
	if(g.totalbytes > g.gctrigger) {
		# Trigger GC
		if(!g.gcstop) {
			singlestep(g, L);
		}
	}

	# Allocate in young generation if using generational
	if(g.ggcmajorinc > 0) {
		return allocyoung(g, sz, type);
	}

	# Otherwise regular allocation
	obj := ref GCheader;
	obj.marked = CURRENT;
	obj.tt = type;
	obj.next = g.allgc;
	obj.refcount = 1;
	g.allgc = obj;

	return obj;
}

# Free GC object
freeluaobj(g: ref G, obj: ref GCheader)
{
	if(g == nil || obj == nil)
		return;

	sz := 0;
	case(obj.tt) {
	TSTRING =>	sz = 32;
	TTABLE =>	sz = 64;
	TFUNCTION =>	sz = 48;
	TUSERDATA =>	sz = 32;
	TTHREAD =>	sz = 128;
	TPROTO =>	sz = 64;
	}

	g.totalbytes -= big(sz);
}

# ====================================================================
# GC Control Interface
# ====================================================================

# collectgarbage("collect") - Full collection
collectgarbage_collect(L: ref State): int
{
	if(L == nil)
		return 0;

	g := getglobalgc(L);
	if(g == nil)
		return 0;

	# Stop incremental if running
	wasinc := g.gcemergency;
	g.gcemergency = 1;

	# Run full collection
	freed := fullgc(g, L);

	# Restore
	g.gcemergency = wasinc;

	# Push bytes collected
	pushnumber(L, real(freed));
	return 1;
}

# collectgarbage("stop") - Stop GC
collectgarbage_stop(L: ref State): int
{
	if(L == nil)
		return 0;

	g := getglobalgc(L);
	if(g == nil)
		return 0;

	g.gcstop = 1;
	return 0;
}

# collectgarbage("restart") - Restart GC
collectgarbage_restart(L: ref State): int
{
	if(L == nil)
		return 0;

	g := getglobalgc(L);
	if(g == nil)
		return 0;

	g.gcstop = 0;
	return 0;
}

# collectgarbage("count") - Get memory in KB
collectgarbage_count(L: ref State): int
{
	if(L == nil)
		return 0;

	g := getglobalgc(L);
	if(g == nil)
		return 0;

	kb := g.totalbytes / 1024big;
	pushnumber(L, real(kb));
	return 1;
}

# collectgarbage("countB") - Get remainder / 1024
collectgarbage_countB(L: ref State): int
{
	if(L == nil)
		return 0;

	g := getglobalgc(L);
	if(g == nil)
		return 0;

	rem := g.totalbytes % 1024big;
	pushnumber(L, real(rem));
	return 1;
}

# collectgarbage("step") - Incremental step
collectgarbage_step(L: ref State, arg: real): int
{
	if(L == nil)
		return 0;

	g := getglobalgc(L);
	igc := getglobaligc(L);
	if(g == nil || igc == nil)
		return 0;

	# If argument is 0 or not provided, do single step
	if(arg == 0.0) {
		work := incstep(L, igc, 0);
		pushboolean(L, 1);
		return 1;
	}

	# Otherwise, step until memory is reduced by arg*KB
	target := g.totalbytes - big(arg * 1024.0);

	while(g.totalbytes > target) {
		work := incstep(L, igc, 0);
		if(work == 0big)
			break;
	}

	pushboolean(L, 1);
	return 1;
}

# collectgarbage("setpause") - Set pause parameter
collectgarbage_setpause(L: ref State, pause: real): int
{
	if(L == nil)
		return 0;

	igc := getglobaligc(L);
	if(igc == nil)
		return 0;

	p := int(pause);
	if(p < 50 || p > 500) {
		pushstring(L, "pause out of range");
		return ERRRUN;
	}

	setgcpause(igc, p);
	pushnumber(L, pause);
	return 1;
}

# collectgarbage("setstepmul") - Set step multiplier
collectgarbage_setstepmul(L: ref State, mul: real): int
{
	if(L == nil)
		return 0;

	igc := getglobaligc(L);
	if(igc == nil)
		return 0;

	m := int(mul);
	if(m < 0 || m > 5000) {
		pushstring(L, "step multiplier out of range");
		return ERRRUN;
	}

	setgcmajorinc(igc, m);
	pushnumber(L, mul);
	return 1;
}

# collectgarbage("isrunning") - Check if GC is running
collectgarbage_isrunning(L: ref State): int
{
	if(L == nil)
		return 0;

	g := getglobalgc(L);
	if(g == nil)
		return 0;

	running := !g.gcstop;
	pushboolean(L, running);
	return 1;
}

# collectgarbage("generational") - Toggle generational GC
collectgarbage_generational(L: ref State, enable: int): int
{
	if(L == nil)
		return 0;

	g := getglobalgc(L);
	if(g == nil)
		return 0;

	if(enable != 0) {
		g.gcmajorinc = 200;  # Enable generational
	} else {
		g.gcmajorinc = 0;  # Disable
	}

	pushboolean(L, enable);
	return 1;
}

# ====================================================================
# Main collectgarbage Function
# ====================================================================

# collectgarbage(opt [, arg]) - Main GC control function
collectgarbage(L: ref State): int
{
	if(L == nil || L.top < 1)
		return 0;

	opt := L.stack[L.top - 1];
	if(opt == nil || opt.ty != TSTRING) {
		pushstring(L, "collectgarbage: string expected");
		return ERRRUN;
	}

	option := opt.s;

	case(option) {
	"collect" =>
		return collectgarbage_collect(L);

	"stop" =>
		return collectgarbage_stop(L);

	"restart" =>
		return collectgarbage_restart(L);

	"count" =>
		return collectgarbage_count(L);

	"countB" =>
		return collectgarbage_countB(L);

	"step" =>
		arg := 0.0;
		if(L.top >= 2) {
			argval := L.stack[L.top - 2];
			if(argval != nil && argval.ty == TNUMBER)
				arg = argval.n;
		}
		return collectgarbage_step(L, arg);

	"setpause" =>
		if(L.top < 2) {
			pushstring(L, "setpause: argument expected");
			return ERRRUN;
		}
		pauseval := L.stack[L.top - 2];
		if(pauseval == nil || pauseval.ty != TNUMBER) {
			pushstring(L, "setpause: number expected");
			return ERRRUN;
		}
		return collectgarbage_setpause(L, pauseval.n);

	"setstepmul" =>
		if(L.top < 2) {
			pushstring(L, "setstepmul: argument expected");
			return ERRRUN;
		}
		mulval := L.stack[L.top - 2];
		if(mulval == nil || mulval.ty != TNUMBER) {
			pushstring(L, "setstepmul: number expected");
			return ERRRUN;
		}
		return collectgarbage_setstepmul(L, mulval.n);

	"isrunning" =>
		return collectgarbage_isrunning(L);

	"generational" =>
		enable := 1;
		if(L.top >= 2) {
			enableval := L.stack[L.top - 2];
			if(enableval != nil && enableval.ty == TBOOLEAN)
				enable = enableval.b;
		}
		return collectgarbage_generational(L, enable);

	* =>
		pushstring(L, "collectgarbage: invalid option");
		return ERRRUN;
	}
}

# ====================================================================
# Module Interface Functions
# ====================================================================

# Get global GC state
getglobalgc(L: ref State): ref G
{
	if(L == nil)
		return nil;
	# Would return actual global GC state
	return nil;
}

# Get global incremental GC state
getglobaligc(L: ref State): ref IGC
{
	if(L == nil)
		return nil;
	# Would return actual incremental GC state
	return nil;
}

# Get table value
gettablevalue(t: ref Table, key: ref Value): ref Value
{
	if(t == nil || key == nil)
		return nil;
	result := ref Value;
	result.ty = TNIL;
	return result;
}

# Push values
pushnumber(L: ref State, n: real)
{
	if(L == nil || L.stack == nil)
		return;
	v := ref Value;
	v.ty = TNUMBER;
	v.n = n;
	if(L.top < len L.stack)
		L.stack[L.top++] = v;
}

pushboolean(L: ref State, b: int)
{
	if(L == nil || L.stack == nil)
		return;
	v := ref Value;
	v.ty = TBOOLEAN;
	v.b = b;
	if(L.top < len L.stack)
		L.stack[L.top++] = v;
}

pushstring(L: ref State, s: string)
{
	if(L == nil || L.stack == nil)
		return;
	v := ref Value;
	v.ty = TSTRING;
	v.s = s;
	if(L.top < len L.stack)
		L.stack[L.top++] = v;
}

# Type constants
TNIL, TBOOLEAN, TNUMBER, TSTRING, TTABLE, TFUNCTION, TUSERDATA, TTHREAD: con iota;

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
		"GC Interface and collectgarbage()",
		"Memory allocation and GC control",
	};
}
