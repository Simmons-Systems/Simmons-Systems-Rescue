# Shared helpers for autorun test scripts.
# Sourced by autorun0 and by each autorun/tests/*.sh.

# Default config — overridden by /run/sysrescue-config/default.env if present
# (build-rescue-usb.sh writes config/default.env to that location on the FAT32
# partition).
: "${STRESS_DURATION_SEC:=7200}"
: "${MEMTESTER_PCT:=95}"
: "${RESULTS_DIR:=/run/results}"

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

# Run a command and capture exit code without aborting on -e.
run_or_warn() {
    local desc="$1"
    shift
    if "$@"; then
        return 0
    else
        local rc=$?
        log "WARN: $desc exited with code $rc"
        return "$rc"
    fi
}
