#!/bin/bash
# Network interface inventory and link-status snapshot.
# Informational — does not fail the run if no link is detected (the box may
# legitimately be off-LAN during burn-in).
set -uo pipefail
# shellcheck source=../lib.sh
source "$(dirname "$0")/../lib.sh"

for iface_path in /sys/class/net/*; do
    iface="$(basename "$iface_path")"
    [[ "$iface" == "lo" ]] && continue
    section "interface ${iface}"
    ip -br addr show "$iface" 2> /dev/null
    ethtool "$iface" 2> /dev/null | grep -E "(Speed|Duplex|Link detected|driver|firmware-version):" || true
done

exit 0
