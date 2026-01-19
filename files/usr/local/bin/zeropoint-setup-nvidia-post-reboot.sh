#!/bin/bash
set -e
source /usr/local/bin/zeropoint-common.sh

check_initialized

_log_notice "Starting NVIDIA GPU Post-Reboot Verification"

_log_notice "Driver installation with reboot detected - verifying installation..."
mark "verification-started"

# Restart container services to pick up new configuration
_log_notice "Restarting Docker and containerd..."
systemctl restart docker containerd || true
mark "services-restarted"

# Wait for nvidia-smi to become available (kernel module loading)
_log_notice "Waiting for NVIDIA drivers to activate..."
MAX_ATTEMPTS=30
ATTEMPT=0
while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
    if nvidia-smi > /dev/null 2>&1; then
        DRIVER_VERSION=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader,nounits | head -1)
        _log_notice "NVIDIA Driver version: $DRIVER_VERSION - GPU ready"
        mark "driver-verified"
        break
    fi
    ATTEMPT=$((ATTEMPT + 1))
    _log_notice "Waiting for nvidia-smi (attempt $ATTEMPT/$MAX_ATTEMPTS)..."
    sleep 1
done

if [ $ATTEMPT -eq $MAX_ATTEMPTS ]; then
    _log_warning "nvidia-smi still not available after $MAX_ATTEMPTS seconds"
    _log_warning "GPU drivers may require additional kernel configuration"
fi

# Test NVIDIA container runtime on Docker
_log_notice "Testing NVIDIA container runtime on Docker..."
if docker run --rm --gpus all nvidia/cuda:12.0.0-runtime-ubuntu22.04 nvidia-smi > /dev/null 2>&1; then
    _log_notice "Docker NVIDIA runtime working"
    mark "docker-runtime-verified"
else
    _log_warning "Docker NVIDIA runtime test failed or GPU unavailable"
    mark "docker-runtime-test-failed"
fi

# Test NVIDIA container runtime on containerd
_log_notice "Testing NVIDIA container runtime on containerd..."
if ctr run --rm --gpus all docker.io/nvidia/cuda:12.0.0-runtime-ubuntu22.04 test-nvidia nvidia-smi > /dev/null 2>&1; then
    _log_notice "containerd NVIDIA runtime working"
    mark "containerd-runtime-verified"
else
    _log_warning "containerd NVIDIA runtime test failed or GPU unavailable"
    mark "containerd-runtime-test-failed"
fi

# Mark complete
mark_done

_log_notice "NVIDIA GPU Post-Reboot Verification Complete"
