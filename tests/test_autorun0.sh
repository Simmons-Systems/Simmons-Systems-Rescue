#!/bin/bash
set -euo pipefail

echo "Running tests for find_results_partition..."

# Set up mock filesystem root
MOCK_FS_ROOT="$(mktemp -d)"
export MOCK_FS_ROOT
cleanup() {
    rm -rf "$MOCK_FS_ROOT"
}
trap cleanup EXIT

# Mock findmnt
findmnt() {
    echo "/dev/sdc1 ${MOCK_FS_ROOT}/mnt/vfat1 vfat rw,relatime"
    echo "/dev/sdd1 ${MOCK_FS_ROOT}/mnt/vfat2 vfat rw,relatime"
    echo "/dev/sde1 ${MOCK_FS_ROOT}/mnt/ext4 ext4 rw,relatime"
}
export -f findmnt

# Extract just the function to test
eval "$(sed -n '/find_results_partition() {/,/^}/p' autorun/autorun0)"

FAILURES=0

assert_eq() {
    local expected="$1"
    local actual="$2"
    local msg="$3"
    if [[ "$expected" != "$actual" ]]; then
        echo "FAIL: $msg"
        echo "  Expected: '$expected'"
        echo "  Actual:   '$actual'"
        FAILURES=$((FAILURES + 1))
    else
        echo "PASS: $msg"
    fi
}

run_test() {
    local test_name="$1"
    # Clean up mock fs between tests
    rm -rf "${MOCK_FS_ROOT:?}"/*
    "$test_name"
}

test_fallback_finds_first_vfat() {
    mkdir -p "${MOCK_FS_ROOT}/mnt/vfat1"
    touch "${MOCK_FS_ROOT}/mnt/vfat1/.simsys-rescue"

    local out
    local rc=0
    out="$(find_results_partition)" || rc=$?

    assert_eq 0 "$rc" "test_fallback_finds_first_vfat (return code)"
    assert_eq "${MOCK_FS_ROOT}/mnt/vfat1" "$out" "test_fallback_finds_first_vfat (output)"
}

test_fallback_finds_second_vfat() {
    mkdir -p "${MOCK_FS_ROOT}/mnt/vfat1"
    mkdir -p "${MOCK_FS_ROOT}/mnt/vfat2"
    touch "${MOCK_FS_ROOT}/mnt/vfat2/.simsys-rescue"

    local out
    local rc=0
    out="$(find_results_partition)" || rc=$?

    assert_eq 0 "$rc" "test_fallback_finds_second_vfat (return code)"
    assert_eq "${MOCK_FS_ROOT}/mnt/vfat2" "$out" "test_fallback_finds_second_vfat (output)"
}

test_fallback_ignores_non_vfat() {
    mkdir -p "${MOCK_FS_ROOT}/mnt/ext4"
    touch "${MOCK_FS_ROOT}/mnt/ext4/.simsys-rescue"

    local out
    local rc=0
    out="$(find_results_partition)" || rc=$?

    assert_eq 1 "$rc" "test_fallback_ignores_non_vfat (return code)"
    assert_eq "" "$out" "test_fallback_ignores_non_vfat (output)"
}

test_fallback_no_marker_found() {
    mkdir -p "${MOCK_FS_ROOT}/mnt/vfat1"
    mkdir -p "${MOCK_FS_ROOT}/mnt/vfat2"

    local out
    local rc=0
    out="$(find_results_partition)" || rc=$?

    assert_eq 1 "$rc" "test_fallback_no_marker_found (return code)"
    assert_eq "" "$out" "test_fallback_no_marker_found (output)"
}

test_finds_direct_paths() {
    # Extract original function, modify paths to use mock root
    eval "$(sed -n '/find_results_partition() {/,/^}/p' autorun/autorun0 | \
        sed "s|/run/sysrescue-config|${MOCK_FS_ROOT}/run/sysrescue-config|g; \
             s|/run/archiso/bootmnt|${MOCK_FS_ROOT}/run/archiso/bootmnt|g; \
             s|/run/usbstick|${MOCK_FS_ROOT}/run/usbstick|g; \
             s|/mnt/usb|${MOCK_FS_ROOT}/mnt/usb|g")"

    mkdir -p "${MOCK_FS_ROOT}/run/usbstick"
    touch "${MOCK_FS_ROOT}/run/usbstick/.simsys-rescue"

    local out
    local rc=0
    out="$(find_results_partition)" || rc=$?

    assert_eq 0 "$rc" "test_finds_direct_paths (return code)"
    assert_eq "${MOCK_FS_ROOT}/run/usbstick" "$out" "test_finds_direct_paths (output)"

    # Restore the standard mocked function for subsequent tests
    eval "$(sed -n '/find_results_partition() {/,/^}/p' autorun/autorun0)"
}

run_test test_fallback_finds_first_vfat
run_test test_fallback_finds_second_vfat
run_test test_fallback_ignores_non_vfat
run_test test_fallback_no_marker_found
run_test test_finds_direct_paths

if [[ $FAILURES -gt 0 ]]; then
    echo "Tests failed: $FAILURES"
    false
else
    echo "All tests passed!"
fi
