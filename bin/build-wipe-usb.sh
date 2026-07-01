#!/bin/bash
# Build a Simmons-Systems-Rescue Disk Wipe USB: SystemRescue ISO + NIST 800-88
# wipe scripts baked into a writable second partition.
#
# Usage:
#   build-wipe-usb.sh /dev/sdX                     # flash directly to USB
#   build-wipe-usb.sh --output dist/wipe.img       # build sparse image file
#   build-wipe-usb.sh --dry-run --output /tmp/test.img
#
# Requires: curl, gpg, dosfstools, parted, util-linux (losetup), mtools.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CACHE_DIR="${REPO_ROOT}/.cache"
SYSRESCUE_VERSION="${SYSRESCUE_VERSION:-13.00}"
SYSRESCUE_ISO_URL="https://fastly-cdn.system-rescue.org/releases/${SYSRESCUE_VERSION}/systemrescue-${SYSRESCUE_VERSION}-amd64.iso"
SYSRESCUE_SIG_URL="${SYSRESCUE_ISO_URL}.asc"
SYSRESCUE_SIGNING_KEY="0FF11AF081E9834559481203 7091115F8320B897"
SYSRESCUE_SIGNING_KEY="${SYSRESCUE_SIGNING_KEY// /}"

WRITABLE_PART_MB="${WRITABLE_PART_MB:-512}"

dry_run=0
output=""
target=""

usage() {
    sed -n '2,12p' "$0"
    exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h | --help) usage 0 ;;
        --dry-run) dry_run=1; shift ;;
        --output) output="$2"; shift 2 ;;
        /dev/*) target="$1"; shift ;;
        *) echo "Unknown arg: $1" >&2; usage 1 ;;
    esac
done

if [[ -z "$output" && -z "$target" ]]; then
    echo "ERROR: must supply either --output FILE or /dev/sdX" >&2
    usage 1
fi

if [[ -n "$target" && "$target" == "/dev/sda" ]]; then
    echo "ERROR: refusing to write to /dev/sda (almost always your system disk)" >&2
    exit 2
fi

work_path=""
if [[ -n "$output" ]]; then
    work_path="$output"
    mkdir -p "$(dirname "$work_path")"
elif [[ -n "$target" ]]; then
    work_path="$target"
    if [[ $dry_run -eq 0 ]]; then
        echo
        lsblk "$target"
        echo
        read -r -p "Type 'yes' to overwrite ${target}: " confirm
        [[ "$confirm" == "yes" ]] || { echo "Aborted."; exit 3; }
    fi
fi

mkdir -p "$CACHE_DIR"
iso_path="${CACHE_DIR}/systemrescue-${SYSRESCUE_VERSION}-amd64.iso"
sig_path="${iso_path}.asc"

download_iso() {
    if [[ -f "$iso_path" ]]; then
        echo "==> Using cached ISO: $iso_path"
    else
        echo "==> Downloading SystemRescue ${SYSRESCUE_VERSION}..."
        curl -fL --retry 3 -o "$iso_path" "$SYSRESCUE_ISO_URL"
    fi
    if [[ ! -f "$sig_path" ]]; then
        curl -fL --retry 3 -o "$sig_path" "$SYSRESCUE_SIG_URL"
    fi
    echo "==> Verifying signature..."
    if ! gpg --list-keys "$SYSRESCUE_SIGNING_KEY" > /dev/null 2>&1; then
        gpg --keyserver keyserver.ubuntu.com --recv-keys "$SYSRESCUE_SIGNING_KEY" \
            || gpg --keyserver keys.openpgp.org --recv-keys "$SYSRESCUE_SIGNING_KEY"
    fi
    gpg --verify "$sig_path" "$iso_path"
}

build_image() {
    local out="$1"
    local iso_size_bytes
    iso_size_bytes="$(stat -c%s "$iso_path")"
    local iso_size_mb=$((iso_size_bytes / 1024 / 1024 + 1))
    local total_mb=$((iso_size_mb + WRITABLE_PART_MB + 4))

    echo "==> Allocating ${total_mb}MB image..."
    if [[ "${out}" == /dev/* ]]; then
        sudo dd if="$iso_path" of="$out" bs=4M conv=fsync status=progress

        echo "==> Adding writable FAT32 partition for wipe scripts + audit..."
        sudo parted -s "$out" mkpart primary fat32 "${iso_size_mb}MiB" 100%
        sudo partprobe "$out" || true
        sleep 1
        local part
        part="$(lsblk -blnpo NAME,SIZE,TYPE "$out" \
            | awk '$3=="part" {print $2, $1}' \
            | sort -nr | head -1 | awk '{print $2}')"
        sudo mkfs.vfat -n "SSRWIPE" "$part"
        local mp
        mp="$(mktemp -d)"
        sudo mount "$part" "$mp"
        sudo mkdir -p "$mp/autorun" "$mp/audit"
        sudo cp "${REPO_ROOT}/autorun/wipe-lib.sh" "$mp/autorun/"
        sudo cp "${REPO_ROOT}/autorun/wipe-wizard.sh" "$mp/autorun/"
        sudo cp "${REPO_ROOT}/autorun/wipe-now.sh" "$mp/autorun/"
        sudo chmod +x "$mp/autorun/"*.sh
        sudo touch "$mp/.simsys-wipe"
        sudo umount "$mp"
        rmdir "$mp"
    else
        truncate -s "${total_mb}M" "$out"
        dd if="$iso_path" of="$out" conv=notrunc bs=1M status=none

        local fat_img
        fat_img="$(mktemp)"
        truncate -s "${WRITABLE_PART_MB}M" "$fat_img"
        mkfs.vfat -n "SSRWIPE" "$fat_img"
        mmd -i "$fat_img" ::/autorun ::/audit
        mcopy -i "$fat_img" "${REPO_ROOT}/autorun/wipe-lib.sh" ::/autorun/
        mcopy -i "$fat_img" "${REPO_ROOT}/autorun/wipe-wizard.sh" ::/autorun/
        mcopy -i "$fat_img" "${REPO_ROOT}/autorun/wipe-now.sh" ::/autorun/
        marker_file="$(mktemp)"
        mcopy -i "$fat_img" "$marker_file" ::/.simsys-wipe
        rm -f "$marker_file"
        dd if="$fat_img" of="$out" bs=1M seek="$iso_size_mb" \
            count="$WRITABLE_PART_MB" conv=notrunc status=none
        rm -f "$fat_img"
    fi
    echo "==> Built: $out"
}

if [[ $dry_run -eq 1 ]]; then
    echo "==> Dry run: would download ${SYSRESCUE_ISO_URL} and build ${work_path}"
    echo "==> Skipping download + build (--dry-run)."
    if [[ -n "$output" ]]; then
        truncate -s 1M "$output"
        echo "==> Wrote 1MB stub at $output"
    fi
    exit 0
fi

download_iso
build_image "$work_path"

cat << EOF

==> SUCCESS — Disk Wipe USB built

Image: $work_path

Boot menu:
  1. WIPE-WIZARD — Interactive, per-drive selection + confirmation
  2. WIPE-NOW    — eWaste mode, 5-min countdown then auto-wipe all

Audit logs are written to the USB's /audit/ directory (JSON).

Physical labeling: mark with red electrical tape + "WIPE" to distinguish
from the rescue stick.

EOF
