# DIS Parser - Binary DIS File Reader
# Implements reading and parsing of DIS binary files

implement Luadisparser;

include "sys.m";
include "draw.m";
include "dis.m";
include "loader.m";
include "luadisparser.m";

sys: Sys;
print, sprint, fprint: import sys;

dis: Dis;
DISInst, DISFile, DISHeader, DISType, DISData: import dis;

# Error state
errmsg: string;

# Constants from dis.m
XMAGIC: con 819248;
SMAGIC: con 923426;

DEFZ: con 0;
DEFB: con 1;
DEFW: con 2;
DEFS: con 3;
DEFF: con 4;
DEFA: con 5;
DIND: con 6;
DAPOP: con 7;
DEFL: con 8;

# ====================================================================
# Error Handling
# ====================================================================

seterror(msg: string)
{
	errmsg = msg;
}

error(msg: string): string
{
	return msg;
}

geterrmsg(): string
{
	return errmsg;
}

# ====================================================================
# DIS File Reading
# ====================================================================

# Main parse function - opens and parses a DIS file
parse(path: string): (ref DISFile, string)
{
	if(path == nil) {
		seterror("nil path");
		return (nil, "nil path");
	}

	# Open file
	fd := sys->open(path, Sys->OREAD);
	if(fd == nil) {
		err := sprint("cannot open %s: %r", path);
		seterror(err);
		return (nil, err);
	}

	# Read entire file
	buf := "";
	buflen := 8192;
	tmp := array[buflen] of byte;

	while((n := fd.read(tmp, len tmp)) > 0) {
		buf += string tmp[0:n];
	}
	fd.close();

	if(len buf == 0) {
		err := sprint("empty file: %s", path);
		seterror(err);
		return (nil, err);
	}

	# Parse DIS file from buffer
	file := parsebuf(buf, path);
	if(file == nil) {
		return (nil, errmsg);
	}

	return (file, nil);
}

# Parse DIS file from buffer
parsebuf(buf: string; path: string): ref DISFile
{
	if(buf == nil || len buf == 0) {
		seterror("empty buffer");
		return nil;
	}

	# Load dis module for utilities
	dis = load Dis Dis->PATH;
	if(dis == nil) {
		seterror("cannot load dis module");
		return nil;
	}

	# Use dis->loadobj to parse
	(mod, err) := dis->loadobj(path);
	if(mod == nil) {
		seterror(err);
		return nil;
	}

	# Convert Dis->Mod to our DISFile format
	return convertmod(mod);
}

# Convert Dis->Mod to DISFile
convertmod(mod: ref Dis->Mod): ref DISFile
{
	if(mod == nil)
		return nil;

	file := ref DISFile;
	file.name = mod.name;
	file.srcpath = mod.srcpath;

	# Convert header
	file.header = ref DISHeader;
	file.header.magic = mod.magic;
	file.header.rt = mod.rt;
	file.header.ssize = mod.ssize;
	file.header.isize = mod.isize;
	file.header.dsize = mod.dsize;
	file.header.tsize = mod.tsize;
	file.header.lsize = mod.lsize;
	file.header.entry = mod.entry;
	file.header.entryt = mod.entryt;

	# Convert instructions
	if(mod.inst != nil) {
		file.inst = array[len mod.inst] of ref DISInst;
		for(i := 0; i < len mod.inst; i++) {
			file.inst[i] = convertinst(mod.inst[i]);
		}
	}

	# Convert types
	if(mod.types != nil) {
		file.types = array[len mod.types] of ref DISType;
		for(i := 0; i < len mod.types; i++) {
			file.types[i] = converttype(mod.types[i]);
		}
	}

	# Data is already in correct format (list)
	file.data = mod.data;

	# Convert links
	if(mod.links != nil) {
		file.links = array[len mod.links] of ref DISLink;
		for(i := 0; i < len mod.links; i++) {
			file.links[i] = convertlink(mod.links[i]);
		}
	}

	# Imports
	file.imports = mod.imports;

	# Handlers
	file.handlers = mod.handlers;

	# Signature
	file.sign = mod.sign;

	return file;
}

# Convert Dis->Inst to DISInst
convertinst(dinst: ref Dis->Inst): ref DISInst
{
	if(dinst == nil)
		return nil;

	inst := ref DISInst;
	inst.op = dinst.op;
	inst.addr = dinst.addr;
	inst.mid = dinst.mid;
	inst.src = dinst.src;
	inst.dst = dinst.dst;

	return inst;
}

# Convert Dis->Type to DISType
converttype(dtype: ref Dis->Type): ref DISType
{
	if(dtype == nil)
		return nil;

	t := ref DISType;
	t.size = dtype.size;
	t.np = dtype.np;

	if(dtype.map != nil) {
		t.map = array[len dtype.map] of byte;
		t.map[:] = dtype.map[:];
	}

	return t;
}

# Convert Dis->Link to DISLink
convertlink(dlink: ref Dis->Link): ref DISLink
{
	if(dlink == nil)
		return nil;

	link := ref DISLink;
	link.name = dlink.name;
	link.sig = dlink.sig;
	link.pc = dlink.pc;
	link.tdesc = dlink.desc;

	return link;
}

# ====================================================================
# Validation
# ====================================================================

validate(file: ref DISFile): int
{
	if(file == nil)
		return 0;

	# Check magic number
	if(file.header.magic != XMAGIC && file.header.magic != SMAGIC) {
		seterror(sprint("bad magic number: %x", file.header.magic));
		return 0;
	}

	# Check sizes are non-negative
	if(file.header.isize < 0 || file.header.dsize < 0 ||
	   file.header.tsize < 0 || file.header.lsize < 0) {
		seterror("invalid size in header");
		return 0;
	}

	# Check arrays match header sizes
	if(file.inst != nil && len file.inst != file.header.isize) {
		seterror("instruction count mismatch");
		return 0;
	}

	if(file.types != nil && len file.types != file.header.tsize) {
		seterror("type count mismatch");
		return 0;
	}

	if(file.links != nil && len file.links != file.header.lsize) {
		seterror("link count mismatch");
		return 0;
	}

	return 1;
}

# ====================================================================
# Export Information
# ====================================================================

getexports(file: ref DISFile): list of string
{
	if(file == nil || file.links == nil)
		return nil;

	exports: list of string = nil;

	# Collect all link names
	for(i := len file.links - 1; i >= 0; i--) {
		link := file.links[i];
		if(link != nil && link.name != nil) {
			exports = link.name :: exports;
		}
	}

	return exports;
}

findlink(file: ref DISFile; name: string): ref DISLink
{
	if(file == nil || name == nil || file.links == nil)
		return nil;

	for(i := 0; i < len file.links; i++) {
		link := file.links[i];
		if(link != nil && link.name == name)
			return link;
	}

	return nil;
}

# ====================================================================
# Entry Point
# ====================================================================

getentry(file: ref DISFile): int
{
	if(file == nil)
		return -1;

	return file.header.entry;
}

# ====================================================================
# File Properties
# ====================================================================

issigned(file: ref DISFile): int
{
	if(file == nil || file.sign == nil)
		return 0;

	return len file.sign > 0;
}

isexecutable(file: ref DISFile): int
{
	if(file == nil)
		return 0;

	return file.header.magic == XMAGIC;
}

# ====================================================================
# Instruction Utilities (use dis module)
# ====================================================================

op2str(op: int): string
{
	if(dis == nil)
		return sprint("op%d", op);

	return dis->op2s(op);
}

inst2str(inst: ref DISInst): string
{
	if(inst == nil)
		return "nil";

	if(dis == nil) {
		return sprint("op=%d addr=%d mid=%d src=%d dst=%d",
			inst.op, inst.addr, inst.mid, inst.src, inst.dst);
	}

	# Convert to Dis->Inst format
	dinst := ref Dis->Inst;
	dinst.op = inst.op;
	dinst.addr = inst.addr;
	dinst.mid = inst.mid;
	dinst.src = inst.src;
	dinst.dst = inst.dst;

	return dis->inst2s(dinst);
}

# ====================================================================
# Module Interface
# ====================================================================

init(): string
{
	sys = load Sys Sys;
	dis = nil;
	errmsg = nil;
	return nil;
}

about(): array of string
{
	return array[] of {
		"Lua DIS Parser",
		"Binary DIS file parser",
		"Loads and parses Inferno DIS files",
		"Extracts instructions, data, types, links",
	};
}
