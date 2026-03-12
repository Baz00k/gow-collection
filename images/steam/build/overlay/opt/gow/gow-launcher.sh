#!/bin/bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/logging.sh"

# =============================================================================
# gow-launcher.sh — Generic Process Restart Wrapper
# =============================================================================
#
# A generic wrapper script that monitors a child process and automatically
# restarts it based on exit code and configuration.
#
# USAGE:
#   gow-launcher.sh <command> [args...]
#
# ENVIRONMENT VARIABLES:
#   GOW_RESTART_ON_EXIT0  - Restart when exit code is 0 (default: false)
#                           Set to "true" for Steam update restart scenario
#   GOW_RESTART_ON_ERROR  - Restart on non-zero, non-7 exit codes (default: true)
#   GOW_RESTART_DELAY     - Seconds to wait before restart (default: 1)
#   GOW_MAX_RESTARTS      - Maximum restart attempts (default: 3)
#
# EXIT CODES:
#   0   - Process exited with 0 and GOW_RESTART_ON_EXIT0=false (or max restarts hit)
#   1   - Process exited with error and GOW_RESTART_ON_ERROR=false (or max restarts hit)
#   7   - Shutdown requested by child process (no restart)
#   124 - Timeout waiting for process
#
# EXAMPLES:
#   # Run Steam with restart on exit 0 (Steam update scenario)
#   GOW_RESTART_ON_EXIT0=true gow-launcher.sh steam -bigpicture
#
#   # Run with unlimited restarts on error
#   GOW_MAX_RESTARTS=0 gow-launcher.sh ./my-app
#
#   # Immediate restart (no delay)
#   GOW_RESTART_DELAY=0 gow-launcher.sh ./my-app
#
# =============================================================================

# =============================================================================
# Configuration (with defaults)
# =============================================================================
GOW_RESTART_ON_EXIT0="${GOW_RESTART_ON_EXIT0:-false}"
GOW_RESTART_ON_ERROR="${GOW_RESTART_ON_ERROR:-true}"
GOW_RESTART_DELAY="${GOW_RESTART_DELAY:-1}"
GOW_MAX_RESTARTS="${GOW_MAX_RESTARTS:-3}"

# Special exit code meaning "shutdown requested, do not restart"
readonly SHUTDOWN_EXIT_CODE=7

# =============================================================================
# Signal handling
# =============================================================================
shutdown_requested=false
child_pid=""

handle_signal() {
    log_info "Received shutdown signal, terminating child process..."
    shutdown_requested=true
    if [ -n "${child_pid}" ] && kill -0 "${child_pid}" 2>/dev/null; then
        kill -TERM "${child_pid}" 2>/dev/null || true
        # Give child process time to clean up
        sleep 1
        kill -KILL "${child_pid}" 2>/dev/null || true
    fi
}

trap handle_signal SIGTERM SIGINT

# =============================================================================
# Validate arguments
# =============================================================================
if [ $# -eq 0 ]; then
    log_error "No command specified"
    log_error "Usage: gow-launcher.sh <command> [args...]"
    exit 1
fi

# =============================================================================
# Main restart loop
# =============================================================================
restart_count=0
last_exit_code=0

log_info "Starting gow-launcher with command: $*"
log_info "Configuration: RESTART_ON_EXIT0=${GOW_RESTART_ON_EXIT0}, RESTART_ON_ERROR=${GOW_RESTART_ON_ERROR}, RESTART_DELAY=${GOW_RESTART_DELAY}s, MAX_RESTARTS=${GOW_MAX_RESTARTS}"

while true; do
    # Check if shutdown was requested
    if [ "${shutdown_requested}" = "true" ]; then
        log_info "Shutdown requested, exiting..."
        exit 0
    fi

    # Run the command
    log_info "Starting process (attempt $((restart_count + 1)))..."
    set +e
    "$@" &
    child_pid=$!
    wait "${child_pid}"
    last_exit_code=$?
    set -e
    child_pid=""

    log_info "Process exited with code ${last_exit_code}"

    # Check for shutdown signal (exit code 7)
    if [ "${last_exit_code}" -eq "${SHUTDOWN_EXIT_CODE}" ]; then
        log_info "Shutdown signal received (exit code ${SHUTDOWN_EXIT_CODE}), exiting..."
        exit 0
    fi

    # Determine if we should restart
    should_restart=false

    if [ "${last_exit_code}" -eq 0 ]; then
        # Clean exit
        if [ "${GOW_RESTART_ON_EXIT0}" = "true" ]; then
            should_restart=true
            log_info "Clean exit (0) with RESTART_ON_EXIT0=true, will restart..."
        else
            log_info "Clean exit (0), exiting normally..."
            exit 0
        fi
    else
        # Error exit (non-zero, non-7)
        if [ "${GOW_RESTART_ON_ERROR}" = "true" ]; then
            should_restart=true
            log_warn "Error exit (${last_exit_code}) with RESTART_ON_ERROR=true, will restart..."
        else
            log_error "Error exit (${last_exit_code}) with RESTART_ON_ERROR=false, exiting..."
            exit "${last_exit_code}"
        fi
    fi

    # Check max restarts (0 means unlimited)
    if [ "${should_restart}" = "true" ]; then
        if [ "${GOW_MAX_RESTARTS}" != "0" ] && [ "${restart_count}" -ge "${GOW_MAX_RESTARTS}" ]; then
            log_error "Maximum restart attempts reached (${GOW_MAX_RESTARTS}), exiting with last exit code ${last_exit_code}"
            exit "${last_exit_code}"
        fi

        restart_count=$((restart_count + 1))
        log_info "Waiting ${GOW_RESTART_DELAY}s before restart (attempt ${restart_count}/${GOW_MAX_RESTARTS})..."
        sleep "${GOW_RESTART_DELAY}"
    else
        exit "${last_exit_code}"
    fi
done
