#!/bin/bash
# Test script to build Kryon with Limbo support inside TaijiOS emu

cd /mnt/storage/Projects/TaijiOS

# Build with mk (should be run inside emu)
echo "Building Kryon with Limbo support..."
echo "Run this inside TaijiOS emu:"
echo "  cd /kryon"
echo "  mk clean"
echo "  mk"
echo ""
echo "If successful, the Limbo plugin will be automatically enabled."
