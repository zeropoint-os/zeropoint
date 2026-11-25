#!/bin/bash
set -euo pipefail

# Build a bootable ZeroPoint x86_64 image from an immutable agent release.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/.build"
AGENT_VERSION="${ZEROPOINT_AGENT_VERSION:-2.0.0}"
AGENT_WHEEL="zeropoint_agent-${AGENT_VERSION}-py3-none-any.whl"
AGENT_RELEASE_URL="${ZEROPOINT_AGENT_RELEASE_URL:-https://github.com/zeropoint-os/zeropoint-agent/releases/download/v${AGENT_VERSION}/${AGENT_WHEEL}}"
AGENT_SHA256="${ZEROPOINT_AGENT_SHA256:-2f9187d5bf7ac45421603d275a528dec856e8f0730ce9b2a08ab357d078fe85a}"
AGENT_WHEEL_PATH="$BUILD_DIR/zeropoint-agent/$AGENT_WHEEL"

if [ "$AGENT_SHA256" = "PENDING_RELEASE_SHA256" ]; then
    echo "ERROR: build-image.sh has not been pinned to the released agent wheel checksum" >&2
    exit 1
fi

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR/zeropoint-agent"

curl --fail --location --retry 3 --output "$AGENT_WHEEL_PATH" "$AGENT_RELEASE_URL"
printf '%s  %s\n' "$AGENT_SHA256" "$AGENT_WHEEL_PATH" | sha256sum --check --status

{
    echo "version=$AGENT_VERSION"
    echo "url=$AGENT_RELEASE_URL"
    echo "sha256=$AGENT_SHA256"
} > "$BUILD_DIR/zeropoint-agent/RELEASE.txt"

echo "=== ZeroPoint Agent release ==="
cat "$BUILD_DIR/zeropoint-agent/RELEASE.txt"

echo "=== Generating ZeroPoint boot services ==="
cd "$SCRIPT_DIR"
python3 generate-unit-files.py

echo "=== Building image with pimod ==="
sudo /usr/src/pimod/pimod.sh ./images/Amd64-Debian.Pifile

echo "=== Build complete ==="
find "$SCRIPT_DIR" -maxdepth 1 -type f -name '*.img' -printf '%p\n'
