#!/bin/bash
# CPU + IO + memory stress for STRESS_DURATION_SEC seconds (default 7200 = 2h).
# Catches thermal-creep, power-rail, and intermittent-fault issues that show
# up under sustained load.
set -uo pipefail
# shellcheck source=../lib.sh
source "$(dirname "$0")/../lib.sh"

if ! command -v stress-ng > /dev/null; then
    fail "stress-ng not installed in SystemRescue ISO"
    exit 1
fi

cpus="$(nproc)"
section "stress-ng --cpu ${cpus} --vm 2 --hdd 1 --metrics --timeout ${STRESS_DURATION_SEC}s"
log "Stressing for ${STRESS_DURATION_SEC} seconds (~$((STRESS_DURATION_SEC / 60)) min)"

if stress-ng \
    --cpu "$cpus" \
    --vm 2 --vm-bytes 25% \
    --hdd 1 --hdd-bytes 1G \
    --metrics \
    --timeout "${STRESS_DURATION_SEC}s"; then
    pass "stress-ng ${STRESS_DURATION_SEC}s completed without error"
    exit 0
fi
fail "stress-ng reported errors during run"
exit 1
