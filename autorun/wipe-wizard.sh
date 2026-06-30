#!/bin/bash
# WIPE-WIZARD — Careful Mode
# Interactive per-drive NIST 800-88 wipe with confirmation.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/wipe-lib.sh"

WIPE_TMP_DIR=$(mktemp -d)
trap 'rm -rf "$WIPE_TMP_DIR"' EXIT

printf "${CYAN}${BOLD}"
cat << 'BANNER'
 __        _____ ____  _____   __        _____ _____   _    ____  ____
 \ \      / /_ _|  _ \| ____| \ \      / /_ _|__  /  / \  |  _ \|  _ \
  \ \ /\ / / | || |_) |  _|    \ \ /\ / / | |  / /  / _ \ | |_) | | | |
   \ V  V /  | ||  __/| |___    \ V  V /  | | / /_ / ___ \|  _ <| |_| |
    \_/\_/  |___|_|   |_____|    \_/\_/  |___/____/_/   \_\_| \_\____/
                        CAREFUL MODE — NIST 800-88
BANNER
printf "${RESET}\n"

read -rp "Operator name (optional, for audit log): " OPERATOR
export OPERATOR

AUDIT_FILE=$(init_audit "wizard")
log "Audit log initialized: $AUDIT_FILE"

printf "\n${BOLD}Enumerating drives...${RESET}\n\n"
printf "%-12s %-30s %-20s %-10s %-8s %-6s %-15s\n" \
    "DEVICE" "MODEL" "SERIAL" "SIZE" "TYPE" "TRAN" "WIPE METHOD"
printf '%0.s-' {1..105}; echo

drives=()
while IFS='|' read -r name model serial size rota tran; do
    dtype=$(detect_drive_type "$name" "$rota" "$tran")
    method_info=$(nist_method_for_type "$dtype")
    nist_tier=$(echo "$method_info" | cut -d'|' -f1)
    method_desc=$(echo "$method_info" | cut -d'|' -f2)

    printf "%-12s %-30s %-20s %-10s %-8s %-6s %-15s\n" \
        "/dev/$name" "${model:0:28}" "${serial:0:18}" "$size" "$dtype" "$tran" "$method_desc"
    drives+=("$name|$model|$serial|$size|$rota|$tran|$dtype|$nist_tier|$method_desc")
done < <(enumerate_drives "true" "false")

if [[ ${#drives[@]} -eq 0 ]]; then
    printf "\n${YELLOW}No wipeable drives found.${RESET}\n"
    finalize_audit "$AUDIT_FILE"
    exit 0
fi

printf "\n${BOLD}Select drives to wipe (one at a time):${RESET}\n\n"

selected=()
for i in "${!drives[@]}"; do
    IFS='|' read -r name model serial size rota tran dtype nist_tier method_desc <<< "${drives[$i]}"
    printf "  [%d] /dev/%-8s  %-28s  %-18s  %s\n" "$((i+1))" "$name" "$model" "$serial" "$size"
done

printf "\nEnter drive numbers separated by spaces (e.g., '1 3'), or 'q' to abort: "
read -r selection

[[ "$selection" == "q" ]] && { log "Aborted by operator"; exit 0; }

for num in $selection; do
    idx=$((num - 1))
    if [[ $idx -ge 0 && $idx -lt ${#drives[@]} ]]; then
        selected+=("${drives[$idx]}")
    fi
done

if [[ ${#selected[@]} -eq 0 ]]; then
    printf "${YELLOW}No drives selected. Aborting.${RESET}\n"
    exit 0
fi

printf "\n${RED}${BOLD}=== CONFIRMATION REQUIRED ===${RESET}\n\n"
printf "You are about to PERMANENTLY ERASE the following drives:\n\n"

for entry in "${selected[@]}"; do
    IFS='|' read -r name model serial size rota tran dtype nist_tier method_desc <<< "$entry"
    printf "  /dev/%-8s  %-28s  serial=%s  method=%s\n" "$name" "$model" "$serial" "$method_desc"
done

printf "\n${BOLD}For each drive, type WIPE followed by the last 4 characters of the serial number.${RESET}\n\n"

confirmed=()
for entry in "${selected[@]}"; do
    IFS='|' read -r name model serial size rota tran dtype nist_tier method_desc <<< "$entry"
    suffix="${serial: -4}"
    printf "To wipe /dev/%s (%s), type '${RED}WIPE %s${RESET}': " "$name" "$model" "$suffix"
    read -r confirm
    if [[ "$confirm" == "WIPE $suffix" ]]; then
        confirmed+=("$entry")
        printf "${GREEN}  Confirmed.${RESET}\n"
    else
        printf "${YELLOW}  Skipped (incorrect confirmation).${RESET}\n"
    fi
done

if [[ ${#confirmed[@]} -eq 0 ]]; then
    printf "\n${YELLOW}No drives confirmed. Aborting.${RESET}\n"
    finalize_audit "$AUDIT_FILE"
    exit 0
fi

printf "\n"
countdown_banner 30 "WIPING ${#confirmed[@]} DRIVE(S) IN:"

for entry in "${confirmed[@]}"; do
    IFS='|' read -r name model serial size rota tran dtype nist_tier method_desc <<< "$entry"
    size_bytes=$(blockdev --getsize64 "/dev/$name" 2>/dev/null || echo 0)
    started=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    errors=""
    result="success"

    if wipe_drive "$name" "$dtype" 2>&1 | tee -a "$WIPE_TMP_DIR/wipe-${name}.log"; then
        log "Wipe of /dev/$name completed"
    else
        result="failed"
        errors="\"wipe command returned non-zero\""
        log "WARN: Wipe of /dev/$name may have failed"
    fi

    verify_ok="false"
    if [[ "$result" == "success" ]]; then
        if verify_wipe "$name"; then
            verify_ok="true"
            log "Verification passed for /dev/$name"
        else
            log "WARN: Verification sampling found non-zero data on /dev/$name"
        fi
    fi

    completed=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    append_drive_audit "$AUDIT_FILE" "$name" "$model" "$serial" "$size_bytes" \
        "$dtype" "$nist_tier" "$method_desc" "$started" "$completed" "$result" \
        "$verify_ok" "$errors"
done

printf "\n${GREEN}${BOLD}=== WIPE COMPLETE ===${RESET}\n\n"
finalize_audit "$AUDIT_FILE"
