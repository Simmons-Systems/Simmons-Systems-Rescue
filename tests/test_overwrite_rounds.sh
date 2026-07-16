#!/bin/bash
# Tests for the opt-in overwrite pass-count resolver (resolve_overwrite_rounds)
# and the audit mapping (overwrite_rounds_for_type) in wipe-lib.sh.

set -euo pipefail

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "$REPO_ROOT/autorun/wipe-lib.sh"

fails=0
check() {
    local name="$1" expected="$2" actual="$3"
    if [[ "$actual" == "$expected" ]]; then
        echo "PASS: $name -> $actual"
    else
        echo "FAIL: $name — expected [$expected], got [$actual]"
        fails=$((fails + 1))
    fi
}

# Empty cmdline / config by default; point the source overrides at temp files.
EMPTY_CMDLINE="$TMP/cmdline.empty"
: > "$EMPTY_CMDLINE"
NO_CFG="$TMP/does-not-exist.env"

rounds() { WIPE_CMDLINE_FILE="${1:-$EMPTY_CMDLINE}" WIPE_CONFIG_FILE="${2:-$NO_CFG}" resolve_overwrite_rounds 2>/dev/null; }

echo "== precedence & default =="

unset WIPE_OVERWRITE_ROUNDS
check "all sources unset -> default 1" "1" "$(rounds)"

# Baked config file only.
echo "WIPE_OVERWRITE_ROUNDS=3" > "$TMP/wipe.env"
check "baked file only -> 3" "3" "$(rounds "$EMPTY_CMDLINE" "$TMP/wipe.env")"

# Kernel cmdline overrides the file.
echo "BOOT_IMAGE=/vmlinuz quiet ssr.overwrite-rounds=5 splash" > "$TMP/cmdline.5"
check "cmdline overrides file (5 vs 3)" "5" "$(rounds "$TMP/cmdline.5" "$TMP/wipe.env")"

# Env overrides everything.
check "env overrides cmdline+file" "7" "$(WIPE_OVERWRITE_ROUNDS=7 rounds "$TMP/cmdline.5" "$TMP/wipe.env")"

echo "== validation / fall-through =="

# Invalid env falls through to a valid cmdline.
check "invalid env -> cmdline" "5" "$(WIPE_OVERWRITE_ROUNDS=abc rounds "$TMP/cmdline.5" "$NO_CFG")"

# Invalid env + invalid cmdline -> valid file.
echo "ssr.overwrite-rounds=-1" > "$TMP/cmdline.bad"
echo "WIPE_OVERWRITE_ROUNDS=4" > "$TMP/wipe4.env"
check "invalid env+cmdline -> file" "4" "$(WIPE_OVERWRITE_ROUNDS=0 rounds "$TMP/cmdline.bad" "$TMP/wipe4.env")"

# Everything invalid -> default 1 (never 0 / never silently drops passes).
echo "WIPE_OVERWRITE_ROUNDS=nope" > "$TMP/wipe.bad"
check "all invalid -> default 1" "1" "$(WIPE_OVERWRITE_ROUNDS=x rounds "$TMP/cmdline.bad" "$TMP/wipe.bad")"

# Zero is rejected (would be a dangerous no-op wipe).
check "zero rejected -> default 1" "1" "$(WIPE_OVERWRITE_ROUNDS=0 rounds)"

echo "== overwrite_rounds_for_type (audit mapping) =="

unset WIPE_OVERWRITE_ROUNDS
otype() { WIPE_CMDLINE_FILE="$EMPTY_CMDLINE" WIPE_CONFIG_FILE="$NO_CFG" overwrite_rounds_for_type "$1" 2>/dev/null; }

check "nvme-ssd -> null (erase)" "null" "$(otype nvme-ssd)"
check "nvme-ssd-sed -> null (crypto)" "null" "$(otype nvme-ssd-sed)"
check "sata-ssd -> null (erase)" "null" "$(otype sata-ssd)"
check "sata-ssd-sed -> null (crypto)" "null" "$(otype sata-ssd-sed)"
check "hdd -> 1 (overwrite, default)" "1" "$(otype hdd)"
check "usb-flash -> 1 (overwrite, default)" "1" "$(otype usb-flash)"
check "unknown type -> 1 (fallback overwrite)" "1" "$(otype weird-type)"
check "hdd honors env override" "2" "$(WIPE_OVERWRITE_ROUNDS=2 WIPE_CMDLINE_FILE="$EMPTY_CMDLINE" WIPE_CONFIG_FILE="$NO_CFG" overwrite_rounds_for_type hdd 2>/dev/null)"

if [[ $fails -eq 0 ]]; then
    echo "All overwrite-rounds tests passed."
else
    echo "$fails test(s) failed."
    /bin/false
fi
