# Lua VM - .dis Module Loader
# Loads Limbo .dis files as Lua modules

implement Luavm;

include "sys.m";
include "draw.m";
include "luavm.m";
include "lua_inferno.m";

sys: Sys;
print, sprint, fprint: import sys;

# ====================================================================
# .dis Module Loading
# ====================================================================

# Module cache
dismodules: ref Table;

# Initialize .dis loader
initdisloader()
{
	dismodules = createtable(0, 20);
}

# Load .dis module
loaddismodule(L: ref State; modname: string): ref Value
{
	if(L == nil || modname == nil)
		return nil;

	# Initialize if needed
	if(dismodules == nil)
		initdisloader();

	# Check cache
	key := ref Value;
	key.ty = TSTRING;
	key.s = modname;

	cached := gettablevalue(dismodules, key);
	if(cached != nil && cached.ty != TNIL)
		return cached;

	# Try to load .dis file
	modulepath := findmodule(modname);
	if(modulepath == nil)
		return nil;

	# Load the .dis module
	mod := loadlimbomodule(modulepath);
	if(mod == nil)
		return nil;

	# Cache it
	val := ref Value;
	val.ty = TTABLE;
	val.t = mod;

	settablevalue(dismodules, key, val);

	return val;
}

# Find module file
findmodule(modname: string): string
{
	if(modname == nil)
		return nil;

	# Convert module name to file path
	# e.g., "mymodule" -> "mymodule.dis"
	# e.g., "mypackage.submodule" -> "mypackage/submodule.dis"

	# Search paths to try
	paths := [] of {
		"./" + modname + ".dis",
		"/dis/lib/" + modname + ".dis",
		"/dis/lib/" + modname + ".dis",
		"./" + replaceslashes(modname) + ".dis",
		"/dis/lib/" + replaceslashes(modname) + ".dis",
	};

	for(i := 0; i < len paths; i++) {
		fd := sys->open(paths[i], Sys->OREAD);
		if(fd != nil) {
			fd.close();
			return paths[i];
		}
	}

	return nil;
}

# Replace dots with slashes
replaceslashes(s: string): string
{
	if(s == nil)
		return nil;

	result := "";
	for(i := 0; i < len s; i++) {
		if(s[i] == '.')
			result[len result] = '/';
		else
			result[len result] = s[i];
	}
	return result;
}

# Load Limbo .dis module
loadlimbomodule(path: string): ref Table
{
	if(path == nil)
		return nil;

	# In a real implementation, this would use Sys->load or similar
	# to dynamically load the .dis file

	# For now, create a placeholder table
	mod := createtable(0, 10);

	# Set module name
	key := ref Value;
	key.ty = TSTRING;
	key.s = "_NAME";

	val := ref Value;
	val.ty = TSTRING;
	val.s = path;

	settablevalue(mod, key, val);

	# Set module path
	key.s = "_PATH";
	val.s = path;
	settablevalue(mod, key, val);

	return mod;
}

# Register .dis loader in package.searchers
registerdisloader(L: ref State)
{
	if(L == nil)
		return;

	# Get package table
	packkey := ref Value;
	packkey.ty = TSTRING;
	packkey.s = "package";

	packval := gettablevalue(L.globals, packkey);
	if(packval == nil || packval.ty != TTABLE)
		return;

	package := packval.t;

	# Get searchers table
	searcherskey := ref Value;
	searcherskey.ty = TSTRING;
	searcherskey.s = "searchers";

	searchersval := gettablevalue(package, searcherskey);
	if(searchersval == nil || searchersval.ty != TTABLE)
		return;

	searchers := searchersval.t;

	# Add .dis loader as searcher 5 (after standard Lua searchers)
	loaderkey := ref Value;
	loaderkey.ty = TNUMBER;
	loaderkey.n = 5.0;

	loaderval := ref Value;
	loaderval.ty = TFUNCTION;
	loaderval.f = newcclosure(dismodule_loader);

	settablevalue(searchers, loaderkey, loaderval);
}

# .dis module searcher function
dismodule_loader(L: ref State): int
{
	if(L == nil || L.top < 1)
		return 0;

	nameval := L.stack[L.top - 1];
	if(nameval == nil || nameval.ty != TSTRING) {
		pushstring(L, "loader: module name must be string");
		return ERRRUN;
	}

	modname := nameval.s;

	# Try to load .dis module
	mod := loaddismodule(L, modname);
	if(mod != nil) {
		# Return module table
		pushvalue(L, mktable(mod));
		return 1;
	}

	# Not found
	return 0;
}

# ====================================================================
# Module Export Helpers
# ====================================================================

# Export Limbo function to Lua module
exportfunction(mod: ref Table; name: string; func: fn(L: ref State): int)
{
	if(mod == nil || name == nil)
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

	settablevalue(mod, key, val);
}

# Export string constant to Lua module
exportstring(mod: ref Table; name: string; value: string)
{
	if(mod == nil || name == nil)
		return;

	key := ref Value;
	key.ty = TSTRING;
	key.s = name;

	val := ref Value;
	val.ty = TSTRING;
	val.s = value;

	settablevalue(mod, key, val);
}

# Export number constant to Lua module
exportnumber(mod: ref Table; name: string; value: real)
{
	if(mod == nil || name == nil)
		return;

	key := ref Value;
	key.ty = TSTRING;
	key.s = name;

	val := ref Value;
	val.ty = TNUMBER;
	val.n = value;

	settablevalue(mod, key, val);
}

# ====================================================================
# Helper Functions
# ====================================================================

createtable(narray: int, nhash: int): ref Table
{
	t := ref Table;
	t.sizearray = narray;
	if(narray > 0)
		t.arr = array[narray] of ref Value;
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

	return nil;
}

pushstring(L: ref State; s: string)
{
	if(L == nil)
		return;

	if(L.top >= L.stacksize)
		return;

	val := ref Value;
	val.ty = TSTRING;
	val.s = s;

	L.stack[L.top] = val;
	L.top++;
}

pushvalue(L: ref State; v: ref Value)
{
	if(L == nil || v == nil)
		return;

	if(L.top >= L.stacksize)
		return;

	L.stack[L.top] = v;
	L.top++;
}

newcclosure(func: fn(L: ref State): int): ref Function
{
	f := ref Function;
	f.isc = 1;
	f.cfunc = func;
	f.upvals = nil;
	f.env = nil;
	return f;
}

# ====================================================================
# Module Interface
# ====================================================================

init(): string
{
	sys = load Sys Sys;
	initdisloader();
	return nil;
}

about(): array of string
{
	return array[] of {
		"Lua VM for Inferno/Limbo",
		".dis Module Loader",
		"Load Limbo .dis files as Lua modules",
	};
}
