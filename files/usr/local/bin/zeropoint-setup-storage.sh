#!/bin/bash
set -e

STORAGE_ROOT="/var/lib/zeropoint"
MARKER_FILE="/var/lib/zeropoint/.storage-initialized"

# Check for manual storage mode
if [ -f "/boot/NO_STORAGE_SETUP" ]; then
    logger -t zeropoint-storage "Manual storage mode detected - skipping automatic storage setup"
    
    # Create basic directory structure on boot device
    mkdir -p "$STORAGE_ROOT"
    echo "MODULE_STORAGE_ROOT=$STORAGE_ROOT" > /etc/zeropoint.env
    
    # Create manual mode markers
    mkdir -p /var/lib/zeropoint
    touch "/var/lib/zeropoint/.storage-manual-mode"
    touch "$MARKER_FILE"
    
    logger -t zeropoint-storage "Manual storage mode initialized - use zeropoint-agent UI to configure storage"
    exit 0
fi

# Exit if already initialized
if [ -f "$MARKER_FILE" ]; then
    logger -t zeropoint-storage "Storage already initialized, skipping..."
    exit 0
fi

logger -t zeropoint-storage "=== Zeropoint Storage Setup ==="
logger -t zeropoint-storage "Searching for available storage devices..."

# Get the boot device (the device mounted at /)
BOOT_DEVICE=$(findmnt -n -o SOURCE / | sed 's/[0-9]*$//' | sed 's|/dev/||')
logger -t zeropoint-storage "Boot device: $BOOT_DEVICE (will be excluded)"

# Find all non-removable disks that are not the boot device and have no partitions
AVAILABLE_DISKS=$(lsblk -nd -o NAME,TYPE,RM,SIZE --bytes | \
    awk '$2=="disk" && $3==0' | \
    grep -v "^${BOOT_DEVICE}" | \
    awk '{print $1}' || true)

if [ -z "$AVAILABLE_DISKS" ]; then
    logger -t zeropoint-storage "WARNING: No additional storage devices found!"
    logger -t zeropoint-storage "Creating storage directory on boot device (limited space)"
    mkdir -p "$STORAGE_ROOT"
    echo "MODULE_STORAGE_ROOT=$STORAGE_ROOT" > /etc/zeropoint.env
    
    # Create intermediate marker
    mkdir -p /var/lib/zeropoint
    touch "/var/lib/zeropoint/.storage-no-disks-found"
    
    # Configure Docker to use boot device storage (fallback)
    mkdir -p /etc/docker
    cat > /etc/docker/daemon.json << DOCKEREOF
{
  "data-root": "$STORAGE_ROOT/docker"
}
DOCKEREOF
    
    # Configure containerd to use boot device storage (fallback)
    mkdir -p /etc/containerd
    cat > /etc/containerd/config.toml << CONTAINERDEOF
version = 2
root = "$STORAGE_ROOT/containerd"
state = "/run/containerd"
CONTAINERDEOF
    
    touch "$MARKER_FILE"
    exit 0
fi

logger -t zeropoint-storage "Available disks:"
logger -t zeropoint-storage "$AVAILABLE_DISKS"

# Find the largest disk (Option A: single disk strategy)
# TODO: When switching to mergerfs, iterate over all disks instead
LARGEST_DISK=$(echo "$AVAILABLE_DISKS" | while read disk; do
    SIZE=$(lsblk -bdn -o SIZE /dev/$disk)
    echo "$SIZE $disk"
done | sort -rn | head -1 | awk '{print $2}')

if [ -z "$LARGEST_DISK" ]; then
    logger -t zeropoint-storage "ERROR: Could not determine largest disk"
    exit 1
fi

DISK_SIZE=$(lsblk -bdn -o SIZE /dev/$LARGEST_DISK | awk '{printf "%.2f GB", $1/1024/1024/1024}')
logger -t zeropoint-storage "Selected largest disk: /dev/$LARGEST_DISK ($DISK_SIZE)"

# Check if disk has actual partitions (count lines with 'part' type)
PART_COUNT=$(lsblk -n -o TYPE /dev/$LARGEST_DISK | grep -c '^part$' || true)
if [ "$PART_COUNT" -gt 0 ]; then
    logger -t zeropoint-storage "WARNING: /dev/$LARGEST_DISK has $PART_COUNT existing partitions, skipping format for safety"
    logger -t zeropoint-storage "Creating storage directory on boot device (limited space)"
    mkdir -p "$STORAGE_ROOT"
    echo "MODULE_STORAGE_ROOT=$STORAGE_ROOT" > /etc/zeropoint.env
    
    # Create intermediate marker
    mkdir -p /var/lib/zeropoint
    touch "/var/lib/zeropoint/.storage-partitions-detected"
    
    # Configure Docker to use boot device storage (fallback)
    mkdir -p /etc/docker
    cat > /etc/docker/daemon.json << DOCKEREOF
{
  "data-root": "$STORAGE_ROOT/docker"
}
DOCKEREOF
    
    # Configure containerd to use boot device storage (fallback)
    mkdir -p /etc/containerd
    cat > /etc/containerd/config.toml << CONTAINERDEOF
version = 2
root = "$STORAGE_ROOT/containerd"
state = "/run/containerd"
CONTAINERDEOF
    
    touch "$MARKER_FILE"
    exit 0
fi

# Format and mount the disk
logger -t zeropoint-storage "Formatting /dev/$LARGEST_DISK as ext4..."
mkfs.ext4 -F -L zeropoint-storage /dev/$LARGEST_DISK

logger -t zeropoint-storage "Creating mount point at $STORAGE_ROOT..."
mkdir -p "$STORAGE_ROOT"

logger -t zeropoint-storage "Mounting /dev/$LARGEST_DISK to $STORAGE_ROOT..."
mount /dev/$LARGEST_DISK "$STORAGE_ROOT"

# Add to fstab for persistence
logger -t zeropoint-storage "Adding mount to /etc/fstab..."
DISK_UUID=$(blkid -s UUID -o value /dev/$LARGEST_DISK)
echo "UUID=$DISK_UUID $STORAGE_ROOT ext4 defaults,nofail 0 2" >> /etc/fstab

# Set environment variable
echo "MODULE_STORAGE_ROOT=$STORAGE_ROOT" > /etc/zeropoint.env

# Configure Docker to use the HDD storage
logger -t zeropoint-storage "Configuring Docker data-root..."
mkdir -p /etc/docker
cat > /etc/docker/daemon.json << DOCKEREOF
{
  "data-root": "$STORAGE_ROOT/docker"
}
DOCKEREOF

# Configure containerd to use the HDD storage
logger -t zeropoint-storage "Configuring containerd root..."
mkdir -p /etc/containerd
cat > /etc/containerd/config.toml << CONTAINERDEOF
version = 2
root = "$STORAGE_ROOT/containerd"
state = "/run/containerd"
CONTAINERDEOF

# Create marker file
mkdir -p /var/lib/zeropoint
touch "$MARKER_FILE"

logger -t zeropoint-storage "=== Storage setup complete ==="
logger -t zeropoint-storage "Storage root: $STORAGE_ROOT"
logger -t zeropoint-storage "Docker data-root: $STORAGE_ROOT/docker"
logger -t zeropoint-storage "Disk: /dev/$LARGEST_DISK ($DISK_SIZE)"

# Ensure Docker picks up the new configuration on first start
# Since this service runs Before=docker.service, Docker will read the config when it starts