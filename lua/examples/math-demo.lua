-- Lua Math Module Demo
-- Demonstrates loading the math module using generic DIS loader

print("Lua Math Module Demo")
print("====================")

-- Load math module using generic DIS loader
local math = require("math")

if math then
    print("Math module loaded successfully!")
    print()

    -- Test basic math functions
    print("Basic functions:")
    print("  math.sin(0) =", math.sin(0))
    print("  math.cos(0) =", math.cos(0))
    print("  math.tan(0) =", math.tan(0))
    print()

    print("  math.sqrt(16) =", math.sqrt(16))
    print("  math.abs(-42) =", math.abs(-42))
    print("  math.floor(3.7) =", math.floor(3.7))
    print("  math.ceil(3.2) =", math.ceil(3.2))
    print()

    -- Test constants
    print("Constants:")
    print("  math.Pi =", math.Pi)
    print("  math.Infinity =", math.Infinity)
    print()

    -- Test trigonometry
    print("Trigonometry:")
    print("  math.sin(math.Pi / 2) =", math.sin(math.Pi / 2))
    print("  math.cos(math.Pi) =", math.cos(math.Pi))
    print("  math.atan2(1, 1) =", math.atan2(1, 1))
    print()

    print("SUCCESS: All math functions work!")
else
    print("ERROR: Failed to load math module")
end
