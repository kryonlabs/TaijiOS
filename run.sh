#!/bin/sh
# LimboOS build and run script
# Works on NixOS and OpenBSD

set -e

# Determine OS
if [ -f /etc/NIXOS ]; then
    OS="nixos"
elif [ "$(uname)" = "OpenBSD" ]; then
    OS="openbsd"
else
    OS="linux"
fi

echo "=== LimboOS Build & Run Script ==="
echo "Detected OS: $OS"
echo ""

# Change to script directory
cd "$(dirname "$0")"

# Function to build on NixOS
build_nixos() {
    echo "Building on NixOS using nix-shell..."
    if [ ! -f Linux/amd64/bin/emu ]; then
        nix-shell --run 'export PATH="$PWD/Linux/amd64/bin:$PATH"; mk install'
    else
        echo "emu binary already exists, skipping build..."
    fi
}

# Function to build on OpenBSD
build_openbsd() {
    echo "Building on OpenBSD..."
    if [ ! -f Linux/amd64/bin/emu ]; then
        # OpenBSD native build
        export SYSTARG=OpenBSD
        export OBJTYPE=amd64

        # Build mk first if needed
        if [ ! -f Linux/amd64/bin/mk ]; then
            echo "Building mk build tool..."
            (cd mk && mk && mv mk /usr/local/bin/ || true)
        fi

        # Build and install
        mk install
    else
        echo "emu binary already exists, skipping build..."
    fi
}

# Function to build on generic Linux
build_linux() {
    echo "Building on generic Linux..."
    if [ ! -f Linux/amd64/bin/emu ]; then
        export PATH="$PWD/Linux/amd64/bin:$PATH"
        mk install
    else
        echo "emu binary already exists, skipping build..."
    fi
}

# Build based on OS
case "$OS" in
    nixos)
        build_nixos
        ;;
    openbsd)
        build_openbsd
        ;;
    linux)
        build_linux
        ;;
esac

echo ""
echo "=== Build Complete! ==="
echo ""

# Set up namespace for emu
EMU_ROOT="$(pwd)"
export ROOT="$EMU_ROOT"

# Create minimal namespace
mkdir -p "$ROOT/tmp"

# Function to run on NixOS
run_nixos() {
    echo "Starting emu on NixOS..."
    echo "Type 'exit' to quit emu"
    echo ""

    # Run emu with nix-shell environment
    exec nix-shell --run "
        export PATH='$ROOT/Linux/amd64/bin:\$PATH'
        export ROOT='$ROOT'
        cd '$ROOT'
        exec Linux/amd64/bin/emu -r '$ROOT' "\$@"
    " -- "$@"
}

# Function to run on OpenBSD
run_openbsd() {
    echo "Starting emu on OpenBSD..."
    echo "Type 'exit' to quit emu"
    echo ""

    export PATH="$ROOT/Linux/amd64/bin:$PATH"

    # Run emu
    exec "$ROOT/Linux/amd64/bin/emu" -r "$ROOT" "$@"
}

# Function to run on generic Linux
run_linux() {
    echo "Starting emu..."
    echo "Type 'exit' to quit emu"
    echo ""

    export PATH="$ROOT/Linux/amd64/bin:$PATH"

    # Run emu
    exec "$ROOT/Linux/amd64/bin/emu" -r "$ROOT" "$@"
}

# Run based on OS
case "$OS" in
    nixos)
        run_nixos "$@"
        ;;
    openbsd)
        run_openbsd "$@"
        ;;
    linux)
        run_linux "$@"
        ;;
esac
