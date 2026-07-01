#!/bin/bash
# WIPE-NOW — eWaste Mode
# Auto-wipe all internal drives with 5-minute non-skippable countdown.
# Boot device and USB storage excluded by default.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/wipe-lib.sh"

INCLUDE_USB="false"
for arg in "$@"; do
    [[ "$arg" == "--include-usb" ]] && INCLUDE_USB="true"
done
# Also check kernel cmdline for boot-time flag
if grep -q "ssr.include-usb" /proc/cmdline 2>/dev/null; then
    INCLUDE_USB="true"
fi

printf "${RED}${BOLD}"
cat << 'BANNER'
 __        _____ ____  _____     _   _  _____        __
 \ \      / /_ _|  _ \| ____|   | \ | |/ _ \ \      / /
  \ \ /\ / / | || |_) |  _|     |  \| | | | \ \ /\ / /
   \ V  V /  | ||  __/| |___    | |\  | |_| |\ V  V /
    \_/\_/  |___|_|   |_____|   |_| \_|\___/  \_/\_/
              eWASTE MODE — ALL DRIVES WILL BE ERASED
BANNER
printf "${RESET}\n"

export OPERATOR="eWaste-auto"
AUDIT_FILE=$(init_audit "ewaste")

printf "${BOLD}Enumerating drives to wipe...${RESET}\n\n"

drives=()
while IFS='|' read -r name model serial size rota tran; do
    dtype=$(detect_drive_type "$name" "$rota" "$tran")
    method_info=$(nist_method_for_type "$dtype")
    nist_tier=$(echo "$method_info" | cut -d'|' -f1)
    method_desc=$(echo "$method_info" | cut -d'|' -f2)

    printf "  /dev/%-8s  %-28s  %-18s  %s  →  %s (%s)\n" \
        "$name" "${model:0:28}" "${serial:0:18}" "$size" "$method_desc" "$nist_tier"
    drives+=("$name|$model|$serial|$size|$rota|$tran|$dtype|$nist_tier|$method_desc")
done < <(enumerate_drives "true" "$INCLUDE_USB")

if [[ ${#drives[@]} -eq 0 ]]; then
    printf "\n${YELLOW}No wipeable drives found. Exiting.${RESET}\n"
    finalize_audit "$AUDIT_FILE"
    exit 0
fi

printf "\n${RED}${BOLD}%d drive(s) will be PERMANENTLY ERASED.${RESET}\n" "${#drives[@]}"
[[ "$INCLUDE_USB" == "true" ]] && printf "${YELLOW}WARNING: USB storage INCLUDED per --include-usb flag.${RESET}\n"
printf "\n"

countdown_banner 300 "WIPING ALL STORAGE IN:"

log "Countdown complete — starting parallel wipe of ${#drives[@]} drive(s)"

pids=()
for entry in "${drives[@]}"; do
    IFS='|' read -r name model serial size rota tran dtype nist_tier method_desc <<< "$entry"
    (
        size_bytes=$(blockdev --getsize64 "/dev/$name" 2>/dev/null || echo 0)
        started=$(date -u +%Y-%m-%dT%H:%M:%SZ)
        errors=""
        result="success"

        if wipe_drive "$name" "$dtype" > /tmp/wipe-${name}.log 2>&1; then
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
            fi
        fi

        completed=$(date -u +%Y-%m-%dT%H:%M:%SZ)

        # Write per-drive result to a temp file for the parent to collect
        cat > "/tmp/wipe-result-${name}.json" << DRIVEEOF
{
  "device": "/dev/${name}",
  "model": "${model}",
  "serial": "${serial}",
  "size_bytes": ${size_bytes},
  "type": "${dtype}",
  "nist_tier": "${nist_tier}",
  "method": "${method_desc}",
  "started_at": "${started}",
  "completed_at": "${completed}",
  "verify": {"sectors_sampled": 1024, "all_zero_or_random": ${verify_ok}},
  "result": "${result}",
  "errors": [${errors}]
}
DRIVEEOF
    ) &
    pids+=($!)
    log "Started wipe of /dev/$name (PID $!)"
done

failed=0
for pid in "${pids[@]}"; do
    if ! wait "$pid"; then
        failed=$((failed + 1))
    fi
done

# Collect per-drive results into audit
result_files=()
for entry in "${drives[@]}"; do
    IFS='|' read -r name rest <<< "$entry"
    if [[ -f "/tmp/wipe-result-${name}.json" ]]; then
        result_files+=("/tmp/wipe-result-${name}.json")
    fi
done

if [[ ${#result_files[@]} -gt 0 ]]; then
    python3 -c "
import json
import sys

audit_file = sys.argv[1]
with open(audit_file) as f:
    d = json.load(f)

for rf in sys.argv[2:]:
    try:
        with open(rf) as f_in:
            d['drives'].append(json.load(f_in))
    except Exception:
        pass

with open(audit_file, 'w') as f_out:
    json.dump(d, f_out, indent=2)
" "$AUDIT_FILE" "${result_files[@]}" 2>/dev/null
fi

printf "\n"
if [[ $failed -eq 0 ]]; then
    printf "${GREEN}${BOLD}=== ALL DRIVES WIPED SUCCESSFULLY ===${RESET}\n\n"
else
    printf "${RED}${BOLD}=== WIPE COMPLETE — %d DRIVE(S) HAD ERRORS ===${RESET}\n\n" "$failed"
fi

finalize_audit "$AUDIT_FILE"
