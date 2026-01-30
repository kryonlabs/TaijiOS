# How to Test krbview with Real Kryon Files

## Prerequisites

Before testing krbview, you need to build the Kryon compiler and toolchain.

## Step 1: Build the Kryon Compiler

The Kryon compiler (`kryon`) is needed to compile `.kry` source files into `.krb` binary files.

```bash
cd /mnt/storage/Projects/TaijiOS

# Build the entire toolchain (including Kryon)
mk build

# Or build just Kryon
cd kryon
mk
mk install
```

This should produce the `kryon` executable at:
- `$ROOT/$OBJDIR/bin/kryon` or
- `/mnt/storage/Projects/TaijiOS/kryon/kryon`

### Verify Kryon is Built

```bash
# Check if kryon exists
./kryon/kryon --help

# You should see usage information
```

---

## Step 2: Available Test Files

The repository includes many example KRY files in `/mnt/storage/Projects/TaijiOS/kryon/examples/`:

### Simple Examples
- `hello-world.kry` - Basic "Hello World" text display
- `button.kry` - Simple button widget
- `text_input.kry` - Text input field
- `checkbox.kry` - Checkbox widget

### Interactive Examples
- `counters_demo.kry` - Counter with buttons
- `todo.kry` - Todo list application
- `tabs.kry` - Tab navigation
- `dropdown.kry` - Dropdown menu

### Advanced Examples
- `rc_shell_demo.kry` - **RC script execution demo**
- `mixed_languages.kry` - Multiple script languages
- `all_features_demo.kry` - All widget types
- `z_index_test.kry` - Z-ordering and stacking

---

## Step 3: Compile KRY Files to KRB

### Option A: Compile Individual Files

```bash
cd /mnt/storage/Projects/TaijiOS

# Compile hello-world example
./kryon/kryon compile kryon/examples/hello-world.kry -o /tmp/hello-world.krb

# Compile RC shell demo
./kryon/kryon compile kryon/examples/rc_shell_demo.kry -o /tmp/rc_demo.krb

# Compile counter demo
./kryon/kryon compile kryon/examples/counters_demo.kry -o /tmp/counters.krb
```

### Option B: Compile All Examples

```bash
#!/bin/bash
# Compile all KRY files in examples directory

KRYON="./kryon/kryon"
EXAMPLE_DIR="kryon/examples"
OUTPUT_DIR="/tmp/krb_tests"

mkdir -p "$OUTPUT_DIR"

for kry_file in "$EXAMPLE_DIR"/*.kry; do
    base_name=$(basename "$kry_file" .kry)
    krb_file="$OUTPUT_DIR/${base_name}.krb"

    echo "Compiling $kry_file -> $krb_file"
    $KRYON compile "$kry_file" -o "$krb_file"

    if [ $? -eq 0 ]; then
        echo "  ✓ Success"
    else
        echo "  ✗ Failed"
    fi
done

echo ""
echo "Compiled files are in: $OUTPUT_DIR"
ls -lh "$OUTPUT_DIR"
```

Save this as `compile_examples.sh` and run it.

---

## Step 4: Build krbview

```bash
cd /mnt/storage/Projects/TaijiOS

# Build krbview and dependencies
mk install

# Verify krbview exists
ls -lh $ROOT/$OBJDIR/bin/krbview
# or
ls -lh ./utils/krbview/krbview
```

---

## Step 5: Test krbview with Real Files

### Test 1: Hello World (Basic Rendering)

```bash
cd /mnt/storage/Projects/TaijiOS

# Compile
./kryon/kryon compile kryon/examples/hello-world.kry -o /tmp/hello.krb

# Run krbview
./utils/krbview/krbview /tmp/hello.krb
```

**Expected Result:**
- Window opens with dark blue background
- Yellow "Hello World" text in center
- Window responds to close (Del key or click close button)

### Test 2: Button (Interactive Widget)

```bash
# Compile
./kryon/kryon compile kryon/examples/button.kry -o /tmp/button.krb

# Run
./utils/krbview/krbview /tmp/button.krb
```

**Expected Result:**
- Button appears on screen
- Clicking button triggers visual feedback
- Mouse hover effects work

### Test 3: Counters Demo (RC Scripts)

```bash
# Compile
./kryon/kryon compile kryon/examples/counters_demo.kry -o /tmp/counters.krb

# Run with RC debug output
./utils/krbview/krbview -rc-debug /tmp/counters.krb
```

**Expected Result:**
- Multiple counters with increment/decrement buttons
- Clicking buttons updates counters
- Status bar shows RC script output
- Variables synchronized correctly

### Test 4: RC Shell Demo (Full RC Integration)

```bash
# Compile
./kryon/kryon compile kryon/examples/rc_shell_demo.kry -o /tmp/rc_demo.krb

# Run with debug mode
./utils/krbview/krbview -debug -rc-debug /tmp/rc_demo.krb
```

**Expected Result:**
- Full counter demo with RC scripts
- Increment/decrement buttons work
- RC functions execute correctly
- Status bar shows echo output
- Time-based features work

### Test 5: Todo App (Complex Interactive)

```bash
# Compile
./kryon/kryon compile kryon/examples/todo.kry -o /tmp/todo.krb

# Run
./utils/krbview/krbview /tmp/todo.krb
```

**Expected Result:**
- Todo list interface
- Add/remove items
- Interactive elements work

---

## Step 6: Automated Testing Script

Save this as `test_krbview.sh`:

```bash
#!/bin/bash
set -e

echo "=== krbview Testing Script ==="
echo ""

KRYON="./kryon/kryon"
KRBVIEW="./utils/krbview/krbview"
TEST_DIR="/tmp/krbview_tests"
EXAMPLES="kryon/examples"

# Check prerequisites
if [ ! -f "$KRYON" ]; then
    echo "Error: Kryon compiler not found at $KRYON"
    echo "Build it first: cd kryon && mk install"
    exit 1
fi

if [ ! -f "$KRBVIEW" ]; then
    echo "Error: krbview not found at $KRBVIEW"
    echo "Build it first: mk install"
    exit 1
fi

# Create test directory
rm -rf "$TEST_DIR"
mkdir -p "$TEST_DIR"

echo "Step 1: Compiling test files..."
echo "=============================="

# Test files to compile
TEST_FILES=(
    "hello-world.kry"
    "button.kry"
    "counters_demo.kry"
    "rc_shell_demo.kry"
    "text_input.kry"
)

for kry_file in "${TEST_FILES[@]}"; do
    src="$EXAMPLES/$kry_file"
    dst="$TEST_DIR/${kry_file%.kry}.krb"

    if [ -f "$src" ]; then
        echo -n "Compiling $kry_file... "
        $KRYON compile "$src" -o "$dst" 2>/dev/null

        if [ $? -eq 0 ]; then
            echo "✓"
        else
            echo "✗ Failed"
            exit 1
        fi
    else
        echo "✗ $src not found"
    fi
done

echo ""
echo "Step 2: Running tests..."
echo "========================"

# Test 1: Load test (non-interactive)
echo "Test 1: File loading"
for krb_file in "$TEST_DIR"/*.krb; do
    echo -n "  Loading $(basename $krb_file)... "
    timeout 1 $KRBVIEW -W 100 -H 100 "$krb_file" >/dev/null 2>&1
    if [ $? -eq 124 ] || [ $? -eq 0 ]; then
        echo "✓"
    else
        echo "✗ Failed to load"
    fi
done

echo ""
echo "Step 3: Interactive tests..."
echo "============================"

echo ""
echo "Manual testing required for interactive features:"
echo ""
echo "  # Test basic rendering:"
echo "  $KRBVIEW $TEST_DIR/hello-world.krb"
echo ""
echo "  # Test button interaction:"
echo "  $KRBVIEW $TEST_DIR/button.krb"
echo ""
echo "  # Test RC scripts:"
echo "  $KRBVIEW -rc-debug $TEST_DIR/counters_demo.krb"
echo ""
echo "  # Test full RC integration:"
echo "  $KRBVIEW -debug -rc-debug $TEST_DIR/rc_shell_demo.krb"

echo ""
echo "=== Test suite ready ==="
echo "Test files are in: $TEST_DIR"
ls -lh "$TEST_DIR"
```

Run it:
```bash
chmod +x test_krbview.sh
./test_krbview.sh
```

---

## Step 7: Verification Checklist

### Basic Functionality
- [ ] Window opens and displays content
- [ ] Background colors render correctly
- [ ] Text renders with correct fonts and colors
- [ ] Window can be closed (Del key)

### Interactive Elements
- [ ] Mouse clicks trigger events
- [ ] Buttons respond to clicks
- [ ] Mouse hover effects work
- [ ] Keyboard input works
- [ ] Focus management works

### RC Script Execution
- [ ] RC scripts execute on events
- [ ] Variables update correctly
- [ ] Status bar shows RC output
- [ ] Built-in functions work (get/set_widget_prop)
- [ ] echo commands display in status bar

### Layout
- [ ] Containers render correctly
- [ ] Column layout works
- [ ] Row layout works
- [ ] Padding and margins work
- [ ] Nested containers work

---

## Troubleshooting

### "kryon: command not found"
**Solution:** Build Kryon first
```bash
cd /mnt/storage/Projects/TaijiOS/kryon
mk install
```

### "krbview: error while loading shared libraries"
**Solution:** Ensure libraries are built
```bash
cd /mnt/storage/Projects/TaijiOS
mk install
```

### "Failed to initialize display"
**Solution:** Check DISPLAY environment variable
```bash
echo $DISPLAY
# Should show something like :0 or :1
# If empty, start X server or set DISPLAY=:0
```

### Window doesn't appear
**Possible causes:**
1. Window opened off-screen - try `-W 800 -H 600`
2. Display not initialized - check X11/Wayland
3. KRB file invalid - verify with `kryon decompile file.krb`

### RC events not firing
**Debug:**
```bash
krbview -rc-debug -debug file.krb
```
Check stderr for RC execution logs.

### "RC shell integration failed"
**Solution:** This is a warning, app will continue without RC
- Check libkrb_shell.a is built
- Verify Inferno sh.dis is available

---

## Quick Test Commands

```bash
# Fast test loop (compile and run)
test_file() {
    name=$(basename $1 .kry)
    echo "Testing $name..."
    ./kryon/kryon compile "$1" -o /tmp/$name.krb
    ./utils/krbview/krbview /tmp/$name.krb
}

# Usage
test_file kryon/examples/hello-world.kry
test_file kryon/examples/button.kry
test_file kryon/examples/rc_shell_demo.kry
```

---

## Next Steps

Once basic testing is complete:

1. **Test all examples** - Try every .kry file in examples/
2. **Create custom KRY files** - Test your own UIs
3. **Stress test** - Large widget trees, many events
4. **Performance test** - Measure FPS, memory usage
5. **Report issues** - Document any bugs found

---

## Summary

**To test krbview:**
1. Build Kryon: `cd kryon && mk install`
2. Build krbview: `mk install`
3. Compile KRY: `./kryon/kryon compile file.kry -o file.krb`
4. Run viewer: `./utils/krbview/krbview file.krb`
5. Interact and verify functionality

**Best test files to start with:**
- `hello-world.kry` - Simple rendering
- `button.kry` - Basic interaction
- `counters_demo.kry` - RC scripts
- `rc_shell_demo.kry` - Full RC integration
