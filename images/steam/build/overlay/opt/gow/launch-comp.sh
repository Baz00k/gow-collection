#!/bin/bash
set -euo pipefail

# launch-comp.sh — Performance tuning script for Steam container
# Applies sysctl tunings for gaming workloads where container capabilities permit.
# Gracefully degrades if permissions are insufficient.

source "$(dirname "${BASH_SOURCE[0]}")/logging.sh"

APPLIED_COUNT=0
SKIPPED_COUNT=0

# Args: $1 = sysctl key, $2 = value
try_sysctl() {
    local key="$1"
    local value="$2"
    
    if sysctl -w "${key}=${value}" 2>/dev/null; then
        log_info "Applied: ${key}=${value}"
        ((APPLIED_COUNT++))
    else
        log_warn "SKIP: ${key} (insufficient permissions or not available)"
        ((SKIPPED_COUNT++))
    fi
}

log_info "Starting performance tuning..."

# Gaming performance tunings — see images/steam/docs/performance-analysis.md
# vm.max_map_count=1048576: Prevents crashes in memory-intensive games (CS2, DayZ, The Finals)
try_sysctl "vm.max_map_count" "1048576"

# kernel.sched_autogroup_enabled=0: Disables autogroup for potentially lower scheduling latency
try_sysctl "kernel.sched_autogroup_enabled" "0"

# net.core.rmem_max=2097152: Increased network receive buffer for online gaming
try_sysctl "net.core.rmem_max" "2097152"

# net.core.wmem_max=2097152: Increased network send buffer for online gaming
try_sysctl "net.core.wmem_max" "2097152"

log_info "Performance tuning complete: ${APPLIED_COUNT} applied, ${SKIPPED_COUNT} skipped"

# Always exit 0 — graceful degradation; missing permissions must not crash container startup
exit 0
