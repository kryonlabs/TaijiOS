#!/dis/wlua
-- Integration test for wlua GUI
-- Tests both draw and tk libraries together

print("GUI Integration Test")
print("====================")

-- Verify libraries are loaded
print("Verifying libraries...")
assert(type(draw) == "table", "draw library should be loaded")
assert(type(tk) == "table", "tk library should be loaded")
print("  ✓ Libraries loaded")

-- Create GUI
print("\nCreating GUI widgets...")

-- Create canvas for drawing
tk.cmd("canvas .c -width 400 -height 400 -bg white")
tk.cmd("label .l -text 'Integration Test'")
tk.cmd("button .b -text 'Draw Random' -command on_draw")
tk.cmd("button .q -text Quit -command on_quit")

tk.cmd("pack .l")
tk.cmd("pack .c -fill both -expand 1")
tk.cmd("pack .b .q -side left")

print("  ✓ GUI created")

-- Create image for drawing
print("\nCreating drawing surface...")
local img = draw.image(400, 400)
assert(img ~= nil, "image creation should succeed")
print("  ✓ Image created")

-- Draw initial pattern
print("\nDrawing initial pattern...")
for i = 1, 20 do
    local x = math.random(400)
    local y = math.random(400)
    local r = math.random(30) + 10
    local color = draw.color(
        math.random(256),
        math.random(256),
        math.random(256)
    )
    draw.circle(img, x, y, r, color)
end
print("  ✓ Pattern drawn")

-- Event handlers
function on_draw()
    print("Draw button clicked!")
    -- Draw random circles
    for i = 1, 10 do
        local x = math.random(400)
        local y = math.random(400)
        local r = math.random(20) + 5
        local color = draw.color(
            math.random(256),
            math.random(256),
            math.random(256)
        )
        draw.circle(img, x, y, r, color)
    end
    tk.cmd(".l configure -text 'Drew 10 random circles'")
end

function on_quit()
    print("Quit button clicked!")
    os.exit()
end

-- Bind events
print("\nBinding events...")
tk.bind(".b", "<Button-1>", on_draw)
tk.bind(".q", "<Button-1>", on_quit)
print("  ✓ Events bound")

-- Set up timer for animation
print("\nSetting up timer...")
counter = 0
function tick()
    counter = counter + 1
    if counter <= 10 then
        -- Draw a point at random location
        local x = math.random(400)
        local y = math.random(400)
        local color = draw.color(0, 0, 0)
        draw.point(img, x, y, color)
        tk.cmd(".l configure -text 'Timer tick: " .. counter .. "'")
        tk.after(500, tick)
    else
        tk.cmd(".l configure -text 'Timer complete'")
    end
end

tk.after(1000, tick)
print("  ✓ Timer started")

print("\n====================")
print("Integration test running...")
print("Click 'Draw Random' to draw more circles")
print("Click 'Quit' to exit")
print("Watch the timer update the label")
print("====================")
