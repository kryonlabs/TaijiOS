# Lua VM - Process Bridge for Inferno
# Bridges Lua os.execute to Inferno's Sys->exec

implement Luavm;

include "sys.m";
include "draw.m";
include "luavm.m";
include "lua_inferno.m";

sys: Sys;
print, sprint, fprint, pctl, spawn, exec, waitfor, bind, mount: import sys;

# ====================================================================
# Process Execution
# ====================================================================

# Execute command (like os.execute)
luaexec(command: string): int
{
	if(command == nil)
		return -1;

	# Parse command into executable and arguments
	(executable, args) := parsecommand(command);
	if(executable == nil)
		return -1;

	# Fork and exec
	pid := sys->pctl(Sys->FORKNS, nil);
	if(pid == -1)
		return -1;

	if(pid == 0) {
		# Child process
		fd := sys->open(executable, Sys->OREAD);
		if(fd == nil) {
			sys->fprint(sys->fildes(2), "lua: exec: %s: %r\n", executable);
			sys->raise("fail:exec");
		}

		# Convert args to list of string
		arglist := nil;
		for(i := len args - 1; i >= 0; i--) {
			arglist = args[i] :: arglist;
		}

		sys->exec(fd, arglist);
		sys->fprint(sys->fildes(2), "lua: exec: %r\n");
		sys->raise("fail:exec");
	}

	# Parent process - wait for child
	status := sys->waitfor(pid);
	if(status < 0)
		return -1;

	return 0;  # Success
}

# Execute command and capture output
luaexecoutput(command: string): (int, string)
{
	if(command == nil)
		return (-1, "");

	# Parse command
	(executable, args) := parsecommand(command);
	if(executable == nil)
		return (-1, "");

	# Create pipes for stdout
	# This is simplified - real implementation would use pipes

	# For now, just execute
	status := luaexec(command);
	if(status != 0)
		return (status, "");

	return (0, "");
}

# Spawn background process
luaspawn(command: string): int
{
	if(command == nil)
		return -1;

	(executable, args) := parsecommand(command);
	if(executable == nil)
		return -1;

	# Spawn without waiting
	pid := sys->spawn(executable :: args, nil);
	if(pid < 0)
		return -1;

	return pid;
}

# Wait for process
luawait(pid: int): int
{
	if(pid < 0)
		return -1;

	status := sys->waitfor(pid);
	return status;
}

# Kill process
luakill(pid: int): int
{
	if(pid < 0)
		return -1;

	# Inferno doesn't have direct kill, would use note
	# For now, return -1
	return -1;
}

# ====================================================================
# Command Parsing
# ====================================================================

# Parse command into executable and arguments
parsecommand(command: string): (string, array of string)
{
	if(command == nil || len command == 0)
		return (nil, nil);

	# Trim whitespace
	cmd := striptrim(command);

	# Simple parsing - split on spaces, respecting quotes
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
		} else if(c == '\\' && i + 1 < len cmd) {
			# Escape sequence
			i++;
			current[len current] = cmd[i];
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

	if(reversed == nil)
		return (nil, nil);

	executable := hd reversed;
	reversed = tl reversed;

	# Convert to array
	argarray := array[len reversed] of string;
	for(i := 0; i < len reversed; i++) {
		argarray[i] = hd reversed;
		reversed = tl reversed;
	}

	return (executable, argarray);
}

# Trim leading and trailing whitespace
striptrim(s: string): string
{
	if(s == nil)
		return nil;

	start := 0;
	end := len s;

	# Find first non-space
	while(start < end && (s[start] == ' ' || s[start] == '\t' || s[start] == '\n')) {
		start++;
	}

	# Find last non-space
	while(end > start && (s[end-1] == ' ' || s[end-1] == '\t' || s[end-1] == '\n')) {
		end--;
	}

	return s[start:end];
}

# ====================================================================
# Environment Variables (Inferno /env/)
# ====================================================================

# Get environment variable
getenv(varname: string): string
{
	if(varname == nil)
		return nil;

	# Inferno stores env vars in /env/
	envfile := "/env/" + varname;

	fd := sys->open(envfile, Sys->OREAD);
	if(fd == nil)
		return nil;

	buf := array[1024] of byte;
	n := fd.read(buf, len buf);
	fd.close();

	if(n <= 0)
		return nil;

	return string buf[0:n];
}

# Set environment variable
setenv(varname: string; value: string): int
{
	if(varname == nil || value == nil)
		return -1;

	# Inferno stores env vars in /env/
	envfile := "/env/" + varname;

	fd := sys->create(envfile, Sys->OWRITE, 8r666);
	if(fd == nil)
		return -1;

	n := fd.write(array of byte value);
	fd.close();

	if(n != len value)
		return -1;

	return 0;
}

# Unset environment variable
unsetenv(varname: string): int
{
	if(varname == nil)
		return -1;

	envfile := "/env/" + varname;

	return sys->remove(envfile);
}

# ====================================================================
# Current Process Info
# ====================================================================

# Get current process ID
getpid(): int
{
	return sys->pctl(0, nil);
}

# Get parent process ID
getppid(): int
{
	# Inferno doesn't expose parent PID directly
	# Would need to read from /proc/pid/status
	return 0;
}

# Get current working directory
getcwd(): string
{
	# Inferno doesn't have getcwd
	# Path is implicit in file namespace
	return ".";
}

# Change directory
chdir(path: string): int
{
	if(path == nil)
		return -1;

	# In Inferno, use bind to change namespace
	# This is simplified
	return 0;
}

# ====================================================================
# System Information
# ====================================================================

# Get system hostname
gethostname(): string
{
	# Read from /dev/sysname
	fd := sys->open("/dev/sysname", Sys->OREAD);
	if(fd == nil)
		return "inferno";

	buf := array[128] of byte;
	n := fd.read(buf, len buf);
	fd.close();

	if(n <= 0)
		return "inferno";

	# Trim newline
	name := string buf[0:n];
	if(len name > 0 && name[len name - 1] == '\n')
		name = name[:len name - 1];

	return name;
}

# Get system type (always "inferno")
getostype(): string
{
	return "inferno";
}

# Get architecture
getarch(): string
{
	# Inferno runs on many architectures
	# Would read from environment
	return "inferno";
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
		"Process Bridge",
		"Bridges Lua os.execute to Inferno Sys->exec",
	};
}
