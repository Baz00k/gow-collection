#!/bin/bash
set -euo pipefail

# Applies sysctl tunings for gaming workloads where container capabilities permit.
# Missing permissions are expected in many container runtimes and must not block startup.

source "$(dirname "${BASH_SOURCE[0]}")/logging.sh"

APPLIED_COUNT=0
SKIPPED_COUNT=0

try_sysctl() {
    local key="$1"
    local value="$2"

    if sysctl -w "${key}=${value}" 2>/dev/null; then
        log_info "Applied: ${key}=${value}"
        ((APPLIED_COUNT += 1))
    else
        log_warn "SKIP: ${key} (insufficient permissions or not available)"
        ((SKIPPED_COUNT += 1))
    fi
}

log_info "Starting performance tuning..."

try_sysctl "vm.max_map_count" "1048576"
try_sysctl "kernel.sched_autogroup_enabled" "0"
try_sysctl "net.core.rmem_max" "2097152"
try_sysctl "net.core.wmem_max" "2097152"

log_info "Performance tuning complete: ${APPLIED_COUNT} applied, ${SKIPPED_COUNT} skipped"
