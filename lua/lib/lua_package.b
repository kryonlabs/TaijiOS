# Lua VM - Package Library
# Implements package.* functions and require()
# Adapted for Inferno's .dis file loading

implement Luavm;

include "sys.m";
include "draw.m";
include "luavm.m";
include "lua_baselib.m";

sys: Sys;
print, sprint, fprint: import sys;

# ====================================================================
# Package State
# ====================================================================

Package: adt {
	loaded: ref Table;      # Loaded modules
	preload: ref Table;     # Preloaded modules
	path: string;           # Search path for Lua files
	cpath: string;          # Search path for .dis files
	searchers: ref Table;   # Searcher functions
};

# Global package state
packagestate: ref Package;

# ====================================================================
# Package Functions
# ====================================================================

# package.loadlib(libname, funcname) - Load dynamic library
package_loadlib(L: ref State): int
{
	if(L == nil || L.top < 2)
		return 0;

	# Inferno uses .dis files, not dynamic libraries
	# This is a placeholder for compatibility

	pushnil(L);
	pushstring(L, "loadlib: not supported on Inferno");
	return 2;
}

# package.searchpath(name, path[, sep[, rep]]) - Search for module
package_searchpath(L: ref State): int
{
	if(L == nil || L.top < 2)
		return 0;

	nameval := L.stack[L.top - 1];
	pathval := L.stack[L.top - 2];

	if(nameval == nil || nameval.ty != TSTRING ||
	   pathval == nil || pathval.ty != TSTRING) {
		pushnil(L);
		pushstring(L, "searchpath: invalid arguments");
		return 2;
	}

	name := nameval.s;
	searchpath := pathval.s;

	# Get separator (default ".")
	sep := ".";
	if(L.top >= 3) {
		sepval := L.stack[L.top - 3];
		if(sepval != nil && sepval.ty == TSTRING)
			sep = sepval.s;
	}

	# Get replacement (default "/")
	rep := "/";
	if(L.top >= 4) {
		repval := L.stack[L.top - 4];
		if(repval != nil && repval.ty == TSTRING)
			rep = repval.s;
	}

	# Replace separator in name
	modulename := name;
	# Simple replacement (simplified)

	# Search path
	paths := splitpath(searchpath);
	while(paths != nil) {
		template := hd paths;
		paths = tl paths;

		# Replace ? with module name
		filename := replaceplaceholder(template, modulename);

		# Check if file exists
		fd := sys->open(filename, Sys->OREAD);
		if(fd != nil) {
			fd.close();
			pushstring(L, filename);
			return 1;
		}
	}

	pushnil(L);
	pushstring(L, sprint("searchpath: %s not found", name));
	return 2;
}

# package.seeall(module) - Set module metatable to __index=_G
package_seeall(L: ref State): int
{
	if(L == nil || L.top < 1)
		return 0;

	modval := L.stack[L.top - 1];
	if(modval == nil || modval.ty != TTABLE)
		return 0;

	module := modval.t;

	# Get global table
	global := L.globals;

	# Set metatable with __index
	meta := createtable(0, 1);
	key := ref Value;
	val := ref Value;

	key.ty = TSTRING;
	key.s = "__index";

	val.ty = TTABLE;
	val.t = global;

	settablevalue(meta, key, val);

	# Set module metatable
	module.meta = meta;

	pushvalue(L, modval);
	return 1;
}

# package.config - Configuration string
package_config(L: ref State): int
{
	if(L == nil)
		return 0;

	# Inferno-specific configuration
	config := "/\n?\n-\n?\n!\n/";

	pushstring(L, config);
	return 1;
}

# package.cpath - C loader path
package_cpath(L: ref State): int
{
	if(L == nil)
		return 0;

	if(packagestate != nil && packagestate.cpath != nil) {
		pushstring(L, packagestate.cpath);
		return 1;
	}

	# Default .dis search path
	cpath := "./?.dis;/dis/lib/?.dis;/dis/lib/?/init.dis";
	pushstring(L, cpath);
	return 1;
}

# package.path - Lua loader path
package_path(L: ref State): int
{
	if(L == nil)
		return 0;

	if(packagestate != nil && packagestate.path != nil) {
		pushstring(L, packagestate.path);
		return 1;
	}

	# Default .lua search path
	path := "./?.lua;/lua/lib/?.lua;/lua/lib/?/init.lua";
	pushstring(L, path);
	return 1;
}

# ====================================================================
# Require Function
# ====================================================================

# require(modname) - Load and return module
require(L: ref State): int
{
	if(L == nil || L.top < 1)
		return 0;

	nameval := L.stack[L.top - 1];
	if(nameval == nil || nameval.ty != TSTRING) {
		pushstring(L, "require: module name must be string");
		return ERRRUN;
	}

	modname := nameval.s;

	# Initialize package state if needed
	if(packagestate == nil)
		initpackage(L);

	# Check if already loaded
	key := ref Value;
	key.ty = TSTRING;
	key.s = modname;

	loadedval := gettablevalue(packagestate.loaded, key);
	if(loadedval != nil && loadedval.ty != TNIL) {
		pushvalue(L, loadedval);
		return 1;
	}

	# Try each searcher
	nsearchers := 4;  # Standard Lua has 4 searchers
	for(i := 1; i <= nsearchers; i++) {
		searcherkey := mknumber(real(i));
		searcherval := gettablevalue(packagestate.searchers, searcherkey);

		if(searcherval != nil && searcherval.ty == TFUNCTION) {
			# Call searcher
			pushstring(L, modname);

			# Execute searcher (simplified)
			result := callsearcher(L, searcherval, modname);

			if(result != nil) {
				# Module found and loaded
				# Store in loaded table
				settablevalue(packagestate.loaded, key, result);

				pushvalue(L, result);
				return 1;
			}
		}
	}

	pushstring(L, sprint("require: module '%s' not found", modname));
	return ERRRUN;
}

# ====================================================================
# Searcher Functions
# ====================================================================

# Searcher 1: Preloaded modules
searcher_preload(L: ref State, modname: string): ref Value
{
	if(packagestate == nil || packagestate.preload == nil)
		return nil;

	key := ref Value;
	key.ty = TSTRING;
	key.s = modname;

	val := gettablevalue(packagestate.preload, key);
	if(val == nil)
		return nil;

	# Execute loader
	return callloader(L, val, modname);
}

# Searcher 2: Lua files
searcher_lua(L: ref State, modname: string): ref Value
{
	if(packagestate == nil || packagestate.path == nil)
		return nil;

	# Build filename from modname and path
	filename := modname + ".lua";

	# Try to load and execute
	return loadluafile(L, filename, modname);
}

# Searcher 3: C loaders (.dis files in Inferno)
searcher_c(L: ref State, modname: string): ref Value
{
	if(packagestate == nil || packagestate.cpath == nil)
		return nil;

	# Try to load .dis module
	return loaddismodule(L, modname);
}

# Searcher 4: All-in-one loader
searcher_allinone(L: ref State, modname: string): ref Value
{
	# Simplified - just try lua then c
	result := searcher_lua(L, modname);
	if(result != nil)
		return result;

	return searcher_c(L, modname);
}

# ====================================================================
# Helper Functions
# ====================================================================

# Initialize package state
initpackage(L: ref State)
{
	packagestate = ref Package;

	# Create loaded table
	packagestate.loaded = createtable(0, 10);

	# Create preload table
	packagestate.preload = createtable(0, 5);

	# Set paths
	packagestate.path = "./?.lua;/lua/lib/?.lua;/lua/lib/?/init.lua";
	packagestate.cpath = "./?.dis;/dis/lib/?.dis;/dis/lib/?/init.dis";

	# Create searchers table
	packagestate.searchers = createtable(4, 0);

	# Register searchers
	key := ref Value;
	val := ref Value;

	key.ty = TNUMBER;
	val.ty = TFUNCTION;

	# Searcher 1: Preload
	key.n = 1.0;
	val.f = newcclosure(searcher_preload);
	settablevalue(packagestate.searchers, key, val);

	# Searcher 2: Lua
	key.n = 2.0;
	val.f = newcclosure(searcher_lua);
	settablevalue(packagestate.searchers, key, val);

	# Searcher 3: C
	key.n = 3.0;
	val.f = newcclosure(searcher_c);
	settablevalue(packagestate.searchers, key, val);

	# Searcher 4: All-in-one
	key.n = 4.0;
	val.f = newcclosure(searcher_allinone);
	settablevalue(packagestate.searchers, key, val);
}

# Load Lua file
loadluafile(L: ref State, filename: string, modname: string): ref Value
{
	# Try to open and load Lua file
	fd := sys->open(filename, Sys->OREAD);
	if(fd == nil)
		return nil;

	# Read entire file
	buf := array[8192] of byte;
	all := "";
	while((n := fd.read(buf, len buf)) > 0) {
		all += string buf[0:n];
	}
	fd.close();

	# Compile and execute
	# This would call lua_loadfile() internally
	# For now, return nil as placeholder
	return nil;
}

# Load .dis module using generic DIS loader
loaddismodule(L: ref State, modname: string): ref Value
{
	# Import the generic DIS loading modules
	# Note: This is a simplified implementation
	# Full implementation would use lua_disloader_new.b directly

	# 1. Find .dis file
	dispath := finddisfile(modname);
	if(dispath == nil)
		return nil;

	# 2. Find .m file for signatures
	modpath := findmfile(modname);
	if(modpath == nil)
		modpath = guessmodpath(modname);

	# 3. Parse module signatures
	sig := parsemodulefile(modpath);
	if(sig == nil) {
		# Create minimal signature if parsing fails
		sig = ref ModSignature;
		sig.modname = modname;
		sig.functions = nil;
		sig.adts = nil;
		sig.constants = nil;
	}

	# 4. Create module table with placeholders
	# In full implementation, this would:
	# - Load DIS binary via Loader module
	# - Link and compile module
	# - Generate function proxies
	# - Call init() function

	modtab := createtable(0, 10);

	# Add a placeholder function that indicates the module was found
	# This allows Lua to know the module exists, even if we can't fully load it yet
	placeholder := ref Value;
	placeholder.ty = TFUNCTION;
	placeholder.f = ref Function;
	placeholder.f.isc = 1;
	placeholder.f.cfunc = module_placeholder;

	key := ref Value;
	key.ty = TSTRING;
	key.s = "_loaded";

	val := ref Value;
	val.ty = TBOOLEAN;
	val.b = 1;

	settablevalue(modtab, key, val);

	# Return module table
	result := ref Value;
	result.ty = TTABLE;
	result.t = modtab;

	return result;
}

# Placeholder function for loaded modules
module_placeholder(L: ref State): int
{
	pushstring(L, "module loaded (generic loader not fully implemented)");
	return 1;
}

# Find .dis file for module
finddisfile(modname: string): string
{
	if(modname == nil)
		return nil;

	paths := [] of {modname + ".dis", "./" + modname + ".dis",
	                "/dis/lib/" + modname + ".dis"};

	for(i := 0; i < len paths; i++) {
		fd := sys->open(paths[i], Sys->OREAD);
		if(fd != nil) {
			fd.close();
			return paths[i];
		}
	}

	return nil;
}

# Find .m file for module
findmfile(modname: string): string
{
	if(modname == nil)
		return nil;

	paths := [] of {"./" + modname + ".m", "/module/" + modname + ".m",
	                "/mnt/storage/Projects/TaijiOS/module/" + modname + ".m"};

	for(i := 0; i < len paths; i++) {
		fd := sys->open(paths[i], Sys->OREAD);
		if(fd != nil) {
			fd.close();
			return paths[i];
		}
	}

	return nil;
}

# Guess module path
guessmodpath(modname: string): string
{
	if(modname == nil)
		return nil;
	return "/module/" + modname + ".m";
}

# Parse module file (simplified version)
parsemodulefile(modpath: string): ref ModSignature
{
	if(modpath == nil)
		return nil;

	# This would use lua_modparse.b in full implementation
	# For now, return nil to indicate parsing not available
	return nil;
}

# Module signature ADT (simplified)
ModSignature: adt {
	modname: string;
	functions: list of string;  # Simplified: just names
	adts: list of string;
	constants: list of string;
};

# Call loader function
callloader(L: ref State, loader: ref Value, modname: string): ref Value
{
	if(loader == nil || loader.ty != TFUNCTION)
		return nil;

	# Push loader function
	pushvalue(L, loader);

	# Push module name
	pushstring(L, modname);

	# Call loader
	nargs := 1;
	nresults := callcfunction(L, nargs);

	if(nresults < 1)
		return nil;

	result := L.stack[L.top - 1];
	return result;
}

# Call searcher
callsearcher(L: ref State, searcher: ref Value, modname: string): ref Value
{
	# Similar to callloader
	if(searcher == nil || searcher.ty != TFUNCTION)
		return nil;

	pushvalue(L, searcher);
	pushstring(L, modname);

	nargs := 1;
	nresults := callcfunction(L, nargs);

	if(nresults < 1)
		return nil;

	result := L.stack[L.top - 1];
	return result;
}

# Split path by separator
splitpath(path: string): list of string
{
	if(path == nil)
		return nil;

	result: list of string = nil;
	current := "";

	for(i := 0; i < len path; i++) {
		if(path[i] == ';') {
			if(len current > 0) {
				result = current :: result;
				current = "";
			}
		} else {
			current[len current] = path[i];
		}
	}

	if(len current > 0)
		result = current :: result;

	# Reverse
	reversed: list of string = nil;
	while(result != nil) {
		reversed = hd result :: reversed;
		result = tl result;
	}

	return reversed;
}

# Replace ? placeholder
replaceplaceholder(template: string, name: string): string
{
	if(template == nil)
		return name;

	result := "";

	for(i := 0; i < len template; i++) {
		if(i + 1 < len template && template[i] == '?' && template[i+1] == '?') {
			# Replace ?? with single ?
			result[len result] = '?';
			i++;
		} else if(template[i] == '?') {
			# Replace ? with name
			result += name;
		} else {
			result[len result] = template[i];
		}
	}

	return result;
}

# ====================================================================
# Library Registration
# ====================================================================

# Open package library
open package(L: ref State): int
{
	if(L == nil)
		return 0;

	# Initialize package state
	initpackage(L);

	# Create package library table
	lib := createtable(0, 10);

	# Register functions
	setlibfunc(lib, "loadlib", package_loadlib);
	setlibfunc(lib, "searchpath", package_searchpath);
	setlibfunc(lib, "seeall", package_seeall);

	# Set fields
	key := ref Value;
	val := ref Value;

	key.ty = TSTRING;

	# config
	key.s = "config";
	val.ty = TSTRING;
	val.s = "/\n?\n-\n?\n!\n/";
	settablevalue(lib, key, val);

	# loaded
	key.s = "loaded";
	val.ty = TTABLE;
	val.t = packagestate.loaded;
	settablevalue(lib, key, val);

	# preload
	key.s = "preload";
	val.t = packagestate.preload;
	settablevalue(lib, key, val);

	# path
	key.s = "path";
	val.ty = TSTRING;
	val.s = packagestate.path;
	settablevalue(lib, key, val);

	# cpath
	key.s = "cpath";
	val.s = packagestate.cpath;
	settablevalue(lib, key, val);

	# searchers
	key.s = "searchers";
	val.ty = TTABLE;
	val.t = packagestate.searchers;
	settablevalue(lib, key, val);

	pushvalue(L, mktable(lib));

	# Store in global registry
	if(L.globals != nil) {
		packkey := ref Value;
		packkey.ty = TSTRING;
		packkey.s = "package";

		packval := ref Value;
		packval.ty = TTABLE;
		packval.t = lib;

		settablevalue(L.globals, packkey, packval);
	}

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
		"Package Library",
		"Module loading and require()",
	};
}
