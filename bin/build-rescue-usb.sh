#!/bin/bash
# Build a Simmons-Systems-Rescue USB image: SystemRescue ISO + autorun
# harness baked into a writable second partition.
#
# Usage:
#   build-rescue-usb.sh /dev/sdX                     # flash directly to USB
#   build-rescue-usb.sh --output dist/rescue.img     # build sparse image file
#   build-rescue-usb.sh --dry-run --output /tmp/test.img
#
# Requires: curl, gpg, dosfstools, parted, util-linux (losetup), mtools.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CACHE_DIR="${REPO_ROOT}/.cache"
SYSRESCUE_VERSION="${SYSRESCUE_VERSION:-13.00}"
SYSRESCUE_ISO_URL="https://fastly-cdn.system-rescue.org/releases/${SYSRESCUE_VERSION}/systemrescue-${SYSRESCUE_VERSION}-amd64.iso"
SYSRESCUE_SIG_URL="${SYSRESCUE_ISO_URL}.asc"
# SystemRescue release-signing key fingerprint (Francois Dupoux)
SYSRESCUE_SIGNING_KEY="A2A4FB72F60429AC7C13923753DDFE5BDBC2EE3B"

# Size of writable FAT32 partition appended after the ISO (MB).
# Override at the call site: WRITABLE_PART_MB=128 ./bin/build-rescue-usb.sh /dev/sdX
WRITABLE_PART_MB="${WRITABLE_PART_MB:-512}"

dry_run=0
output=""
target=""

usage() {
    sed -n '2,12p' "$0"
    exit "${1:-0}"
}

# Parse args
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h | --help)
            usage 0
            ;;
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
    echo "ERROR: refusing to write to /dev/sda (almost always your system disk)" >&2
    exit 2
fi

# Resolve write target: file (--output) or block device.
work_path=""
if [[ -n "$output" ]]; then
    work_path="$output"
    mkdir -p "$(dirname "$work_path")"
elif [[ -n "$target" ]]; then
    work_path="$target"
    if [[ $dry_run -eq 0 ]]; then
        # Interactive confirmation before writing to a block device
        echo
        lsblk "$target"
        echo
        read -r -p "Type 'yes' to overwrite ${target}: " confirm
        [[ "$confirm" == "yes" ]] || {
            echo "Aborted."
            exit 3
        }
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
    # Import key if missing, then verify
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
        # Block device — write hybrid ISO directly + create writable region after
        sudo dd if="$iso_path" of="$out" bs=4M conv=fsync status=progress
    else
        truncate -s "${total_mb}M" "$out"
        # ISO occupies first iso_size_mb; we copy it in
        dd if="$iso_path" of="$out" conv=notrunc bs=1M status=none
    fi

    echo "==> Adding writable FAT32 partition for autorun + results..."
    # parted picks up where the ISO partition table ends and adds a new one
    # spanning the rest of the device.
    if [[ "${out}" == /dev/* ]]; then
        sudo parted -s "$out" mkpart primary fat32 "${iso_size_mb}MiB" 100%
        sudo partprobe "$out" || true
        # Identify the partition we just created (highest-numbered)
        local part
        part="$(lsblk -lnpo NAME "$out" | tail -1)"
        sudo mkfs.vfat -n "RESCUE" "$part"
        local mp
        mp="$(mktemp -d)"
        sudo mount "$part" "$mp"
        sudo cp -r "${REPO_ROOT}/autorun" "$mp/"
        sudo cp "${REPO_ROOT}/config/default.env" "$mp/"
        sudo cp "${REPO_ROOT}/config/sysrescue.yaml.template" "$mp/sysrescue.yaml"
        sudo touch "$mp/.simsys-rescue"
        sudo umount "$mp"
        rmdir "$mp"
    else
        # Sparse image: use mtools to write directly without loop-mounting (no sudo).
        # Build a separate FAT image then dd it in.
        local fat_img
        fat_img="$(mktemp)"
        truncate -s "${WRITABLE_PART_MB}M" "$fat_img"
        mkfs.vfat -n "RESCUE" "$fat_img"
        mcopy -i "$fat_img" -s "${REPO_ROOT}/autorun" ::/
        mcopy -i "$fat_img" "${REPO_ROOT}/config/default.env" ::/
        mcopy -i "$fat_img" "${REPO_ROOT}/config/sysrescue.yaml.template" ::/sysrescue.yaml
        : > /tmp/.simsys-rescue.marker
        mcopy -i "$fat_img" /tmp/.simsys-rescue.marker ::/.simsys-rescue
        rm -f /tmp/.simsys-rescue.marker
        dd if="$fat_img" of="$out" bs=1M seek="$iso_size_mb" \
            count="$WRITABLE_PART_MB" conv=notrunc status=none
        rm -f "$fat_img"
        # Append a partition entry to the GPT/MBR? SystemRescue ISO uses
        # an isohybrid MBR; we leave it intact and the second region is
        # accessible by SystemRescue's autorun via the marker-file probe in
        # autorun0 (which scans every mounted vfat).
    fi
    echo "==> Built: $out"
}

if [[ $dry_run -eq 1 ]]; then
    echo "==> Dry run: would download ${SYSRESCUE_ISO_URL} and build ${work_path}"
    echo "==> Skipping download + build (--dry-run)."
    # Still produce a tiny stub file so downstream verification works
    if [[ -n "$output" ]]; then
        truncate -s 1M "$output"
        echo "==> Wrote 1MB stub at $output"
    fi
    exit 0
fi

download_iso
build_image "$work_path"

cat << EOF

==> SUCCESS

Built rescue image: $work_path

Next steps:
  1. If you wrote to a block device, eject it and plug into a NUC.
  2. Power on. The box will boot SystemRescue, run autorun, then poweroff.
  3. Plug the USB into your dev box and run bin/collect-results.sh to read
     the results file.

EOF
