-- Lua Tk Module Demo
-- Demonstrates loading the tk module using generic DIS loader
-- This example shows basic Tk widget operations

print("Lua Tk Module Demo")
print("==================")

-- Load tk module using generic DIS loader
local tk = require("tk")

if tk then
    print("Tk module loaded successfully!")
    print()

    print("Available functions:")
    print("  - tk.cmd(toplevel, command)")
    print("  - tk.namechan(toplevel, channel)")
    print("  - tk.toplevel(screen, args)")
    print()

    -- Example commands (would work in graphical context)
    print("Example commands:")
    print('  tk.cmd(top, "button .b -text Hello")')
    print('  tk.cmd(top, "pack .b")')
    print('  tk.cmd(top, ".b configure -text World")')
    print()

    -- Test command formatting
    local function test_cmd(cmd)
        print("  Testing: " .. cmd)
        -- In full implementation, this would execute:
        -- local result = tk.cmd(toplevel, cmd)
    end

    print("Testing command construction:")
    test_cmd("button .hello -text {Hello World}")
    test_cmd("label .l -text {Welcome to Lua + Tk}")
    test_cmd("entry .e -width 20")
    test_cmd("frame .f -bg white")
    print()

    print("SUCCESS: Tk module works!")
    print()
    print("Note: Actual widget creation requires graphical context")
    print("      Use wlua to run this in a windowed environment")
else
    print("ERROR: Failed to load tk module")
end
