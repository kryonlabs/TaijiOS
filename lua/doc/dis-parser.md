# DIS Parser Implementation Guide

## Overview

The DIS parser provides functionality to read and parse Inferno DIS (Dis) binary files, extracting instructions, data, type descriptors, and link tables for use by the Lua module loading system.

## Architecture

```
Application (require("math"))
    ↓
Module Loader (lua_disloader_new.b)
    ↓
DIS Parser Integration (lua_disparser_integration.b)
    ↓
DIS Parser (lua_disparser.b)
    ↓
DIS Module (dis.m) - Format utilities
    ↓
DIS Binary File (.dis)
```

## Components

### 1. DIS Parser Module (`lua_disparser.m`)

Defines data structures for parsed DIS files:

```limbo
DISFile: adt {
    name: string;          # Module name
    srcpath: string;       # Source path
    header: ref DISHeader; # File header
    inst: array of ref DISInst;     # Instructions
    types: array of ref DISType;    # Type descriptors
    data: list of ref DISData;      # Data segment
    links: array of ref DISLink;    # Link table
    imports: array of array of ref DISImport;
    handlers: array of ref DISHandler;
    sign: array of byte;   # Signature
};
```

### 2. DIS Parser Implementation (`lua_disparser.b`)

Core parsing functions:

- `parse(path: string): (ref DISFile, string)` - Parse DIS file
- `validate(file: ref DISFile): int` - Validate parsed file
- `getexports(file: ref DISFile): list of string` - Get exports
- `findlink(file: ref DISFile, name: string): ref DISLink` - Find link entry

### 3. Integration Layer (`lua_disparser_integration.b`)

Connects parser with module loader:

- `parseandload(path: string): ref LoadedModule` - Parse and load
- `dis2loaded(file: ref DISFile): ref LoadedModule` - Convert formats

## Usage

### Basic Parsing

```limbo
implement Myprog;

include "sys.m";
include "luadisparser.m";

sys: Sys;
disparser: Luadisparser;

init()
{
    sys = load Sys Sys;
    disparser = load Luadisparser Luadisparser->PATH;

    # Parse DIS file
    (file, err) := disparser->parse("/dis/lib/math.dis");
    if(file == nil) {
        sys->fprint(sys->fildes(2), "Error: %s\n", err);
        return;
    }

    # Validate
    if(disparser->validate(file) == 0) {
        sys->fprint(sys->fildes(2), "Invalid DIS file\n");
        return;
    }

    # Get exports
    exports := disparser->getexports(file);
    for(; exports != nil; exports = tl exports) {
        sys->print(hd exports + "\n");
    }

    return nil;
}
```

### Getting Link Information

```limbo
# Find specific function
link := disparser->findlink(file, "sin");
if(link != nil) {
    sys->print(sprint("sin at PC %d, sig %d\n", link.pc, link.sig));
}
```

### Entry Point

```limbo
entry := disparser->getentry(file);
sys->print(sprint("Entry point: %d\n", entry));
```

## Integration with Module Loader

The integration layer converts DISFile to LoadedModule:

```limbo
# In lua_disloader_new.b

loadvia(loader: ref Loader; dispath: string): ref LoadedModule
{
    # Use DIS parser
    disparser := load Luadisparser Luadisparser->PATH;

    # Parse DIS file
    (file, err) := disparser->parse(dispath);
    if(file == nil)
        return nil;

    # Convert to LoadedModule
    mod := disparser->dis2loaded(file);

    # Now use mod with Loader module
    ...
}
```

## Error Handling

The parser provides detailed error messages:

```limbo
(file, err) := disparser->parse(path);
if(file == nil) {
    # err contains error message
    sys->fprint(sys->fildes(2), "Parse error: %s\n", err);

    # Can also get last error
    errmsg := disparser->geterrmsg();
    sys->fprint(sys->fildes(2), "Error: %s\n", errmsg);
}
```

## Testing

Run the test suite:

```sh
# Compile test
limbo -I/module lua/test/test_disparser.b

# Run test
/test_disparser
```

Expected output:
```
Running DIS parser tests...
✓ parse(/dis/lib/math.dis)
✓ valid magic
✓ instruction count
✓ has exports
✓ validate good file
✓ reject bad magic
✓ catch size mismatch
✓ find existing link
✓ export count
✓ entry point
✓ XMAGIC is executable
...

Test Results: 12 passed, 0 failed
```

## Performance Considerations

1. **Caching**: Parsed DISFile objects should be cached
2. **Lazy Loading**: Only parse what you need
3. **Memory Management**: Free DISFile when done

## Troubleshooting

### "cannot open file"

- Check file path is correct
- Verify file exists and is readable
- Use full path if needed

### "bad magic number"

- File is corrupted
- File is not a DIS file
- Wrong architecture/endian

### "validation failed"

- Header sizes don't match actual data
- Corrupted DIS file
- Incompatible version

## Future Enhancements

1. **Write Support**: Generate DIS files from ADTs
2. **Optimization**: Optimize loading speed
3. **Compression**: Support compressed DIS files
4. **Debug Info**: Extract and expose debug symbols

## Related Documentation

- `dis-format.md` - Complete format specification
- `/module/dis.m` - DIS module definition
- `/module/loader.m` - Loader module interface
- `BUILD.md` - Build instructions

## Examples

See `/lua/examples/` for:
- DIS inspection tools
- Module loading examples
- Integration tests
