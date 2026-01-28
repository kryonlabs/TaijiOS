#!/bin/sh
# TaijiOS Inferno Shell Launcher

# Change to script directory
cd "$(dirname "$0")"

echo "=== TaijiOS Inferno Shell ==="
echo "Starting Inferno shell..."
echo "Type 'exit' to quit"
echo ""

# Run the Inferno shell
exec ./Linux/amd64/bin/emu -r. dis/sh.dis
