#!/bin/bash
set -e
source /usr/local/bin/zeropoint-common.sh

check_initialized

logger -t zeropoint-rootfs "=== Starting Root Filesystem Expansion ==="

# Detect root device and partition
ROOT_DEV=$(findmnt -n -o SOURCE /)
if [ -z "$ROOT_DEV" ]; then
    logger -t zeropoint-rootfs "ERROR: Could not detect root device"
    mark "root-device-detection-failed"
    exit 1
fi

logger -t zeropoint-rootfs "Detected root device: $ROOT_DEV"

# Extract device name and partition number (e.g. /dev/sdb1 -> /dev/sdb and 1)
if [[ "$ROOT_DEV" =~ ^(.+[^0-9])([0-9]+)$ ]]; then
    DEVICE="${BASH_REMATCH[1]}"
    PARTITION="${BASH_REMATCH[2]}"
else
    logger -t zeropoint-rootfs "ERROR: Could not parse device and partition from $ROOT_DEV"
    mark "device-parsing-failed"
    exit 1
fi

logger -t zeropoint-rootfs "Device: $DEVICE, Partition: $PARTITION"
mark "device-detected"

# Attempt to expand the partition using growpart
# growpart is provided by cloud-utils and works on nearly all systems
logger -t zeropoint-rootfs "Attempting to expand partition $PARTITION on device $DEVICE..."

growpart "$DEVICE" "$PARTITION" 2>&1 | tee /tmp/growpart.log
GROWPART_EXIT=$?

# Handle growpart result
if [ $GROWPART_EXIT -ne 0 ]; then
    if grep -q "NOCHANGE" /tmp/growpart.log; then
        logger -t zeropoint-rootfs "Partition already uses full device space - no expansion needed"
        mark_done
        exit 0
    else
        logger -t zeropoint-rootfs "ERROR: Failed to expand partition with growpart"
        mark "partition-expansion-failed"
        exit 1
    fi
fi

logger -t zeropoint-rootfs "Partition expanded successfully using growpart"
mark "partition-expanded"

# Expand the filesystem
logger -t zeropoint-rootfs "Expanding filesystem on $ROOT_DEV"

if resize2fs "$ROOT_DEV"; then
    logger -t zeropoint-rootfs "Filesystem expanded successfully"
else
    logger -t zeropoint-rootfs "ERROR: Failed to expand filesystem"
    mark "filesystem-expansion-failed"
    exit 1
fi

# Check new size
NEW_SIZE=$(df -h "$ROOT_DEV" | awk 'NR==2 {print $2}')
logger -t zeropoint-rootfs "Root filesystem expanded to: $NEW_SIZE"
mark "filesystem-expanded"

# Create completion marker and done
mark_done
logger -t zeropoint-rootfs "=== Root Filesystem Expansion Complete ==="