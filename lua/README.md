# Lua VM Implementation for TaijiOS/Limbo

## Overview

This is a complete Lua 5.4 compatible VM implementation for Inferno/Limbo in the TaijiOS project. The implementation follows the pattern established by ECMAScript and TCL implementations in the codebase.

## Current Implementation Status

### ✅ Phase 1: Foundation (COMPLETE)

**Files Implemented:**
- `lua/vm/lua_types.b` - Value type system (TValue ADT)
- `lua/vm/lua_string.b` - String interning and string operations
- `lua/vm/lua_state.b` - Lua state management
- `lua/vm/lua_object.b` - Object allocation and GC foundation

**Features:**
- Complete value type system with all Lua 5.4 types
- Tagged union implementation (NIL, BOOLEAN, NUMBER, STRING, TABLE, FUNCTION, USERDATA, THREAD)
- String interning with hash table for efficient storage
- String operations: concat, compare, substring, upper/lower, reverse, repeat, strip, find, split
- Lua state with stack management (push/pop operations)
- Absolute and negative stack indexing
- Error handling infrastructure
- GC object model with mark-and-sweep foundation

### ✅ Phase 2: Table Implementation (COMPLETE)

**Files Implemented:**
- `lua/vm/lua_table.b` - Hybrid array+hash table
- `lua/vm/lua_hash.b` - Hash utilities with collision resolution

**Features:**
- Hybrid array+hash table implementation
- Automatic array part growth
- Integer key optimization
- Metamethod support (__index, __newindex)
- Table iteration (next for pairs/ipairs)
- Table length operator (#)
- Raw get/set operations
- Table operations: insert, remove, sort, pack, unpack
- External chaining hash table
- Dynamic resizing (power-of-2 sizes)
- Weak table support infrastructure

### 🚧 Phase 3: Virtual Machine Core (PENDING)

**To Implement:**
- `lua/vm/lua_vm.b` - Main VM executor
- `lua/vm/lua_opcodes.b` - Opcode definitions
- `lua/vm/lua_parser.b` - Lua source parser
- `lua/vm/lua_lexer.b` - Lexer
- `lua/vm/lua_code.b` - Bytecode generator
- `lua/vm/lua_debug.b` - Debug interface

**Features:**
- All 38 Lua 5.4 opcodes
- Instruction encoding (iABC, iABx, iAsBx, iAx)
- Recursive descent parser
- AST generation
- Bytecode generation
- Register allocation
- Upvalue detection

### 🚧 Phase 4: Functions, Closures & Upvalues (PENDING)

**To Implement:**
- `lua/vm/lua_func.b` - Closures and upvalues
- `lua/vm/lua_upval.b` - Upvalue management

**Features:**
- LClosure and CClosure types
- Open and closed upvalues
- Upvalue chaining
- Call protocol
- Tail call optimization

### 🚧 Phase 5: Coroutines (PENDING)

**To Implement:**
- `lua/vm/lua_coro.b` - Coroutine implementation
- `lua/vm/lua_thread.b` - Thread states

**Features:**
- Thread status tracking
- Resume/yield operations
- Separate stacks per coroutine

### 🚧 Phase 6: Garbage Collector (PENDING)

**To Implement:**
- `lua/vm/lua_gc.b` - Full GC implementation
- `lua/vm/lua_mem.b` - Memory allocation

**Features:**
- Incremental GC
- Generational GC (Lua 5.4)
- Write barriers
- Weak table clearing
- Finalization (__gc metamethod)

### 🚧 Phase 7: Standard Library (PENDING)

**To Implement:**
- `lua/lib/lua_baselib.b` - Basic functions
- `lua/lib/lua_strlib.b` - String library
- `lua/lib/lua_tablib.b` - Table library
- `lua/lib/lua_mathlib.b` - Math library
- `lua/lib/lua_iolib.b` - I/O library (Inferno-adapted)
- `lua/lib/lua_oslib.b` - OS library (Inferno-adapted)
- `lua/lib/lua_package.b` - Module system
- `lua/lib/lua_debug.b` - Debug library
- `lua/lib/lua_utf8.b` - UTF-8 library
- `lua/lib/lua_corolib.b` - Coroutine library

### 🚧 Phase 8: Inferno/Limbo Integration (PENDING)

**To Implement:**
- `lua/inferno/lua_inferno.b` - Main integration
- `lua/inferno/lua_fileio.b` - File I/O bridge
- `lua/inferno/lua_process.b` - Process bridge
- `lua/inferno/lua_syscalls.b` - System call bridge
- `lua/inferno/lua_disloader.b` - .dis module loader

### 🚧 Phase 9: Lua Shell & Wish Equivalent (PENDING)

**To Implement:**
- `appl/cmd/lua.b` - Lua REPL shell
- `appl/wm/wlua.b` - Windowing shell

### 🚧 Phase 10: Kryon Integration (PENDING)

**To Implement:**
- Kryon language plugin for Lua
- KRB → Lua compilation
- Lua event handlers in KRB files

### 🚧 Phase 11: Testing & Documentation (PENDING)

**To Implement:**
- Comprehensive test suite
- Performance benchmarks
- API documentation
- Tutorial

## Directory Structure

```
/mnt/storage/Projects/TaijiOS/lua/
├── vm/                    # Core Lua VM implementation ✅
│   ├── lua_types.b        # Value type system ✅
│   ├── lua_string.b       # String interning ✅
│   ├── lua_state.b        # State management ✅
│   ├── lua_object.b       # Object allocation ✅
│   ├── lua_table.b        # Table implementation ✅
│   ├── lua_hash.b         # Hash utilities ✅
│   ├── mkfile            # Build file ✅
│   ├── lua_vm.b          # VM executor (TODO)
│   ├── lua_opcodes.b     # Opcodes (TODO)
│   ├── lua_parser.b      # Parser (TODO)
│   ├── lua_lexer.b       # Lexer (TODO)
│   ├── lua_code.b        # Code generator (TODO)
│   ├── lua_debug.b       # Debug interface (TODO)
│   ├── lua_func.b        # Functions (TODO)
│   ├── lua_upval.b       # Upvalues (TODO)
│   ├── lua_coro.b        # Coroutines (TODO)
│   ├── lua_thread.b      # Threads (TODO)
│   ├── lua_gc.b          # GC (TODO)
│   └── lua_mem.b         # Memory (TODO)
├── lib/                   # Standard library modules (TODO)
├── inferno/              # Inferno/Limbo integration (TODO)
├── include/              # Public headers (TODO)
├── docs/                 # Documentation (TODO)
├── tests/                # Test files (TODO)
└── README.md             # This file
```

## Module Interface

The main module interface is defined in `/mnt/storage/Projects/TaijiOS/module/luavm.m`:

```limbo
Luavm : module {
    PATH: con "/dis/lib/luavm.dis";

    # Type constants
    TNIL, TBOOLEAN, TNUMBER, TSTRING, TTABLE, TFUNCTION, TUSERDATA, TTHREAD: con iota;

    # Status codes
    OK, YIELD, ERRRUN, ERRSYNTAX, ERRMEM, ERRERR, ERRFILE: con iota;

    # Core ADTs
    Value: adt { ... };
    Table: adt { ... };
    Function: adt { ... };
    State: adt { ... };

    # API functions
    init: fn(): string;
    newstate: fn(): ref State;
    close: fn(L: ref State);
    loadstring: fn(L: ref State, s: string): int;
    # ... and many more
};
```

## Building

Currently, Phase 1 and Phase 2 components can be built:

```sh
cd /mnt/storage/Projects/TaijiOS/lua/vm
mk
mk install
```

This will compile the basic type system and table implementation.

## Usage Example

```limbo
implement Myprogram;

include "sys.m";
include "luavm.m";

sys: Sys;
Luavm: Luavm;

init(nil: ref Draw->Context, nil: list of string)
{
	sys = load Sys Sys;
	Luavm = load Luavm Luavm->PATH;

	err := Luavm->init();
	if(err != nil) {
		sys->fprint(sys->fildes(2), "Lua init error: %s\n", err);
		return;
	}

	# Create Lua state
	L := Luavm->newstate();

	# Create and manipulate a table
	t := Luavm->newtable(L);
	Luavm->setfield(L, -1, "hello");
	Luavm->pushstring(L, "world");
	Luavm->settable(L, -2);

	# Clean up
	Luavm->close(L);
}
```

## Architecture Decisions

### Type System
- Tagged union for Value representation (similar to Lua C implementation)
- Direct value storage for small types (nil, bool, number)
- Reference storage for complex types (table, function, userdata, thread)

### Table Implementation
- Hybrid array+hash design matching Lua 5.4
- Array part: contiguous integers 1..n for efficiency
- Hash part: external chaining for collision resolution
- Automatic rebalancing between array and hash parts
- Integer key optimization

### String Interning
- Global string table with hash-based lookup
- Automatic deduplication
- Cached hash values for performance

### Memory Management
- GC object header with mark bits
- Incremental mark-and-sweep (foundation laid)
- Finalization support planned

## Compatibility

Targeting Lua 5.4 compatibility with deviations where necessary for Limbo:
- Full Lua 5.4 semantics where possible
- Adapted I/O for Inferno file system
- Adapted OS operations for Inferno system calls
- .dis file loading for modules

## Next Steps

1. **Complete Phase 3**: Implement virtual machine core
   - Opcode definitions and encoding
   - Parser and lexer
   - Bytecode generator
   - VM executor loop

2. **Add Tests**: Unit tests for completed phases
   - Type system tests
   - Table operation tests
   - String operation tests

3. **Continue Implementation**: Follow the plan for phases 4-11

## References

- [Lua 5.4 Source Code](https://www.lua.org/source/5.4/)
- [Lua 5.4 Reference Manual](https://www.lua.org/manual/5.4/)
- [The Implementation of Lua 5.0](https://www.lua.org/doc/jucs05.pdf)
- [ECMAScript Implementation in TaijiOS](/mnt/storage/Projects/TaijiOS/appl/lib/ecmascript/)
- [Inferno/Limbo Documentation](https://infernos-tos.com/)

## Contributing

This is part of the TaijiOS project. Please follow the project's coding standards and submit changes via the project's contribution process.

## License

Same license as TaijiOS project.

---

**Status**: Phase 1 ✅ COMPLETE | Phase 2 ✅ COMPLETE | Phase 3-11 🚧 IN PROGRESS

**Last Updated**: 2025-02-01
