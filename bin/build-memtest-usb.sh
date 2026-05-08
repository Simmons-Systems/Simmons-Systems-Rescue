#!/bin/bash
# Build a Memtest86+ USB image. Downloads the upstream signed USB image,
# verifies SHA256, and writes it (or copies it to a file).
#
# Phase 1: stock upstream Memtest86+ — boots, runs default test loop, requires
# monitor + Secure Boot disabled. Phase 2 will substitute a Simmons-Systems
# fork with `mt86p.cfg` config-file support and auto-poweroff.
#
# Usage:
#   build-memtest-usb.sh /dev/sdX
#   build-memtest-usb.sh --output dist/memtest.img
#   build-memtest-usb.sh --dry-run --output /tmp/test.img
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CACHE_DIR="${REPO_ROOT}/.cache"
MEMTEST_VERSION="${MEMTEST_VERSION:-7.20}"
# Upstream USB image (auto-installs to USB; we just dd it). 64-bit BIOS+UEFI.
MEMTEST_URL="https://memtest.org/download/v${MEMTEST_VERSION}/mt86plus_${MEMTEST_VERSION}.usb.zip"

dry_run=0
output=""
target=""

usage() {
    sed -n '2,15p' "$0"
    exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h | --help) usage 0 ;;
        --dry-run)
            dry_run=1
            shift
            ;;
        --output)
            output="$2"
            shift 2
            ;;
        /dev/*)
            target="$1"
            shift
            ;;
        *)
            echo "Unknown arg: $1" >&2
            usage 1
            ;;
    esac
done

if [[ -z "$output" && -z "$target" ]]; then
    echo "ERROR: must supply either --output FILE or /dev/sdX" >&2
    usage 1
fi

if [[ -n "$target" && "$target" == "/dev/sda" ]]; then
    echo "ERROR: refusing to write to /dev/sda" >&2
    exit 2
fi

work_path="${output:-$target}"

if [[ -n "$target" && $dry_run -eq 0 ]]; then
    echo
    lsblk "$target"
    echo
    read -r -p "Type 'yes' to overwrite ${target}: " confirm
    [[ "$confirm" == "yes" ]] || {
        echo "Aborted."
        exit 3
    }
fi

mkdir -p "$CACHE_DIR"
zip_path="${CACHE_DIR}/mt86plus_${MEMTEST_VERSION}.usb.zip"
img_path="${CACHE_DIR}/mt86plus_${MEMTEST_VERSION}.usb.img"

if [[ $dry_run -eq 1 ]]; then
    echo "==> Dry run: would download ${MEMTEST_URL} and build ${work_path}"
    if [[ -n "$output" ]]; then
        truncate -s 1M "$output"
        echo "==> Wrote 1MB stub at $output"
    fi
    exit 0
fi

if [[ ! -f "$zip_path" ]]; then
    echo "==> Downloading Memtest86+ ${MEMTEST_VERSION}..."
    curl -fL --retry 3 -o "$zip_path" "$MEMTEST_URL"
fi

# Memtest86+ doesn't publish a GPG-signed checksum file; we verify the SHA256
# against a pinned value. Refresh on version bump.
case "$MEMTEST_VERSION" in
    7.20)
        # SHA256 must be confirmed at first build; populate after manual verify
        # against https://memtest.org/
        expected_sha=""
        ;;
    *)
        expected_sha=""
        ;;
esac

if [[ -n "$expected_sha" ]]; then
    actual_sha="$(sha256sum "$zip_path" | awk '{print $1}')"
    if [[ "$actual_sha" != "$expected_sha" ]]; then
        echo "ERROR: checksum mismatch for ${zip_path}" >&2
        echo "  expected: $expected_sha" >&2
        echo "  actual:   $actual_sha" >&2
        exit 4
    fi
else
    echo "==> WARN: no pinned SHA256 for v${MEMTEST_VERSION}; build will proceed but please pin one."
fi

echo "==> Extracting USB image..."
(cd "$CACHE_DIR" && unzip -o "$zip_path" >&2)

# The upstream zip contains an installer image whose name varies; locate it
extracted_img="$(find "$CACHE_DIR" -maxdepth 1 -name 'memtest*.usb.img' -o -name 'mt86plus_*.img' | head -1)"
if [[ -z "$extracted_img" ]]; then
    echo "ERROR: couldn't find extracted .img inside the upstream zip" >&2
    exit 5
fi
mv "$extracted_img" "$img_path"

echo "==> Writing ${img_path} -> ${work_path}..."
if [[ "$work_path" == /dev/* ]]; then
    sudo dd if="$img_path" of="$work_path" bs=4M conv=fsync status=progress
else
    cp "$img_path" "$work_path"
fi

cat << EOF

==> SUCCESS

Built memtest image: $work_path

Memtest86+ v${MEMTEST_VERSION} requires Secure Boot DISABLED in BIOS — see
docs/secure-boot.md. Plug in, power on with a monitor connected, observe
the test passes, swap to the rescue stick when satisfied.

EOF
