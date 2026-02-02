#!/dis/wlua
-- Simple Tk GUI example
-- Demonstrates basic Tk widget control

print("Simple GUI Example")
print("===================")

-- Create GUI widgets
print("Creating widgets...")

-- Create label
tk.cmd("label .l1 -text 'TaijiOS Lua GUI'")
tk.cmd("label .l2 -text 'Click the buttons below'")

-- Create buttons
tk.cmd("button .b1 -text 'Greet' -command on_greet")
tk.cmd("button .b2 -text 'Counter' -command on_counter")
tk.cmd("button .b3 -text 'Clear' -command on_clear")
tk.cmd("button .q -text Quit -command on_quit")

-- Create text area for output
tk.cmd("text .t -width 60 -height 15 -bg white")
tk.cmd("pack .l1 .l2 .t .b1 .b2 .b3 .q -side top -fill x")

print("Widgets created")

-- Counter variable
counter = 0

-- Event handlers
function on_greet()
    local greetings = {
        "Hello from TaijiOS Lua!",
        "Welcome to the windowing shell!",
        "Tk bindings are working!",
        "Lua + Inferno = Great combination!"
    }
    local greeting = greetings[math.random(#greetings)]
    tk.cmd(".t insert end '" .. greeting .. "\\n'")
end

function on_counter()
    counter = counter + 1
    tk.cmd(".t insert end 'Counter: " .. counter .. "\\n'")
end

function on_clear()
    tk.cmd(".t delete 1.0 end")
    counter = 0
end

function on_quit()
    print("Quit button clicked!")
    os.exit()
end

-- Also bind keyboard shortcuts
tk.bind(".b1", "<Return>", on_greet)
tk.bind(".q", "<Escape>", on_quit)

-- Set up a timer to show time
function show_time()
    local time = os.date("%H:%M:%S")
    tk.cmd(".l2 configure -text 'Current time: " .. time .. "'")
    tk.after(1000, show_time)
end

-- Start the timer
tk.after(1000, show_time)

-- Add some initial text
tk.cmd(".t insert end 'Welcome to TaijiOS Lua GUI!\\n\\n'")
tk.cmd(".t insert end 'Try the buttons:\\n'")
tk.cmd(".t insert end '  - Greet: Shows a random greeting\\n'")
tk.cmd(".t insert end '  - Counter: Increments a counter\\n'")
tk.cmd(".t insert end '  - Clear: Clears the text area\\n'")
tk.cmd(".t insert end '  - Quit: Exits the program\\n'")
tk.cmd(".t insert end '\\nThe time updates every second.\\n'")

print("===================")
print("GUI is running!")
print("Use the buttons or press:")
print("  - Enter on Greet button")
print("  - Escape on Quit button")
