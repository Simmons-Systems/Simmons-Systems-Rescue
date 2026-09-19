# Shared helpers for autorun test scripts.
# Sourced by autorun0 and by each autorun/tests/*.sh.

# Load the baked-in tunables. build-rescue-usb.sh writes config/default.env
# onto the FAT32 partition, which SystemRescue mounts under
# /run/sysrescue-config. Anything set there overrides the defaults below.
for _cfg in /run/sysrescue-config/default.env /default.env; do
    if [[ -r "$_cfg" ]]; then
        # shellcheck disable=SC1090
        source "$_cfg"
        break
    fi
done
unset _cfg

: "${STRESS_DURATION_SEC:=7200}"
: "${MEMTESTER_PCT:=95}"
# Empty => autorun0 writes results to the writable FAT32 partition when one is
# found (survives reboot); set an absolute path to override.
: "${RESULTS_DIR:=}"

section() {
    printf '\n=== %s ===\n' "$1"
}

log() {
    printf '[%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1"
}

pass() {
    printf 'PASS: %s\n' "$1"
}

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    return 1
}
