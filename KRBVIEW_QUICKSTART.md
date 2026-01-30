# KRB Viewer Quick Start Guide

## What Was Fixed

**Problem**: The KRB viewer Limbo implementation wasn't working because `krbloader->init()` was never called after loading the module.

**Solution**: Added single line `krbloader->init()` at line 379 in `appl/wm/krbview.b`

## Quick Commands

### 1. Compile the Fixed Limbo Implementation

```bash
./compile_krbview.sh
```

Or manually:
```bash
./Linux/amd64/bin/emu -r . sh -c 'cd /appl/wm && mk krbview.dis krbloader.dis'
```

### 2. Run the Viewer

```bash
# Basic usage
./run_krbview.sh kryon/examples/hello-world.krb

# With custom window size
./run_krbview.sh kryon/examples/simple_grid.krb 800 600
```

### 3. Remove C Implementations

```bash
./remove_c_krbview.sh
```

This removes:
- `utils/krbview/` - Standalone C viewer (964 lines)
- `os/port/krbexec.c` - C wrapper (110 lines)
- `kryon/src/renderers/krbview/` - Stub renderer
- Makefile references to krbview renderer

All files are archived before deletion.

## File Locations

### Limbo Implementation (Keep These)
- `appl/wm/krbview.b` - GUI application (494 lines)
- `appl/wm/krbloader.b` - Core module (1414 lines)
- `appl/wm/krbloader.m` - Module interface (239 lines)
- `appl/wm/krbview.dis` - Compiled bytecode
- `appl/wm/krbloader.dis` - Compiled bytecode

### C Implementation (Remove These)
- `utils/krbview/*.c` - Standalone C viewer
- `os/port/krbexec.c` - C wrapper
- `kryon/src/renderers/krbview/*.c` - Stub renderer

## Why Limbo Is Better

✅ **Platform Independent** - Runs on any Inferno-supported platform
✅ **No External Dependencies** - Uses only Inferno standard modules
✅ **Memory Safe** - Automatic garbage collection
✅ **Simpler Build** - No C compilation required
✅ **Better Integration** - Native Tk widgets, proper event handling
✅ **Fully Functional** - All features implemented (1908 lines total)

The C implementation was:
- Incomplete (stub renderer, partial implementation)
- Platform-specific (requires porting)
- More complex to build (C compiler, linking)
- Harder to maintain (manual memory management)

## Next Steps

1. ✅ **Compile**: `./compile_krbview.sh`
2. ✅ **Test**: `./run_krbview.sh kryon/examples/hello-world.krb`
3. ✅ **Remove C code**: `./remove_c_krbview.sh`
4. ✅ **Enjoy pure Limbo implementation!**

## Documentation

- Full details: `KRB_VIEWER_FIX.md`
- Run script: `run_krbview.sh`
- Compile script: `compile_krbview.sh`
- Removal script: `remove_c_krbview.sh`
