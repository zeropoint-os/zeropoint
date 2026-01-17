#!/bin/bash
# Observability and marker file functions for zeropoint scripts
# Source this in scripts that need structured logging and idempotency markers

SCRIPT_NAME="${SCRIPT_NAME:-${0##*/}}"
SCRIPT_BASE="${SCRIPT_BASE:-${SCRIPT_NAME%.sh}}"
MARKER_DIR="${MARKER_DIR:-/etc/zeropoint}"
LOG_STREAM="/tmp/zeropoint-log"

# Internal function to write to both syslog and log stream
_log() {
    local priority=$1
    local message=$2
    
    # Write to syslog
    logger -t "$SCRIPT_BASE" -p "$priority" "$message"
    
    # Write to log stream FIFO
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $SCRIPT_BASE: $message" >> "$LOG_STREAM" 2>/dev/null || true
}

# Convenience wrappers for common log levels
_log_notice() {
    _log "user.notice" "$1"
}

_log_err() {
    _log "user.err" "$1"
}

_log_warning() {
    _log "user.warning" "$1"
}

# Log a completed step with tag and message
mark() {
    local step=$1
    _log_notice "Completed: $step"
}

# Create a custom marker file for inter-service communication
mark_custom() {
    local marker_name=$1
    mkdir -p "$MARKER_DIR"
    touch "$MARKER_DIR/.${SCRIPT_BASE}.${marker_name}"
    _log_notice "marker created: $marker_name"
}

# Error trap handler - logs error details to journald and log stream
on_error() {
    local line_num=$1
    local exit_code=$?
    _log_err "Failed at line $line_num (exit: $exit_code): ${BASH_COMMAND}"
}

# Log successful completion and create sentinel marker file
mark_done() {
    mkdir -p "$MARKER_DIR"
    touch "$MARKER_DIR/.${SCRIPT_BASE}"
    _log_notice "Completed: ${SCRIPT_BASE}"
}

# Check if already initialized - exit 0 if marker exists
check_initialized() {
    # Initialize log stream (named pipe)
    if [ ! -p "$LOG_STREAM" ]; then
        mkfifo "$LOG_STREAM" 2>/dev/null || true
    fi
    
    if [ -f "$MARKER_DIR/.${SCRIPT_BASE}" ]; then
        _log "$SCRIPT_BASE" "user.notice" "Already initialized, skipping..."
        exit 0
    fi
}

# Enable error trapping
trap 'on_error ${LINENO}' ERR
