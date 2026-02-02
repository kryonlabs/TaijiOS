# Lua DIS Module Loading System - Build Guide

## Build Status

✅ **Implementation Complete** - All components written
⚠️ **Testing Required** - Needs compilation and runtime testing

## Building the Components

### Prerequisites

```sh
# Ensure TaijiOS build environment is set up
cd /mnt/storage/Projects/TaijiOS
```

### Build Steps

#### 1. Build the Core Libraries

```sh
# Build type marshaling
limbo -I/module -I. lua/lib/lua_marshal.b

# Build module parser
limbo -I/module -I. lua/lib/lua_modparse.b

# Build DIS loader
limbo -I/module -I. lua/lib/lua_disloader_new.b

# Build function proxy
limbo -I/module -I. lua/lib/lua_proxy.b

# Build Limbo module interface
limbo -I/module -I. lua/module/limbo.m
```

#### 2. Build Test Suite

```sh
# Build marshaling tests
limbo -I/module -I. lua/test/test_marshal.b

# Build parser tests
limbo -I/module -I. lua/test/test_modparse.b
```

#### 3. Rebuild Package Library

```sh
# Build updated package library
limbo -I/module -I. lua/lib/lua_package.b
```

#### 4. Rebuild wlua

```sh
# Build updated wlua (no hardcoded libs)
limbo -I/module -I. appl/wm/wlua.b
```

### Building All at Once

```sh
cd /mnt/storage/Projects/TaijiOS

# Build all new components
for f in lua/lib/lua_*.b lua/test/*.b lua/module/*.m; do
    echo "Building $f..."
    limbo -I/module -I. "$f"
done
```

## Running Tests

### Run Marshaling Tests

```sh
# Compile test
limbo -I/module lua/test/test_marshal.b > /dis/test_marshal.dis

# Run test
/test_marshal
```

### Run Parser Tests

```sh
# Compile test
limbo -I/module lua/test/test_modparse.b > /dis/test_modparse.dis

# Run test
/test_modparse
```

### Run Examples

```sh
# Math demo (no graphics required)
lua lua/examples/math-demo.lua

# Draw demo (requires graphics context)
wlua lua/examples/draw-demo.lua

# Tk demo (requires window system)
wlua lua/examples/tk-demo.lua
```

## Integration with Existing Build

### Update mkfile

Add to main mkfile:

```limbo
MODULES=\
	lua/lib/lua_marshal\
	lua/lib/lua_modparse\
	lua/lib/lua_disloader_new\
	lua/lib/lua_proxy\
	lua/module/limbo\

TESTS=\
	lua/test/test_marshal\
	lua/test/test_modparse\

MODULE=${MODULES:%=$O.%}
TEST=${TESTS:%=$O.%}

all:V:	$MODULE $TEST

$O.lua_marshal.dis:	lua/lib/lua_marshal.b
	limbo -I/module -I. $prereq > $target

$O.lua_modparse.dis:	lua/lib/lua_modparse.b
	limbo -I/module -I. $prereq > $target

$O.lua_disloader_new.dis:	lua/lib/lua_disloader_new.b
	limbo -I/module -I. $prereq > $target

$O.lua_proxy.dis:	lua/lib/lua_proxy.b
	limbo -I/module -I. $prereq > $target

$O.limbo.dis:	lua/module/limbo.m
	limbo -I/module $prereq > $target
```

## Known Issues

### 1. Missing Imports

Some modules may need additional includes:

```limbo
# Add to files that need them
include "loader.m";
include "lua_marshal.m";
include "lua_modparse.m";
```

### 2. Module Dependencies

Build order matters:
1. Build `lua_marshal.b` first (no dependencies)
2. Build `lua_modparse.b` (no dependencies)
3. Build `lua_disloader_new.b` (depends on marshal, modparse)
4. Build `lua_proxy.b` (depends on marshal, modparse)
5. Build `lua_package.b` (updated, uses above)

### 3. Type Conversion Issues

If you see "type mismatch" errors:
- Check that Value adt matches luavm.m
- Verify Type enum values are correct
- Ensure function signatures match

## Debugging

### Enable Debug Output

Add to modules:

```limbo
DEBUG: con 0;  # Set to 1 for debug output

if(DEBUG) {
    fprint(sys->fildes(2), "Debug: loading module %s\n", modname);
}
```

### Trace Execution

```sh
# Run with tracing
limbo -t lua/lib/lua_marshal.b

# Check generated DIS
limbo -S lua/lib/lua_marshal.b  # Output assembly
```

### Common Errors

**"cannot load module"**
- Check file paths in finddisfile()
- Verify .dis files exist in search paths

**"parse error"**
- Check .m file syntax
- Verify tokenizer handles all cases

**"type mismatch"**
- Check type signatures match
- Verify Lua value types

## Testing Checklist

- [ ] Type marshaling tests pass
- [ ] Module parser tests pass
- [ ] Can load math module
- [ ] Can load draw module (with graphics)
- [ ] Can load tk module (with window system)
- [ ] Module caching works
- [ ] Type conversions work correctly
- [ ] No memory leaks

## Next Steps

1. **Fix Compilation Errors**: Address any build issues
2. **Complete DIS Parsing**: Implement full DIS binary reader
3. **Implement Function Calling**: Make proxy generation work
4. **Integration Testing**: Test with real modules
5. **Performance Testing**: Measure overhead
6. **Documentation**: Update with real-world usage

## Maintenance

### Updating Components

When modifying:
1. Update .b file
2. Rebuild: `limbo -I/module file.b`
3. Test: Run relevant test
4. Commit: Document changes

### Adding New Modules

1. Create module .m file
2. Implement in .b file
3. Add to build system
4. Write tests
5. Document in examples

## Support

For issues or questions:
- Check /lua/doc/*.md for documentation
- Review test files for examples
- Examine .m files for signatures
- Use debug output to trace execution
