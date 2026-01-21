{ pkgs ? import <nixpkgs> {} }:

pkgs.mkShell {
  buildInputs = with pkgs; [
    # Core build tools
    gcc
    gnumake
    binutils

    # X11 for graphics support (optional but useful)
    xorg.libX11
    xorg.libXext

    # Utilities
    coreutils
    bash
    perl

    # For building emu (Inferno emulator)
    linuxHeaders

    # Debugging tools
    gdb
    valgrind
  ];

  # Set environment variables for the build
  shellHook = ''
    echo "Welcome to LimboOS (Inferno OS amd64) build environment"

    # Find the LimboOS root directory by looking for mkfile
    if [ -f mkfile ] && [ -d emu ] && [ -d lib ]; then
      ROOT="$(pwd)"
    elif [ -f ./LimboOS/mkfile ] && [ -d ./LimboOS/emu ]; then
      ROOT="$(pwd)/LimboOS"
    else
      echo "Warning: Cannot find LimboOS root directory. Please run from the LimboOS directory."
      ROOT="$(pwd)"
    fi
    export ROOT
    echo "LimboOS root: $ROOT"
    echo "Current directory: $(pwd)"
    echo ""
    echo "Quick start:"
    echo "  build9ferno    - Build LimboOS"
    echo "  run9ferno      - Run emu (Inferno emulator)"
    echo "  emu            - Run emu directly"
    echo ""

    # Set PATH for LimboOS tools
    # Include utils/mk for the mk build tool, and Linux/amd64/bin for built binaries
    export PATH="$ROOT/utils/mk:$ROOT/Linux/amd64/bin:$PATH"

    # Add X11 library paths to linker search path
    export LD_LIBRARY_PATH="${pkgs.xorg.libX11}/lib:${pkgs.xorg.libXext}/lib:$LD_LIBRARY_PATH"
    export LIBRARY_PATH="${pkgs.xorg.libX11}/lib:${pkgs.xorg.libXext}/lib:$LIBRARY_PATH"

    # Helper function to build
    build9ferno() {
      echo "Building LimboOS..."
      cd "$ROOT"

      # Set LDFLAGS to help find X11 libraries
      export LDFLAGS="-L${pkgs.xorg.libX11}/lib -L${pkgs.xorg.libXext}/lib $LDFLAGS"

      # Ensure mk can find its configuration
      export SYSHOST=Linux
      export SYSTARG=Linux
      export OBJTYPE=amd64
      export SHELLTYPE=sh

      # Use mk from utils/mk explicitly if needed
      mk install
    }

    # Helper function to run emu
    run9ferno() {
      echo "Starting LimboOS (Inferno emulator)..."
      echo "Type 'exit' or Ctrl+D to quit"
      echo ""
      cd "$ROOT" || exit 1
      exec "$ROOT/Linux/amd64/bin/emu" -r "$ROOT" "$@"
    }

    # Alias for direct emu access
    emu() {
      run9ferno "$@"
    }
  '';

  # Hardening disabled for Inferno (it has its own build system)
  hardeningDisable = [ "all" ];
}
