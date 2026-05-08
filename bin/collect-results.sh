#!/bin/bash
# Read the most recent results-*.txt off a Simmons-Systems-Rescue USB stick.
#
# Usage:
#   collect-results.sh                 # auto-detect any plugged-in rescue USB
#   collect-results.sh /dev/sdX        # specify the device
#   collect-results.sh --copy /dev/sdX # also copy results into ~/nuc-burnin-results/
set -euo pipefail

DEST="${HOME}/nuc-burnin-results"
do_copy=0
target=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --copy)
            do_copy=1
            shift
            ;;
        /dev/*)
            target="$1"
            shift
            ;;
        -h | --help)
            sed -n '2,9p' "$0"
            exit 0
            ;;
        *)
            echo "Unknown arg: $1" >&2
            exit 1
            ;;
    esac
done

find_rescue_partition() {
    # Scan vfat partitions for a .simsys-rescue marker file.
    while read -r _src tgt fs _; do
        [[ "$fs" == "vfat" ]] || continue
        [[ -f "${tgt}/.simsys-rescue" ]] && {
            echo "$tgt"
            return 0
        }
    done < <(findmnt -rno SOURCE,TARGET,FSTYPE)
    return 1
}

mp=""
if [[ -n "$target" ]]; then
    # Find the writable partition on this device and mount it
    part="$(lsblk -lnpo NAME,FSTYPE "$target" | awk '$2=="vfat"{print $1; exit}')"
    [[ -n "$part" ]] || {
        echo "ERROR: no vfat partition found on $target" >&2
        exit 2
    }
    mp="$(mktemp -d)"
    sudo mount "$part" "$mp"
    trap 'sudo umount "$mp" 2>/dev/null; rmdir "$mp" 2>/dev/null' EXIT
else
    if ! mp="$(find_rescue_partition)"; then
        echo "ERROR: no Simmons-Systems-Rescue USB found mounted." >&2
        echo "       Mount the rescue stick first, or pass /dev/sdX explicitly." >&2
        exit 3
    fi
fi

results_dir="${mp}/results"
if [[ ! -d "$results_dir" ]]; then
    echo "ERROR: ${results_dir} not found on USB" >&2
    exit 4
fi

latest="$(ls -1t "$results_dir"/results-*.txt 2> /dev/null | head -1)"
if [[ -z "$latest" ]]; then
    echo "ERROR: no results-*.txt files found in ${results_dir}" >&2
    exit 5
fi

echo "==> Latest results: $latest"
echo
cat "$latest"

if [[ $do_copy -eq 1 ]]; then
    mkdir -p "$DEST"
    cp -v "$latest" "$DEST/"
    echo
    echo "==> Copied to $DEST/"
fi

# Quick top-of-output summary line
echo
overall="$(grep -E '^OVERALL: ' "$latest" || true)"
echo "==> Summary: ${overall:-no OVERALL line found}"
