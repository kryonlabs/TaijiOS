#!/bin/bash
# Script to launch KRB viewer using nix-shell build environment
# Use this if you're developing and need the build environment

export ROOT="/mnt/storage/Projects/TaijiOS"
cd "$ROOT"

# Check if a file argument was provided
if [ -z "$1" ]; then
    echo "Usage: $0 <krb_file> [width] [height]"
    echo ""
    echo "Example: $0 kryon/examples/simple_grid.krb"
    echo "Example: $0 kryon/examples/simple_grid.krb 800 600"
    echo ""
    # List available KRB files
    echo "Available KRB files:"
    find "$ROOT/kryon/examples" -name "*.krb" 2>/dev/null || echo "  (none found in kryon/examples/)"
    exit 1
fi

KRB_FILE="$1"
WIDTH="${2:-800}"
HEIGHT="${3:-600}"

# Check if the KRB file exists
if [ ! -f "$ROOT/$KRB_FILE" ]; then
    echo "Error: KRB file not found: $ROOT/$KRB_FILE"
    exit 1
fi

echo "Launching KRB Viewer via nix-shell..."
echo "  File: $KRB_FILE"
echo "  Size: ${WIDTH}x${HEIGHT}"
echo ""
echo "Note: Close the window to exit"
echo ""

# Run via nix-shell with graphics support
nix-shell --run "./Linux/amd64/bin/emu -r . -g1 \"wm/krbview -W $WIDTH -H $HEIGHT $KRB_FILE\""
