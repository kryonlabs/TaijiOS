#!/bin/bash
# Script to launch KRB viewer for debugging

export ROOT="/home/wao/Projects/TaijiOS"
export PATH="$ROOT/Linux/amd64/bin:$PATH"

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

echo "Launching KRB Viewer..."
echo "  File: $KRB_FILE"
echo "  Size: ${WIDTH}x${HEIGHT}"
echo "  Root: $ROOT"
echo ""
echo "Note: Close the window to exit"
echo ""

# Run the emulator with graphics support
# -r $ROOT : Set Inferno root
# -g1      : Enable graphics
exec "$ROOT/Linux/amd64/bin/emu" -r "$ROOT" -g1 "wm/krbview -W $WIDTH -H $HEIGHT $KRB_FILE"
