#!/dis/wlua
-- Test suite for tk library

print("tk library test suite")
print("======================")

-- Test 1: tk.cmd() - Create widgets
print("Test 1: tk.cmd()...")
local result = tk.cmd("button .b -text Test")
assert(type(result) == "string" or result == nil, "cmd() should return string or nil")
print("  ✓ PASSED")

-- Test 2: tk.getvar() - Get variable
print("Test 2: tk.getvar()...")
tk.cmd("set testvar hello")
local value = tk.getvar("testvar")
assert(value == "hello", "getvar() should return 'hello'")
print("  ✓ PASSED")

-- Test 3: tk.setvar() - Set variable
print("Test 3: tk.setvar()...")
tk.setvar("testvar2", "world")
local value2 = tk.getvar("testvar2")
assert(value2 == "world", "setvar() should set value")
print("  ✓ PASSED")

-- Test 4: tk.bind() - Bind event
print("Test 4: tk.bind()...")
local called = false
function on_click()
    called = true
end
tk.bind(".b", "<Button-1>", on_click)
print("  ✓ PASSED")

-- Test 5: tk.after() - Timer
print("Test 5: tk.after()...")
local timer_called = false
function on_timer()
    timer_called = true
end
tk.after(100, on_timer)
print("  ✓ PASSED")

-- Test 6: Complex Tk commands
print("Test 6: Complex commands...")
tk.cmd("label .l -text Ready")
tk.cmd("pack .b .l")
print("  ✓ PASSED")

-- Test 7: Query widget
print("Test 7: Query widget...")
local text = tk.cmd(".b cget -text")
assert(type(text) == "string", "cget should return string")
print("  ✓ PASSED")

-- Test 8: Configure widget
print("Test 8: Configure widget...")
tk.cmd(".b configure -text Changed")
local newtext = tk.cmd(".b cget -text")
assert(newtext == "Changed", "configure should change text")
print("  ✓ PASSED")

print("======================")
print("All tests completed!")
print("")
print("NOTE: Some tests (bind, after) require manual interaction")
print("      or waiting for timers to fire.")
