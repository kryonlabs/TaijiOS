#!/bin/bash
# Integration test runner for Lua DIS module loading

echo "Lua DIS Module Loading - Integration Test Runner"
echo "================================================="
echo ""

# Check component files
echo "Component Status:"
echo "================"

components=(
    "lua/lib/lua_marshal.b:Type Marshaling"
    "lua/lib/lua_modparse.b:Module Parser"
    "lua/lib/lua_disloader_new.b:DIS Loader"
    "lua/lib/lua_proxy.b:Function Proxy"
    "lua/module/limbo.m:Module Interface"
    "lua/test/test_marshal.b:Marshaling Tests"
    "lua/test/test_modparse.b:Parser Tests"
    "lua/test/integration.lua:Integration Test"
    "lua/doc/ffi.md:FFI Documentation"
    "lua/doc/type-mapping.md:Type Mapping Guide"
    "lua/doc/module-loading.md:Module Loading Guide"
    "lua/doc/BUILD.md:Build Guide"
    "lua/examples/math-demo.lua:Math Demo"
    "lua/examples/draw-demo.lua:Draw Demo"
    "lua/examples/tk-demo.lua:Tk Demo"
)

for component in "${components[@]}"; do
    file="${component%%:*}"
    name="${component##*:}"
    
    if [ -f "$file" ]; then
        size=$(wc -l < "$file")
        printf "  [✓] %-25s  (%4d lines)\n" "$name" "$size"
    else
        printf "  [✗] %-25s  (missing: %s)\n" "$name" "$file"
    fi
done

echo ""
echo "Summary:"
echo "========"

total=0
found=0
for component in "${components[@]}"; do
    file="${component%%:*}"
    total=$((total + 1))
    if [ -f "$file" ]; then
        found=$((found + 1))
    fi
done

echo "Files found: $found / $total"

# Count lines of code
echo ""
echo "Lines of Code:"
echo "============="

total_loc=0
for dir in lua/lib lua/test lua/doc; do
    if [ -d "$dir" ]; then
        loc=$(find "$dir" -name "*.b" -o -name "*.md" | xargs wc -l 2>/dev/null | tail -1 | awk '{print $1}')
        echo "$dir: $loc"
        total_loc=$((total_loc + loc))
    fi
done

echo ""
echo "Total: ~$total_loc LOC"

echo ""
echo "Next Steps:"
echo "-----------"
echo "1. Review documentation: cat lua/doc/ffi.md"
echo "2. Build components: see lua/BUILD.md"
echo "3. Run tests when compiled"
echo ""
