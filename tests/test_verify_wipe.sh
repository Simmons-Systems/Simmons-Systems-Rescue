#!/bin/bash
# Tests for host_info() JSON escaping and the method-aware verify_wipe() in
# wipe-lib.sh. External commands (dmidecode, blockdev, dd) are stubbed via a
# PATH-prepended mock dir; od/tr/grep run for real.

set -euo pipefail

MOCK_DIR="$(mktemp -d)"
trap 'rm -rf "$MOCK_DIR"' EXIT

# --- Mock dmidecode: returns whatever MOCK_DMI_VALUE holds (verbatim) --------
cat << 'MOCK_EOF' > "$MOCK_DIR/dmidecode"
#!/bin/bash
printf '%s\n' "$MOCK_DMI_VALUE"
MOCK_EOF
chmod +x "$MOCK_DIR/dmidecode"

# --- Mock blockdev: MOCK_DEV_SIZE bytes -------------------------------------
cat << 'MOCK_EOF' > "$MOCK_DIR/blockdev"
#!/bin/bash
# called as: blockdev --getsize64 /dev/X
printf '%s\n' "${MOCK_DEV_SIZE:-0}"
MOCK_EOF
chmod +x "$MOCK_DIR/blockdev"

# --- Mock dd: emits one block per MOCK_DD_MODE, records skip offsets ---------
# MOCK_DD_MODE: zero | ff | random | allzero | fail
cat << 'MOCK_EOF' > "$MOCK_DIR/dd"
#!/bin/bash
skip=0
for a in "$@"; do
    case "$a" in
        skip=*) skip="${a#skip=}" ;;
    esac
done
[[ -n "${MOCK_SKIP_LOG:-}" ]] && printf '%s\n' "$skip" >> "$MOCK_SKIP_LOG"
case "${MOCK_DD_MODE:-random}" in
    fail)    exit 1 ;;
    zero|allzero) head -c 512 /dev/zero ;;
    ff)      head -c 512 /dev/zero | tr '\000' '\377' ;;
    random)  head -c 512 /dev/urandom ;;
esac
MOCK_EOF
chmod +x "$MOCK_DIR/dd"

export PATH="$MOCK_DIR:$PATH"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "$REPO_ROOT/autorun/wipe-lib.sh"

fails=0
pass() { echo "PASS: $1"; }
failt() {
    echo "FAIL: $1"
    fails=$((fails + 1))
}

# Keep verify_wipe loops cheap.
export VERIFY_SAMPLES=64

echo "== host_info() JSON escaping =="

# A DMI value with an embedded double-quote used to produce invalid JSON.
export MOCK_DMI_VALUE='Dell Inc. "Special" Edition'
hi="$(host_info)"
if printf '%s' "$hi" | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null; then
    pass "host_info emits valid JSON when DMI value contains double-quotes"
else
    failt "host_info produced invalid JSON: $hi"
fi

# And the escaped value round-trips intact.
got="$(printf '%s' "$hi" | python3 -c 'import json,sys; print(json.load(sys.stdin)["manufacturer"])')"
if [[ "$got" == 'Dell Inc. "Special" Edition' ]]; then
    pass "host_info preserves the quoted manufacturer value"
else
    failt "host_info mangled the value: got [$got]"
fi

# Backslashes must not break JSON either.
export MOCK_DMI_VALUE='Back\slash \ Co'
if host_info | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null; then
    pass "host_info emits valid JSON when DMI value contains backslashes"
else
    failt "host_info produced invalid JSON for a backslash value"
fi

echo "== verify_wipe() method-aware pattern =="

export MOCK_DEV_SIZE=$((512 * 1000000)) # ~512MB, plenty of blocks

# Overwrite methods: random data must PASS, all-zero must FAIL.
export MOCK_DD_MODE=random
if verify_wipe "sdX" "hdd"; then
    pass "hdd (random overwrite): random data verifies OK (no false negative)"
else
    failt "hdd random data was wrongly rejected"
fi

export MOCK_DD_MODE=allzero
if ! verify_wipe "sdX" "hdd"; then
    pass "hdd (random overwrite): all-zero (unwritten) region fails verification"
else
    failt "hdd all-zero region wrongly passed verification"
fi

export MOCK_DD_MODE=random
if ! verify_wipe "sdX" "usb-flash"; then
    failt "usb-flash random data was wrongly rejected"
else
    pass "usb-flash (random overwrite): random data verifies OK"
fi

# Erase methods: zeros/0xFF must PASS, random must FAIL.
export MOCK_DD_MODE=zero
if verify_wipe "sdX" "nvme-ssd"; then
    pass "nvme-ssd (block erase): all-zero verifies OK"
else
    failt "nvme-ssd all-zero was wrongly rejected"
fi

export MOCK_DD_MODE=ff
if verify_wipe "sdX" "sata-ssd"; then
    pass "sata-ssd (secure erase): all-0xFF verifies OK"
else
    failt "sata-ssd all-0xFF was wrongly rejected"
fi

export MOCK_DD_MODE=random
if ! verify_wipe "sdX" "nvme-ssd"; then
    pass "nvme-ssd (block erase): leftover random data fails verification"
else
    failt "nvme-ssd random data wrongly passed verification"
fi

echo "== verify_wipe() read-failure detection =="

export MOCK_DD_MODE=fail
if ! verify_wipe "sdX" "hdd"; then
    pass "dd read failure fails verification (not silently skipped)"
else
    failt "dd read failure was silently treated as a pass"
fi

echo "== verify_wipe() zero-size guard =="
export MOCK_DEV_SIZE=0
export MOCK_DD_MODE=random
if ! verify_wipe "sdX" "hdd"; then
    pass "zero-size device fails verification"
else
    failt "zero-size device wrongly passed"
fi

echo "== verify_wipe() full-width offset coverage (>500GB) =="
# 2TB device: the old RANDOM*RANDOM ceiling (~1.07e9 blocks) could not reach
# past ~550GB. Assert sampled offsets exceed that ceiling.
export MOCK_DEV_SIZE=$((2 * 1000 * 1000 * 1000 * 1000)) # 2 TB
export MOCK_DD_MODE=random
export MOCK_SKIP_LOG="$MOCK_DIR/skips.log"
: > "$MOCK_SKIP_LOG"
VERIFY_SAMPLES=500 verify_wipe "sdX" "hdd" || true
max_skip=$(sort -n "$MOCK_SKIP_LOG" | tail -1)
old_ceiling=1073676289 # 32767 * 32767
if [[ "${max_skip:-0}" -gt "$old_ceiling" ]]; then
    pass "offsets reach past the old RANDOM*RANDOM ceiling (max=$max_skip > $old_ceiling)"
else
    failt "offsets never exceeded old ceiling (max=${max_skip:-0}); tail of large drives unreachable"
fi
unset MOCK_SKIP_LOG

if [[ $fails -eq 0 ]]; then
    echo "All verify_wipe/host_info tests passed."
else
    echo "$fails test(s) failed."
    /bin/false
fi
