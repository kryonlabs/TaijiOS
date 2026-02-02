# DIS Parser Integration Layer
# Connects DIS parser with module loader

implement Luadisparser;

include "sys.m";
include "draw.m";
include "loader.m";
include "luadisparser.m";
include "lua_disparser_new.m";

sys: Sys;
print, sprint, fprint: import sys;

loader: Loader;

# ====================================================================
# High-Level Loading
# ====================================================================

# Parse DIS file and create LoadedModule structure
parseandload(path: string): ref LoadedModule
{
	if(path == nil)
		return nil;

	# Parse DIS file
	(file, err) := parse(path);
	if(file == nil) {
		fprint(sys->fildes(2), "parseandload: %s\n", err);
		return nil;
	}

	# Validate
	if(validate(file) == 0) {
		fprint(sys->fildes(2), "parseandload: validation failed\n");
		return nil;
	}

	# Convert to LoadedModule format
	return dis2loaded(file);
}

# Convert DISFile to LoadedModule
dis2loaded(file: ref DISFile): ref LoadedModule
{
	if(file == nil)
		return nil;

	mod := ref LoadedModule;
	mod.name = file.name;
	mod.dispath = file.srcpath;
	mod.modpath = "";  # Will be filled by caller
	mod.sig = nil;     # Parsed separately from .m file
	mod.modinst = nil; # Will be created by loader
	mod.linktab = nil;
	mod.initialized = 0;

	# Convert instructions to Loader format
	mod.insts = dis2loaderinsts(file.inst);

	# Convert data
	mod.data = dis2loaderdata(file);

	return mod;
}

# Convert DISInst array to Loader->Inst array
dis2loaderinsts(dinsts: array of ref DISInst): array of Loader->Inst
{
	if(dinsts == nil)
		return nil;

	insts := array[len dinsts] of Loader->Inst;

	for(i := 0; i < len dinsts; i++) {
		d := dinsts[i];
		if(d == nil)
			continue;

		insts[i].op = byte d.op;
		insts[i].addr = byte d.addr;
		insts[i].src = d.src;
		insts[i].mid = d.mid;
		insts[i].dst = d.dst;
	}

	return insts;
}

# Convert DIS data to Loader->Niladt
dis2loaderdata(file: ref DISFile): ref Loader->Niladt
{
	if(file == nil || file.data == nil)
		return nil;

	if(loader == nil) {
		loader = load Loader Loader->PATH;
		if(loader == nil)
			return nil;
	}

	# Calculate total data size
	dsize := 0;
	for(d := file.data; d != nil; d = tl d) {
		data := hd d;
		if(data != nil) {
			case data {
			Bytes =>
				if(data.bytes != nil)
					dsize += len data.bytes;
			Words =>
				if(data.words != nil)
					dsize += len data.words * 4;  # 4 bytes per word
			String =>
				if(data.str != nil)
					dsize += len data.str;
			Reals =>
				if(data.reals != nil)
					dsize += len data.reals * 8;  # 8 bytes per real
			Bigs =>
				if(data.bigs != nil)
					dsize += len data.bigs * 8;  # Approximate
			* =>
				# Other types don't contribute to data size
				;
			}
		}
	}

	# Create type map for data (all non-pointers for now)
	map := array[(dsize + 3) / 4] of byte;  # 1 byte per word

	# Create data using Loader->dnew
	niladt := loader.dnew(dsize, map);

	return niladt;  # Placeholder - real implementation would fill data
}

# ====================================================================
# Extract Information
# ====================================================================

# Get exported function names
getexports(file: ref DISFile): list of string
{
	if(file == nil)
		return nil;

	exports: list of string = nil;

	# Collect from link table
	if(file.links != nil) {
		for(i := len file.links - 1; i >= 0; i--) {
			link := file.links[i];
			if(link != nil && link.name != nil) {
				exports = link.name :: exports;
			}
		}
	}

	return exports;
}

# Get entry point
getentrypoint(file: ref DISFile): int
{
	if(file == nil)
		return -1;

	return file.header.entry;
}

# ====================================================================
# Module Interface
# ====================================================================

init(): string
{
	sys = load Sys Sys;
	loader = nil;
	return nil;
}

about(): array of string
{
	return array[] of {
		"Lua DIS Parser Integration",
		"Connects parser with module loader",
	};
}
