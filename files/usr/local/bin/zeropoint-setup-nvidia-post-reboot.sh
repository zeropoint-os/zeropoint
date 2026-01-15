#!/bin/bash
set -e
source /usr/local/bin/zeropoint-common.sh

check_initialized

PENDING_MARKER="/etc/zeropoint/.zeropoint-setup-nvidia-drivers.driver-install-pending-reboot"

logger -t zeropoint-nvidia-post "=== Starting NVIDIA GPU Post-Reboot Verification ==="

# Check if we have the pending-reboot marker from the driver installation
if [ ! -f "$PENDING_MARKER" ]; then
    logger -t zeropoint-nvidia-post "Driver installation not yet complete, skipping verification"
    exit 0
fi

logger -t zeropoint-nvidia-post "Driver installation pending reboot marker found - verifying installation..."
mark "verification-started"

# Restart container services to pick up new configuration
logger -t zeropoint-nvidia-post "Restarting Docker and containerd..."
systemctl restart docker containerd || true
mark "services-restarted"

# Wait for nvidia-smi to become available (kernel module loading)
logger -t zeropoint-nvidia-post "Waiting for NVIDIA drivers to activate..."
MAX_ATTEMPTS=30
ATTEMPT=0
while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
    if nvidia-smi > /dev/null 2>&1; then
        DRIVER_VERSION=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader,nounits | head -1)
        logger -t zeropoint-nvidia-post "✓ NVIDIA Driver version: $DRIVER_VERSION - GPU ready"
        mark "driver-verified"
        break
    fi
    ATTEMPT=$((ATTEMPT + 1))
    logger -t zeropoint-nvidia-post "Waiting for nvidia-smi (attempt $ATTEMPT/$MAX_ATTEMPTS)..."
    sleep 1
done

if [ $ATTEMPT -eq $MAX_ATTEMPTS ]; then
    logger -t zeropoint-nvidia-post "⚠ nvidia-smi still not available after $MAX_ATTEMPTS seconds"
    logger -t zeropoint-nvidia-post "GPU drivers may require additional kernel configuration"
fi

# Test NVIDIA container runtime on Docker
logger -t zeropoint-nvidia-post "Testing NVIDIA container runtime on Docker..."
if docker run --rm --gpus all nvidia/cuda:12.0.0-runtime-ubuntu22.04 nvidia-smi > /dev/null 2>&1; then
    logger -t zeropoint-nvidia-post "✓ Docker NVIDIA runtime working"
    mark "docker-runtime-verified"
else
    logger -t zeropoint-nvidia-post "⚠ Docker NVIDIA runtime test failed or GPU unavailable"
    mark "docker-runtime-test-failed"
fi

# Test NVIDIA container runtime on containerd
logger -t zeropoint-nvidia-post "Testing NVIDIA container runtime on containerd..."
if ctr run --rm --gpus all docker.io/nvidia/cuda:12.0.0-runtime-ubuntu22.04 test-nvidia nvidia-smi > /dev/null 2>&1; then
    logger -t zeropoint-nvidia-post "✓ containerd NVIDIA runtime working"
    mark "containerd-runtime-verified"
else
    logger -t zeropoint-nvidia-post "⚠ containerd NVIDIA runtime test failed or GPU unavailable"
    mark "containerd-runtime-test-failed"
fi

# Mark complete
mark_done

logger -t zeropoint-nvidia-post "=== NVIDIA GPU Post-Reboot Verification Complete ==="
