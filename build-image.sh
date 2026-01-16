#!/bin/bash
set -e

# Build script for zeropoint-os images
# Supports local agent builds via USE_LOCAL_AGENT_BUILD=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/.build"

# Ensure build directory exists
mkdir -p "$BUILD_DIR"

# Clean up any previous builds
rm -rf "$BUILD_DIR"/*

echo "=== Preparing zeropoint-agent binary ==="

if [ "${USE_LOCAL_AGENT_BUILD:-0}" = "1" ]; then
    echo "Using local zeropoint-agent build..."
    
    LOCAL_AGENT_PATH="$SCRIPT_DIR/zeropoint-agent/bin/zeropoint-agent"
    if [ ! -f "$LOCAL_AGENT_PATH" ]; then
        echo "ERROR: Local agent binary not found at $LOCAL_AGENT_PATH"
        echo "Build the agent first or unset USE_LOCAL_AGENT_BUILD"
        exit 1
    fi
    
    echo "Copying local agent from $LOCAL_AGENT_PATH"
    cp "$LOCAL_AGENT_PATH" "$BUILD_DIR/zeropoint-agent"
    chmod +x "$BUILD_DIR/zeropoint-agent"
    echo "✓ Local agent ready"
else
    echo "Downloading latest zeropoint-agent from GitHub..."
    
    DOWNLOAD_URL="https://github.com/zeropoint-os/zeropoint-agent/releases/latest/download/zeropoint-agent-linux-amd64.tar.gz"
    
    curl -fsSL "$DOWNLOAD_URL" -o "$BUILD_DIR/zeropoint-agent.tar.gz"
    
    # Extract to a temporary directory to avoid naming conflicts
    TEMP_DIR="$BUILD_DIR/temp_extract"
    mkdir -p "$TEMP_DIR"
    tar -xzf "$BUILD_DIR/zeropoint-agent.tar.gz" -C "$TEMP_DIR/"
    rm "$BUILD_DIR/zeropoint-agent.tar.gz"
    
    # Move files from the nested structure to build root
    if [ -d "$TEMP_DIR/zeropoint-agent" ]; then
        # Move the binary file
        mv "$TEMP_DIR/zeropoint-agent/zeropoint-agent" "$BUILD_DIR/"
        # Move the web folder if it exists
        if [ -d "$TEMP_DIR/zeropoint-agent/web" ]; then
            mv "$TEMP_DIR/zeropoint-agent/web" "$BUILD_DIR/"
        fi
    fi
    
    # Clean up temp directory
    rm -rf "$TEMP_DIR"
    
    chmod +x "$BUILD_DIR/zeropoint-agent"
    echo "✓ GitHub release agent ready"
fi

# Show version
AGENT_VERSION=$("$BUILD_DIR/zeropoint-agent" --version 2>/dev/null || echo "unknown")
echo "Agent version: $AGENT_VERSION"

echo "=== Generating zeropoint boot services ==="
python3 generate-unit-files.py

echo ""
echo "=== Building image with pimod ==="

# Run pimod with the Pifile
cd "$SCRIPT_DIR"
sudo /usr/src/pimod/pimod.sh ./images/Amd64-Debian.Pifile

echo ""
echo "=== Build complete ==="
