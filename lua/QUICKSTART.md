# Lua VM Quick Start Guide

## Building the Current Implementation

The Lua VM implementation is in early stages. Currently, only Phase 1 (Foundation) and Phase 2 (Tables) are complete.

### Prerequisites

- Inferno/Limbo environment (TaijiOS)
- mk build system
- Access to /mnt/storage/Projects/TaijiOS

### Build Steps

```sh
cd /mnt/storage/Projects/TaijiOS/lua/vm
mk
mk install
```

This will build the basic type system and table implementation modules.

## Using the Lua VM API

### Basic Example

```limbo
implement Testlua;

include "sys.m";
include "luavm.m";

sys: Sys;
luavm: Luavm;

init(nil: ref Draw->Context, nil: list of string)
{
	sys = load Sys Sys;
	luavm = load Luavm Luavm->PATH;

	# Initialize Lua VM
	err := luavm->init();
	if(err != nil) {
		sys->fprint(sys->fildes(2), "Error: %s\n", err);
		return;
	}

	# Create a new Lua state
	L := luavm->newstate();

	# Push some values
	luavm->pushnil(L);
	luavm->pushboolean(L, 1);
	luavm->pushnumber(L, 42.0);
	luavm->pushstring(L, "Hello, Lua!");

	# Check stack depth
	sys->print("Stack depth: %d\n", luavm->gettop(L));

	# Create and use a table
	luavm->newtable(L);
	luavm->pushstring(L, "Lua");
	luavm->setfield(L, -2, "language");
	luavm->pushnumber(L, 5.4);
	luavm->setfield(L, -2, "version");

	# Clean up
	luavm->close(L);
}
```

## Available API Functions (Currently Implemented)

### State Management
- `newstate(): ref State` - Create new Lua state
- `close(L: ref State)` - Close Lua state
- `gettop(L: ref State): int` - Get stack depth
- `settop(L: ref State, idx: int)` - Set stack depth
- `pop(L: ref State, n: int)` - Pop n values

### Stack Operations
- `pushvalue(L: ref State, v: ref Value)` - Push value
- `pushnil(L: ref State)` - Push nil
- `pushboolean(L: ref State, b: int)` - Push boolean
- `pushnumber(L: ref State, n: real)` - Push number
- `pushstring(L: ref State, s: string)` - Push string
- `getvalue(L: ref State, idx: int): ref Value` - Get value at index

### Table Operations
- `newtable(L: ref State): ref Table` - Create new table
- `createtable(narr, nrec: int): ref Table` - Create table with sizes
- `getfield(L: ref State, idx: int, k: string)` - Get field by string key
- `setfield(L: ref State, idx: int, k: string)` - Set field by string key
- `gettable(L: ref State, idx: int)` - Get table (key at top-1)
- `settable(L: ref State, idx: int)` - Set table (key at top-2, value at top)

### Type Checking
- `typeName(v: ref Value): string` - Get type name
- `isnil/isboolean/isnumber/isstring/istable/isfunction/isuserdata/isthread`
- `toboolean/tonumber/tostring`

### String Operations
- `strhash(s: string): int` - Hash string
- `internstring(s: string): ref TString` - Intern string
- `objlen(v: ref Value): int` - Get string length

## What's Missing

The following are NOT YET implemented but are planned:

- ❌ Parser and lexer (cannot execute Lua code yet)
- ❌ Virtual machine executor
- ❌ Function calls
- ❌ Coroutines
- ❌ Full garbage collection
- ❌ Standard library functions
- ❌ File I/O
- ❌ loadstring() and loadfile() - return placeholder errors

## Testing the Implementation

### Manual Testing

You can test basic operations manually:

```limbo
# Test value types
L := luavm->newstate();
luavm->pushnumber(L, 123.45);
v := luavm->getvalue(L, -1);
sys->print("Type: %s, Value: %s\n", luavm->typeName(v), luavm->tostring(v));

# Test table operations
luavm->newtable(L);
luavm->pushstring(L, "test");
luavm->setfield(L, -2, "key");
luavm->getfield(L, -1, "key");  # Pushes "test"
result := luavm->getvalue(L, -1);
sys->print("Got: %s\n", luavm->tostring(result));

luavm->close(L);
```

## Development Roadmap

### ✅ Phase 1: Foundation (COMPLETE)
- Value type system
- String interning
- State management
- Object allocation

### ✅ Phase 2: Tables (COMPLETE)
- Hybrid array+hash tables
- Metatables
- Iteration support

### 🚧 Phase 3: VM Core (NEXT)
- Implement Lua opcodes
- Build parser and lexer
- Create bytecode generator
- Write VM executor loop

### Future Phases
- Functions and closures
- Coroutines
- Garbage collection
- Standard libraries
- Inferno integration
- Kryon integration

## Contributing

When adding new functionality:

1. Follow Limbo coding conventions
2. Update the module interface (`module/luavm.m`)
3. Add to appropriate `.b` file or create new one
4. Update `lua/vm/mkfile` if adding new files
5. Test manually (automated tests coming later)
6. Update this README

## Debugging

To debug issues:

1. Check return values from `init()` and other functions
2. Use `typeName()` to verify value types
3. Check stack depth with `gettop()`
4. Enable debug output in implementation if needed

## Resources

- Main README: `/mnt/storage/Projects/TaijiOS/lua/README.md`
- Module interface: `/mnt/storage/Projects/TaijiOS/module/luavm.m`
- Implementation files: `/mnt/storage/Projects/TaijiOS/lua/vm/*.b`
- Lua 5.4 manual: https://www.lua.org/manual/5.4/

## Known Limitations

1. Cannot execute Lua code yet (parser/VM not implemented)
2. No standard library functions
3. Garbage collection is incomplete
4. No coroutines
5. No file I/O
6. No module loading

These will be implemented in future phases following the implementation plan.
