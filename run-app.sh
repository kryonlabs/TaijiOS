#!/bin/sh
# Universal app launcher for TaijiOS
# Runs any .dis app in an isolated emu instance with its own X11 window
# Usage: ./run-app.sh app.dis [args...]
# Example: ./run-app.sh wm/bounce.dis 8

set -e

# Change to script directory
cd "$(dirname "$0")"

# Parse arguments
if [ $# -lt 1 ]; then
    echo "Usage: $0 <app.dis> [args...]"
    echo ""
    echo "Examples:"
    echo "  $0 wm/bounce.dis 8          # Run bounce with 8 balls"
    echo "  $0 wm/clock.dis             # Run clock"
    echo "  $0 wm/snake.dis             # Run snake game"
    echo ""
    echo "This launches an isolated emu instance with the app."
    echo "Each instance creates its own X11 window on the host."
    exit 1
fi

APPDIS="$1"  # e.g., "wm/bounce.dis"
shift        # Remaining args go to the app

export ROOT="$(pwd)"
export APPNAME="$APPDIS"
export APPDIS

# Determine OS
if [ -f /etc/NIXOS ]; then
    OS="nixos"
elif [ "$(uname)" = "OpenBSD" ]; then
    OS="openbsd"
else
    OS="linux"
fi

echo "=== TaijiOS App Launcher ==="
echo "App: $APPDIS"
echo "Args: $*"
echo "OS: $OS"
echo ""

# Function to build on NixOS
build_nixos() {
    # Determine app directory and name
    APPDIR=$(dirname "$APPDIS")     # e.g., "wm" or "cmd"
    APPBASE=$(basename "$APPDIS" .dis)  # e.g., "bounce" or "hello"

    nix-shell --run "
        export PATH=\"$ROOT/Linux/amd64/bin:$PATH\"
        export ROOT=\"$ROOT\"
        cd \"$ROOT/appl/$APPDIR\"
        if [ ! -f \"$ROOT/dis/$APPDIS\" ]; then
            echo \"Building $APPDIS...\"
            mk $APPBASE.dis || echo 'Build failed, trying anyway...'
        fi
    "
}

# Function to build on OpenBSD
build_openbsd() {
    export SYSTARG=OpenBSD
    export OBJTYPE=amd64
    export ROOT="$(pwd)"

    # Determine app directory and name
    APPDIR=$(dirname "$APPDIS")
    APPBASE=$(basename "$APPDIS" .dis)

    if [ ! -f "$ROOT/dis/$APPDIS" ]; then
        echo "Building $APPDIS..."
        cd "$ROOT/appl/$APPDIR" && mk "$APPBASE.dis" || echo "Build failed, trying anyway..."
    fi
}

# Function to build on generic Linux
build_linux() {
    export PATH="$ROOT/Linux/amd64/bin:$PATH"
    export ROOT="$(pwd)"

    # Determine app directory and name
    APPDIR=$(dirname "$APPDIS")
    APPBASE=$(basename "$APPDIS" .dis)

    if [ ! -f "$ROOT/dis/$APPDIS" ]; then
        echo "Building $APPDIS..."
        cd "$ROOT/appl/$APPDIR" && mk "$APPBASE.dis" || echo "Build failed, trying anyway..."
    fi
}

# Build wminit.dis if needed
build_wminit() {
    case "$OS" in
        nixos)
            nix-shell --run "
                export PATH=\"$ROOT/Linux/amd64/bin:$PATH\"
                export ROOT=\"$ROOT\"
                cd \"$ROOT/appl/cmd\"
                if [ ! -f \"$ROOT/dis/wminit.dis\" ]; then
                    echo \"Building wminit.dis...\"
                    mk wminit.dis
                fi
            "
            ;;
        openbsd)
            if [ ! -f "$ROOT/dis/wminit.dis" ]; then
                echo "Building wminit.dis..."
                cd "$ROOT/appl/cmd" && mk wminit.dis
            fi
            ;;
        linux)
            export PATH="$ROOT/Linux/amd64/bin:$PATH"
            if [ ! -f "$ROOT/dis/wminit.dis" ]; then
                echo "Building wminit.dis..."
                cd "$ROOT/appl/cmd" && mk wminit.dis
            fi
            ;;
    esac
}

# Build the app if needed
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

# Special case for wmclient-based apps (acme, etc.)
# These apps require full WM infrastructure including plumber
# Run them through wm.dis with the app as the initial command
is_wmclient_app() {
    case "$APPDIS" in
        acme.dis|acme/acme.dis|/dis/acme.dis|/dis/acme/acme.dis)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Build wminit or wm depending on app type
if is_wmclient_app; then
    # For wmclient apps, build wm.dis instead of wminit.dis
    build_wminit() {
        case "$OS" in
            nixos)
                nix-shell --run "
                    export PATH=\"$ROOT/Linux/amd64/bin:$PATH\"
                    export ROOT=\"$ROOT\"
                    cd \"$ROOT/appl/wm\"
                    if [ ! -f \"$ROOT/dis/wm.dis\" ]; then
                        echo \"Building wm.dis...\"
                        mk wm.dis
                    fi
                "
                ;;
            openbsd)
                if [ ! -f "$ROOT/dis/wm.dis" ]; then
                    echo "Building wm.dis..."
                    cd "$ROOT/appl/wm" && mk wm.dis
                fi
                ;;
            linux)
                export PATH="$ROOT/Linux/amd64/bin:$PATH"
                if [ ! -f "$ROOT/dis/wm.dis" ]; then
                    echo "Building wm.dis..."
                    cd "$ROOT/appl/wm" && mk wm.dis
                fi
                ;;
        esac
    }
    build_wminit
else
    # For other apps, build wminit.dis
    build_wminit
fi

echo ""
echo "Starting app: $APPDIS"
echo ""

# Set up namespace (same as run.sh)
setup_namespace() {
    ROOT="$1"

    # Create standard system directories
    mkdir -p "$ROOT/tmp"
    mkdir -p "$ROOT/mnt"

    # Create /n network namespace structure
    mkdir -p "$ROOT/n"
    mkdir -p "$ROOT/n/cd"
    mkdir -p "$ROOT/n/client"
    mkdir -p "$ROOT/n/client/chan"
    mkdir -p "$ROOT/n/client/dev"
    mkdir -p "$ROOT/n/disk"
    mkdir -p "$ROOT/n/dist"
    mkdir -p "$ROOT/n/dump"
    mkdir -p "$ROOT/n/ftp"
    mkdir -p "$ROOT/n/gridfs"
    mkdir -p "$ROOT/n/kfs"
    mkdir -p "$ROOT/n/local"
    mkdir -p "$ROOT/n/rdbg"
    mkdir -p "$ROOT/n/registry"
    mkdir -p "$ROOT/n/remote"

    # Create services directories
    mkdir -p "$ROOT/services/logs"

    # Set permissions
    chmod 555 "$ROOT/n"
    chmod 755 "$ROOT/tmp"
    chmod 755 "$ROOT/mnt"
}

setup_namespace "$ROOT"

# Function to run on NixOS
run_nixos() {
    # Build the argument list
    args=""
    for arg in "$@"; do
        args="$args \"$arg\""
    done

    # Export APPDIS so nix-shell can see it
    export APPDIS

    # For wmclient apps (acme), run through wm.dis with the app as initial command
    # This ensures plumber is started via wmsetup before the app runs
    if is_wmclient_app; then
        exec nix-shell --run "
            export PATH=\"$ROOT/Linux/amd64/bin:$PATH\"
            export ROOT=\"$ROOT\"
            cd \"$ROOT\"
            # Run WM with acme as the initial command (wm will start plumber first)
            exec Linux/amd64/bin/emu -r \"$ROOT\" /dis/wm/wm.dis acme $args
        "
    fi

    # For other apps, use wminit as before
    exec nix-shell --run "
        export PATH=\"$ROOT/Linux/amd64/bin:$PATH\"
        export ROOT=\"$ROOT\"
        cd \"$ROOT\"
        exec Linux/amd64/bin/emu -r \"$ROOT\" /dis/wminit.dis \${APPDIS#/dis/} $args
    "
}

# Function to run on OpenBSD
run_openbsd() {
    export PATH="$ROOT/Linux/amd64/bin:$PATH"

    # For wmclient apps (acme), run through wm.dis with the app as initial command
    if is_wmclient_app; then
        exec "$ROOT/Linux/amd64/bin/emu" -r "$ROOT" "/dis/wm/wm.dis" "acme" "$@"
    fi

    # For other apps, use wminit as before
    exec "$ROOT/Linux/amd64/bin/emu" -r "$ROOT" "/dis/wminit.dis" "${APPDIS#/dis/}" "$@"
}

# Function to run on generic Linux
run_linux() {
    export PATH="$ROOT/Linux/amd64/bin:$PATH"

    # For wmclient apps (acme), run through wm.dis with the app as initial command
    if is_wmclient_app; then
        exec "$ROOT/Linux/amd64/bin/emu" -r "$ROOT" "/dis/wm/wm.dis" "acme" "$@"
    fi

    # For other apps, use wminit as before
    exec "$ROOT/Linux/amd64/bin/emu" -r "$ROOT" "/dis/wminit.dis" "${APPDIS#/dis/}" "$@"
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
