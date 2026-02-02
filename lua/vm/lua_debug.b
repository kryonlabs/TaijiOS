# Lua VM - Debug Interface
# Provides debugging, tracing, and inspection capabilities

implement Luavm;

include "sys.m";
include "luavm.m";

sys: Sys;
print, sprint, fprint: import sys;

# ====================================================================
# Debug State
# ====================================================================

Debug: adt {
	L:			ref State;		# Lua state
	activerefs:	list of int;	# Active references
	breakpoints:	list of int;	# Breakpoint PCs
	hook:		ref DebugHook;	# Debug hook
	hookmask:	int;			# Hook mask
	hookcount:	int;			# Hook count
};

# Debug hook callback
DebugHook: adt {
	fn:		fn(debug: ref Debug, ar: ref DebugInfo);
};

# Debug information (activation record)
DebugInfo: adt {
	event:		int;		# Event (call, return, line, etc.)
	currentline:	int;		# Current line
	name:		string;		# Function name
	namewhat:	string;		# "global", "local", "method", etc.
	what:		string;		# "Lua", "C", "main"
	source:		string;		# Source file
	srclen:		int;		# Source length
	linedefined:	int;		# Line where defined
	lastlinedefined: int;	# Last line defined
	shortsrc:	string;		# Short source name
	i-ci:		int;		# Call info index
	nparams:		int;		# Number of parameters
	isvararg:	int;		# Vararg flag
	ftailcall:	int;		# Tail call flag
};

# Debug events
HOOKCALL:	con 1;
HOOKRETURN:	con 2;
HOOKLINE:	con 3;
HOOKCOUNT:	con 4;

# Hook masks
MASKCALL:	con 1 << HOOKCALL;
MASKRETURN:	con 1 << HOOKRETURN;
MASKLINE:	con 1 << HOOKLINE;
MASKCOUNT:	con 1 << HOOKCOUNT;

# ====================================================================
# Debug Creation
# ====================================================================

newdebug(L: ref State): ref Debug
{
	d := ref Debug;
	d.L = L;
	d.activerefs = nil;
	d.breakpoints = nil;
	d.hook = nil;
	d.hookmask = 0;
	d.hookcount = 0;
	return d;
}

# ====================================================================
# Stack Trace
# ====================================================================

# Get stack trace
getstacktrace(L: ref State): list of string
{
	trace: list of string;

	if(L == nil || L.ci == nil)
		return trace;

	# Walk call info chain
	ci := L.ci;
	level := 0;
	while(ci != nil) {
		info := getstackinfo(L, level);
		if(info != nil) {
			line := sprintfmt("%d: %s %s", level, info.what, info.name);
			trace = list of {line} + trace;
		}
		ci = ci.next;
		level++;
	}

	return trace;
}

# Get info about stack level
getstackinfo(L: ref State, level: int): ref DebugInfo
{
	if(L == nil || L.ci == nil)
		return nil;

	# Find call info at level
	ci := L.ci;
	curlevel := 0;
	while(ci != nil && curlevel < level) {
		ci = ci.next;
		curlevel++;
	}

	if(ci == nil)
		return nil;

	ar := ref DebugInfo;
	ar.event = 0;
	ar.currentline = -1;
	ar.i-ci = level;

	# Get function info
	if(ci.func != nil && ci.func.ty == TFUNCTION && ci.func.f != nil) {
		f := ci.func.f;
		if(f.proto != nil) {
			ar.name = "function";
			ar.namewhat = "Lua";
			ar.what = "Lua";
			ar.source = f.proto.sourcename;
			ar.linedefined = f.proto.lineDefined;
			ar.lastlinedefined = f.proto.lastLineDefined;
			ar.nparams = f.proto.numparams;
			ar.isvararg = f.proto.is_vararg;
		} else if(f.isc) {
			ar.name = "C function";
			ar.namewhat = "C";
			ar.what = "C";
		}
	} else {
		ar.name = "main";
		ar.what = "main";
		ar.namewhat = "main";
	}

	ar.shortsrc = getshortsrc(ar.source);

	return ar;
}

# Get short source name
getshortsrc(source: string): string
{
	if(source == nil || len source == 0)
		return "";

	# Extract filename from path
	# If source is "@filename", return filename
	if(len source > 0 && source[0] == '@')
		return source[1:];

	# If source is long, truncate
	if(len source > 60)
		return source[0:30] + "..." + source[len source - 27:];

	return source;
}

# ====================================================================
# Variable Inspection
# ====================================================================

# Get local variable at level
getlocal(L: ref State, level, n: int): ref Value
{
	if(L == nil)
		return nil;

	info := getstackinfo(L, level);
	if(info == nil)
		return nil;

	# For now, return nil
	# Full implementation would track locals in FuncState
	return nil;
}

# Set local variable at level
setlocal(L: ref State, level, n: int, val: ref Value): int
{
	if(L == nil || val == nil)
		return 0;

	info := getstackinfo(L, level);
	if(info == nil)
		return 0;

	# Full implementation would set local
	return 0;
}

# Get upvalue
getupvalue(func: ref Function, n: int): (string, ref Value)
{
	if(func == nil || func.upvals == nil || n < 1 || n > len func.upvals)
		return (nil, nil);

	uv := func.upvals[n - 1];
	if(uv == nil || uv.v == nil)
		return (nil, nil);

	name := sprint("upval_%d", n);
	return (name, uv.v);
}

# Setupvalue
setupvalue(func: ref Function, n: int, val: ref Value): int
{
	if(func == nil || func.upvals == nil || n < 1 || n > len func.upvals)
		return 0;

	uv := func.upvals[n - 1];
	if(uv == nil)
		return 0;

	uv.v = val;
	return 1;
}

# ====================================================================
# Breakpoints
# ====================================================================

# Set breakpoint
setbreakpoint(d: ref Debug, pc: int)
{
	d.breakpoints = list of {pc} + d.breakpoints;
}

# Clear breakpoint
clearbreakpoint(d: ref Debug, pc: int)
{
	found := 0;
	newlist: list of int;

	while(d.breakpoints != nil) {
		bp := hd d.breakpoints;
		if(bp == pc && !found) {
			found = 1;
		} else {
			newlist = list of {bp} + newlist;
		}
		d.breakpoints = tl d.breakpoints;
	}

	d.breakpoints = newlist;
}

# Check breakpoint
isbreakpoint(d: ref Debug, pc: int): int
{
	while(d.breakpoints != nil) {
		if(hd d.breakpoints == pc)
			return 1;
		d.breakpoints = tl d.breakpoints;
	}
	return 0;
}

# ====================================================================
# Hooks
# ====================================================================

# Set hook
sethook(d: ref Debug, hook: ref DebugHook, mask: int, count: int)
{
	d.hook = hook;
	d.hookmask = mask;
	d.hookcount = count;
}

# Get hook mask
gethookmask(d: ref Debug): int
{
	return d.hookmask;
}

# Get hook count
gethookcount(d: ref Debug): int
{
	return d.hookcount;
}

# Call hook
callhook(d: ref Debug, event: int, ar: ref DebugInfo)
{
	if(d.hook == nil)
		return;

	if((d.hookmask & (1 << event)) != 0) {
		ar.event = event;
		d.hook.fn(d, ar);
	}
}

# ====================================================================
# Stack Inspection
# ====================================================================

# Dump stack to string
dumpstack(L: ref State): string
{
	if(L == nil || L.stack == nil)
		return "empty stack";

	s := "";
	for(i := 0; i < L.top; i++) {
		v := L.stack[i];
		s += sprint("[%d] %s: %s\n", i, typeName(v), tostring(v));
	}
	return s;
}

# Dump call stack
dumpcallstack(L: ref State): string
{
	trace := getstacktrace(L);
	s := "";
	while(trace != nil) {
		s += hd trace + "\n";
		trace = tl trace;
	}
	return s;
}

# ====================================================================
# Code Inspection
# ====================================================================

# Disassemble function
disassemblefunc(func: ref Function): list of string
{
	if(func == nil || func.proto == nil || func.proto.code == nil)
		return nil;

	return disassemblecode(func.proto.code);
}

# Get function info
getfuncinfo(func: ref Function): ref DebugInfo
{
	if(func == nil)
		return nil;

	ar := ref DebugInfo;
	ar.event = 0;
	ar.currentline = -1;
	ar.i-ci = -1;

	if(func.proto != nil) {
		p := func.proto;
		ar.what = "Lua";
		ar.source = p.sourcename;
		ar.linedefined = p.lineDefined;
		ar.lastlinedefined = p.lastLineDefined;
		ar.nparams = p.numparams;
		ar.isvararg = p.is_vararg;
		ar.name = "function";
		ar.namewhat = "Lua";
	} else if(func.isc) {
		ar.what = "C";
		ar.name = "C function";
		ar.namewhat = "C";
		ar.source = "[C]";
		ar.linedefined = -1;
		ar.lastlinedefined = -1;
	}

	ar.shortsrc = getshortsrc(ar.source);

	return ar;
}

# ====================================================================
# Profiling
# ====================================================================

# Profile entry
ProfileEntry: adt {
	name:		string;
	count:		big;
	time:		big;
};

# Profile state
Profile: adt {
	entries:	list of ref ProfileEntry;
	total:		big;
	start:		big;
};

# Create profile
newprofile(): ref Profile
{
	p := ref Profile;
	p.entries = nil;
	p.total = 0big;
	p.start = 0big;
	return p;
}

# Start profiling
startprofile(p: ref Profile)
{
	p.start = 0big;  # Would use real time
}

# Stop profiling
stopprofile(p: ref Profile): big
{
	return 0big;  # Would return elapsed time
}

# Add profile entry
addprofile(p: ref Profile, name: string, time: big)
{
	# Check if entry exists
	entries := p.entries;
	while(entries != nil) {
		e := hd entries;
		if(e.name == name) {
			e.count++;
			e.time += time;
			return;
		}
		entries = tl entries;
	}

	# Create new entry
	e := ref ProfileEntry;
	e.name = name;
	e.count = 1big;
	e.time = time;
	p.entries = list of {e} + p.entries;
	p.total += time;
}

# Get profile report
getprofilereport(p: ref Profile): list of string
{
	report: list of string;
	report = list of {"Function\tCalls\tTime\t%"} + report;

	entries := p.entries;
	while(entries != nil) {
		e := hd entries;
		pct := 0.0;
		if(p.total > 0big)
			pct = (real(e.time) * 100.0) / real(p.total);

		line := sprintfmt("%s\t%d\t%d\t%.1f%%", e.name, e.count, e.time, pct);
		report = list of {line} + report;
		entries = tl entries;
	}

	return report;
}

# ====================================================================
# Debug Print Functions
# ====================================================================

# Print stack
printstack(L: ref State)
{
	s := dumpstack(L);
	if(s != nil)
		print(s);
}

# Print call stack
printcallstack(L: ref State)
{
	s := dumpcallstack(L);
	if(s != nil)
		print(s);
}

# Print value
printvalue(v: ref Value)
{
	if(v == nil) {
		print("nil\n");
		return;
	}

	print(sprint("%s\t%s\n", typeName(v), tostring(v)));
}

# Print table
printtable(t: ref Table, indent: int)
{
	if(t == nil) {
		print("nil\n");
		return;
	}

	# Print array part
	for(i := 0; i < t.sizearray; i++) {
		if(t.arr[i] != nil) {
			for(j := 0; j < indent; j++)
				print("  ");
			print(sprint("[%d] = %s\n", i + 1, tostring(t.arr[i])));
		}
	}

	# Print hash part (simplified)
	if(t.hash != nil) {
		# Would iterate hash chain
	}
}

# ====================================================================
# Formatted Sprint
# ====================================================================

sprintfmt(fmt: string, args: array of ...): string
{
	# Simplified formatted string
	result := fmt;
	argidx := 0;

	# Format specifiers
	%s =>	{
			if(argidx < len args)
				result += sprint("%s", args[argidx++]);
		}
	%d =>	{
			if(argidx < len args)
				result += sprint("%d", args[argidx++]);
		}
	%g =>	{
			if(argidx < len args)
				result += sprint("%g", args[argidx++]);
		}
	%. =>	{
			if(argidx < len args)
				result += sprint("%.1f", args[argidx++]);
		}
	* =>
		skip;
	}

	return result;
}

# ====================================================================
# Module Interface
# ====================================================================

# Initialize debug system
initdebug(L: ref State): ref Debug
{
	return newdebug(L);
}

# Get debug info at level
getinfo(L: ref State, level: int): ref DebugInfo
{
	return getstackinfo(L, level);
}

# Get local
getlocal(L: ref State, level, n: int): ref Value
{
	return getlocal(L, level, n);
}

# Set local
setlocal(L: ref State, level, n: int, val: ref Value): int
{
	return setlocal(L, level, n, val);
}

# Module initialization
init(): string
{
	sys = load Sys Sys;
	return nil;
}

about(): array of string
{
	return array[] of {
		"Lua VM for Inferno/Limbo",
		"Debug Interface",
		"Provides debugging, tracing, and inspection",
	};
}
