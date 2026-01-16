#!/bin/bash
# Observability and marker file functions for zeropoint scripts
# Source this in scripts that need structured logging and idempotency markers

SCRIPT_NAME="${SCRIPT_NAME:-${0##*/}}"
SCRIPT_BASE="${SCRIPT_BASE:-${SCRIPT_NAME%.sh}}"
MARKER_DIR="${MARKER_DIR:-/etc/zeropoint}"

# Log a completed step with tag and message
mark() {
    local step=$1
    logger -t "$SCRIPT_BASE" "✓ $step"
}

# Create a custom marker file for inter-service communication
mark_custom() {
    local marker_name=$1
    mkdir -p "$MARKER_DIR"
    touch "$MARKER_DIR/.${SCRIPT_BASE}.${marker_name}"
    logger -t "$SCRIPT_BASE" "✓ $marker_name (marker created)"
}

# Error trap handler - logs error details to journald
on_error() {
    local line_num=$1
    local exit_code=$?
    logger -t "$SCRIPT_BASE" -p err "✗ Failed at line $line_num (exit: $exit_code): ${BASH_COMMAND}"
}

# Log successful completion and create sentinel marker file
mark_done() {
    logger -t "$SCRIPT_BASE" "✓ Initialization complete"
    mkdir -p "$MARKER_DIR"
    touch "$MARKER_DIR/.${SCRIPT_BASE}"
}

# Check if already initialized - exit 0 if marker exists
check_initialized() {
    if [ -f "$MARKER_DIR/.${SCRIPT_BASE}" ]; then
        logger -t "$SCRIPT_BASE" "Already initialized, skipping..."
        exit 0
    fi
}

# Enable error trapping
trap 'on_error ${LINENO}' ERR
