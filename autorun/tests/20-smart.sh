#!/bin/bash
# SMART health check on every detected drive.
# Fails the test if any drive reports "FAILED" overall health.
set -uo pipefail
# shellcheck source=../lib.sh
source "$(dirname "$0")/../lib.sh"

failures=0

# SATA / SAS
for d in /dev/sd?; do
    [[ -b "$d" ]] || continue
    section "smartctl -a $d"
    if ! out=$(smartctl -a "$d" 2>&1); then
        echo "$out"
        # Some USB enclosures don't pass through SMART — note but don't fail
        log "WARN: smartctl failed on $d (likely USB-pass-through limitation)"
        continue
    fi
    echo "$out"
    if echo "$out" | grep -qE "result: FAILED"; then
        fail "$d reports overall SMART status FAILED"
        failures=$((failures + 1))
    fi
done

# NVMe
for d in /dev/nvme?n?; do
    [[ -b "$d" ]] || continue
    section "smartctl -a $d"
    out=$(smartctl -a "$d" 2>&1) || log "WARN: smartctl failed on $d"
    echo "$out"
    if echo "$out" | grep -qE "result: FAILED"; then
        fail "$d reports overall SMART status FAILED"
        failures=$((failures + 1))
    fi
done

if [[ $failures -gt 0 ]]; then
    fail "${failures} drive(s) failed SMART health check"
    exit 1
fi
exit 0
