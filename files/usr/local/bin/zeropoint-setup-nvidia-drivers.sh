#!/bin/bash
set -e
source /usr/local/bin/zeropoint-common.sh

check_initialized

_log_notice "Starting NVIDIA GPU Driver Installation"

# Check for NVIDIA GPUs
NVIDIA_DEVICES=$(lspci | grep -i nvidia || true)
if [ -z "$NVIDIA_DEVICES" ]; then
    _log_notice "No NVIDIA GPUs detected, skipping NVIDIA setup"
    mark "no-gpu-detected"
    mark_done
    exit 0
fi

_log_notice "NVIDIA GPU(s) detected: $NVIDIA_DEVICES"
mark "gpu-detected"

# Update package lists
_log_notice "Updating package lists..."
apt-get update
mark "apt-updated"

# Add non-free repository for NVIDIA drivers
_log_notice "Enabling non-free repository for NVIDIA drivers..."
sed -i 's/^Components: main.*/Components: main contrib non-free non-free-firmware/' /etc/apt/sources.list.d/debian.sources
apt-get update
mark "non-free-enabled"

# Install linux headers (required for DKMS)
_log_notice "Installing kernel headers for NVIDIA driver compilation..."
apt-get install -y linux-headers-$(uname -r) dkms
mark "kernel-headers-installed"

# Detect and install appropriate NVIDIA driver
_log_notice "Detecting recommended NVIDIA driver..."
apt-get install -y nvidia-detect
RECOMMENDED_DRIVER=$(nvidia-detect 2>/dev/null | grep -oP 'nvidia-driver-\d+' | head -1)

if [ -n "$RECOMMENDED_DRIVER" ]; then
    _log_notice "Installing recommended driver: $RECOMMENDED_DRIVER"
    apt-get install -y "$RECOMMENDED_DRIVER"
else
    _log_notice "Installing latest NVIDIA driver..."
    apt-get install -y nvidia-driver
fi
mark "driver-installed"

# Add NVIDIA container toolkit repository
_log_notice "Adding NVIDIA container toolkit repository..."
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | gpg --dearmor --batch --yes -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
    sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
    tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
apt-get update
mark "toolkit-repo-added"

# Install NVIDIA container toolkit
_log_notice "Installing NVIDIA container toolkit..."
apt-get install -y nvidia-container-toolkit
mark "toolkit-installed"

# Configure Docker to use NVIDIA runtime
_log_notice "Configuring Docker for NVIDIA container support..."
nvidia-ctk runtime configure --runtime=docker
mark "docker-configured"

# Configure containerd for NVIDIA support
_log_notice "Configuring containerd for NVIDIA container support..."
nvidia-ctk runtime configure --runtime=containerd
mark "containerd-configured"

# Mark that driver installation requires reboot
mark_custom "reboot-required"

# Mark service as done before rebooting
mark_done

_log_notice "Driver installation complete - rebooting to activate"

# Reboot to activate the drivers
reboot
