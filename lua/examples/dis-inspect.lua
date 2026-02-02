#!/dis/lua
-- DIS File Inspection Tool
-- Displays information about DIS binary files

print("DIS File Inspection Tool")
print("=======================\n")

-- Get file path from command line
local arg = arg or {}
local filepath = arg[1]

if not filepath then
    print("Usage: dis-inspect.lua <file.dis>")
    print("\nExample:")
    print("  dis-inspect.lua /dis/lib/math.dis")
    os.exit(1)
end

print("File: " .. filepath)
print()

-- Load disparser module
local disparser = require("disparser")
if not disparser then
    print("Error: Failed to load disparser module")
    print("Make sure lua_disparser.dis is compiled")
    os.exit(1)
end

-- Parse the file
local file, err = disparser.parse(filepath)
if not file then
    print("Error: " .. (err or "unknown error"))
    os.exit(1)
end

-- Validate
if disparser.validate(file) == 0 then
    print("Error: Invalid DIS file")
    os.exit(1)
end

-- Display header information
print("Header Information:")
print("-------------------")
local h = file.header
print(string.format("  Magic:      0x%x (%s)", h.magic,
    h.magic == 819248 and "executable" or "library"))
print(string.format("  Stack size: %d bytes", h.ssize))
print(string.format("  Code size:  %d instructions", h.isize))
print(string.format("  Data size:  %d bytes", h.dsize))
print(string.format("  Types:      %d descriptors", h.tsize))
print(string.format("  Links:      %d entries", h.lsize))
print(string.format("  Entry:      PC %d", h.entry))
print()

-- Display instructions
if file.inst and #file.inst > 0 then
    print("Instructions (first 10):")
    print("------------------------")
    local count = math.min(10, #file.inst)
    for i = 1, count do
        local inst = file.inst[i]
        local str = disparser.inst2str(inst)
        print(string.format("  [%4d] %s", i-1, str))
    end
    if #file.inst > 10 then
        print(string.format("  ... and %d more", #file.inst - 10))
    end
    print()
end

-- Display types
if file.types and #file.types > 0 then
    print("Type Descriptors:")
    print("-----------------")
    for i = 1, #file.types do
        local t = file.types[i]
        print(string.format("  [%2d] size=%d np=%d", i-1, t.size, t.np))
    end
    print()
end

-- Display exports (link table)
if file.links and #file.links > 0 then
    print("Exported Functions:")
    print("-------------------")
    for i = 1, #file.links do
        local link = file.links[i]
        print(string.format("  %-20s  PC=%4d  sig=%d  tdesc=%d",
            link.name, link.pc, link.sig, link.tdesc))
    end
    print()
end

-- Display data segment
if file.data then
    print("Data Segment:")
    print("-------------")
    local count = 0
    for d in file.data do
        local dtype = d.op
        local dtypename = {
            [0] = "Zero",
            [1] = "Bytes",
            [2] = "Words",
            [3] = "String",
            [4] = "Reals",
            [5] = "Array",
            [6] = "Index",
            [7] = "Restore",
            [8] = "Bigs",
        }
        local typename = dtypename[dtype] or "Unknown"
        print(string.format("  [%2d] %-10s n=%-6d off=%d",
            count, typename, d.n, d.off))
        count = count + 1
        if count >= 10 then
            print("  ...")
            break
        end
    end
    print()
end

-- Display signature
if file.sign and #file.sign > 0 then
    print("Signature:")
    print("----------")
    print(string.format("  %d bytes (signed)", #file.sign))
    print()
end

print("Inspection complete.")
