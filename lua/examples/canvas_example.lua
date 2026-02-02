#!/dis/wlua
-- Canvas drawing example
-- Combines Tk widgets with draw operations

print("Canvas Drawing Example")
print("======================")

-- Create GUI
tk.cmd("label .title -text 'Click on canvas to draw!'")
tk.cmd("canvas .c -width 600 -height 400 -bg white")
tk.cmd("button .clear -text 'Clear Canvas' -command on_clear")
tk.cmd("button .save -text 'Save Image' -command on_save")
tk.cmd("button .quit -text Quit -command on_quit")

tk.cmd("pack .title")
tk.cmd("pack .c -fill both -expand 1")
tk.cmd("pack .clear .save .quit -side left")

-- Create off-screen image for drawing
local img = draw.image(600, 400)
local white = draw.color(255, 255, 255)
draw.rect(img, 0, 0, 600, 400, white)

-- Current drawing settings
local current_color = draw.color(0, 0, 0)
local brush_size = 5

-- Color palette
local colors = {
    black = draw.color(0, 0, 0),
    red = draw.color(255, 0, 0),
    green = draw.color(0, 255, 0),
    blue = draw.color(0, 0, 255),
    yellow = draw.color(255, 255, 0),
    cyan = draw.color(0, 255, 255),
    magenta = draw.color(255, 0, 255),
}

local color_names = {"black", "red", "green", "blue", "yellow", "cyan", "magenta"}
local color_index = 1

-- Drawing function
function on_canvas_click(x, y)
    -- Draw a circle at the clicked position
    local cx = tonumber(x)
    local cy = tonumber(y)

    if cx and cy then
        draw.circle(img, cx, cy, brush_size, current_color)

        -- Update canvas (simulated - in real implementation would copy image to canvas)
        tk.cmd(".c create oval " ..
               (cx - brush_size) .. " " .. (cy - brush_size) .. " " ..
               (cx + brush_size) .. " " .. (cy + brush_size) ..
               " -fill " .. color_names[color_index])
    end
end

function on_clear()
    -- Clear the image
    draw.rect(img, 0, 0, 600, 400, white)
    tk.cmd(".c delete all")
    print("Canvas cleared")
end

function on_save()
    -- Save the image
    local filename = "/tmp/canvas_drawing.bit"
    draw.save(img, filename)
    print("Image saved to " .. filename)
    tk.cmd(".title configure -text 'Saved to " .. filename .. "'")
end

function on_quit()
    print("Quitting...")
    os.exit()
end

function change_color()
    color_index = (color_index % #color_names) + 1
    current_color = colors[color_names[color_index]]
    local msg = "Current color: " .. color_names[color_index] .. " (Click to cycle)"
    tk.cmd(".title configure -text '" .. msg .. "'")
    print("Color changed to " .. color_names[color_index])
end

-- Bind events
-- Note: In a full implementation, we'd bind canvas clicks to Lua callbacks
tk.bind(".c", "<Button-1>", on_canvas_click)
tk.bind(".c", "<Button-3>", change_color)

-- Set up timer to animate something
local anim_x = 50
local anim_dir = 1

function animate()
    -- Clear previous ball
    local bg = draw.color(255, 255, 255)
    draw.circle(img, anim_x, 50, 15, bg)

    -- Update position
    anim_x = anim_x + (anim_dir * 10)

    -- Bounce off walls
    if anim_x >= 550 or anim_x <= 50 then
        anim_dir = -anim_dir
    end

    -- Draw new ball
    local red = draw.color(255, 0, 0)
    draw.circle(img, anim_x, 50, 15, red)

    -- Continue animation
    tk.after(100, animate)
end

-- Start animation
tk.after(500, animate)

-- Initial message
tk.cmd(".title configure -text 'Left-click: draw | Right-click: change color'")

print("======================")
print("Canvas example running!")
print("Left-click on canvas to draw")
print("Right-click to change color")
print("Watch the bouncing ball animation!")
