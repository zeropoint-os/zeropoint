#!/bin/bash
# Observability and marker file functions for zeropoint scripts
# Safe for early boot, initramfs, and headless execution

set -o errexit
set -o pipefail
set -o errtrace

SCRIPT_NAME="${SCRIPT_NAME:-${0##*/}}"
SCRIPT_BASE="${SCRIPT_BASE:-${SCRIPT_NAME%.sh}}"
MARKER_DIR="${MARKER_DIR:-/etc/zeropoint}"

LOG_STREAM="/tmp/zeropoint-log"
LOG_FD=3

# -----------------------------------------------------------------------------
# Initialize logging (FIFO-safe, non-blocking)
# -----------------------------------------------------------------------------
_init_log_stream() {
    # If path exists but is not a FIFO, remove it
    if [ -e "$LOG_STREAM" ] && [ ! -p "$LOG_STREAM" ]; then
        rm -f "$LOG_STREAM"
    fi

    # Create FIFO if missing
    if [ ! -p "$LOG_STREAM" ]; then
        mkfifo "$LOG_STREAM" 2>/dev/null || true
    fi

    # Open FIFO read+write so writes never block
    # This is the critical fix
    exec {LOG_FD}<>"$LOG_STREAM" 2>/dev/null || true
}

# -----------------------------------------------------------------------------
# Internal logging primitive
# -----------------------------------------------------------------------------
_log() {
    local priority="$1"
    local message="$2"

    # Syslog (never blocks)
    logger -t "$SCRIPT_BASE" -p "$priority" "$message" || true

    # FIFO log stream (never blocks due to RDWR open)
    if [ -e "/proc/$$/fd/$LOG_FD" ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] $SCRIPT_BASE: $message" >&$LOG_FD 2>/dev/null || true
    fi
}

# -----------------------------------------------------------------------------
# Convenience wrappers
# -----------------------------------------------------------------------------
_log_notice() {
    _log "user.notice" "$1"
}

_log_err() {
    _log "user.err" "$1"
}

_log_warning() {
    local message="$1"
    _log "user.warning" "$message"

    mkdir -p "$MARKER_DIR"
    {
        echo "timestamp=$(date -Iseconds)"
        echo "message=$message"
    } > "$MARKER_DIR/.${SCRIPT_BASE}.warning"
}

# -----------------------------------------------------------------------------
# Marker helpers
# -----------------------------------------------------------------------------
mark() {
    local step="$1"
    _log_notice "Completed: $step"
}

mark_custom() {
    local marker_name="$1"
    mkdir -p "$MARKER_DIR"
    touch "$MARKER_DIR/.${SCRIPT_BASE}.${marker_name}"
    _log_notice "marker created: $marker_name"
}

mark_done() {
    mkdir -p "$MARKER_DIR"
    touch "$MARKER_DIR/.${SCRIPT_BASE}"
    _log_notice "Completed: ${SCRIPT_BASE}"
}

# -----------------------------------------------------------------------------
# Error handling (safe, non-recursive)
# -----------------------------------------------------------------------------
on_error() {
    local line_num="$1"
    local exit_code="$?"
    local cmd="${BASH_COMMAND:-unknown}"

    # Disable ERR trap inside handler to avoid recursion
    trap - ERR

    _log_err "Failed at line $line_num (exit: $exit_code): $cmd"

    mkdir -p "$MARKER_DIR"
    {
        echo "timestamp=$(date -Iseconds)"
        echo "line=$line_num"
        echo "exit_code=$exit_code"
        echo "command=$cmd"
    } > "$MARKER_DIR/.${SCRIPT_BASE}.error"

    mark "error-at-line-$line_num"

    exit "$exit_code"
}

# -----------------------------------------------------------------------------
# Initialization guard
# -----------------------------------------------------------------------------
check_initialized() {
    _init_log_stream

    if [ -f "$MARKER_DIR/.${SCRIPT_BASE}" ]; then
        _log_notice "Already initialized, skipping..."
        exit 0
    fi
}

# -----------------------------------------------------------------------------
# Enable error trapping
# -----------------------------------------------------------------------------
trap 'on_error ${LINENO}' ERR
