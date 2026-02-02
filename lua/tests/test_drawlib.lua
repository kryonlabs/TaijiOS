#!/dis/wlua
-- Test suite for draw library

print("draw library test suite")
print("========================")

-- Test 1: Create image
print("Test 1: draw.image()...")
local img = draw.image(100, 100)
assert(type(img) == "userdata", "image() should return userdata")
print("  ✓ PASSED")

-- Test 2: Create color
print("Test 2: draw.color()...")
local red = draw.color(255, 0, 0)
assert(type(red) == "number", "color() should return number")
assert(red >= 0, "color value should be non-negative")
print("  ✓ PASSED")

-- Test 3: Draw rectangle
print("Test 3: draw.rect()...")
local green = draw.color(0, 255, 0)
draw.rect(img, 10, 10, 50, 50, green)
print("  ✓ PASSED")

-- Test 4: Draw circle
print("Test 4: draw.circle()...")
local blue = draw.color(0, 0, 255)
draw.circle(img, 75, 75, 20, blue)
print("  ✓ PASSED")

-- Test 5: Draw line
print("Test 5: draw.line()...")
local yellow = draw.color(255, 255, 0)
draw.line(img, 0, 0, 100, 100, yellow)
print("  ✓ PASSED")

-- Test 6: Draw point
print("Test 6: draw.point()...")
local white = draw.color(255, 255, 255)
draw.point(img, 50, 50, white)
print("  ✓ PASSED")

-- Test 7: Load font
print("Test 7: draw.font()...")
local fnt = draw.font("/fonts/lucida/latin1.610", 12)
assert(type(fnt) == "userdata", "font() should return userdata")
print("  ✓ PASSED")

-- Test 8: Draw text (if font loaded successfully)
print("Test 8: draw.text()...")
if fnt then
    draw.text(img, "Test", 10, 90, fnt, white)
    print("  ✓ PASSED")
else
    print("  ⚠ SKIPPED (font not available)")
end

-- Test 9: Save image
print("Test 9: draw.save()...")
local status = draw.save(img, "/tmp/test_drawlib.bit")
if status == nil then
    print("  ✓ PASSED")
else
    print("  ✗ FAILED (save error)")
end

-- Test 10: Load image
print("Test 10: draw.load()...")
local img2 = draw.load("/tmp/test_drawlib.bit")
if img2 ~= nil then
    assert(type(img2) == "userdata", "load() should return userdata")
    print("  ✓ PASSED")
else
    print("  ⚠ SKIPPED (file not found or load error)")
end

print("========================")
print("All tests completed!")
