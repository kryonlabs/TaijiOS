# Limbo Function Caller Module
# Defines interfaces for calling Limbo functions from Lua

Limbocaller: module {
	PATH:	con "/dis/lib/limbocaller.dis";

	# Execution context for function calls
	Context: adt {
		mod:		ref Luadisparser->DISFile;
		modinst:	Loader->Nilmod;
		pc:		int;
		fp:		int;		# Frame pointer
		sp:		int;		# Stack pointer
		stack:		array of ref Value;
		nargs:		int;
		status:		int;
		error:		string;
	};

	# Return value
	Return: adt {
		count:	int;		# Number of return values
		values:	list of ref Value;	# Return values
	};

	# Error types
	EOK:		con 0;		# Success
	ENOMEM:		con 1;		# Out of memory
	ESTACK:		con 2;		# Stack overflow
	EINSTR:		con 3;		# Invalid instruction
	ETYPE:		con 4;		# Type mismatch
	EEXCEPT:	con 5;		# Exception raised
	ETIMEOUT:	con 6;		# Execution timeout

	# Caller API
	createcontext:	fn(mod: ref Luadisparser->DISFile, link: ref Luadisparser->DISLink): ref Context;
	setupcall:	fn(ctx: ref Context, nargs: int): int;
	pusharg:		fn(ctx: ref Context, arg: ref Value, typesig: string): int;
	call:		fn(ctx: ref Context): ref Return;
	freectx:	fn(ctx: ref Context);

	# Instruction execution
	execute:	fn(ctx: ref Context): int;
	step:		fn(ctx: ref Context): int;

	# Value conversion (using lua_marshal)
	marshalarg:	fn(val: ref Value, typesig: string): ref Value;
	unmarshalresult:	fn(ret: ref Return, typesig: string): list of ref Value;

	# Error handling
	geterror:	fn(ctx: ref Context): string;
	errstr:		fn(err: int): string;

	# Utility
	getentry:	fn(link: ref Luadisparser->DISLink): int;
	issafe:		fn(ctx: ref Context): int;

	# About
	about:		fn(): array of string;
};

# Value ADT (for execution)
Value: adt {
	pick {
	Nil =>
		(void);
	Int =>
		v: int;
	Real =>
		v: real;
	String =>
		v: string;
	Array =>
		v:	array of ref Value;
	}
};
