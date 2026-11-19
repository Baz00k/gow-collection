#!/usr/bin/env bash
# Count gamescope vblank timer fires and double fires.
#
# Run on the Wolf host while a game runs:
#   ./vblank-trace.sh [seconds]
#
# Traces timerfd_settime on gamescope from a throwaway container, so the host needs
# no strace. A healthy nested session fires at the stream refresh with no pairs.
set -euo pipefail

SECONDS_TO_TRACE="${1:-5}"
CONTAINER="${CONTAINER:-$(docker ps --format '{{.Names}}' | grep -m1 '^WolfSteam_')}"
PID="$(docker top "${CONTAINER:?no WolfSteam_ container running; set CONTAINER}" -eo pid,comm | awk '$2 == "gamescope-wl" {print $1; exit}')"

docker run --rm --pid=host --cap-add SYS_PTRACE --security-opt seccomp=unconfined alpine:3.22 \
    sh -c "apk add -q strace >/dev/null && timeout ${SECONDS_TO_TRACE} strace -f -tt -e trace=timerfd_settime -p ${PID:?gamescope-wl not found} 2>&1" |
    awk '
        /timerfd_settime/ && /it_value=\{tv_sec=0, tv_nsec=0\}/ {
            for (i = 1; i <= NF; i++) if ($i ~ /^[0-9]+:[0-9]+:[0-9.]+$/) { split($i, t, ":"); break }
            now = t[1] * 3600 + t[2] * 60 + t[3]
            if (last) { fires++; if (now - last < 0.004) doubles++ }
            if (!first) first = now
            last = now
        }
        END {
            span = last - first
            if (span <= 0) { print "no vblank fires seen"; exit 1 }
            printf "vblank fires %.1f/s, double fires (<4 ms apart) %d (%.1f/s)\n", fires / span, doubles, doubles / span
        }'
