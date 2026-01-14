#!/bin/bash
set -e

MARKER_FILE="/var/lib/zeropoint/.nvidia-initialized"

# Exit if already initialized
if [ -f "$MARKER_FILE" ]; then
    logger -t zeropoint-nvidia "NVIDIA setup already completed, skipping..."
    exit 0
fi

logger -t zeropoint-nvidia "=== Starting NVIDIA GPU Setup ==="

# Check for NVIDIA GPUs
NVIDIA_DEVICES=$(lspci | grep -i nvidia || true)
if [ -z "$NVIDIA_DEVICES" ]; then
    logger -t zeropoint-nvidia "No NVIDIA GPUs detected, skipping NVIDIA setup"
    mkdir -p /var/lib/zeropoint
    touch "/var/lib/zeropoint/.nvidia-not-detected"
    touch "$MARKER_FILE"
    exit 0
fi

logger -t zeropoint-nvidia "NVIDIA GPU(s) detected: $NVIDIA_DEVICES"

# Update package lists
logger -t zeropoint-nvidia "Updating package lists..."
apt-get update

# Add non-free repository for NVIDIA drivers
logger -t zeropoint-nvidia "Enabling non-free repository for NVIDIA drivers..."
# Update the new Debian sources format to include non-free
sed -i 's/^Components: main.*/Components: main contrib non-free non-free-firmware/' /etc/apt/sources.list.d/debian.sources
apt-get update

# Install linux headers (required for DKMS)
logger -t zeropoint-nvidia "Installing kernel headers for NVIDIA driver compilation..."
apt-get install -y linux-headers-$(uname -r) dkms

# Detect and install appropriate NVIDIA driver
logger -t zeropoint-nvidia "Installing NVIDIA drivers..."
apt-get install -y nvidia-detect
RECOMMENDED_DRIVER=$(nvidia-detect 2>/dev/null | grep -oP 'nvidia-driver-\d+' | head -1)

if [ -n "$RECOMMENDED_DRIVER" ]; then
    logger -t zeropoint-nvidia "Installing recommended driver: $RECOMMENDED_DRIVER"
    apt-get install -y "$RECOMMENDED_DRIVER"
else
    logger -t zeropoint-nvidia "Installing latest NVIDIA driver..."
    apt-get install -y nvidia-driver
fi

# Add NVIDIA container toolkit repository
logger -t zeropoint-nvidia "Adding NVIDIA container toolkit repository..."
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
    sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
    tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

apt-get update

# Install NVIDIA container toolkit
logger -t zeropoint-nvidia "Installing NVIDIA container toolkit..."
apt-get install -y nvidia-container-toolkit

# Configure Docker to use NVIDIA runtime
logger -t zeropoint-nvidia "Configuring Docker for NVIDIA container support..."
nvidia-ctk runtime configure --runtime=docker

# Configure containerd for NVIDIA support
logger -t zeropoint-nvidia "Configuring containerd for NVIDIA container support..."
nvidia-ctk runtime configure --runtime=containerd

# Restart container services to pick up new configuration
logger -t zeropoint-nvidia "Restarting container services..."
systemctl restart docker
systemctl restart containerd

# Test NVIDIA runtime availability
logger -t zeropoint-nvidia "Testing NVIDIA runtime installation..."
if nvidia-smi > /dev/null 2>&1; then
    DRIVER_VERSION=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader,nounits | head -1)
    logger -t zeropoint-nvidia "✓ NVIDIA Driver version: $DRIVER_VERSION - GPU ready"
else
    logger -t zeropoint-nvidia "⚠ nvidia-smi not available yet - reboot required for driver activation"
fi

# Create marker files
mkdir -p /var/lib/zeropoint
touch "/var/lib/zeropoint/.nvidia-driver-installed"
touch "$MARKER_FILE"

logger -t zeropoint-nvidia "=== NVIDIA setup complete - rebooting to activate drivers ==="

# Reboot to activate the drivers
reboot