#!/bin/bash
# Shared functions for the NIST 800-88 disk-wipe USB.
# Sourced by wipe-wizard.sh and wipe-now.sh.

set -euo pipefail

SSR_WIPE_VERSION="1.0.0"
AUDIT_DIR="${AUDIT_DIR:-/run/audit}"

RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
BOLD='\033[1m'
RESET='\033[0m'

log() { printf '[%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1"; }
die() { printf "${RED}FATAL: %s${RESET}\n" "$1" >&2; exit 1; }

boot_device() {
    local root_dev
    root_dev=$(findmnt -no SOURCE / 2>/dev/null || echo "")
    if [[ -z "$root_dev" ]]; then
        root_dev=$(awk '$2 == "/" {print $1}' /proc/mounts | head -1)
    fi
    lsblk -ndo PKNAME "$root_dev" 2>/dev/null || basename "$(readlink -f "$root_dev" | sed 's/[0-9]*$//')"
}

is_usb_device() {
    local dev="$1"
    local transport
    transport=$(lsblk -ndo TRAN "/dev/$dev" 2>/dev/null || echo "")
    [[ "$transport" == "usb" ]]
}

enumerate_drives() {
    local exclude_boot="$1"
    local include_usb="${2:-false}"
    local boot_dev=""
    [[ "$exclude_boot" == "true" ]] && boot_dev=$(boot_device)

    local name model serial size rota tran type_raw remainder
    while read -r name model serial size rota tran type_raw remainder; do
        [[ "$name" == "$boot_dev" ]] && continue
        [[ "$include_usb" != "true" && "$tran" == "usb" ]] && continue
        [[ "$type_raw" != "disk" ]] && continue

        echo "$name|$model|$serial|$size|$rota|$tran"
    done < <(lsblk -dnpo NAME,MODEL,SERIAL,SIZE,ROTA,TRAN,TYPE 2>/dev/null | sed 's|/dev/||')
}

detect_drive_type() {
    local dev="$1"
    local rota="$2"
    local tran="$3"

    if [[ "$tran" == "nvme" ]]; then
        if nvme id-ctrl "/dev/$dev" 2>/dev/null | grep -qi "oacs.*0x[0-9a-f]*[02468ace].*sanitize"; then
            if sedutil-cli --query "/dev/$dev" 2>/dev/null | grep -q "Locking.*Y"; then
                echo "nvme-ssd-sed"
            else
                echo "nvme-ssd"
            fi
        else
            echo "nvme-ssd"
        fi
    elif [[ "$tran" == "usb" ]]; then
        echo "usb-flash"
    elif [[ "$rota" == "0" ]]; then
        if sedutil-cli --query "/dev/$dev" 2>/dev/null | grep -q "Locking.*Y"; then
            echo "sata-ssd-sed"
        else
            echo "sata-ssd"
        fi
    else
        echo "hdd"
    fi
}

nist_method_for_type() {
    local dtype="$1"
    case "$dtype" in
        nvme-ssd)      echo "Purge|Block Erase|nvme sanitize -a 2" ;;
        nvme-ssd-sed)  echo "Purge|Crypto Erase|nvme sanitize -a 4" ;;
        sata-ssd)      echo "Purge|ATA Secure Erase Enhanced|hdparm --security-erase-enhanced" ;;
        sata-ssd-sed)  echo "Purge|Crypto Erase|sedutil-cli --revertNoErase" ;;
        hdd)           echo "Purge|Random overwrite + verify|nwipe -m random -r 1 --verify=last" ;;
        usb-flash)     echo "Clear|Random overwrite (best-effort)|nwipe -m random" ;;
        *)             echo "Clear|Random overwrite (fallback)|nwipe -m random" ;;
    esac
}

unfreeze_drive() {
    local dev="$1"
    local state
    state=$(hdparm -I "/dev/$dev" 2>/dev/null | grep -i "frozen" || echo "")
    if echo "$state" | grep -qi "frozen"; then
        log "Drive /dev/$dev is frozen — attempting suspend-resume to unfreeze"
        rtcwake -m mem -s 3 2>/dev/null || true
        sleep 2
        state=$(hdparm -I "/dev/$dev" 2>/dev/null | grep -i "frozen" || echo "")
        if echo "$state" | grep -qi "frozen"; then
            log "WARN: /dev/$dev still frozen after suspend-resume"
            return 1
        fi
        log "Drive /dev/$dev unfrozen successfully"
    fi
    return 0
}

wipe_drive() {
    local dev="$1"
    local dtype="$2"
    local method_info
    method_info=$(nist_method_for_type "$dtype")
    local method_desc
    method_desc=$(echo "$method_info" | cut -d'|' -f2)
    local method_cmd
    method_cmd=$(echo "$method_info" | cut -d'|' -f3)

    log "Wiping /dev/$dev (type=$dtype, method=$method_desc)"

    case "$dtype" in
        nvme-ssd)
            nvme sanitize "/dev/$dev" -a 2 2>&1
            local rc=$?
            if [[ $rc -eq 0 ]]; then
                log "Waiting for NVMe sanitize to complete..."
                while nvme sanitize-log "/dev/$dev" 2>/dev/null | grep -q "in progress"; do
                    sleep 5
                done
            fi
            return $rc
            ;;
        nvme-ssd-sed)
            nvme sanitize "/dev/$dev" -a 4 2>&1
            local rc=$?
            if [[ $rc -eq 0 ]]; then
                while nvme sanitize-log "/dev/$dev" 2>/dev/null | grep -q "in progress"; do
                    sleep 5
                done
            fi
            return $rc
            ;;
        sata-ssd)
            if ! unfreeze_drive "$dev"; then
                log "FALLBACK: frozen drive, using nwipe overwrite instead"
                nwipe --autonuke --method=random --rounds=1 --verify=last "/dev/$dev" 2>&1
                return $?
            fi
            local wipe_pass
            wipe_pass=$(openssl rand -hex 16)
            hdparm --user-master u --security-set-pass "$wipe_pass" "/dev/$dev" 2>&1
            hdparm --user-master u --security-erase-enhanced "$wipe_pass" "/dev/$dev" 2>&1
            return $?
            ;;
        sata-ssd-sed)
            sedutil-cli --revertNoErase "/dev/$dev" debug 2>&1
            return $?
            ;;
        hdd)
            nwipe --autonuke --method=random --rounds=1 --verify=last "/dev/$dev" 2>&1
            return $?
            ;;
        usb-flash|*)
            nwipe --autonuke --method=random "/dev/$dev" 2>&1
            return $?
            ;;
    esac
}

verify_wipe() {
    local dev="$1"
    local samples=1024
    local block_size=512
    local dev_size
    dev_size=$(blockdev --getsize64 "/dev/$dev" 2>/dev/null || echo 0)
    [[ "$dev_size" -eq 0 ]] && return 1

    local all_zero=true
    for _ in $(seq 1 "$samples"); do
        local offset=$((RANDOM * RANDOM % (dev_size / block_size)))
        local data
        data=$(dd if="/dev/$dev" bs=$block_size skip="$offset" count=1 2>/dev/null | od -A n -t x1 | tr -d ' \n')
        if [[ -n "$data" ]] && ! echo "$data" | grep -qP '^(00|ff)+$'; then
            all_zero=false
            break
        fi
    done
    $all_zero
}

host_info() {
    local hostname manufacturer model service_tag
    hostname=$(hostname 2>/dev/null || echo "unknown")
    manufacturer=$(dmidecode -s system-manufacturer 2>/dev/null || echo "unknown")
    model=$(dmidecode -s system-product-name 2>/dev/null || echo "unknown")
    service_tag=$(dmidecode -s system-serial-number 2>/dev/null || echo "unknown")
    printf '{"hostname":"%s","manufacturer":"%s","model":"%s","service_tag":"%s"}' \
        "$hostname" "$manufacturer" "$model" "$service_tag"
}

init_audit() {
    local mode="$1"
    mkdir -p "$AUDIT_DIR"
    local ts
    ts=$(date -u +%Y%m%dT%H%M%SZ)
    local hostname
    hostname=$(hostname 2>/dev/null || echo "unknown")
    AUDIT_FILE="${AUDIT_DIR}/${hostname}-${ts}.json"

    python3 -c "
import json, sys
data = {
    'ssr_wipe_version': sys.argv[1],
    'mode': sys.argv[2],
    'host': json.loads(sys.argv[3]),
    'operator': sys.argv[4],
    'started_at': sys.argv[5],
    'completed_at': None,
    'drives': []
}
with open(sys.argv[6], 'w') as f:
    json.dump(data, f, indent=2)
" "${SSR_WIPE_VERSION}" "${mode}" "$(host_info)" "${OPERATOR:-}" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$AUDIT_FILE"
    echo "$AUDIT_FILE"
}

append_drive_audit() {
    local audit_file="$1"
    local dev="$2" model="$3" serial="$4" size_bytes="$5"
    local dtype="$6" nist_tier="$7" method_desc="$8"
    local started="$9" completed="${10}" result="${11}"
    local verify_ok="${12:-}" errors="${13:-}"

    local entry
    entry=$(cat << EOF
    {
      "device": "/dev/${dev}",
      "model": "${model}",
      "serial": "${serial}",
      "size_bytes": ${size_bytes},
      "type": "${dtype}",
      "nist_tier": "${nist_tier}",
      "method": "${method_desc}",
      "started_at": "${started}",
      "completed_at": "${completed}",
      "verify": {"sectors_sampled": 1024, "all_zero_or_random": ${verify_ok:-false}},
      "result": "${result}",
      "errors": [${errors}]
    }
EOF
    )

    local tmp
    tmp=$(mktemp)
    python3 -c '
import json, sys
with open(sys.argv[1]) as f:
    d = json.load(f)
d["drives"].append(json.loads(sys.argv[3]))
with open(sys.argv[2], "w") as f:
    json.dump(d, f, indent=2)
' "$audit_file" "$tmp" "$entry" 2>/dev/null && mv "$tmp" "$audit_file" || rm -f "$tmp"
}

finalize_audit() {
    local audit_file="$1"
    local tmp
    tmp=$(mktemp)
    local now
    now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    python3 -c '
import json, sys
with open(sys.argv[1]) as f:
    d = json.load(f)
d["completed_at"] = sys.argv[3]
with open(sys.argv[2], "w") as f:
    json.dump(d, f, indent=2)
' "$audit_file" "$tmp" "$now" 2>/dev/null && mv "$tmp" "$audit_file" || rm -f "$tmp"

    if command -v qrencode &>/dev/null; then
        qrencode -t ANSIUTF8 < "$audit_file" 2>/dev/null || true
    fi

    printf "\n${GREEN}Audit log: %s${RESET}\n" "$audit_file"
    cat "$audit_file"
}

countdown_banner() {
    local seconds="$1"
    local msg="$2"
    while [[ $seconds -gt 0 ]]; do
        local mins=$((seconds / 60))
        local secs=$((seconds % 60))
        printf "\r${RED}${BOLD}%s %d:%02d — POWER OFF TO ABORT${RESET}    " "$msg" "$mins" "$secs"
        if [[ $((seconds % 5)) -eq 0 ]]; then
            printf '\a'
        fi
        sleep 1
        seconds=$((seconds - 1))
    done
    printf "\n"
}
