#!/dis/sh
# Integration test runner for Lua DIS module loading

echo "Lua DIS Module Loading - Integration Test Runner"
echo "================================================="
echo ""

# Check if we're in the right directory
if (! test -f ./lua/test/integration.lua) {
    echo "Error: Run from TaijiOS root directory"
    exit 1
}

# Try to run the Lua integration test
if (command lua? >/dev/null >[2=1]) {
    echo "Running Lua integration test..."
    lua ./lua/test/integration.lua
} else {
    echo "Note: 'lua' command not available"
    echo "The integration test requires Lua to be built first"
    echo ""
    echo "To build Lua:"
    echo "  cd /mnt/storage/Projects/TaijiOS/lua"
    echo "  mk"
    echo ""
}

echo ""
echo "Component Status:"
echo "================"

# Check for component files
for component in \
    "lua/lib/lua_marshal.b:Type Marshaling" \
    "lua/lib/lua_modparse.b:Module Parser" \
    "lua/lib/lua_disloader_new.b:DIS Loader" \
    "lua/lib/lua_proxy.b:Function Proxy" \
    "lua/module/limbo.m:Module Interface" \
    "lua/test/test_marshal.b:Marshaling Tests" \
    "lua/test/test_modparse.b:Parser Tests" \
    "lua/doc/ffi.md:FFI Documentation"
do
    file=`{echo $component | awk -F: '{print $1}'}
    name=`{echo $component | awk -F: '{print $2}'}
    
    if (test -f $file) {
        echo "  [✓] $name"
    } else {
        echo "  [✗] $name (missing: $file)"
    }
done

echo ""
echo "Next Steps:"
echo "-----------"
echo "1. Build components: cd /mnt/storage/Projects/TaijiOS/lua && mk"
echo "2. Run tests: /dis/test_marshal, /dis/test_modparse"
echo "3. Try examples: lua lua/examples/math-demo.lua"
echo ""
