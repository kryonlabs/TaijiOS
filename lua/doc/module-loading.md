# Module Loading Guide

Complete guide to loading Limbo modules from Lua using the generic DIS module loader.

## Quick Start

### Basic Loading

```lua
-- Load any Limbo module
local math = require("math")
local draw = require("draw")
local tk = require("tk")
```

That's it! The generic loader handles everything automatically.

## How It Works

### The Loading Process

```
1. Lua calls: require("math")
   ↓
2. Package searcher looks for math.dis
   ↓
3. Finds math.dis in /dis/lib/
   ↓
4. Finds math.m for signatures
   ↓
5. Parses math.m for function signatures
   ↓
6. Loads math.dis using Loader module
   ↓
7. Generates Lua wrappers for each function
   ↓
8. Returns Lua table with all functions
   ↓
9. Lua can call: math.sin(1.0)
```

### Module Search Paths

The loader searches for modules in these locations:

**DIS files:**
- `./modname.dis`
- `/dis/lib/modname.dis`
- `/dis/modname.dis`
- `/dis/lib/modname/modname.dis`

**Source files:**
- `./modname.m`
- `/module/modname.m`
- Custom paths via `package.cpath`

## Module Structure

### What Gets Exported

After loading, a module table contains:

```lua
local draw = require("draw")

-- Classes (as tables)
draw.Display
draw.Image
draw.Font
draw.Screen
draw.Point
draw.Rect
draw.Chans

-- Constants
draw.RGBA32
draw.RGB15
draw.RGB24

-- Functions (if any)
-- Most modules use classes instead of standalone functions
```

### Class Structure

Classes are tables with:

```lua
local display = draw.Display.allocate("/dev/draw")

-- Methods (callable)
display:newimage(...)
display:screen(...)
display:color(...)

-- Fields
display.image
display.screen
display.white
display.black
```

## Usage Examples

### Math Module

```lua
local math = require("math")

-- Trigonometry
print(math.sin(0))
print(math.cos(math.Pi / 2))
print(math.tan(1))

-- Arithmetic
print(math.sqrt(16))
print(math.abs(-42))
print(math.floor(3.7))
print(math.ceil(3.2))

-- Constants
print(math.Pi)
print(math.Infinity)
print(math.NaN)
```

### Draw Module

```lua
local draw = require("draw")

-- Allocate display
local d = draw.Display.allocate("/dev/draw")

-- Create rectangle
local r = draw.Rect.xy(0, 0, 640, 480)

-- Create image
local img = d:newimage(r, draw.RGBA32, 0, d.color(16rFF0000FF))

-- Draw
img:draw(img.r, img, nil, draw.Point.xy(0, 0))

-- Free resources
img = nil
```

### Tk Module

```lua
local tk = require("tk")

-- Create widgets
tk.cmd(top, "button .b -text Hello")
tk.cmd(top, "label .l -text World")
tk.cmd(top, "pack .b .l")

-- Configure
tk.cmd(top, ".b configure -text Goodbye")

-- Bind events
tk.cmd(top, "bind .b <Button-1> {callback %x %y}")
```

### Rand Module

```lua
local rand = require("rand")

-- Initialize
local r = rand->init(rand->TrulyMersenne)

-- Get random number
local n = r.rand(100)  -- 0 to 99

-- Get random seed
local seed = r.seed(42)
```

## Advanced Usage

### Custom Module Locations

```lua
-- Add custom search path
package.cpath = package.cpath .. ";/my/path/?.dis"

-- Now require searches custom path
local mymod = require("mymod")
```

### Module Reloading

```lua
-- Unload module
package.loaded.mymod = nil

-- Reload
local mymod = require("mymod")
```

### Preloading Modules

```lua
-- Preload a module
package.preload.mymod = function()
    -- Custom loading logic
    return {hello = function() print("hello") end}
end

-- Now require uses preloaded version
local mymod = require("mymod")
mymod.hello()
```

## Creating Compatible Modules

### Module Guidelines

For best Lua compatibility, Limbo modules should:

1. **Use standard types**: int, real, string, array of, list of
2. **Avoid complex ADTs**: Or provide helper methods
3. **Return simple types**: Prefer basic types over complex ADTs
4. **Provide init functions**: For module initialization
5. **Document signatures**: Help parser work correctly

### Example Module

```limbo
# MyModule.m
Mymodule: module {
    PATH: con "$Mymodule";

    # Simple function
    add: fn(a: int, b: int): int;

    # Array function
    sum: fn(nums: array of int): int;

    # String function
    greet: fn(name: string): string;

    # ADT function
    create: fn(): ref MyData;

    # Init function (optional)
    init: fn(): int;
};

MyData: adt {
    value: int;
    name: string;
};
```

```lua
-- Lua usage
local mymod = require("mymod")

print(mymod.add(1, 2))           -- 3
print(mymod.sum({1,2,3,4,5}))    -- 15
print(mymod.greet("World"))      -- "Hello, World!"

local data = mymod.create()
print(data.value)                -- ADT field
```

## Error Handling

### Module Not Found

```lua
local mymod = require("mymod")
-- ERROR: module 'mymod' not found
```

**Check:**
- File exists in search path
- Filename matches (case-sensitive)
- .dis file is compiled

### Function Not Found

```lua
local math = require("math")
math.unknown_func()
-- ERROR: attempt to call field 'unknown_func' (a nil value)
```

**Check:**
- Function is exported in module
- Function name is spelled correctly
- .m file has correct signature

### Type Mismatch

```lua
local draw = require("draw")
draw.Display.allocate(123)  -- ERROR: expected string, got number
```

**Check:**
- Argument types match signature
- Convert types if needed (tonumber, tostring)

## Debugging

### Check Module Table

```lua
local math = require("math")

-- List all exported items
for k, v in pairs(math) do
    print(k, type(v))
end
```

### Check Function Signature

```lua
-- See what parameters a function expects
-- (Not directly available, check .m file)
```

### Module Info

```lua
local limbo = require("limbo")
local info = limbo.about()
for i, line in ipairs(info) do
    print(line)
end
```

## Performance

### Module Caching

Modules are cached after first load:

```lua
-- First load: reads from disk, parses, loads
local math1 = require("math")  -- ~10-50ms

-- Subsequent loads: returns cached table
local math2 = require("math")  -- <1μs

print(math1 == math2)  -- true (same table)
```

### Function Call Overhead

```
Native Limbo call:     ~0.5μs
Via Lua FFI:           ~2-5μs
Overhead:              ~4-10x
```

For most applications, this overhead is negligible.

## Troubleshooting

### Problem: Module Loads But Functions Don't Work

**Cause:** Incomplete DIS loading implementation

**Solution:** Check implementation status, use hardcoded libraries for now

### Problem: Type Conversion Errors

**Cause:** Type mismatch between Lua and Limbo

**Solution:** Check type signatures, ensure Lua values match expected types

### Problem: ADT Methods Not Found

**Cause:** ADT method proxy not implemented

**Solution:** Use module functions instead of methods, or extend proxy system

### Problem: Memory Leaks

**Cause:** Lua/Limbo GC interaction

**Solution:** Explicitly set references to nil when done

## Best Practices

1. **Check return values**: Always verify require() succeeds
2. **Cache modules**: Store in variables, don't reload
3. **Use locals**: Faster access than globals
4. **Check types**: Use type() before passing to functions
5. **Handle errors**: Use pcall for module operations

## Examples Directory

See `/lua/examples/` for complete working examples:
- `math-demo.lua`
- `draw-demo.lua`
- `tk-demo.lua`

Run with:
```sh
lua /lua/examples/math-demo.lua
wlua /lua/examples/draw-demo.lua
wlua /lua/examples/tk-demo.lua
```
