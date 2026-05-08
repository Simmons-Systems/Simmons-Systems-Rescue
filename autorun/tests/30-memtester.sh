#!/bin/bash
# Userspace RAM test via memtester. Tests roughly MEMTESTER_PCT% of available
# RAM (default 95%). Does NOT test kernel-space, DMA buffers, or page tables —
# for that, boot the Memtest86+ USB instead.
set -uo pipefail
# shellcheck source=../lib.sh
source "$(dirname "$0")/../lib.sh"

if ! command -v memtester > /dev/null; then
    fail "memtester not installed in SystemRescue ISO"
    exit 1
fi

# Available memory in MB (free shows kB)
avail_kb="$(awk '/MemAvailable:/ {print $2}' /proc/meminfo)"
test_mb=$((avail_kb / 1024 * MEMTESTER_PCT / 100))

section "memtester ${test_mb}M 1"
log "Testing ${test_mb}MB (${MEMTESTER_PCT}% of MemAvailable)"

if memtester "${test_mb}M" 1; then
    pass "memtester ${test_mb}MB passed 1 round"
    exit 0
fi
fail "memtester reported errors"
exit 1
