# Lua VM - Limbo FFI Module Interface
# Provides generic Foreign Function Interface for loading Limbo modules from Lua

Limbo: module {
	PATH:	con "/dis/lib/limbo.dis";

	# Type conversion functions
	# Convert Lua value at stack index idx to Limbo value of type typesig
	lua2limbo:	fn(L: ref Luavm->State, idx: int, typesig: string): ref Value;

	# Convert Limbo value to Lua value of type typesig, push on stack
	limbo2lua:	fn(L: ref Luavm->State, limboval: ref Value, typesig: string): int;

	# Module loading functions
	# Load a Limbo module by name, returns Lua table with functions
	loadmodule:	fn(modname: string): ref Value;

	# Parse module signature from .m file
	parsemodule:	fn(modpath: string): ref ModSignature;

	# Function proxy generation
	# Create Lua-callable wrapper for Limbo function
	genproxy:	fn(mod: ref LoadedModule, sig: ref FuncSig): ref Value;

	# Cache management
	# Clear module cache
	clearcache:	fn();

	# Get information about implementation
	about:		fn(): array of string;

	# Type descriptor ADTs (for internal use)
	# These are exposed for advanced use cases

	# Type descriptor
	Type: adt {
		pick {
		Basic =>
			name: string;  # int, real, string, byte, etc.
		Array =>
			elem: ref Type;
			len: int;  # 0 for dynamic
		List =>
			elem: ref Type;
		Ref =>
			target: string;  # ADT or module name
		Function =>
			params: list of ref Param;
			returns: ref Type;
		};
	};

	# Function parameter
	Param: adt {
		name: string;
		typ: ref Type;
	};

	# Function signature
	FuncSig: adt {
		name: string;
		params: list of ref Param;
		returns: list of ref Type;
	};

	# ADT signature
	ADTSig: adt {
		name: string;
		fields: list of ref ADTField;
	};

	# ADT field
	ADTField: adt {
		name: string;
		typ: ref Type;
	};

	# Constant signature
	ConstSig: adt {
		name: string;
		typ: ref Type;
		value: string;
	};

	# Complete module signature
	ModSignature: adt {
		modname: string;
		functions: list of ref FuncSig;
		adts: list of ref ADTSig;
		constants: list of ref ConstSig;
	};

	# Loaded module reference
	LoadedModule: adt {
		name: string;
		dispath: string;
		modpath: string;
		sig: ref ModSignature;
		linktab: array of ref Link;  # Loader link table
		initialized: int;
	};

	# Loader link entry (from loader.m)
	Link: adt {
		name: string;
		sig: int;
		pc: int;
		tdesc: int;
	};

	# Value wrapper (generic Limbo value)
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
			v: array of ref Value;
		List =>
			v: list of ref Value;
		Ref =>
			v: ref void;  # Pointer/reference
		Function =>
			v: fn(...: ref Value): ref Value;
		};
	};
};
