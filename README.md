# TaijiOS

## What is TaijiOS?

TaijiOS is a modern fork of **Inferno®** Distributed Operating System, originally developed at Bell Labs and maintained by Vita Nuova® as Free Software (MIT License since 2021).

TaijiOS brings Inferno's powerful distributed computing capabilities to modern systems with updated build tools, C11 compliance, and enhanced platform support.

### Core Features

- **Limbo Programming Language** - Concise concurrent language compiled to portable Dis bytecode
- **Distributed Design** - Built-in networking and resource sharing across heterogeneous systems
- **Virtual Machine** - Run anywhere: native (bare metal) or hosted (Linux, BSD, Windows, macOS)
- **Everything is a File** - Unified interface to all resources via Styx protocol
- **Portable Applications** - Write once, run on any supported architecture

### How TaijiOS Differs from Inferno

- **Modern Build System** - C11 standard compliance, modern gcc/clang support
- **Multi-Platform Support** - Native amd64 support for Linux, OpenBSD, 9front, and Plan 9
- **9front Integration** - Modern drivers, IP stack, and file system improvements
- **NixOS Ready** - First-class NixOS integration with reproducible builds
- **Enhanced Security** - Modern cryptography and security features
- **Active Development** - Regular updates and bug fixes for contemporary systems

## Quick Start

### On NixOS (Recommended):

```bash
cd /path/to/TaijiOS

# Option 1: Use the universal script (recommended)
./run.sh              # Build and run emu in one command

# Option 2: Use nix-shell environment
nix-shell             # Enter the build environment
./run.sh              # Build and run

# For a clean rebuild
./run.sh --clean      # Clean build then run
```

### On OpenBSD:

```bash
cd /path/to/TaijiOS
chmod +x run.sh
./run.sh              # Build and run in one command
```

### On Other Linux:

```bash
# Install dependencies first:
# Debian/Ubuntu: sudo apt install build-essential libx11-dev libxext-dev
# Fedora: sudo dnf install gcc make libX11-devel libXext-devel
# Arch: sudo pacman -S base-devel libx11 libxext

cd /path/to/TaijiOS
chmod +x run.sh
./run.sh              # Build and run in one command
```

## Build and Run Scripts

### run.sh - Universal Build & Run

The `run.sh` script works on NixOS, OpenBSD, and generic Linux:

```bash
./run.sh              # Build and run raw emu (no auto-start)
./run.sh --clean      # Clean build then run
./run.sh -h           # Show emu help options
./run.sh -g 800x600   # Run with specific geometry
```

This script:
- Automatically detects your OS (NixOS/OpenBSD/Linux)
- Builds TaijiOS if needed
- Sets up the namespace directory structure
- Runs the raw emu interpreter

### run-wm.sh - Window Manager Mode

Builds and runs with the window manager auto-started:

```bash
./run-wm.sh           # Build and run with wm/wm.dis
./run-wm.sh --clean   # Clean build then run with WM
```

### run-app.sh - Isolated App Mode

Run any app in its own isolated emu instance with its own X11 window:

```bash
./run-app.sh wm/bounce.dis 8    # Run bounce with 8 balls
./run-app.sh wm/clock.dis       # Run clock
```

Each instance creates its own emu process and X11 window, completely isolated from others.

## NixOS Shell Environment

When you enter `nix-shell`, the `shell.nix` provides:

- **Build dependencies**: gcc, make, binutils, X11 libraries, linux headers
- **Helper functions**: Convenience wrappers that run the scripts above
- **Environment**: Sets PATH for mk build tool and emu binaries

The helper functions in shell.nix are simply wrappers around the scripts:
- `build9ferno` → runs `./run.sh` (build portion)
- `run9ferno` → runs `./run.sh`
- `emu` → runs `./run.sh` (with any arguments passed through)

## Running Apps

### Full Window Manager Mode

Run the complete window manager with all apps:

```bash
./run.sh
```

Once emu starts, you'll see the `;` prompt. You can run Limbo programs:

```limbo
# Start the window manager
wm/wm

# List available commands
ls /dis

# Run a program
/wm/bounce.dis 8

# Exit
exit
```

### Isolated App Mode

Run any app in its own isolated emu instance with its own X11 window:

```bash
# Run bouncing balls with 8 balls
./run-app.sh wm/bounce.dis 8

# Run clock
./run-app.sh wm/clock.dis

# Run multiple instances (each in separate terminal)
./run-app.sh wm/bounce.dis 8
./run-app.sh wm/clock.dis
./run-app.sh wm/bounce.dis 16
```

Each instance creates its own emu process and X11 window, completely isolated from others.

#### Creating Your Own App

**Simple Console App** (`hello.b`):

```limbo
implement Hello;

include "sys.m";
    sys: Sys;

Hello: module {
    init: fn(ctxt: ref Draw->Context, argv: list of string);
};

init(ctxt: ref Draw->Context, argv: list of string)
{
    sys = load Sys Sys->PATH;
    sys->print("Hello from TaijiOS!\n");
}
```

Compile and run:
```bash
cd appl/cmd
mk hello.dis
./run-app.sh hello.dis
```

**Simple Tk App** (`mytkapp.b`):

```limbo
implement Mytkapp;

include "sys.m";
    sys: Sys;
include "draw.m";
    draw: Draw;
include "tk.m";
    tk: Tk;

Mytkapp: module {
    init: fn(ctxt: ref Draw->Context, argv: list of string);
};

init(ctxt: ref Draw->Context, argv: list of string)
{
    sys = load Sys Sys->PATH;
    draw = load Draw Draw->PATH;
    tk = load Tk Tk->PATH;

    # Create window
    top := tk->toplevel(ctxt.display, "");

    # Add UI
    tk->cmd(top, "label .l -text {My App}");
    tk->cmd(top, "button .b -text Exit -command {send cmd exit}");
    tk->cmd(top, "pack .l .b");

    # Wait for exit
    cmdch := chan of string;
    tk->namechan(top, cmdch, "cmd");
    <-cmdch;
}
```

## Directory Structure

```
TaijiOS/
├── Linux/amd64/      # Platform-specific binaries
│   ├── bin/          # Built binaries (emu, limbo, etc.)
│   └── lib/          # Libraries
├── dis/              # Compiled Limbo programs (.dis files)
├── appl/             # Limbo application source code
├── module/           # Limbo module definitions
├── emu/              # Inferno emulator source
├── lib*/             # Library source code
├── shell.nix         # NixOS shell environment
├── run.sh            # Universal build/run script (full WM)
└── run-app.sh        # Run isolated app instances
```

## Building from Scratch

If you need to do a complete clean build:

```bash
# In nix-shell on NixOS
mk nuke              # Clean all built files
mk install           # Rebuild everything
```

## Platform Support

TaijiOS runs in two modes:

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

This was a known issue with X11 threading initialization. Fixed in TaijiOS - if you still see crashes:

```bash
# Make sure you have the latest version
git pull

# Rebuild
cd /path/to/TaijiOS
nix-shell
build9ferno
```

### Username warnings

When you see `cd: /usr/username: '/usr/username' does not exist`, this is normal. TaijiOS tries to set up a home directory but falls back gracefully.

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

### App fails to load in isolated mode

```bash
# Build the app first
cd appl/wm  # or wherever the app is
mk bounce.dis

# Then run
./run-app.sh wm/bounce.dis 8
```

### "cannot open display"

```bash
# Make sure X11 is running
echo $DISPLAY

# If empty, set it (Linux)
export DISPLAY=:0
```

## Contributing

TaijiOS welcomes contributions! Please see the source repository for guidelines on submitting patches and bug reports.

## Original Source

Based on Inferno OS Fourth Edition by Vita Nuova Holdings:
- https://inferno-os.org/
- https://github.com/inferno-os/inferno-os

TaijiOS incorporates enhancements from the 9front community:
- https://9front.org/

## License

MIT License (since 2021)

See individual source files for details.

## Acknowledgments

- Bell Labs for the original Inferno operating system
- Vita Nuova Holdings for releasing Inferno as free software
- The 9front community for continued development and improvements
- All contributors to TaijiOS

---

**TaijiOS** - Distributed computing for the modern era.
