#!/bin/bash
export DEBIAN_FRONTEND=noninteractive

logger -t zeropoint-agent-update "=== Zeropoint Agent Update Check ==="

CURRENT_VERSION=$(/usr/local/bin/zeropoint-agent --version 2>/dev/null || echo "unknown")
logger -t zeropoint-agent-update "Current version: $CURRENT_VERSION"

logger -t zeropoint-agent-update "Checking for latest release..."
DOWNLOAD_URL="https://github.com/zeropoint-os/zeropoint-agent/releases/latest/download/zeropoint-agent-linux-amd64.tar.gz"

# Download to temp location
logger -t zeropoint-agent-update "Downloading latest agent..."
if ! curl -fsSL "$DOWNLOAD_URL" -o /tmp/zeropoint-agent-new.tar.gz; then
    logger -t zeropoint-agent-update "ERROR: Failed to download agent update"
    rm -f /tmp/zeropoint-agent-new.tar.gz
    exit 0  # Non-fatal, continue boot
fi

# Verify it's a valid gzip file
if ! file /tmp/zeropoint-agent-new.tar.gz | grep -q "gzip compressed"; then
    logger -t zeropoint-agent-update "ERROR: Downloaded file is not a valid gzip archive"
    cat /tmp/zeropoint-agent-new.tar.gz
    rm -f /tmp/zeropoint-agent-new.tar.gz
    exit 0  # Non-fatal, continue boot
fi

# Extract to temp location
logger -t zeropoint-agent-update "Extracting agent archive..."
if ! tar -xzf /tmp/zeropoint-agent-new.tar.gz -C /tmp/; then
    logger -t zeropoint-agent-update "ERROR: Failed to extract agent archive"
    rm -f /tmp/zeropoint-agent-new.tar.gz
    exit 0  # Non-fatal, continue boot
fi

# Handle nested directory structure from GitHub releases
if [ -d /tmp/zeropoint-agent ]; then
    # GitHub release has nested structure: zeropoint-agent/zeropoint-agent
    AGENT_BINARY="/tmp/zeropoint-agent/zeropoint-agent"
    WEB_DIR="/tmp/zeropoint-agent/web"
else
    # Direct binary extraction (fallback)
    AGENT_BINARY="/tmp/zeropoint-agent"
    WEB_DIR="/tmp/web"
fi

if [ ! -f "$AGENT_BINARY" ]; then
    logger -t zeropoint-agent-update "ERROR: Agent binary not found in extracted archive"
    rm -rf /tmp/zeropoint-agent* /tmp/web /tmp/zeropoint-agent-new.tar.gz
    exit 0  # Non-fatal, continue boot
fi

chmod +x "$AGENT_BINARY"

# Check new version
NEW_VERSION=$("$AGENT_BINARY" --version 2>/dev/null || echo "unknown")
logger -t zeropoint-agent-update "Latest version: $NEW_VERSION"

# Don't update if we can't determine the new version
if [ "$NEW_VERSION" = "unknown" ]; then
    logger -t zeropoint-agent-update "ERROR: Cannot determine version of downloaded agent, skipping update for safety"
    rm -rf /tmp/zeropoint-agent* /tmp/web /tmp/zeropoint-agent-new.tar.gz
    exit 0
fi

if [ "$CURRENT_VERSION" = "$NEW_VERSION" ]; then
    logger -t zeropoint-agent-update "Already running latest version, no update needed"
    rm -rf /tmp/zeropoint-agent* /tmp/web /tmp/zeropoint-agent-new.tar.gz
    exit 0
fi

logger -t zeropoint-agent-update "Updating agent from $CURRENT_VERSION to $NEW_VERSION..."

# Stop the agent service if running
systemctl stop zeropoint-agent.service || true

# Replace binary and web folder
mv "$AGENT_BINARY" /usr/local/bin/zeropoint-agent
# Copy web folder if it exists
if [ -d "$WEB_DIR" ]; then
    rm -rf /usr/local/bin/web
    mv "$WEB_DIR" /usr/local/bin/web
fi
chmod +x /usr/local/bin/zeropoint-agent

# Cleanup
rm -f /tmp/zeropoint-agent-new.tar.gz
rm -rf /tmp/zeropoint-agent*

logger -t zeropoint-agent-update "=== Agent updated successfully ==="
logger -t zeropoint-agent-update "New version: $NEW_VERSION"