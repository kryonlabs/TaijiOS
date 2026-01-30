# Makefile wrapper for taiji
# Provides convenient targets for building and running

.PHONY: all build run clean help emu nuke

# Default target
all: build

# Build taiji
build:
	@echo "Building TaijiOS..."
	@if [ -f /etc/NIXOS ]; then \
		nix-shell --run 'export PATH="$$PWD/Linux/amd64/bin:$$PATH"; mk install'; \
	else \
		export PATH="$$PWD/Linux/amd64/bin:$$PATH"; \
		mk install; \
	fi

# Run emu
run:
	@echo "Starting Inferno emulator..."
	@if [ -f /etc/NIXOS ]; then \
		nix-shell --run 'export ROOT="$$PWD"; export PATH="$$ROOT/Linux/amd64/bin:$$PATH"; exec $$ROOT/Linux/amd64/bin/emu -r $$ROOT'; \
	else \
		export ROOT="$$PWD"; \
		export PATH="$$ROOT/Linux/amd64/bin:$$PATH"; \
		exec $$ROOT/Linux/amd64/bin/emu -r $$ROOT; \
	fi

# Run emu (alias)
emu: run

# Clean build artifacts
clean:
	@echo "Cleaning build artifacts..."
	@export PATH="$$PWD/Linux/amd64/bin:$$PATH"; export ROOT="$$PWD"; \
	mk clean

# Complete rebuild
nuke:
	@echo "Removing all built files..."
	@export PATH="$$PWD/Linux/amd64/bin:$$PATH"; export ROOT="$$PWD"; \
	mk nuke

# Show help
help:
	@echo "TaijiOS Makefile targets:"
	@echo ""
	@echo "  make build   - Build TaijiOS (or use: ./run.sh)"
	@echo "  make run     - Run Inferno emulator (or use: ./run.sh)"
	@echo "  make emu     - Alias for 'make run'"
	@echo "  make clean   - Clean build artifacts"
	@echo "  make nuke    - Remove all built files"
	@echo "  make help    - Show this help message"
	@echo ""
	@echo "Quick start:"
	@echo "  On NixOS:     nix-shell"
	@echo "  Any system:   ./run.sh"
	@echo ""
