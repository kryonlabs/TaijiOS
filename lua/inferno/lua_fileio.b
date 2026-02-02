# Lua VM - File I/O Bridge for Inferno
# Bridges Lua I/O operations to Inferno's Sys->FileIO

implement Luavm;

include "sys.m";
include "draw.m";
include "bufio.m";
include "luavm.m";
include "lua_inferno.m";

sys: Sys;
print, sprint, fprint, open, create, remove, fildes: import sys;

bufio: Bufio;
Iobuf: import bufio;

# ====================================================================
# File Handle Bridge
# ====================================================================

LuaFile: adt {
	fd: ref Sys->FD;
	buf: ref Iobuf;
	name: string;
	mode: int;  # Sys->OREAD, OWRITE, ORDWR
	closed: int;
};

# ====================================================================
# File Operations
# ====================================================================

# Open file
luaopen(L: ref LuaFile; filename: string; mode: string): ref LuaFile
{
	if(filename == nil)
		return nil;

	# Determine mode
	openmode := Sys->OREAD;
	if(mode != nil) {
		if(mode == "r")
			openmode = Sys->OREAD;
		else if(mode == "w")
			openmode = Sys->OWRITE;
		else if(mode == "r+")
			openmode = Sys->ORDWR;
		else if(mode == "a")
			openmode = Sys->OWRITE;
	}

	# Try to open
	fd := sys->open(filename, openmode);

	# If write mode and doesn't exist, create
	if(fd == nil && (mode == "w" || mode == "a" || mode == "r+")) {
		perm := 8r666;
		fd = sys->create(filename, openmode, perm);
	}

	if(fd == nil)
		return nil;

	# Create buffered I/O
	buf := bufio->fopen(fd, mode);
	if(buf == nil) {
		fd.close();
		return nil;
	}

	# Create Lua file handle
	lf := ref LuaFile;
	lf.fd = fd;
	lf.buf = buf;
	lf.name = filename;
	lf.mode = openmode;
	lf.closed = 0;

	return lf;
}

# Close file
luaclose(lf: ref LuaFile): int
{
	if(lf == nil || lf.closed)
		return -1;

	if(lf.buf != nil)
		lf.buf.close();
	if(lf.fd != nil)
		lf.fd.close();

	lf.closed = 1;
	return 0;
}

# Read from file
luaread(lf: ref LuaFile; count: int): string
{
	if(lf == nil || lf.closed || lf.buf == nil)
		return nil;

	# If count is 0 or negative, read all
	if(count <= 0) {
		all := "";
		buf := array[8192] of byte;
		while((n := lf.buf.read(buf, len buf)) > 0) {
			all += string buf[0:n];
		}
		return all;
	}

	# Read specified number of bytes
	buf := array[count] of byte;
	n := lf.buf.read(buf, count);
	if(n <= 0)
		return nil;

	return string buf[0:n];
}

# Read line from file
luareadline(lf: ref LuaFile): string
{
	if(lf == nil || lf.closed || lf.buf == nil)
		return nil;

	return lf.buf.reads('\n');
}

# Write to file
luawrite(lf: ref LuaFile; data: string): int
{
	if(lf == nil || lf.closed || data == nil)
		return -1;

	if(lf.buf != nil) {
		lf.buf.puts(data);
	} else if(lf.fd != nil) {
		n := lf.fd.write(array of byte data);
		return n;
	}

	return len data;
}

# Flush file
luaflush(lf: ref LuaFile): int
{
	if(lf == nil || lf.closed || lf.buf == nil)
		return -1;

	lf.buf.flush();
	return 0;
}

# Seek in file
luaseek(lf: ref LuaFile; offset: big; whence: int): big
{
	if(lf == nil || lf.closed || lf.fd == nil)
		return big -1;

	return lf.fd.seek(offset, whence);
}

# Get file position
luatell(lf: ref LuaFile): big
{
	if(lf == nil || lf.closed || lf.fd == nil)
		return big -1;

	return lf.fd.seek(big 0, Sys->SEEKRELA);
}

# Check if file is at EOF
luaeof(lf: ref LuaFile): int
{
	if(lf == nil || lf.closed || lf.buf == nil)
		return 1;

	# Peek at next character
	next := lf.buf.getc();
	if(next == -1)
		return 1;

	# Put it back
	lf.buf.ungetc(next);
	return 0;
}

# ====================================================================
# Directory Operations
# ====================================================================

# Check if file exists
fileexists(filename: string): int
{
	if(filename == nil)
		return 0;

	fd := sys->open(filename, Sys->OREAD);
	if(fd == nil)
		return 0;

	fd.close();
	return 1;
}

# Get file info
fileinfo(filename: string): (big, big, int)
{
	if(filename == nil)
		return (big 0, big 0, 0);

	# Stat file
	info := sys->stat(filename);
	if(info == nil)
		return (big 0, big 0, 0);

	# Return (size, mtime, mode)
	return (info.length, info.mtime, info.mode.dtype);
}

# Remove file
filedelete(filename: string): int
{
	if(filename == nil)
		return -1;

	return sys->remove(filename);
}

# Rename file
filerename(oldname: string; newname: string): int
{
	if(oldname == nil || newname == nil)
		return -1;

	# Inferno doesn't have rename, need to copy + delete
	# Open source
	src := sys->open(oldname, Sys->OREAD);
	if(src == nil)
		return -1;

	# Create destination
	dst := sys->create(newname, Sys->OWRITE, 8r666);
	if(dst == nil) {
		src.close();
		return -1;
	}

	# Copy contents
	buf := array[8192] of byte;
	while((n := src.read(buf, len buf)) > 0) {
		dst.write(buf, n);
	}

	src.close();
	dst.close();

	# Remove source
	sys->remove(oldname);

	return 0;
}

# ====================================================================
# Standard Files
# ====================================================================

lua_stdin(): ref LuaFile
{
	lf := ref LuaFile;
	lf.fd = sys->fildes(0);
	lf.buf = bufio->fopen(lf.fd, Sys->OREAD);
	lf.name = "<stdin>";
	lf.mode = Sys->OREAD;
	lf.closed = 0;
	return lf;
}

lua_stdout(): ref LuaFile
{
	lf := ref LuaFile;
	lf.fd = sys->fildes(1);
	lf.buf = bufio->fopen(lf.fd, Sys->OWRITE);
	lf.name = "<stdout>";
	lf.mode = Sys->OWRITE;
	lf.closed = 0;
	return lf;
}

lua_stderr(): ref LuaFile
{
	lf := ref LuaFile;
	lf.fd = sys->fildes(2);
	lf.buf = bufio->fopen(lf.fd, Sys->OWRITE);
	lf.name = "<stderr>";
	lf.mode = Sys->OWRITE;
	lf.closed = 0;
	return lf;
}

# ====================================================================
# Bridge Functions for Lua
# ====================================================================

# Convert Lua file handle to LuaFile
getluafile(L: ref State; index: int): ref LuaFile
{
	if(L == nil || index < 0 || index >= L.top)
		return nil;

	val := L.stack[index];
	if(val == nil || val.ty != TUSERDATA)
		return nil;

	return val.u;
}

# ====================================================================
# Module Interface
# ====================================================================

init(): string
{
	sys = load Sys Sys;
	bufio = load Bufio Bufio;
	return nil;
}

about(): array of string
{
	return array[] of {
		"Lua VM for Inferno/Limbo",
		"File I/O Bridge",
		"Bridges Lua I/O to Inferno Sys->FileIO",
	};
}
