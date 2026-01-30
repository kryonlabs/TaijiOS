#!/bin/bash
# Compile KRB viewer Limbo modules
# This script compiles the krbview and krbloader modules using Inferno's limbo compiler

cd /mnt/storage/Projects/TaijiOS

echo "Compiling KRB Viewer Limbo modules..."
echo ""

# Method 1: Using mk within Inferno (preferred)
echo "Starting Inferno to compile modules..."
./Linux/amd64/bin/emu -r . sh -c 'cd /appl/wm && mk krbview.dis krbloader.dis' 2>&1

if [ $? -eq 0 ]; then
    echo ""
    echo "Compilation successful!"
    echo "Compiled files:"
    ls -lh appl/wm/krbview.dis appl/wm/krbloader.dis 2>/dev/null
else
    echo ""
    echo "Compilation failed. Check errors above."
    exit 1
fi

echo ""
echo "KRB Viewer is ready to use. Run with:"
echo "  ./run_krbview.sh kryon/examples/hello-world.krb"
