#!/bin/bash
set -e
source /usr/local/bin/zeropoint-common.sh

check_initialized

STORAGE_MARKER="/etc/zeropoint/.zeropoint-setup-storage"

logger -t zeropoint-apt-storage "=== Configuring Apt Storage ==="

# Only configure if storage service succeeded
if [ ! -f "$STORAGE_MARKER" ]; then
    logger -t zeropoint-apt-storage "Storage service not completed, skipping apt storage configuration"
    mark "storage-not-initialized"
    mark_done
    exit 0
fi

# Check for manual storage mode
if [ -f "/etc/zeropoint/.storage-manual-mode" ]; then
    logger -t zeropoint-apt-storage "Manual storage mode detected - skipping automatic apt storage configuration"
    mark "manual-storage-mode"
    mark_done
    exit 0
fi

# Check if we have the NVMe storage mounted
if ! mountpoint -q /var/lib/zeropoint; then
    logger -t zeropoint-apt-storage "NVMe storage not mounted, using default apt configuration"
    mark "storage-not-mounted"
    mark_done
    exit 0
fi

logger -t zeropoint-apt-storage "Configuring apt to use NVMe storage for downloads and cache..."

# Configure apt to use NVMe storage
echo 'Dir::Cache::archives "/var/lib/zeropoint/apt/archives";' > /etc/apt/apt.conf.d/01-zeropoint-cache
echo 'Dir::Cache "/var/lib/zeropoint/apt/cache";' >> /etc/apt/apt.conf.d/01-zeropoint-cache
mark "apt-config-written"

# Create the directories
mkdir -p /var/lib/zeropoint/apt/archives/partial
mkdir -p /var/lib/zeropoint/apt/cache
mkdir -p /var/lib/zeropoint/tmp
mark "directories-created"

# Set permissions
chown -R _apt:root /var/lib/zeropoint/apt/
chmod 755 /var/lib/zeropoint/apt/archives/partial
mark "permissions-set"

# Clean up existing cache to free root filesystem space
apt clean
apt autoremove -y --purge
apt autoclean
mark "cache-cleaned"

logger -t zeropoint-apt-storage "✓ Apt configured to use NVMe storage - Cache: /var/lib/zeropoint/apt/cache, Archives: /var/lib/zeropoint/apt/archives"

# Mark complete
mark_done

logger -t zeropoint-apt-storage "=== Apt storage configuration complete ==="