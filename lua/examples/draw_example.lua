#!/dis/wlua
-- Simple drawing example
-- Demonstrates basic drawing operations

print("Simple Drawing Example")
print("======================")

-- Create image
local width = 640
local height = 480
print("Creating " .. width .. "x" .. height .. " image...")
local img = draw.image(width, height)

-- Fill background with white
print("Drawing background...")
local white = draw.color(255, 255, 255)
draw.rect(img, 0, 0, width, height, white)

-- Draw some shapes
print("Drawing shapes...")

-- Red rectangle
local red = draw.color(255, 0, 0)
draw.rect(img, 50, 50, 200, 150, red)

-- Green circle
local green = draw.color(0, 255, 0)
draw.circle(img, 400, 125, 75, green)

-- Blue line
local blue = draw.color(0, 0, 255)
draw.line(img, 0, 250, 640, 250, blue)

-- Random colored circles
print("Drawing random circles...")
for i = 1, 20 do
    local x = math.random(640)
    local y = math.random(280, 480)
    local r = math.random(20, 50)
    local color = draw.color(
        math.random(256),
        math.random(256),
        math.random(256)
    )
    draw.circle(img, x, y, r, color)
end

-- Draw text
print("Drawing text...")
local fnt = draw.font("/fonts/lucida/latin1.610", 24)
if fnt then
    local black = draw.color(0, 0, 0)
    draw.text(img, "Hello, TaijiOS Lua!", 200, 30, fnt, black)
    draw.text(img, "Press Ctrl-C to exit", 200, 450, fnt, black)
end

-- Save image
local filename = "/tmp/draw_example.bit"
print("Saving image to " .. filename .. "...")
draw.save(img, filename)

print("Done! Image saved to " .. filename)
print("")
print("You can view the image with:")
print("  iprint " .. filename)
