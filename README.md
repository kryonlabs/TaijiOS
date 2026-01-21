# LimboOS

## What is LimboOS?

LimboOS is a modern fork of **Inferno®** Distributed Operating System, originally developed at Bell Labs and maintained by Vita Nuova® as Free Software (MIT License since 2021).

LimboOS brings Inferno's powerful distributed computing capabilities to modern systems with updated build tools, C11 compliance, and enhanced platform support.

### Core Features

- **Limbo Programming Language** - Concise concurrent language compiled to portable Dis bytecode
- **Distributed Design** - Built-in networking and resource sharing across heterogeneous systems
- **Virtual Machine** - Run anywhere: native (bare metal) or hosted (Linux, BSD, Windows, macOS)
- **Everything is a File** - Unified interface to all resources via Styx protocol
- **Portable Applications** - Write once, run on any supported architecture

### How LimboOS Differs from Inferno

- **Modern Build System** - C11 standard compliance, modern gcc/clang support
- **Multi-Platform Support** - Native amd64 support for Linux, OpenBSD, 9front, and Plan 9
- **9front Integration** - Modern drivers, IP stack, and file system improvements
- **NixOS Ready** - First-class NixOS integration with reproducible builds
- **Enhanced Security** - Modern cryptography and security features
- **Active Development** - Regular updates and bug fixes for contemporary systems

## Quick Start

### On NixOS (Recommended):

```bash
cd /path/to/LimboOS

# Enter the build environment
nix-shell

# Build (first time only)
build9ferno

# Run Inferno emulator
run9ferno
# or just type:
emu
```

### On OpenBSD:

```bash
cd /path/to/LimboOS
chmod +x run.sh
./run.sh
```

### On Other Linux:

```bash
# Install dependencies first:
# Debian/Ubuntu: sudo apt install build-essential libx11-dev libxext-dev
# Fedora: sudo dnf install gcc make libX11-devel libXext-devel
# Arch: sudo pacman -S base-devel libx11 libxext

cd /path/to/LimboOS
chmod +x run.sh
./run.sh
```

## Available Commands (in nix-shell)

After entering `nix-shell`, you have these helper functions:

- `build9ferno` - Build LimboOS from scratch
- `run9ferno` - Run the Inferno emulator
- `emu` - Alias for run9ferno

## Using the Universal Script

The `run.sh` script works on NixOS, OpenBSD, and generic Linux:

```bash
./run.sh              # Build and run in one command
./run.sh -h            # Show emu help
./run.sh -g 800x600    # Run with specific geometry
```

## Directory Structure

```
LimboOS/
├── Linux/amd64/      # Platform-specific binaries
│   ├── bin/          # Built binaries (emu, limbo, etc.)
│   └── lib/          # Libraries
├── dis/              # Compiled Limbo programs (.dis files)
├── appl/             # Limbo application source code
├── module/           # Limbo module definitions
├── emu/              # Inferno emulator source
├── lib*/             # Library source code
├── shell.nix         # NixOS shell environment
└── run.sh            # Universal build/run script
```

## Building from Scratch

If you need to do a complete clean build:

```bash
# In nix-shell on NixOS
mk nuke              # Clean all built files
mk install           # Rebuild everything
```

## Running Programs Inside emu

Once emu starts, you'll see the `;` prompt. You can run Limbo programs:

```limbo
# List files
ls /

# Run a program
/dis/ls /

# Start the window manager
wm/wm

# List available commands
ls /dis

# Check environment
cat /env/emuroot

# Exit
exit
```

## Example: Writing a Limbo Program

```limbo
; cat > /tmp/hello.b << 'EOF'
implement Hello;

include "sys.m";

Hello: module {
    init: fn(nil: list of string);
};

init(nil: list of string) {
    sys := load Sys Sys->PATH;
    sys->print("Hello from LimboOS!\n");
}
EOF

; limbo /tmp/hello.b
; hello
```

## Platform Support

LimboOS runs in two modes:

### Hosted Mode (Recommended)
- Runs as an application on top of another OS
- **Available for:** Linux, FreeBSD, OpenBSD, NetBSD, macOS, Windows
- **No reboot required** - just run `emu`

### Native Mode
- Boots directly on hardware
- **Available for:** x86 (32/64-bit), ARM, PowerPC, SPARC, MIPS
- Full control of hardware with minimal footprint

## Troubleshooting

### emu crashes on startup

This was a known issue with X11 threading initialization. Fixed in LimboOS - if you still see crashes:

```bash
# Make sure you have the latest version
git pull

# Rebuild
cd /path/to/LimboOS
nix-shell
build9ferno
```

### Username warnings

When you see `cd: /usr/username: '/usr/username' does not exist`, this is normal. LimboOS tries to set up a home directory but falls back gracefully.

### Build errors on Linux

Make sure you have the required dependencies installed:

**Debian/Ubuntu:**
```bash
sudo apt install build-essential libx11-dev libxext-dev
```

**Fedora/RHEL:**
```bash
sudo dnf install gcc make libX11-devel libXext-devel
```

**Arch Linux:**
```bash
sudo pacman -S base-devel libx11 libxext
```

### Missing directories error

If you get errors about missing `/dis` directories:

```bash
# Run the full build which creates all needed directories
mk install
```

## Contributing

LimboOS welcomes contributions! Please see the source repository for guidelines on submitting patches and bug reports.

## Original Source

Based on Inferno OS Fourth Edition by Vita Nuova Holdings:
- https://inferno-os.org/
- https://github.com/inferno-os/inferno-os

LimboOS incorporates enhancements from the 9front community:
- https://9front.org/

## License

MIT License (since 2021)

See individual source files for details.

## Acknowledgments

- Bell Labs for the original Inferno operating system
- Vita Nuova Holdings for releasing Inferno as free software
- The 9front community for continued development and improvements
- All contributors to LimboOS

---

**LimboOS** - Distributed computing for the modern era.
