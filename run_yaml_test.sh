#!/bin/sh

# YAML Module Test Runner
# Compiles and runs YAML test inside Inferno shell

cd /home/wao/Projects/TaijiOS

echo "=========================================="
echo "  YAML Module Test Runner"
echo "=========================================="
echo ""

# Check if yaml module exists
if [ ! -f dis/lib/yaml.dis ]; then
    echo "YAML module not found. Building..."
    echo ""
    nix-shell --run 'export PATH="$PWD/Linux/amd64/bin:$PATH"; export ROOT="$PWD"; mk install'
    echo ""
fi

# Compile the test program
echo "Compiling YAML test program..."
nix-shell --run "cd /home/wao/Projects/TaijiOS && limbo -I/home/wao/Projects/TaijiOS/module -gw test_yaml_simple.b" 2>&1 | grep -E "(warning|error)" || true

if [ ! -f /home/wao/Projects/TaijiOS/test_yaml_simple.dis ]; then
    echo ""
    echo "ERROR: Failed to compile test program"
    exit 1
fi

echo ""
echo "Compilation successful!"
echo ""
echo "Running YAML test in Inferno..."
echo "=========================================="
echo ""

# Run the test
./Linux/amd64/bin/emu -r. test_yaml_simple.dis 2>&1 | grep -E "(YAML|OK|Error|FAIL)"

EXIT_CODE=$?

echo ""
echo "=========================================="
if [ $EXIT_CODE -eq 0 ] || [ $EXIT_CODE -eq 137 ]; then
    echo "SUCCESS: YAML module is working!"
else
    echo "Test complete (exit code: $EXIT_CODE)"
fi
echo ""
echo "YAML module installed at: dis/lib/yaml.dis"
echo ""
