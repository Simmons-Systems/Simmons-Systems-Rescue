#!/bin/bash
# Hardware inventory snapshot. Runs first so we have it even if later
# tests fail or the box panics mid-stress.
set -uo pipefail
# shellcheck source=../lib.sh
source "$(dirname "$0")/../lib.sh"

section "system / baseboard"
dmidecode -t system -t baseboard 2> /dev/null || log "WARN: dmidecode unavailable"

section "CPU"
lscpu

section "memory (dmidecode)"
dmidecode -t memory 2> /dev/null | grep -E "(Size|Speed|Manufacturer|Part Number|Serial Number|Locator):" || true

section "memory (free -h)"
free -h

section "storage"
lsblk -o NAME,SIZE,TYPE,FSTYPE,MODEL,SERIAL

section "PCI"
lspci -nn 2> /dev/null | head -50

section "USB"
lsusb 2> /dev/null

section "network interfaces"
ip -br link

section "lshw -short"
lshw -short 2> /dev/null | head -100 || log "WARN: lshw unavailable"

# Inventory is informational; never fail the run on this script alone.
exit 0
