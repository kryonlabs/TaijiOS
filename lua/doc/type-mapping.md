# Type Mapping Reference

Complete reference for type conversions between Lua and Limbo.

## Basic Types

### nil

```
Lua: nil
Limbo: nil
```

Direct mapping, no conversion needed.

### boolean

```
Lua: boolean
Limbo: int (0 or 1)
```

**Lua → Limbo:**
```lua
local flag = true   -- Limbo receives 1
local flag = false  -- Limbo receives 0
```

**Limbo → Lua:**
```limbo
# Limbo returns 0 or 1
# Lua receives false or true
```

### int

```
Lua: number (integer range)
Limbo: int
```

**Lua → Limbo:**
```lua
local x = 42  -- Valid int
local y = 3.7  -- Truncated to 3
local z = 2.5e9  -- ERROR: Out of range (32-bit signed)
```

**Range:** -2,147,483,648 to 2,147,483,647

### real

```
Lua: number
Limbo: real
```

**Lua → Limbo:**
```lua
local x = 3.14159
local y = 42.0
```

Lossless conversion.

### string

```
Lua: string
Limbo: string
```

**Lua → Limbo:**
```lua
local s = "hello world"
```

UTF-8 compatible.

### byte

```
Lua: number (0-255) or single-character string
Limbo: byte
```

**Lua → Limbo:**
```lua
local b1 = 65  -- ASCII 'A'
local b2 = "A"  -- Also works
```

**Limbo → Lua:**
```lua
-- Returns number 0-255
```

## Collection Types

### array of T

```
Lua: table (integer keys 1..n)
Limbo: array of T
```

**Lua → Limbo:**
```lua
local arr = {1, 2, 3, 4, 5}
-- Limbo receives: array[5] of int
```

**Limitations:**
- Must use consecutive integer keys starting at 1
- Sparse tables become dense arrays
- Mixed types cause errors

### list of T

```
Lua: table (integer keys)
Limbo: list of T
```

**Lua → Limbo:**
```lua
local lst = {"a", "b", "c"}
-- Limbo receives: list of string
```

**Implementation:**
- Internally converted from table to Limbo list
- Nil values terminate the list

## Reference Types

### ADT (Algebraic Data Type)

```
Lua: userdata
Limbo: ref ADT
```

**Lua → Limbo:**
```lua
local display = draw.Display.allocate("/dev/draw")
-- display is userdata wrapping Limbo Display ref
```

**Operations:**
```lua
-- Call ADT methods
local img = display:newimage(...)

-- Access fields (if available)
local rect = img.r
```

### function

```
Lua: function
Limbo: fn(...)
```

**Lua → Limbo:**
```lua
local callback = function(x, y)
    print(x, y)
end
-- Wrapped as Limbo function pointer
```

**Limbo → Lua:**
```lua
-- Limbo function returned
local func = some.module.getfunc()
func(arg1, arg2)  -- Call from Lua
```

## Type Signatures

Type signatures are strings describing Limbo types:

### Basic Signatures

```
"int"       - 32-bit signed integer
"real"      - 64-bit floating point
"string"    - String
"byte"      - 8-bit unsigned
"nil"       - Nil
```

### Complex Signatures

```
"array of int"     - Array of integers
"array of string"  - Array of strings
"list of real"     - List of reals
"list of list of int"  - Nested list
```

### Function Signatures

```
"fn(int, int): int"           - Two ints, returns int
"fn(): list of string"        - No params, returns string list
"fn(array of byte): int"      - Byte array param, returns int
```

## Conversion Functions

### Lua to Limbo

```lua
local limboval = lua2limbo(L, stack_index, type_signature)
```

### Limbo to Lua

```lua
local count = limbo2lua(L, limbo_value, type_signature)
-- Pushes result(s) onto Lua stack
```

## Error Handling

### Type Mismatch

```lua
-- ERROR: Expected number, got string
local result = math.sin("hello")
```

### Range Error

```lua
-- ERROR: Number out of int range
local x = require("module").setvalue(3.0e9)
```

### Array Error

```lua
-- ERROR: Not an array
local result = module.process({x=1, y=2})  -- Not integer-indexed
```

## Examples

### Math Module

```lua
local math = require("math")

-- int
math.abs(-42)      -- Lua number → Limbo int

-- real
math.sin(1.0)      -- Lua number → Limbo real

-- constants
math.Pi            -- Limbo constant → Lua number
```

### Draw Module

```lua
local draw = require("draw")

-- ADT
local d = draw.Display.allocate("/dev/draw")  -- userdata

-- function
d.newimage(rect, chan, repl, color)  -- method call
```

### Custom Module

```lua
local mymod = require("mymod")

-- array parameter
local result = mymod.process({1, 2, 3})  -- table → array of int

-- list parameter
local items = mymod.getitems()  -- returns list of string → table

-- ADT parameter
local obj = mymod.create()  -- returns ref MyADT → userdata
```

## Best Practices

1. **Type matching**: Ensure Lua types match Limbo signatures
2. **Array indexing**: Use consecutive integers starting at 1
3. **Range checking**: Watch int overflow (use real instead)
4. **ADT handling**: Treat ADTs as opaque userdata
5. **Error checking**: Always check return values

## Debugging

### Type Checking

```lua
-- Check Lua type
print(type(value))  -- "number", "string", "table", etc.

-- Check signature
local sig = "array of int"
print(type2string(sig))  -- Parse and validate
```

### Conversion Testing

```lua
-- Test conversion
local val = lua2limbo(L, 1, "int")
if val == nil then
    print("Conversion failed")
end
```

## Performance Tips

1. **Cache conversions**: Avoid repeated conversions
2. **Use fast types**: int/real/string are fastest
3. **Pre-allocate arrays**: Avoid resizing
4. **Reuse tables**: Don't create new tables unnecessarily
