#!/bin/bash
# Launch KRB viewer with proper graphics support
# This script launches the Inferno emulator with the KRB viewer

if [ -z "$1" ]; then
    echo "Usage: $0 <krb_file> [width] [height]"
    echo ""
    echo "Example: $0 kryon/examples/simple_grid.krb"
    echo "Example: $0 kryon/examples/simple_grid.krb 800 600"
    echo ""
    echo "Available KRB files:"
    find /mnt/storage/Projects/TaijiOS/kryon/examples -name "*.krb" 2>/dev/null || echo "  (none found)"
    exit 1
fi

KRB_FILE="$1"
WIDTH="${2:-800}"
HEIGHT="${3:-600}"

# Check if file exists
if [ ! -f "/mnt/storage/Projects/TaijiOS/$KRB_FILE" ]; then
    echo "Error: File not found: /mnt/storage/Projects/TaijiOS/$KRB_FILE"
    exit 1
fi

cd /mnt/storage/Projects/TaijiOS

echo "Launching KRB Viewer..."
echo "  File: $KRB_FILE"
echo "  Size: ${WIDTH}x${HEIGHT}"
echo ""
echo "Note: Close the window to exit"
echo ""

# Run emulator - IMPORTANT: No quotes around the command!
# The emulator parses arguments directly
exec ./Linux/amd64/bin/emu -r . -g${WIDTH}x${HEIGHT} wm/krbview.dis -W $WIDTH -H $HEIGHT $KRB_FILE
