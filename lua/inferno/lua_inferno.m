# Lua VM for Inferno/Limbo - Main Integration Module
# Provides interface between Limbo and Lua VM

Luavm : module {
	# Types
	State: adt {
		# Internal state (opaque)
		data: array of byte;

		# Stack
		stack: cyclic ref Value;
		top: int;
		stacksize: int;

		# Call info
		ci: cyclic ref CallInfo;
		base: int;

		# Globals
		globals: ref Table;
		registry: ref Table;

		# Error handling
		errorjmp: int;
		errfunc: int;

		# Hooks
		hookfunc: ref Function;
		hookmask: string;
		hookcount: int;
	};

	Value: adt {
		ty: int;
		b: int;
		n: real;
		s: string;
		t: ref Table;
		f: ref Function;
		u: ref userdata;
		th: ref Thread;
	};

	Table: adt {
		meta: ref Table;
		array: cyclic ref Value;
		sizearray: int;
		hash: ref HashNode;
		sizehash: int;
	};

	Function: adt {
		isc: int;
		cfunc: fn(L: ref State): int;
		proto: ref Proto;
		upvals: cyclic ref Upval;
		nupvals: int;
		env: ref Table;
	};

	Proto: adt {
		name: string;
		source: string;
		linedefined: int;
		code: array of int;
		consts: cyclic ref Value;
		nconsts: int;
		protos: cyclic ref Proto;
		nprotos: int;
		upvalues: array of string;
		nupvals: int;
		locals: ref Locvar;
		nlocvars: int;
	};

	Locvar: adt {
		name: string;
		startpc: int;
		endpc: int;
	};

	Upval: adt {
		v: cyclic ref Value;
		open: int;
		prev: ref Upval;
		next: ref Upval;
		stacklevel: int;
	};

	Thread: adt {
		status: int;
		stack: cyclic ref Value;
		stacksize: int;
		ci: cyclic ref CallInfo;
		base: int;
		top: int;
		parent: ref Thread;
	};

	CallInfo: adt {
		func: ref Function;
		base: int;
		top: int;
		savedpc: int;
		nresults: int;
		previous: ref CallInfo;
		callstatus: int;
	};

	HashNode: adt {
		key: ref Value;
		val: ref Value;
		next: ref HashNode;
	};

	# Type constants
	TNIL: con -1;
	TBOOLEAN: con 0;
	TNUMBER: con 1;
	TSTRING: con 2;
	TTABLE: con 3;
	TFUNCTION: con 4;
	TUSERDATA: con 5;
	TTHREAD: con 6;

	# Status constants
	OK: con 0;
	YIELD: con 1;
	ERRRUN: con 2;
	ERRSYNTAX: con 3;
	ERRMEM: con 4;
	ERRERR: con 5;

	# Initialization
	init: fn(ctxt: ref Draw->Context, argv: list of string): int;
	newstate: fn(): ref State;
	close: fn(L: ref State);

	# Load and execute
	loadstring: fn(L: ref State; code: string; chunkname: string): int;
	loadfile: fn(L: ref State; filename: string): int;
	dofile: fn(L: ref State; filename: string): int;

	# Function calls
	pcall: fn(L: ref State; nargs: int; nresults: int): int;
	xpcall: fn(L: ref State; nargs: int; nresults: int; errfunc: int): int;

	# Stack operations
	pushnil: fn(L: ref State);
	pushboolean: fn(L: ref State; b: int);
	pushnumber: fn(L: ref State; n: real);
	pushstring: fn(L: ref State; s: string);
	pushvalue: fn(L: ref State; v: ref Value);
	pushcfunction: fn(L: ref State; f: fn(L: ref State): int);

	pop: fn(L: ref State; n: int);
	gettop: fn(L: ref State): int;
	settop: fn(L: ref State; n: int);

	# Value operations
	tostring: fn(L: ref State; v: ref Value): string;
	tonumber: fn(L: ref State; v: ref Value): (real, int);
	type: fn(L: ref State; v: ref Value): string;

	# Table operations
	newtable: fn(L: ref State): ref Table;
	gettable: fn(L: ref State; t: ref Table; k: ref Value): ref Value;
	settable: fn(L: ref State; t: ref Table; k, v: ref Value);

	# Library registration
	register: fn(L: ref State; name: string; funcs: array of (string, fn(L: ref State): int));

	# Module info
	about: fn(): array of string;
};
