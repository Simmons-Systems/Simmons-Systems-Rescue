#!/bin/bash
set -euo pipefail

# Tests for setup_results_dir function in autorun0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUTORUN0_PATH="${SCRIPT_DIR}/autorun/autorun0"

# --- Test Framework ---

TESTS_RUN=0
TESTS_PASSED=0

# Counters for mock verification
MOUNT_CALLED=0
LOG_WARNING_CALLED=0
MKDIR_CALLED=0
MOUNT_REMOUNT_SUCCESS=1
FIND_RESULTS_PARTITION_SUCCESS=1
MOCK_PARTITION="/mock/partition"

# --- Source the script under test ---
# shellcheck disable=SC1090
source "$AUTORUN0_PATH"

# --- Mocks ---
# Defining these AFTER sourcing so we overwrite the real functions

find_results_partition() {
    if [[ $FIND_RESULTS_PARTITION_SUCCESS -eq 1 ]]; then
        echo "$MOCK_PARTITION"
        return 0
    else
        return 1
    fi
}

mount() {
    MOUNT_CALLED=$((MOUNT_CALLED + 1))
    if [[ $MOUNT_REMOUNT_SUCCESS -eq 1 ]]; then
        return 0
    else
        return 1
    fi
}

log() {
    local msg="$1"
    if [[ "$msg" == *"WARN: no writable FAT32 partition found"* ]]; then
        LOG_WARNING_CALLED=$((LOG_WARNING_CALLED + 1))
    fi
}

mkdir() {
    MKDIR_CALLED=$((MKDIR_CALLED + 1))
    # Don't actually run mkdir -p during tests
}

# --- Test Cases ---

reset_mocks() {
    MOUNT_CALLED=0
    LOG_WARNING_CALLED=0
    MKDIR_CALLED=0
    MOUNT_REMOUNT_SUCCESS=1
    FIND_RESULTS_PARTITION_SUCCESS=1
    unset RESULTS_DIR
}

test_setup_results_dir_happy_path() {
    reset_mocks

    # Execution
    setup_results_dir

    # Assertions
    if [[ "${RESULTS_DIR:-}" != "${MOCK_PARTITION}/results" ]]; then
        echo "FAIL: Expected RESULTS_DIR to be ${MOCK_PARTITION}/results, got ${RESULTS_DIR:-}"
        return 1
    fi
    if [[ $MOUNT_CALLED -ne 1 ]]; then
        echo "FAIL: Expected mount to be called 1 time, got $MOUNT_CALLED"
        return 1
    fi
    if [[ $LOG_WARNING_CALLED -ne 0 ]]; then
        echo "FAIL: Expected log warning to be called 0 times, got $LOG_WARNING_CALLED"
        return 1
    fi
    if [[ $MKDIR_CALLED -ne 1 ]]; then
        echo "FAIL: Expected mkdir to be called 1 time, got $MKDIR_CALLED"
        return 1
    fi

    # Check if exported
    if ! env | grep -q "^RESULTS_DIR=${MOCK_PARTITION}/results"; then
        echo "FAIL: RESULTS_DIR was not exported"
        return 1
    fi

    echo "PASS: test_setup_results_dir_happy_path"
    return 0
}

test_setup_results_dir_remount_fails() {
    reset_mocks
    MOUNT_REMOUNT_SUCCESS=0

    # Execution
    setup_results_dir

    # Assertions
    if [[ "${RESULTS_DIR:-}" != "${MOCK_PARTITION}/results" ]]; then
        echo "FAIL: Expected RESULTS_DIR to be ${MOCK_PARTITION}/results, got ${RESULTS_DIR:-}"
        return 1
    fi
    if [[ $MOUNT_CALLED -ne 1 ]]; then
        echo "FAIL: Expected mount to be called 1 time, got $MOUNT_CALLED"
        return 1
    fi

    echo "PASS: test_setup_results_dir_remount_fails"
    return 0
}

test_setup_results_dir_no_partition() {
    reset_mocks
    FIND_RESULTS_PARTITION_SUCCESS=0

    # Execution
    setup_results_dir

    # Assertions
    if [[ "${RESULTS_DIR:-}" != "/run/results" ]]; then
        echo "FAIL: Expected RESULTS_DIR to be /run/results, got ${RESULTS_DIR:-}"
        return 1
    fi
    if [[ $MOUNT_CALLED -ne 0 ]]; then
        echo "FAIL: Expected mount to be called 0 times, got $MOUNT_CALLED"
        return 1
    fi
    if [[ $LOG_WARNING_CALLED -ne 1 ]]; then
        echo "FAIL: Expected log warning to be called 1 time, got $LOG_WARNING_CALLED"
        return 1
    fi

    echo "PASS: test_setup_results_dir_no_partition"
    return 0
}

# --- Main ---

run_test() {
    local test_func="$1"
    TESTS_RUN=$((TESTS_RUN + 1))
    if "$test_func"; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo "!!! Test $test_func failed"
    fi
}

echo "Running setup_results_dir tests..."
run_test test_setup_results_dir_happy_path
run_test test_setup_results_dir_remount_fails
run_test test_setup_results_dir_no_partition

echo "============================"
echo "Tests run:    $TESTS_RUN"
echo "Tests passed: $TESTS_PASSED"

if [[ $TESTS_RUN -ne $TESTS_PASSED ]]; then
    exit 1
fi
