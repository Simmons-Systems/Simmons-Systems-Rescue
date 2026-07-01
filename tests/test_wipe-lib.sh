#!/bin/bash
# Tests for wipe-lib.sh

set -euo pipefail

# Create a temporary directory for mock commands
MOCK_DIR="$(mktemp -d)"
# Ensure we clean it up
trap 'rm -rf "$MOCK_DIR"' EXIT

# Create mock command for nvme
cat << 'MOCK_EOF' > "$MOCK_DIR/nvme"
#!/bin/bash
echo "$MOCK_NVME_OUTPUT"
MOCK_EOF
chmod +x "$MOCK_DIR/nvme"

# Create mock command for sedutil-cli
cat << 'MOCK_EOF' > "$MOCK_DIR/sedutil-cli"
#!/bin/bash
echo "$MOCK_SEDUTIL_OUTPUT"
MOCK_EOF
chmod +x "$MOCK_DIR/sedutil-cli"

# Prepend MOCK_DIR to PATH
export PATH="$MOCK_DIR:$PATH"

# Define mock outputs
export MOCK_NVME_OUTPUT=""
export MOCK_SEDUTIL_OUTPUT=""

# Source the library to be tested
# We need to ensure we can source it correctly from the test script directory
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "$REPO_ROOT/autorun/wipe-lib.sh"

fails=0

run_test() {
    local test_name="$1"
    local dev="$2"
    local rota="$3"
    local tran="$4"
    local expected="$5"
    local nvme_out="$6"
    local sed_out="$7"

    export MOCK_NVME_OUTPUT="$nvme_out"
    export MOCK_SEDUTIL_OUTPUT="$sed_out"

    local result
    result=$(detect_drive_type "$dev" "$rota" "$tran")

    if [[ "$result" != "$expected" ]]; then
        echo "FAIL: $test_name (dev=$dev rota=$rota tran=$tran)"
        echo "  Expected: $expected"
        echo "  Got:      $result"
        fails=$((fails+1))
    else
        echo "PASS: $test_name -> $expected"
    fi
}

echo "Running tests for detect_drive_type..."

run_test "NVMe SSD with SED" "nvme0n1" "0" "nvme" "nvme-ssd-sed" "oacs: 0x02 sanitize" "Locking Y"
run_test "NVMe SSD without SED" "nvme0n1" "0" "nvme" "nvme-ssd" "oacs: 0x02 sanitize" "Locking N"
run_test "NVMe SSD without Sanitize support" "nvme0n1" "0" "nvme" "nvme-ssd" "oacs: 0x01" "Locking Y"
run_test "USB Flash Drive" "sda" "1" "usb" "usb-flash" "" ""
run_test "SATA SSD with SED" "sdb" "0" "sata" "sata-ssd-sed" "" "Locking Y"
run_test "SATA SSD without SED" "sdb" "0" "sata" "sata-ssd" "" "Locking N"
run_test "Hard Disk Drive (HDD)" "sdc" "1" "sata" "hdd" "" ""

# Additional edge cases
run_test "NVMe SSD (Capitalized SED output)" "nvme0n1" "0" "nvme" "nvme-ssd-sed" "OACS: 0x04 SANITIZE" "Locking Y"
run_test "NVMe SSD (Empty outputs)" "nvme0n1" "0" "nvme" "nvme-ssd" "" ""

if [[ $fails -eq 0 ]]; then
    echo "All tests passed successfully."
else
    echo "$fails test(s) failed."
    # Wait to fail script until exit can be handled outside of subshell
    /bin/false
fi
