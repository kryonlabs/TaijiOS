# Lua VM for Inferno/Limbo - Main Integration
# Bridges Limbo and Lua VM

implement Luavm;

include "sys.m";
include "draw.m";
include "luavm.m";
include "lua_inferno.m";

sys: Sys;
print, sprint, fprint: import sys;

# Include VM modules (these will be loaded separately)
# The actual VM implementation is in lua/vm/

# ====================================================================
# Implementation
# ====================================================================

# Initialize Lua VM with context and arguments
init(ctxt: ref Draw->Context, argv: list of string): int
{
	# Load VM modules
	vm := load Luavm Luavm;
	if(vm == nil) {
		sys->fprint(sys->fildes(2), "lua: failed to load VM\n");
		return -1;
	}

	# Create new Lua state
	L := vm->newstate();
	if(L == nil) {
		sys->fprint(sys->fildes(2), "lua: failed to create state\n");
		return -1;
	}

	# Load standard libraries
	loadbaselib(L);
	loadstringlib(L);
	loadtablelib(L);
	loadmathlib(L);
	loadiolib(L);
	loadoslib(L);
	loadpackagelib(L);
	loaddebuglib(L);
	loadutf8lib(L);

	# Set global _OS
	osval := ref Value;
	osval.ty = TSTRING;
	osval.s = "inferno";

	setglobal(L, "_OS", osval);

	# Execute command line arguments or interactive mode
	if(argv != nil) {
		arg := hd argv;
		if(arg != nil && len arg > 0) {
			# Execute file
			if(dofile(L, arg) != OK) {
				err := tostring(L, L.stack[L.top - 1]);
				sys->fprint(sys->fildes(2), "lua: %s\n", err);
				return -1;
			}
		}
	}

	return 0;
}

# Create new Lua state
newstate(): ref State
{
	# This would call the actual VM initialization
	# For now, return a placeholder

	L := ref State;

	# Initialize stack
	L.stacksize = 2048;
	L.stack = array[L.stacksize] of ref Value;
	L.top = 0;
	L.base = 0;

	# Initialize globals
	L.globals = createtable(0, 50);

	# Initialize registry
	L.registry = createtable(0, 20);

	return L;
}

# Close Lua state
close(L: ref State)
{
	if(L == nil)
		return;

	# Free resources
	# In real implementation, this would trigger GC and cleanup

	L.globals = nil;
	L.registry = nil;
	L.stack = nil;
}

# Load string as Lua code
loadstring(L: ref State; code: string; chunkname: string): int
{
	if(L == nil || code == nil)
		return ERRSYNTAX;

	# Parse and compile code
	# This would call the actual lexer/parser/codegen

	# For now, just check if code is valid
	if(len code == 0)
		return ERRSYNTAX;

	return OK;
}

# Load and compile file
loadfile(L: ref State; filename: string): int
{
	if(L == nil || filename == nil)
		return ERRSYNTAX;

	# Open and read file
	fd := sys->open(filename, Sys->OREAD);
	if(fd == nil)
		return ERRRUN;

	buf := array[8192] of byte;
	all := "";
	while((n := fd.read(buf, len buf)) > 0) {
		all += string buf[0:n];
	}
	fd.close();

	# Compile
	return loadstring(L, all, filename);
}

# Load and execute file
dofile(L: ref State; filename: string): int
{
	if(L == nil || filename == nil)
		return ERRRUN;

	# Load file
	status := loadfile(L, filename);
	if(status != OK)
		return status;

	# Execute
	return pcall(L, 0, LUA_MULTRET);
}

# Protected call
pcall(L: ref State; nargs: int; nresults: int): int
{
	if(L == nil)
		return ERRERR;

	# Save stack top
	oldtop := L.top;

	# Set up error handler
	L->pushnil(L);

	# Call function (simplified)
	status := docall(L, nargs, nresults);

	# Restore stack if error
	if(status != OK) {
		L.top = oldtop + 1;
	}

	return status;
}

# Extended protected call with error handler
xpcall(L: ref State; nargs: int; nresults: int; errfunc: int): int
{
	if(L == nil)
		return ERRERR;

	# Set error handler index
	L.errfunc = errfunc;

	# Call
	status := docall(L, nargs, nresults);

	return status;
}

# Internal call function
docall(L: ref State; nargs: int; nresults: int): int
{
	# Get function
	if(L.top < nargs + 1)
		return ERRERR;

	funcval := L.stack[L.top - nargs - 1];
	if(funcval == nil || funcval.ty != TFUNCTION)
		return ERRERR;

	# Execute (placeholder)
	return OK;
}

LUA_MULTRET: con (-1);

# ====================================================================
# Library Loading Helpers
# ====================================================================

loadbaselib(L: ref State)
{
	lib := openbaselib_internal(L);
	if(lib != nil) {
		key := ref Value;
		key.ty = TSTRING;
		key.s = "_G";

		val := ref Value;
		val.ty = TTABLE;
		val.t = L.globals;

		settablevalue(lib, key, val);
	}
}

loadstringlib(L: ref State)
{
	lib := openstringlib_internal(L);
}

loadtablelib(L: ref State)
{
	lib := opentablelib_internal(L);
}

loadmathlib(L: ref State)
{
	lib := openmathlib_internal(L);
}

loadiolib(L: ref State)
{
	lib := openiolib_internal(L);
}

loadoslib(L: ref State)
{
	lib := openoslib_internal(L);
}

loadpackagelib(L: ref State)
{
	lib := openpackagelib_internal(L);
}

loaddebuglib(L: ref State)
{
	lib := opendebuglib_internal(L);
}

loadutf8lib(L: ref State)
{
	lib := openutf8lib_internal(L);
}

# Placeholder library open functions
# In real implementation, these would be imported from the library modules

openbaselib_internal(L: ref State): ref Table { return nil; }
openstringlib_internal(L: ref State): ref Table { return nil; }
opentablelib_internal(L: ref State): ref Table { return nil; }
openmathlib_internal(L: ref State): ref Table { return nil; }
openiolib_internal(L: ref State): ref Table { return nil; }
openoslib_internal(L: ref State): ref Table { return nil; }
openpackagelib_internal(L: ref State): ref Table { return nil; }
opendebuglib_internal(L: ref State): ref Table { return nil; }
openutf8lib_internal(L: ref State): ref Table { return nil; }

# ====================================================================
# Table Operations
# ====================================================================

createtable(narray: int, nhash: int): ref Table
{
	t := ref Table;

	t.sizearray = narray;
	if(narray > 0)
		t.arr = array[narray] of ref Value;

	t.sizehash = nhash;
	# Hash table allocation would go here

	return t;
}

settablevalue(t: ref Table, k, v: ref Value)
{
	if(t == nil || k == nil)
		return;

	# Array part
	if(k.ty == TNUMBER && k.n > 0.0 && k.n <= real(t.sizearray)) {
		i := int(k.n) - 1;
		if(t.arr != nil && i >= 0 && i < t.sizearray)
			t.arr[i] = v;
		return;
	}

	# Hash part (simplified)
	# Would use hash table lookup
}

gettablevalue(t: ref Table, k: ref Value): ref Value
{
	if(t == nil || k == nil)
		return nil;

	# Array part
	if(k.ty == TNUMBER && k.n > 0.0 && k.n <= real(t.sizearray)) {
		i := int(k.n) - 1;
		if(t.arr != nil && i >= 0 && i < t.sizearray)
			return t.arr[i];
	}

	# Hash part
	return nil;
}

setglobal(L: ref State; name: string; v: ref Value)
{
	if(L == nil || L.globals == nil)
		return;

	key := ref Value;
	key.ty = TSTRING;
	key.s = name;

	settablevalue(L.globals, key, v);
}

# ====================================================================
# Value Operations
# ====================================================================

tostring(L: ref State; v: ref Value): string
{
	if(v == nil)
		return "nil";

	case v.ty {
	TNIL =>
		return "nil";
	TBOOLEAN =>
		return v.b != 0 ? "true" : "false";
	TNUMBER =>
		return sprint("%g", v.n);
	TSTRING =>
		return v.s;
	TTABLE =>
		return sprint("table: %p", v.t);
	TFUNCTION =>
		return sprint("function: %p", v.f);
	TUSERDATA =>
		return sprint("userdata: %p", v.u);
	TTHREAD =>
		return sprint("thread: %p", v.th);
	* =>
		return "unknown";
	}
}

# ====================================================================
# Module Interface
# ====================================================================

initmodule(): string
{
	sys = load Sys Sys;
	return nil;
}

about(): array of string
{
	return array[] of {
		"Lua VM for Inferno/Limbo",
		"Main Integration Module",
		"Version 0.1 (Phase 8)",
	};
}
