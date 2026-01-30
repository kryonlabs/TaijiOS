#!/bin/bash
# Launch KRB viewer via nix-shell (for development)

if [ -z "$1" ]; then
    echo "Usage: $0 <krb_file> [width] [height]"
    echo ""
    echo "Example: $0 kryon/examples/simple_grid.krb"
    echo "Example: $0 kryon/examples/simple_grid.krb 800 600"
    exit 1
fi

KRB_FILE="$1"
WIDTH="${2:-800}"
HEIGHT="${3:-600}"

cd /mnt/storage/Projects/TaijiOS

# Create temporary wrapper script
cat > /tmp/run_krbview_wrapper.sh << EOF
#!/bin/sh
cd /mnt/storage/Projects/TaijiOS
exec ./Linux/amd64/bin/emu -r . -g${WIDTH}x${HEIGHT} wm/krbview.dis -W $WIDTH -H $HEIGHT $KRB_FILE
EOF

chmod +x /tmp/run_krbview_wrapper.sh

echo "Launching KRB Viewer via nix-shell..."
echo "  File: $KRB_FILE"
echo "  Size: ${WIDTH}x${HEIGHT}"
echo ""
echo "Note: Close the window to exit"
echo ""

# Run wrapper via nix-shell
exec nix-shell --run /tmp/run_krbview_wrapper.sh
