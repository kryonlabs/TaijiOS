#!/bin/sh
# Verification script for krbview implementation
# Checks that all required files and components are present

echo "=== krbview Implementation Verification ==="
echo ""

ERRORS=0

# Check source files
echo "1. Checking source files..."
FILES=(
    "krbview.c"
    "krbview.h"
    "krbview_loader.c"
    "krbview_loader.h"
    "krbview_renderer.c"
    "krbview_renderer.h"
    "krbview_events.c"
    "krbview_events.h"
    "krbview_rc.c"
    "krbview_rc.h"
)

for file in "${FILES[@]}"; do
    if [ -f "$file" ]; then
        echo "  ✓ $file"
    else
        echo "  ✗ $file (MISSING)"
        ERRORS=$((ERRORS + 1))
    fi
done

# Check build files
echo ""
echo "2. Checking build files..."
if [ -f "mkfile" ]; then
    echo "  ✓ mkfile"
else
    echo "  ✗ mkfile (MISSING)"
    ERRORS=$((ERRORS + 1))
fi

# Check documentation
echo ""
echo "3. Checking documentation..."
DOCS=(
    "README"
    "IMPLEMENTATION_SUMMARY.md"
)

for doc in "${DOCS[@]}"; do
    if [ -f "$doc" ]; then
        echo "  ✓ $doc"
    else
        echo "  ✗ $doc (MISSING)"
        ERRORS=$((ERRORS + 1))
    fi
done

# Check test files
echo ""
echo "4. Checking test files..."
TEST_DIR="../../tests/krbview"
if [ -d "$TEST_DIR" ]; then
    echo "  ✓ Test directory exists"
    TEST_FILES=(
        "$TEST_DIR/basic_rendering.kry"
        "$TEST_DIR/interactivity.kry"
        "$TEST_DIR/counter.kry"
        "$TEST_DIR/run_tests.sh"
        "$TEST_DIR/TESTING.md"
    )
    for file in "${TEST_FILES[@]}"; do
        if [ -f "$file" ]; then
            echo "  ✓ $(basename $file)"
        else
            echo "  ✗ $(basename $file) (MISSING)"
            ERRORS=$((ERRORS + 1))
        fi
    done
else
    echo "  ✗ Test directory (MISSING)"
    ERRORS=$((ERRORS + 1))
fi

# Check public header
echo ""
echo "5. Checking public API..."
if [ -f "../../include/krbview.h" ]; then
    echo "  ✓ Public header installed"
else
    echo "  ✗ Public header (MISSING)"
    ERRORS=$((ERRORS + 1))
fi

# Check build system integration
echo ""
echo "6. Checking build system integration..."
if grep -q "krbview" ../../utils/mkfile; then
    echo "  ✓ Added to utils/mkfile"
else
    echo "  ✗ Not in utils/mkfile"
    ERRORS=$((ERRORS + 1))
fi

# Count lines of code
echo ""
echo "7. Code statistics..."
TOTAL_LINES=0
for file in *.c; do
    if [ -f "$file" ]; then
        LINES=$(wc -l < "$file")
        TOTAL_LINES=$((TOTAL_LINES + LINES))
        echo "  $file: $LINES lines"
    fi
done
echo "  Total: $TOTAL_LINES lines of C code"

# Summary
echo ""
echo "=== Verification Summary ==="
if [ $ERRORS -eq 0 ]; then
    echo "✓ All checks passed!"
    echo ""
    echo "Next steps:"
    echo "  1. Build: cd ../.. && mk install"
    echo "  2. Test: cd $TEST_DIR && ./run_tests.sh"
    exit 0
else
    echo "✗ Found $ERRORS error(s)"
    exit 1
fi
