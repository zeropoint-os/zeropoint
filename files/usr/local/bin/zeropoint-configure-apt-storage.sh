#!/bin/bash
set -e

MARKER_FILE="/var/lib/zeropoint/.apt-storage-configured"
STORAGE_MARKER="/var/lib/zeropoint/.storage-initialized"

# Exit if already configured
if [ -f "$MARKER_FILE" ]; then
    logger -t zeropoint-apt-storage "Apt storage already configured, skipping..."
    exit 0
fi

logger -t zeropoint-apt-storage "=== Configuring Apt Storage ==="

# Only configure if storage service succeeded
if [ ! -f "$STORAGE_MARKER" ]; then
    logger -t zeropoint-apt-storage "Storage service not completed, skipping apt storage configuration"
    exit 0
fi

# Check for manual storage mode
if [ -f "/var/lib/zeropoint/.storage-manual-mode" ]; then
    logger -t zeropoint-apt-storage "Manual storage mode detected - skipping automatic apt storage configuration"
    mkdir -p /var/lib/zeropoint
    touch "/var/lib/zeropoint/.apt-storage-manual-mode"
    touch "$MARKER_FILE"
    exit 0
fi

# Check if we have the NVMe storage mounted
if ! mountpoint -q /var/lib/zeropoint; then
    logger -t zeropoint-apt-storage "NVMe storage not mounted, using default apt configuration"
    mkdir -p /var/lib/zeropoint
    touch "/var/lib/zeropoint/.apt-storage-skipped"
    touch "$MARKER_FILE"
    exit 0
fi

logger -t zeropoint-apt-storage "Configuring apt to use NVMe storage for downloads and cache..."

# Configure apt to use NVMe storage
echo 'Dir::Cache::archives "/var/lib/zeropoint/apt/archives";' > /etc/apt/apt.conf.d/01-zeropoint-cache
echo 'Dir::Cache "/var/lib/zeropoint/apt/cache";' >> /etc/apt/apt.conf.d/01-zeropoint-cache

# Create the directories
mkdir -p /var/lib/zeropoint/apt/archives/partial
mkdir -p /var/lib/zeropoint/apt/cache
mkdir -p /var/lib/zeropoint/tmp

# Set permissions
chown -R _apt:root /var/lib/zeropoint/apt/
chmod 755 /var/lib/zeropoint/apt/archives/partial

# Clean up existing cache to free root filesystem space
apt clean
apt autoremove -y --purge
apt autoclean

logger -t zeropoint-apt-storage "✓ Apt configured to use NVMe storage - Cache: /var/lib/zeropoint/apt/cache, Archives: /var/lib/zeropoint/apt/archives"

# Create marker file
touch "$MARKER_FILE"

logger -t zeropoint-apt-storage "=== Apt storage configuration complete ==="