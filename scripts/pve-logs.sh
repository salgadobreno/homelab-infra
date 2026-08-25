#!/usr/bin/env bash
# What the hypervisor has been doing. Read-only, no root.
#
# Three sources, because they answer different questions:
#   services  — is the PVE stack and the tunnel up right now
#   tasks     — what was done to this host, BY WHOM. /var/log/pve/tasks/index is
#               the attribution record: every task carries the user that ran it,
#               so it shows whether anything is acting as root@pam rather than as
#               the scoped terraform@pve!tofu token.
#   journal   — recent errors, for when a service is not up
#
# Usage: scripts/pve-logs.sh [lines]   (default 15)
set -uo pipefail
n="${1:-15}"

echo "=== services ==="
for u in pveproxy pvedaemon pvestatd pve-cluster cloudflared; do
    printf '  %-14s %s\n' "$u" "$(systemctl is-active "$u" 2>/dev/null || echo unknown)"
done

echo
echo "=== last $n Proxmox tasks (who did what) ==="
if [ -r /var/log/pve/tasks/index ]; then
    tail -n "$n" /var/log/pve/tasks/index | tac | while IFS= read -r line; do
        upid="${line%% *}"
        rest="${line#* }"
        status="${rest#* }"
        IFS=':' read -r _ _ _ _ start type id user _ <<< "$upid"
        when=$(date -d "@$((16#$start))" '+%m-%d %H:%M' 2>/dev/null || echo '?')
        printf '  %s  %-12s %-8s %-16s %s\n' \
            "$when" "$type" "${id:--}" "$user" "${status:0:44}"
    done
else
    echo "  (/var/log/pve/tasks/index not readable)"
fi

echo
echo "=== recent errors in the journal ==="
if out=$(journalctl -p err -n "$n" --no-pager -o short-iso 2>/dev/null) && [ -n "$out" ]; then
    printf '%s\n' "$out" | sed 's/^/  /'
else
    echo "  (none, or the journal is not readable by this account)"
fi
