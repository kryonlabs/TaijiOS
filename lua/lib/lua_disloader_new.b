# Lua VM - DIS Module Loader (New)
# Loads DIS modules using Loader module at runtime
# Replaces hardcoded library bindings with generic loading

implement Luavm;

include "sys.m";
include "draw.m";
include "loader.m";
include "luadisparser.m";
include "luavm.m";
include "lua_baselib.m";
include "lua_marshal.m";
include "lua_modparse.m";

sys: Sys;
print, sprint, fprint: import sys;

luavm: Luavm;
State, Value, Table, TNIL, TNUMBER, TSTRING, TFUNCTION, TUSERDATA, TTABLE: import luavm;

loader: Loader;

# ====================================================================
# Loaded Module Representation
# ====================================================================

LoadedModule: adt {
	name: string;
	dispath: string;
	modpath: string;
	sig: ref ModSignature;  # Parsed signatures
	modinst: Loader->Nilmod;  # Loaded DIS instance
	linktab: array of Loader->Link;  # Link table
	initialized: int;
};

# Module cache
modulecache: list of ref LoadedModule;

# ====================================================================
# File Finding
# ====================================================================

# Find .dis file for module
finddisfile(modname: string): string
{
	if(modname == nil)
		return nil;

	# Search paths
	paths := [] of {
		"./" + modname + ".dis",
		"/dis/lib/" + modname + ".dis",
		"/dis/" + modname + ".dis",
		"/dis/lib/" + modname + "/" + modname + ".dis",
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

# Find .m file for module
findmfile(modname: string): string
{
	if(modname == nil)
		return nil;

	# Search paths
	paths := [] of {
		"./" + modname + ".m",
		"/module/" + modname + ".m",
		"/mnt/storage/Projects/TaijiOS/module/" + modname + ".m",
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

# Guess module path from name
guessmodpath(modname: string): string
{
	if(modname == nil)
		return nil;

	# Default to module directory
	return "/module/" + modname + ".m";
}

# ====================================================================
# DIS Loading
# ====================================================================

# Load .dis file binary data
readdisbinary(dispath: string): (array of Loader->Inst, ref Loader->Niladt)
{
	if(dispath == nil)
		return (nil, nil);

	# Use DIS parser to read the file
	disparser := load Luadisparser Luadisparser->PATH;
	if(disparser == nil) {
		fprint(sys->fildes(2), "loaddismodule: cannot load disparser\n");
		return (nil, nil);
	}

	# Parse DIS file
	(file, err) := disparser->parse(dispath);
	if(file == nil) {
		fprint(sys->fildes(2), "loaddismodule: %s\n", err);
		return (nil, nil);
	}

	# Validate parsed file
	if(disparser->validate(file) == 0) {
		fprint(sys->fildes(2), "loaddismodule: invalid DIS file\n");
		return (nil, nil);
	}

	# Convert to Loader format
	insts := dis2loaderinsts(file);
	data := dis2loaderdata(file);

	return (insts, data);
}

# Convert DISFile instructions to Loader->Inst format
dis2loaderinsts(file: ref Luadisparser->DISFile): array of Loader->Inst
{
	if(file == nil || file.inst == nil)
		return nil;

	insts := array[len file.inst] of Loader->Inst;

	for(i := 0; i < len file.inst; i++) {
		dinst := file.inst[i];
		if(dinst == nil)
			continue;

		insts[i].op = byte dinst.op;
		insts[i].addr = byte dinst.addr;
		insts[i].src = dinst.src;
		insts[i].mid = dinst.mid;
		insts[i].dst = dinst.dst;
	}

	return insts;
}

# Convert DISFile data to Loader->Niladt format
dis2loaderdata(file: ref Luadisparser->DISFile): ref Loader->Niladt
{
	if(file == nil)
		return nil;

	if(loader == nil) {
		loader = load Loader Loader->PATH;
		if(loader == nil)
			return nil;
	}

	# Calculate data size from data segment
	dsize := 0;
	if(file.data != nil) {
		for(d := file.data; d != nil; d = tl d) {
			data := hd d;
			if(data != nil) {
				case data {
				Luadisparser->Bytes =>
					if(data.bytes != nil)
						dsize += len data.bytes;
				Luadisparser->Words =>
					if(data.words != nil)
						dsize += len data.words * 4;
				Luadisparser->String =>
					if(data.str != nil)
						dsize += len data.str;
				Luadisparser->Reals =>
					if(data.reals != nil)
						dsize += len data.reals * 8;
				Luadisparser->Bigs =>
					if(data.bigs != nil)
						dsize += len data.bigs * 8;
				* =>
					;
				}
			}
		}
	}

	# Create type map (all non-pointers for now)
	if(dsize > 0) {
		mapsize := (dsize + 3) / 4;
		map := array[mapsize] of byte;
		return loader.dnew(dsize, map);
	}

	return loader.dnew(0, nil);
}

# Load module via Loader module
loadvia(loader: ref Loader; dispath: string, sig: ref ModSignature): ref LoadedModule
{
	if(loader == nil || dispath == nil || sig == nil)
		return nil;

	# Read DIS binary
	(inst, data) := readdisbinary(dispath);
	if(inst == nil)
		return nil;

	# Create module instance
	nfuncs := len sig.functions;
	modinst := loader.newmod(sig.modname, len inst, nfuncs, inst, data);
	if(modinst == nil)
		return nil;

	# Create LoadedModule
	mod := ref LoadedModule;
	mod.name = sig.modname;
	mod.dispath = dispath;
	mod.modpath = "";
	mod.sig = sig;
	mod.modinst = modinst;
	mod.linktab = nil;
	mod.initialized = 0;

	return mod;
}

# Link module
linkmodule(mod: ref LoadedModule): int
{
	if(mod == nil || mod.modinst == nil)
		return -1;

	# Get link table
	mod.linktab = loader.link(mod.modinst);
	if(mod.linktab == nil)
		return -1;

	return 0;
}

# Compile module
compilemodule(mod: ref LoadedModule): int
{
	if(mod == nil || mod.modinst == nil)
		return -1;

	# Compile module
	status := loader.compile(mod.modinst, 0);
	if(status < 0)
		return -1;

	return 0;
}

# Call module init() function
callinit(mod: ref LoadedModule): int
{
	if(mod == nil || mod.initialized)
		return 0;

	# Try to call init function
	# This is module-specific - not all modules have init()
	# For now, mark as initialized
	mod.initialized = 1;

	return 0;
}

# ====================================================================
# Main Loader
# ====================================================================

# Load DIS module
loaddismodule(L: ref State; modname: string): ref Value
{
	if(L == nil || modname == nil)
		return nil;

	# Check cache first
	cached := findcached(modname);
	if(cached != nil) {
		# Return cached module table
		return getmoduletable(L, cached);
	}

	# 1. Find .dis file
	dispath := finddisfile(modname);
	if(dispath == nil)
		return nil;

	# 2. Find .m file
	modpath := findmfile(modname);
	if(modpath == nil)
		modpath = guessmodpath(modname);

	# 3. Load Loader module
	if(loader == nil) {
		loader = load Loader Loader->PATH;
		if(loader == nil)
			return nil;
	}

	# 4. Parse signatures
	sig := parsemodulefile(modpath);
	if(sig == nil) {
		# Fallback: create empty signature
		sig = ref ModSignature;
		sig.modname = modname;
		sig.functions = nil;
		sig.adts = nil;
		sig.constants = nil;
	}

	# 5. Load DIS module
	mod := loadvia(loader, dispath, sig);
	if(mod == nil)
		return nil;

	mod.modpath = modpath;

	# 6. Link module
	if(linkmodule(mod) < 0)
		return nil;

	# 7. Compile module
	if(compilemodule(mod) < 0)
		return nil;

	# 8. Call init
	callinit(mod);

	# 9. Cache module
	modulecache = mod :: modulecache;

	# 10. Create Lua table
	return createmoduletable(L, mod);
}

# Create Lua table for module
createmoduletable(L: ref State; mod: ref LoadedModule): ref Value
{
	if(L == nil || mod == nil)
		return nil;

	# Create table with space for all functions
	nfuncs := len mod.sig.functions;
	if(nfuncs == 0)
		nfuncs = 10;  # Default size

	modtab := luavm->createtable(0, nfuncs);

	# Add each function as a closure
	for(funcs := mod.sig.functions; funcs != nil; funcs = tl funcs) {
		f := hd funcs;

		# Create closure that calls the Limbo function
		fnval := createfunctionclosure(L, mod, f);

		if(fnval != nil) {
			# Set in table
			key := ref Value;
			key.ty = TSTRING;
			key.s = f.name;

			settablevalue(modtab, key, fnval);
		}
	}

	# Add constants
	for(consts := mod.sig.constants; consts != nil; consts = tl consts) {
		c := hd consts;

		val := constant2luavalue(c);
		if(val != nil) {
			key := ref Value;
			key.ty = TSTRING;
			key.s = c.name;

			settablevalue(modtab, key, val);
		}
	}

	# Wrap in Value
	result := ref Value;
	result.ty = TTABLE;
	result.t = modtab;

	return result;
}

# Create function closure
createfunctionclosure(L: ref State; mod: ref LoadedModule; sig: ref FuncSig): ref Value
{
	if(L == nil || mod == nil || sig == nil)
		return nil;

	# Create a C closure that will call the Limbo function
	# For now, create a placeholder function

	f := ref Function;
	f.isc = 1;
	f.upvals = nil;
	f.env = nil;

	# Store module and signature in closure context
	# This is simplified - real implementation needs proper closure handling

	val := ref Value;
	val.ty = TFUNCTION;
	val.f = f;

	return val;
}

# Convert constant to Lua value
constant2luavalue(c: ref ConstSig): ref Value
{
	if(c == nil)
		return nil;

	val := ref Value;

	if(c.typ == nil) {
		val.ty = TSTRING;
		val.s = c.value;
		return val;
	}

	case pick c.typ {
	Basic =>
		if(c.typ.name == "int") {
			# Parse integer
			n := 0;
			if(len c.value > 2 && c.value[0:2] == "16r") {
				# Hex
				n = hextoi(c.value);
			} else if(len c.value > 1 && c.value[0] == '-') {
				n = -int big c.value[1:];
			} else {
				n = int big c.value;
			}

			val.ty = TNUMBER;
			val.n = real(n);

		} else if(c.typ.name == "real") {
			val.ty = TNUMBER;
			val.n = real big c.value;

		} else if(c.typ.name == "string") {
			val.ty = TSTRING;
			val.s = c.value;

		} else {
			val.ty = TSTRING;
			val.s = c.value;
		}

	* =>
		val.ty = TSTRING;
		val.s = c.value;
	}

	return val;
}

# Parse hex string to int
hextoi(s: string): int
{
	if(s == nil || len s < 3)
		return 0;

	# Skip "16r" prefix
	s = s[3:];

	result := 0;
	for(i := 0; i < len s; i++) {
		c := s[i];
		d := 0;

		if(c >= '0' && c <= '9')
			d = int c - int '0';
		else if(c >= 'a' && c <= 'f')
			d = int c - int 'a' + 10;
		else if(c >= 'A' && c <= 'F')
			d = int c - int 'A' + 10;
		else
			break;

		result = result * 16 + d;
	}

	return result;
}

# ====================================================================
# Cache Management
# ====================================================================

# Find cached module
findcached(modname: string): ref LoadedModule
{
	for(m := modulecache; m != nil; m = tl m) {
		mod := hd m;
		if(mod != nil && mod.name == modname)
			return mod;
	}
	return nil;
}

# Get module table from cache
getmoduletable(L: ref State; mod: ref LoadedModule): ref Value
{
	if(L == nil || mod == nil)
		return nil;

	# Recreate table from cached module
	return createmoduletable(L, mod);
}

# ====================================================================
# Helper Functions
# ====================================================================

# Set table value
settablevalue(tab: ref Table; key, val: ref Value)
{
	if(tab == nil || key == nil)
		return;

	luavm->settable(nil, tab, key, val);
}

# ====================================================================
# Module Interface
# ====================================================================

init(): string
{
	sys = load Sys Sys;
	loader = nil;
	modulecache = nil;
	return nil;
}

about(): array of string
{
	return array[] of {
		"Lua VM for Inferno/Limbo",
		"DIS Module Loader",
		"Generic DIS module loading via Loader module",
	};
}
