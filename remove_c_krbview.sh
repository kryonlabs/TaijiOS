#!/bin/bash
# Remove C implementation of KRB viewer
# This script removes the C-based krbview implementation in favor of the pure Limbo version

set -e

cd /mnt/storage/Projects/TaijiOS

echo "========================================="
echo "Removing C KRB Viewer Implementation"
echo "========================================="
echo ""
echo "This will remove:"
echo "  - utils/krbview/ (standalone C viewer)"
echo "  - os/port/krbexec.c (C wrapper)"
echo "  - kryon/src/renderers/krbview/ (stub renderer)"
echo "  - Makefile references to krbview renderer"
echo ""
echo "The pure Limbo implementation in appl/wm/ will remain."
echo ""

read -p "Continue? [y/N] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 1
fi

echo ""
echo "Creating archive of C implementations..."
mkdir -p archive/c_implementations/$(date +%Y%m%d)
ARCHIVE_DIR="archive/c_implementations/$(date +%Y%m%d)"

# Archive C krbview
if [ -d "utils/krbview" ]; then
    echo "  Archiving utils/krbview/ ..."
    cp -r utils/krbview "$ARCHIVE_DIR/"
    echo "    → $ARCHIVE_DIR/krbview/"
fi

# Archive krbexec.c
if [ -f "os/port/krbexec.c" ]; then
    echo "  Archiving os/port/krbexec.c ..."
    mkdir -p "$ARCHIVE_DIR/port"
    cp os/port/krbexec.c "$ARCHIVE_DIR/port/"
    echo "    → $ARCHIVE_DIR/port/krbexec.c"
fi

# Archive kryon krbview renderer
if [ -d "kryon/src/renderers/krbview" ]; then
    echo "  Archiving kryon/src/renderers/krbview/ ..."
    mkdir -p "$ARCHIVE_DIR/kryon_renderer"
    cp -r kryon/src/renderers/krbview "$ARCHIVE_DIR/kryon_renderer/"
    echo "    → $ARCHIVE_DIR/kryon_renderer/krbview/"
fi

echo ""
echo "Removing C implementations..."

# Remove C krbview
if [ -d "utils/krbview" ]; then
    echo "  Removing utils/krbview/ ..."
    rm -rf utils/krbview
    echo "    ✓ Removed"
else
    echo "  utils/krbview/ not found (already removed?)"
fi

# Remove krbexec.c
if [ -f "os/port/krbexec.c" ]; then
    echo "  Removing os/port/krbexec.c ..."
    rm -f os/port/krbexec.c
    echo "    ✓ Removed"
else
    echo "  os/port/krbexec.c not found (already removed?)"
fi

# Remove kryon krbview renderer
if [ -d "kryon/src/renderers/krbview" ]; then
    echo "  Removing kryon/src/renderers/krbview/ ..."
    rm -rf kryon/src/renderers/krbview
    echo "    ✓ Removed"
else
    echo "  kryon/src/renderers/krbview/ not found (already removed?)"
fi

# Update Makefile to remove krbview renderer references
echo "  Updating kryon/Makefile ..."
if [ -f "kryon/Makefile" ]; then
    # Create backup
    cp kryon/Makefile kryon/Makefile.bak

    # Remove krbview renderer lines
    sed -i '/# KRBView renderer/,/^endif$/d' kryon/Makefile

    if [ $? -eq 0 ]; then
        echo "    ✓ Updated (backup: kryon/Makefile.bak)"
    else
        echo "    ✗ Failed to update Makefile"
        mv kryon/Makefile.bak kryon/Makefile
    fi
else
    echo "    kryon/Makefile not found"
fi

echo ""
echo "========================================="
echo "✓ C Implementation Removed Successfully"
echo "========================================="
echo ""
echo "Archived to: $ARCHIVE_DIR/"
echo ""
echo "The Limbo implementation is in:"
echo "  - appl/wm/krbview.b (GUI application)"
echo "  - appl/wm/krbloader.b (core module)"
echo "  - appl/wm/krbloader.m (module interface)"
echo ""
echo "Compiled bytecode:"
echo "  - appl/wm/krbview.dis"
echo "  - appl/wm/krbloader.dis"
echo ""
echo "To compile: ./compile_krbview.sh"
echo "To run: ./run_krbview.sh kryon/examples/hello-world.krb"
echo ""
