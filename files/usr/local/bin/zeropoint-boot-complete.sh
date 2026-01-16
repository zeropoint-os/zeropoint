#!/bin/bash
set -e
source /usr/local/bin/zeropoint-common.sh

check_initialized

logger -t zeropoint-boot "=== Zeropoint Boot Process Complete ==="

# Create global boot completion marker
mkdir -p /etc/zeropoint
echo "$(date -Iseconds)" > /etc/zeropoint/.boot-complete
mark "global-boot-complete"

# Log system readiness
UPTIME=$(uptime -p)
HOSTNAME=$(hostname)
MEMORY=$(free -h | awk '/^Mem:/ {print $2}')
DISK_USAGE=$(df -h / | awk 'NR==2 {print $3 "/" $2 " (" $5 ")"}')

logger -t zeropoint-boot "System ready: $HOSTNAME"
logger -t zeropoint-boot "Uptime: $UPTIME, Memory: $MEMORY, Root disk: $DISK_USAGE"
mark "system-status-logged"

mark_done

logger -t zeropoint-boot "=== All Zeropoint services initialized ==="