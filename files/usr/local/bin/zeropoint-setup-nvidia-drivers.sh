#!/bin/bash
set -e
source /usr/local/bin/zeropoint-common.sh

check_initialized

logger -t zeropoint-nvidia-drivers "=== Starting NVIDIA GPU Driver Installation ==="

# Check for NVIDIA GPUs
NVIDIA_DEVICES=$(lspci | grep -i nvidia || true)
if [ -z "$NVIDIA_DEVICES" ]; then
    logger -t zeropoint-nvidia-drivers "No NVIDIA GPUs detected, skipping NVIDIA setup"
    mark "no-gpu-detected"
    mark_done
    exit 0
fi

logger -t zeropoint-nvidia-drivers "NVIDIA GPU(s) detected: $NVIDIA_DEVICES"
mark "gpu-detected"

# Update package lists
logger -t zeropoint-nvidia-drivers "Updating package lists..."
apt-get update
mark "apt-updated"

# Add non-free repository for NVIDIA drivers
logger -t zeropoint-nvidia-drivers "Enabling non-free repository for NVIDIA drivers..."
sed -i 's/^Components: main.*/Components: main contrib non-free non-free-firmware/' /etc/apt/sources.list.d/debian.sources
apt-get update
mark "non-free-enabled"

# Install linux headers (required for DKMS)
logger -t zeropoint-nvidia-drivers "Installing kernel headers for NVIDIA driver compilation..."
apt-get install -y linux-headers-$(uname -r) dkms
mark "kernel-headers-installed"

# Detect and install appropriate NVIDIA driver
logger -t zeropoint-nvidia-drivers "Detecting recommended NVIDIA driver..."
apt-get install -y nvidia-detect
RECOMMENDED_DRIVER=$(nvidia-detect 2>/dev/null | grep -oP 'nvidia-driver-\d+' | head -1)

if [ -n "$RECOMMENDED_DRIVER" ]; then
    logger -t zeropoint-nvidia-drivers "Installing recommended driver: $RECOMMENDED_DRIVER"
    apt-get install -y "$RECOMMENDED_DRIVER"
else
    logger -t zeropoint-nvidia-drivers "Installing latest NVIDIA driver..."
    apt-get install -y nvidia-driver
fi
mark "driver-installed"

# Add NVIDIA container toolkit repository
logger -t zeropoint-nvidia-drivers "Adding NVIDIA container toolkit repository..."
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | gpg --dearmor --batch --yes -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
    sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
    tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
apt-get update
mark "toolkit-repo-added"

# Install NVIDIA container toolkit
logger -t zeropoint-nvidia-drivers "Installing NVIDIA container toolkit..."
apt-get install -y nvidia-container-toolkit
mark "toolkit-installed"

# Configure Docker to use NVIDIA runtime
logger -t zeropoint-nvidia-drivers "Configuring Docker for NVIDIA container support..."
nvidia-ctk runtime configure --runtime=docker
mark "docker-configured"

# Configure containerd for NVIDIA support
logger -t zeropoint-nvidia-drivers "Configuring containerd for NVIDIA container support..."
nvidia-ctk runtime configure --runtime=containerd
mark "containerd-configured"

# Mark that driver installation requires reboot
mark_custom "reboot-required"

# Mark service as done before rebooting
mark_done

logger -t zeropoint-nvidia-drivers "=== Driver installation complete - rebooting to activate ==="

# Reboot to activate the drivers
reboot
