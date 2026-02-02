# Lua VM - I/O Library
# Implements io.* functions for Inferno
# Adapts to Inferno's Sys->FileIO

implement Luavm;

include "sys.m";
include "draw.m";
include "bufio.m";
include "luavm.m";
include "lua_baselib.m";

sys: Sys;
print, sprint, fprint: import sys;

bufio: Bufio;
Iobuf: import bufio;

# ====================================================================
# File Handle for Lua
# ====================================================================

File: adt {
	fid: ref Sys->FD;
	buf: ref Iobuf;
	name: string;
	mode: string;  # "r", "w", "a", "r+"
	closed: int;
};

# ====================================================================
# Standard File Handles
# ====================================================================

stdinfile: ref File;
stdoutfile: ref File;
stderrfile: ref File;

# ====================================================================
# I/O Operations
# ====================================================================

# io.open(filename[, mode]) - Open file
io_open(L: ref State): int
{
	if(L == nil || L.top < 1)
		return 0;

	nameval := L.stack[L.top - 1];
	if(nameval == nil || nameval.ty != TSTRING) {
		pushstring(L, "open: filename must be string");
		return ERRRUN;
	}

	filename := nameval.s;

	# Get mode (default "r")
	mode := "r";
	if(L.top >= 2) {
		modeval := L.stack[L.top - 2];
		if(modeval != nil && modeval.ty == TSTRING)
			mode = modeval.s;
	}

	# Open file
	f := openfile(filename, mode);
	if(f == nil) {
		pushnil(L);
		pushstring(L, sprint("open: cannot open %s", filename));
		return 2;
	}

	# Push file handle as userdata
	pushuserdata(L, f);
	return 1;
}

# io.close([file]) - Close file
io_close(L: ref State): int
{
	if(L == nil)
		return 0;

	f: ref File;

	if(L.top >= 1) {
		fileval := L.stack[L.top - 1];
		if(fileval == nil || fileval.ty != TUSERDATA) {
			# Try to use default output
			f = stdoutfile;
		} else {
			f = fileval.u;
		}
	} else {
		f = stdoutfile;
	}

	if(f != nil && !f.closed) {
		if(f.buf != nil)
			f.buf.close();
		if(f.fid != nil)
			f.fid.close();
		f.closed = 1;
	}

	pushnil(L);
	return 1;
}

# io.read(...) - Read from stdin
io_read(L: ref State): int
{
	if(L == nil)
		return 0;

	return file_read(L, stdinfile);
}

# io.write(...) - Write to stdout
io_write(L: ref State): int
{
	if(L == nil)
		return 0;

	return file_write(L, stdoutfile);
}

# io.flush([file]) - Flush file
io_flush(L: ref State): int
{
	if(L == nil)
		return 0;

	f: ref File;

	if(L.top >= 1) {
		fileval := L.stack[L.top - 1];
		if(fileval != nil && fileval.ty == TUSERDATA)
			f = fileval.u;
		else
			f = stdoutfile;
	} else {
		f = stdoutfile;
	}

	if(f != nil && f.buf != nil && !f.closed)
		f.buf.flush();

	pushnil(L);
	return 1;
}

# io.lines([filename]) - Iterate over lines
io_lines(L: ref State): int
{
	if(L == nil)
		return 0;

	f: ref File;

	# If filename provided, open it
	if(L.top >= 1) {
		nameval := L.stack[L.top - 1];
		if(nameval != nil && nameval.ty == TSTRING) {
			f = openfile(nameval.s, "r");
			if(f == nil) {
				pushnil(L);
				pushstring(L, "lines: cannot open file");
				return 2;
			}
		} else {
			f = stdinfile;
		}
	} else {
		f = stdinfile;
	}

	# Return iterator function
	pushcfunction(L, lines_iterator);
	pushuserdata(L, f);
	pushnil(L);  # State

	return 3;
}

# lines iterator
lines_iterator(L: ref State): int
{
	if(L == nil || L.top < 2)
		return 0;

	fval := L.stack[L.top - 2];
	if(fval == nil || fval.ty != TUSERDATA) {
		pushnil(L);
		return 1;
	}

	f := fval.u;
	if(f == nil || f.closed) {
		pushnil(L);
		return 1;
	}

	# Read line
	line := f.buf.reads('\n');
	if(line == nil || len line == 0) {
		# EOF
		if(f.buf != nil)
			f.buf.close();
		f.closed = 1;
		pushnil(L);
		return 1;
	}

	pushstring(L, line);
	return 1;
}

# io.type(obj) - Get file type
io_type(L: ref State): int
{
	if(L == nil || L.top < 1)
		return 0;

	objval := L.stack[L.top - 1];
	if(objval == nil || objval.ty != TUSERDATA) {
		pushnil(L);
		return 1;
	}

	f := objval.u;
	if(f == nil) {
		pushnil(L);
		return 1;
	}

	if(f.closed)
		pushstring(L, "closed file");
	else
		pushstring(L, "file");

	return 1;
}

# ====================================================================
# File Methods
# ====================================================================

# file:close()
file_close(L: ref State): int
{
	if(L == nil || L.top < 1)
		return 0;

	fileval := L.stack[L.top - 1];
	if(fileval == nil || fileval.ty != TUSERDATA)
		return 0;

	f := fileval.u;
	if(f != nil && !f.closed) {
		if(f.buf != nil)
			f.buf.close();
		if(f.fid != nil)
			f.fid.close();
		f.closed = 1;
	}

	pushnil(L);
	return 1;
}

# file:read(...)
file_read(L: ref State): int
{
	if(L == nil || L.top < 1)
		return 0;

	fileval := L.stack[L.top - 1];
	if(fileval == nil || fileval.ty != TUSERDATA)
		return 0;

	f := fileval.u;

	# Skip file argument, process formats
	nformats := L.top - 1;
	results := 0;

	for(i := 0; i < nformats; i++) {
		fmtval := L.stack[i];
		if(fmtval == nil || fmtval.ty != TNUMBER)
			continue;

		fmt := int(fmtval.n);

		case fmt {
		"*n" =>  # Number
			if(f.buf == nil || f.closed) {
				pushnil(L);
				results++;
				break;
			}
			line := f.buf.reads('\n');
			if(line == nil) {
				pushnil(L);
				results++;
				break;
			}
			# Parse number
			(num, ok) := strtonum(line);
			if(ok)
				pushnumber(L, num);
			else
				pushnil(L);
			results++;

		"*l" or 1 =>  # Line
			if(f.buf == nil || f.closed) {
				pushnil(L);
				results++;
				break;
			}
			line := f.buf.reads('\n');
			if(line == nil) {
				pushnil(L);
				results++;
				break;
			}
			pushstring(L, line);
			results++;

		"*a" =>  # All
			if(f.buf == nil || f.closed) {
				pushstring(L, "");
				results++;
				break;
			}
			# Read all remaining
			all := "";
			for(;;) {
				line := f.buf.reads('\n');
				if(line == nil)
					break;
				all += line;
			}
			pushstring(L, all);
			results++;
		}
	}

	return results;
}

# file:write(...)
file_write(L: ref State): int
{
	if(L == nil || L.top < 1)
		return 0;

	fileval := L.stack[L.top - 1];
	if(fileval == nil || fileval.ty != TUSERDATA)
		return 0;

	f := fileval.u;
	if(f == nil || f.closed || f.fid == nil) {
		pushnil(L);
		pushstring(L, "write: file is closed");
		return 2;
	}

	# Write all arguments
	nargs := L.top - 1;
	for(i := 0; i < nargs; i++) {
		val := L.stack[i];
		if(val == nil)
			continue;

		s: string;
		if(val.ty == TNUMBER)
			s = sprint("%g", val.n);
		else if(val.ty == TSTRING)
			s = val.s;
		else
			s = tostring(val);

		if(f.buf != nil)
			f.buf.puts(s);
		else
			f.fid.write(array of byte s);
	}

	pushvalue(L, fileval);  # Return file
	return 1;
}

# file:flush()
file_flush(L: ref State): int
{
	if(L == nil || L.top < 1)
		return 0;

	fileval := L.stack[L.top - 1];
	if(fileval == nil || fileval.ty != TUSERDATA)
		return 0;

	f := fileval.u;
	if(f != nil && f.buf != nil && !f.closed)
		f.buf.flush();

	pushvalue(L, fileval);
	return 1;
}

# file:lines()
file_lines(L: ref State): int
{
	if(L == nil || L.top < 1)
		return 0;

	fileval := L.stack[L.top - 1];
	if(fileval == nil || fileval.ty != TUSERDATA)
		return 0;

	f := fileval.u;

	pushcfunction(L, lines_iterator);
	pushvalue(L, fileval);
	pushnil(L);

	return 3;
}

# file:setvbuf(mode[, size])
file_setvbuf(L: ref State): int
{
	# Placeholder - Inferno's Bufio handles buffering
	pushnil(L);
	return 1;
}

# file:seek([whence[, offset]])
file_seek(L: ref State): int
{
	if(L == nil || L.top < 1)
		return 0;

	fileval := L.stack[L.top - 1];
	if(fileval == nil || fileval.ty != TUSERDATA)
		return 0;

	f := fileval.u;
	if(f == nil || f.closed || f.fid == nil) {
		pushnil(L);
		pushstring(L, "seek: file is closed");
		return 2;
	}

	# Get whence (default "cur")
	whence := "cur";
	if(L.top >= 2) {
		whenceval := L.stack[L.top - 2];
		if(whenceval != nil && whenceval.ty == TSTRING)
			whence = whenceval.s;
	}

	# Get offset (default 0)
	offset := big 0;
	if(L.top >= 3) {
		offsetval := L.stack[L.top - 3];
		if(offsetval != nil && offsetval.ty == TNUMBER)
			offset = big offsetval.n;
	}

	# Seek
	mode := Sys->SEEKSTART;
	if(whence == "cur")
		mode = Sys->SEEKRELA;
	else if(whence == "end")
		mode = Sys->SEEKEND;

	pos := f.fid.seek(offset, mode);
	if(pos == big -1) {
		pushnil(L);
		pushstring(L, "seek: failed");
		return 2;
	}

	pushnumber(L, real pos);
	return 1;
}

# ====================================================================
# Helper Functions
# ====================================================================

# Open file
openfile(filename: string, mode: string): ref File
{
	if(filename == nil)
		return nil;

	# Determine open mode
	omode := Sys->OREAD;
	if(mode == "w") {
		omode = Sys->OWRITE;
	} else if(mode == "a") {
		omode = Sys->OWRITE;
	} else if(mode == "r+") {
		omode = Sys->ORDWR;
	}

	# Open file
	fid := sys->open(filename, omode);
	if(fid == nil) {
		# Try to create for write mode
		if(mode == "w" || mode == "a") {
			fid = sys->create(filename, Sys->OWRITE, 8r666);
			if(fid == nil)
				return nil;
		} else {
			return nil;
		}
	}

	# Create buffered I/O
	buf := bufio->fopen(fid, mode);
	if(buf == nil) {
		fid.close();
		return nil;
	}

	f := ref File;
	f.fid = fid;
	f.buf = buf;
	f.name = filename;
	f.mode = mode;
	f.closed = 0;

	return f;
}

# ====================================================================
# Library Registration
# ====================================================================

# Initialize standard file handles
initstdio()
{
	stdinfile = ref File;
	stdinfile.fid = sys->fildes(0);
	stdinfile.buf = bufio->fopen(stdinfile.fid, Sys->OREAD);
	stdinfile.name = "<stdin>";
	stdinfile.mode = "r";
	stdinfile.closed = 0;

	stdoutfile = ref File;
	stdoutfile.fid = sys->fildes(1);
	stdoutfile.buf = bufio->fopen(stdoutfile.fid, Sys->OWRITE);
	stdoutfile.name = "<stdout>";
	stdoutfile.mode = "w";
	stdoutfile.closed = 0;

	stderrfile = ref File;
	stderrfile.fid = sys->fildes(2);
	stderrfile.buf = bufio->fopen(stderrfile.fid, Sys->OWRITE);
	stderrfile.name = "<stderr>";
	stderrfile.mode = "w";
	stderrfile.closed = 0;
}

# Open io library
open io(L: ref State): int
{
	if(L == nil)
		return 0;

	# Initialize standard I/O
	initstdio();

	# Create io library table
	lib := createtable(0, 15);

	# Register functions
	setlibfunc(lib, "close", io_close);
	setlibfunc(lib, "flush", io_flush);
	setlibfunc(lib, "lines", io_lines);
	setlibfunc(lib, "open", io_open);
	setlibfunc(lib, "read", io_read);
	setlibfunc(lib, "type", io_type);
	setlibfunc(lib, "write", io_write);

	# Register standard file handles
	key := ref Value;
	val := ref Value;

	key.ty = TSTRING;
	key.s = "stdin";

	val.ty = TUSERDATA;
	val.u = stdinfile;

	settablevalue(lib, key, val);

	key.s = "stdout";
	val.u = stdoutfile;
	settablevalue(lib, key, val);

	key.s = "stderr";
	val.u = stderrfile;
	settablevalue(lib, key, val);

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
	bufio = load Bufio Bufio;
	return nil;
}

about(): array of string
{
	return array[] of {
		"Lua VM for Inferno/Limbo",
		"I/O Library",
		"File operations for Inferno",
	};
}
