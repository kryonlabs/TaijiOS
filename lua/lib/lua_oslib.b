# Lua VM - OS Library
# Implements os.* functions for Inferno
# Adapts to Inferno's Sys->exec and system calls

implement Luavm;

include "sys.m";
include "draw.m";
include "luavm.m";
include "lua_baselib.m";

sys: Sys;
print, sprint, fprint, pctl, sleep, kill, open, mount, bind, unmount: import sys;

# ====================================================================
# Time Functions
# ====================================================================

# os.time([table]) - Get current time or convert table to time
os_time(L: ref State): int
{
	if(L == nil)
		return 0;

	# If no argument, return current time
	if(L.top < 1) {
		t := sys->millisec();
		pushnumber(L, real(t / 1000));
		return 1;
	}

	tabval := L.stack[L.top - 1];
	if(tabval == nil || tabval.ty != TTABLE) {
		t := sys->millisec();
		pushnumber(L, real(t / 1000));
		return 1;
	}

	# Convert table to time (simplified)
	t := sys->millisec();
	pushnumber(L, real(t / 1000));
	return 1;
}

# os.date([format[, time]]) - Format date/time
os_date(L: ref State): int
{
	if(L == nil)
		return 0;

	# Get format (default "%c")
	format := "%c";
	if(L.top >= 1) {
		fmtval := L.stack[L.top - 1];
		if(fmtval != nil && fmtval.ty == TSTRING)
			format = fmtval.s;
	}

	# Get time (default current time)
	t := sys->millisec();
	if(L.top >= 2) {
		timeval := L.stack[L.top - 2];
		if(timeval != nil && timeval.ty == TNUMBER)
			t = int(timeval.n * 1000);
	}

	# If format is "*t", return table
	if(format == "*t") {
		tab := createtable(0, 9);

		# Get time components (simplified)
		sec := int((t / 1000) % 60);
		min := int((t / 60000) % 60);
		hour := int((t / 3600000) % 24);
		day := int((t / 86400000) % 30 + 1);
		month := int((t / 2592000000) % 12 + 1);
		year := int(1970 + t / 31536000000);
		wday := int((t / 86400000) % 7);
		yday := int((t / 86400000) % 365);

		# Set fields
		key := ref Value;
		val := ref Value;

		key.ty = TSTRING;

		key.s = "sec";
		val.ty = TNUMBER;
		val.n = real(sec);
		settablevalue(tab, key, val);

		key.s = "min";
		val.n = real(min);
		settablevalue(tab, key, val);

		key.s = "hour";
		val.n = real(hour);
		settablevalue(tab, key, val);

		key.s = "day";
		val.n = real(day);
		settablevalue(tab, key, val);

		key.s = "month";
		val.n = real(month);
		settablevalue(tab, key, val);

		key.s = "year";
		val.n = real(year);
		settablevalue(tab, key, val);

		key.s = "wday";
		val.n = real(wday);
		settablevalue(tab, key, val);

		key.s = "yday";
		val.n = real(yday);
		settablevalue(tab, key, val);

		key.s = "isdst";
		val.n = 0.0;
		settablevalue(tab, key, val);

		pushvalue(L, mktable(tab));
		return 1;
	}

	# Format string (simplified)
	datestr := sprint("%d", int(t / 1000));
	pushstring(L, datestr);
	return 1;
}

# os.difftime(t2, t1) - Time difference
os_difftime(L: ref State): int
{
	if(L == nil || L.top < 2)
		return 0;

	t2val := L.stack[L.top - 1];
	t1val := L.stack[L.top - 2];

	if(t2val == nil || t2val.ty != TNUMBER ||
	   t1val == nil || t1val.ty != TNUMBER) {
		return 0;
	}

	diff := t2val.n - t1val.n;
	pushnumber(L, diff);
	return 1;
}

# ====================================================================
# System Operations
# ====================================================================

# os.execute([command]) - Execute command
os_execute(L: ref State): int
{
	if(L == nil)
		return 0;

	# If no command, check if shell is available
	if(L.top < 1) {
		pushnumber(L, 1.0);  # Shell available
		return 1;
	}

	cmdval := L.stack[L.top - 1];
	if(cmdval == nil || cmdval.ty != TSTRING) {
		pushnumber(L, 1.0);
		return 1;
	}

	command := cmdval.s;

	# Execute command using Sys->exec
	# This is simplified - real implementation would use sys->exec or sys->pipeline
	pid := sys->pctl(Sys->FORKNS, nil);
	if(pid == -1) {
		pushnil(L);
		pushstring(L, "execute: fork failed");
		pushnumber(L, 1.0);
		return 3;
	}

	if(pid == 0) {
		# Child process
		# Parse and execute command
		args := splitcommand(command);
		if(args != nil && len args > 0) {
			cmd := hd args;
			args = tl args;

			executable := sys->open(cmd, Sys->OREAD);
			if(executable != nil) {
				sys->exec(executable, args);
			}
		}
		sys->fprint(sys->fildes(2), "execute: exec failed\n");
		sys->raise("fail:exec");
	}

	# Parent process - wait for child
	status := sys->waitfor(pid);
	pushnumber(L, 0.0);  # Success
	return 1;
}

# os.exit([code[, close]]) - Exit program
os_exit(L: ref State): int
{
	if(L == nil)
		return 0;

	code := 0;
	if(L.top >= 1) {
		codeval := L.stack[L.top - 1];
		if(codeval != nil && codeval.ty == TBOOLEAN)
			code = int(codeval.b);
		else if(codeval != nil && codeval.ty == TNUMBER)
			code = int(codeval.n);
	}

	# Close Lua state (if requested)
	if(L.top >= 2) {
		closeval := L.stack[L.top - 2];
		if(closeval != nil && closeval.ty == TBOOLEAN && closeval.b != 0) {
			# Close state (placeholder)
		}
	}

	sys->raise("fail:exit");
	return 0;
}

# os.getenv(varname) - Get environment variable
os_getenv(L: ref State): int
{
	if(L == nil || L.top < 1)
		return 0;

	nameval := L.stack[L.top - 1];
	if(nameval == nil || nameval.ty != TSTRING) {
		pushnil(L);
		return 1;
	}

	varname := nameval.s;

	# Inferno doesn't have traditional environment variables
	# We could check /env/ files
	envfile := "/env/" + varname;
	fd := sys->open(envfile, Sys->OREAD);
	if(fd == nil) {
		pushnil(L);
		return 1;
	}

	buf := array[1024] of byte;
	n := fd.read(buf, len buf);
	fd.close();

	if(n <= 0) {
		pushnil(L);
		return 1;
	}

	value := string buf[0:n];
	pushstring(L, value);
	return 1;
}

# os.remove(filename) - Remove file
os_remove(L: ref State): int
{
	if(L == nil || L.top < 1)
		return 0;

	nameval := L.stack[L.top - 1];
	if(nameval == nil || nameval.ty != TSTRING) {
		pushnil(L);
		pushstring(L, "remove: filename must be string");
		return 2;
	}

	filename := nameval.s;

	# Remove file
	ret := sys->remove(filename);
	if(ret < 0) {
		pushnil(L);
		pushstring(L, sprint("remove: cannot remove %s", filename));
		return 2;
	}

	pushnumber(L, 1.0);  # Success
	return 1;
}

# os.rename(oldname, newname) - Rename file
os_rename(L: ref State): int
{
	if(L == nil || L.top < 2)
		return 0;

	oldval := L.stack[L.top - 1];
	newval := L.stack[L.top - 2];

	if(oldval == nil || oldval.ty != TSTRING ||
	   newval == nil || newval.ty != TSTRING) {
		pushnil(L);
		pushstring(L, "rename: arguments must be strings");
		return 2;
	}

	oldname := oldval.s;
	newname := newval.s;

	# Rename using sys->remove + sys->create (simplified)
	fd := sys->open(oldname, Sys->OREAD);
	if(fd == nil) {
		pushnil(L);
		pushstring(L, "rename: cannot open source");
		return 2;
	}

	# Create new file
	newfd := sys->create(newname, Sys->OWRITE, 8r666);
	if(newfd == nil) {
		fd.close();
		pushnil(L);
		pushstring(L, "rename: cannot create target");
		return 2;
	}

	# Copy contents
	buf := array[8192] of byte;
	while((n := fd.read(buf, len buf)) > 0) {
		newfd.write(buf, n);
	}

	fd.close();
	newfd.close();

	# Remove old
	sys->remove(oldname);

	pushnumber(L, 1.0);  # Success
	return 1;
}

# os.tmpname() - Generate temporary file name
os_tmpname(L: ref State): int
{
	if(L == nil)
		return 0;

	# Generate unique temp name
	pid := sys->pctl(0, nil);
	timestamp := sys->millisec();
	tmpname := sprint("/tmp/lua_%d_%d.tmp", pid, timestamp);

	pushstring(L, tmpname);
	return 1;
}

# os.clock() - CPU time (approximate)
os_clock(L: ref State): int
{
	if(L == nil)
		return 0;

	# Return elapsed time in seconds (wall clock, not CPU time)
	t := sys->millisec();
	pushnumber(L, real(t) / 1000.0);
	return 1;
}

# ====================================================================
# Helper Functions
# ====================================================================

# Split command into arguments
splitcommand(cmd: string): list of string
{
	if(cmd == nil)
		return nil;

	args: list of string = nil;
	current := "";
	inquote := 0;

	for(i := 0; i < len cmd; i++) {
		c := cmd[i];

		if(c == ' ' && !inquote) {
			if(len current > 0) {
				args = current :: args;
				current = "";
			}
		} else if(c == '"') {
			inquote = !inquote;
		} else {
			current[len current] = c;
		}
	}

	if(len current > 0)
		args = current :: args;

	# Reverse list
	reversed: list of string = nil;
	while(args != nil) {
		reversed = hd args :: reversed;
		args = tl args;
	}

	return reversed;
}

# ====================================================================
# Library Registration
# ====================================================================

# Open os library
open os(L: ref State): int
{
	if(L == nil)
		return 0;

	# Create os library table
	lib := createtable(0, 12);

	# Register functions
	setlibfunc(lib, "clock", os_clock);
	setlibfunc(lib, "date", os_date);
	setlibfunc(lib, "difftime", os_difftime);
	setlibfunc(lib, "execute", os_execute);
	setlibfunc(lib, "exit", os_exit);
	setlibfunc(lib, "getenv", os_getenv);
	setlibfunc(lib, "remove", os_remove);
	setlibfunc(lib, "rename", os_rename);
	setlibfunc(lib, "time", os_time);
	setlibfunc(lib, "tmpname", os_tmpname);

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
	return nil;
}

about(): array of string
{
	return array[] of {
		"Lua VM for Inferno/Limbo",
		"OS Library",
		"System operations for Inferno",
	};
}
