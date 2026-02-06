#!/bin/sh
# TaijiOS run script - launches the emulator
# Use 'mk && mk all' to build first if needed

cd "$(dirname "$0")"
export ROOT="$(pwd)"
export PATH="$ROOT/Linux/amd64/bin:$PATH"

if [ $# -eq 0 ]; then
    set -- dis/sh.dis
fi

# Set up namespace
mkdir -p "$ROOT/tmp" "$ROOT/mnt" "$ROOT/n"
chmod 555 "$ROOT/n"
chmod 755 "$ROOT/tmp" "$ROOT/mnt"

# Run emu
exec "$ROOT/Linux/amd64/bin/emu" -p heap=128m -r "$ROOT" "$@"
