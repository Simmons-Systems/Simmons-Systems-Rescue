#!/bin/bash
# Test the is_usb_device logic from wipe-lib.sh
set -euo pipefail

# Find repo root
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Source the library
# shellcheck source=../autorun/wipe-lib.sh
source "$REPO_ROOT/autorun/wipe-lib.sh"

echo "==> Testing wipe-lib.sh (is_usb_device)"
failures=0

lsblk() {
    # is_usb_device calls: lsblk -ndo TRAN "/dev/$dev"
    local arg1="$1"
    local arg2="$2"
    local dev="${3:-}"

    if [[ "$arg1" == "-ndo" && "$arg2" == "TRAN" ]]; then
        case "$dev" in
            "/dev/sda") echo "sata" ;;
            "/dev/nvme0n1") echo "nvme" ;;
            "/dev/sdb") echo "usb" ;;
            "/dev/sdc") echo "" ;;  # Simulating empty transport
            "/dev/sdd") return 1 ;; # Simulating error
            *) echo "" ;;
        esac
    else
        # Fallback if called differently
        command lsblk "$@"
    fi
}
# Exporting allows mocked function to be called if subshells were used,
# though here wipe-lib is sourced directly in the current shell.
export -f lsblk

echo "  -> is_usb_device: should return true for usb transport"
if is_usb_device "sdb"; then
    echo "    PASS"
else
    echo "    FAIL: sdb should be detected as usb"
    failures=$((failures + 1))
fi

echo "  -> is_usb_device: should return false for nvme transport"
if ! is_usb_device "nvme0n1"; then
    echo "    PASS"
else
    echo "    FAIL: nvme0n1 should not be detected as usb"
    failures=$((failures + 1))
fi

echo "  -> is_usb_device: should return false for sata transport"
if ! is_usb_device "sda"; then
    echo "    PASS"
else
    echo "    FAIL: sda should not be detected as usb"
    failures=$((failures + 1))
fi

echo "  -> is_usb_device: should return false for empty output"
if ! is_usb_device "sdc"; then
    echo "    PASS"
else
    echo "    FAIL: sdc should not be detected as usb"
    failures=$((failures + 1))
fi

echo "  -> is_usb_device: should return false for lsblk error"
if ! is_usb_device "sdd"; then
    echo "    PASS"
else
    echo "    FAIL: sdd should not be detected as usb"
    failures=$((failures + 1))
fi

if [[ "$failures" -gt 0 ]]; then
    echo "==> $failures tests failed!"
    exit 1
else
    echo "==> All tests passed!"
fi
