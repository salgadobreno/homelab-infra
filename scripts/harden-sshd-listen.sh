#!/usr/bin/env bash
#
# Narrow what sshd exposes: bind it to loopback and the LAN address instead of the
# wildcard, restrict who may log in, and turn off the forwarding features nothing uses.
# Operator-run: this edits /etc/ssh/sshd_config and reloads sshd.
#
#   sudo ./scripts/harden-sshd-listen.sh
#
# Why the bind matters. The tunnel reaches sshd as 127.0.0.1, so the wildcard listener
# serves nobody the tunnel needs — it only answers the LAN and whatever the router
# forwards. Binding to 127.0.0.1 keeps the tunnel working and to LAN_ADDR keeps a rescue
# path that does not depend on cloudflared being alive.
#
# This does NOT close the tunnel path. Anyone who reaches the public hostname still
# reaches sshd; only a Cloudflare Access policy stops that. See SECURITY.md.
#
# Reload, not restart: existing sessions survive, so a mistake here does not disconnect
# the operator mid-repair. `sshd -t` runs first and aborts before anything is applied.
#
# Re-runnable. Reverting: the timestamped backup path is printed at the end.

set -euo pipefail

CONFIG="${SSHD_CONFIG:-/etc/ssh/sshd_config}"
LAN_ADDR="${LAN_ADDR:-192.168.0.21}"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${CONFIG}.${STAMP}.bak"

if [ "$(id -u)" -ne 0 ]; then
  echo "error: run this as root — it edits $CONFIG and reloads sshd" >&2
  exit 1
fi

# sshd refuses to start when a ListenAddress is not present on any interface. A reload
# does not re-bind, so the damage would surface at the next reboot rather than now —
# check before writing rather than discovering it cold.
if ! ip -o addr show | grep -qw "$LAN_ADDR"; then
  echo "error: $LAN_ADDR is not configured on any interface." >&2
  echo "       sshd would fail to bind it at the next restart. Set LAN_ADDR." >&2
  exit 1
fi
echo "LAN rescue address $LAN_ADDR is present"

# Every account that holds keys must appear in AllowUsers, or its logins stop. The one
# that matters is the snippet uploader: nothing fails until the next `make rebuild`.
ALLOW_USERS="${ALLOW_USERS:-buzaga tofu-snippets}"
for u in $ALLOW_USERS; do
  getent passwd "$u" >/dev/null || { echo "error: no such account: $u" >&2; exit 1; }
done
echo "AllowUsers will be: $ALLOW_USERS"

# Warn about any other account holding keys, rather than silently cutting it off.
while IFS= read -r keyfile; do
  owner="$(stat -c %U "$keyfile")"
  case " $ALLOW_USERS " in
    *" $owner "*) ;;
    *) echo "WARNING: $owner holds keys ($keyfile) but is not in AllowUsers — it will lose SSH" ;;
  esac
done < <(find /home /root /var/lib -maxdepth 3 -name authorized_keys -type f 2>/dev/null)

cp -a "$CONFIG" "$BACKUP"
echo "backed up to $BACKUP"

LAN_ADDR="$LAN_ADDR" ALLOW_USERS="$ALLOW_USERS" python3 - "$CONFIG" <<'PY'
import os, re, sys

path = sys.argv[1]
lan = os.environ['LAN_ADDR']
allow_users = os.environ['ALLOW_USERS']
lines = open(path).read().split('\n')


def insert_global(lines, directive):
    """Append a directive to the global section, before any active Match block.

    Everything after a `Match` belongs to that block. Appending at end of file would
    silently scope a global setting to whichever Match happens to be last — the
    directive would still read correctly and mean something else entirely.
    """
    for i, line in enumerate(lines):
        if re.match(r'^\s*Match\s+\S', line, re.I):
            return lines[:i] + [directive] + lines[i:]
    return lines + [directive]


def set_directive(lines, key, value):
    """Set a directive once, replacing any active setting and any commented default."""
    pat_active = re.compile(rf'^\s*{key}\s+\S+', re.I)
    pat_comment = re.compile(rf'^\s*#\s*{key}\s+\S+', re.I)
    done = False
    result = []
    for line in lines:
        if pat_active.match(line):
            if not done:
                result.append(f'{key} {value}')
                done = True
            continue
        if pat_comment.match(line) and not done:
            result.append(f'{key} {value}')
            done = True
            continue
        result.append(line)
    if not done:
        result = insert_global(result, f'{key} {value}')
    return result


def set_multi(lines, key, values):
    """Replace every occurrence of a repeatable directive with exactly `values`.

    ListenAddress is cumulative rather than last-wins, so set_directive's replace-one
    behaviour would leave earlier binds in place and widen what we meant to narrow.
    """
    pat = re.compile(rf'^\s*#?\s*{key}\s+\S+', re.I)
    result, placed = [], False
    for line in lines:
        if pat.match(line):
            if not placed:
                result.extend(f'{key} {v}' for v in values)
                placed = True
            continue
        result.append(line)
    if not placed:
        for v in values:
            result = insert_global(result, f'{key} {v}')
    return result


# Loopback carries the tunnel; the LAN address is the rescue path. ::1 keeps IPv6
# loopback working — naming any ListenAddress drops the IPv6 wildcard too.
out = set_multi(lines, 'ListenAddress', ['127.0.0.1', lan, '::1'])

out = set_directive(out, 'AllowUsers', allow_users)

# Nothing on a headless hypervisor needs these, and each is a step available to a
# session that gets in.
out = set_directive(out, 'X11Forwarding', 'no')
out = set_directive(out, 'AllowAgentForwarding', 'no')
out = set_directive(out, 'PermitTunnel', 'no')

# Down from the defaults of 6 and 120.
out = set_directive(out, 'MaxAuthTries', '3')
out = set_directive(out, 'LoginGraceTime', '30')

# Every tunnel connection arrives as 127.0.0.1, so the source address attributes
# nothing. VERBOSE logs the fingerprint of the key that authenticated, which is the
# only per-device attribution left.
out = set_directive(out, 'LogLevel', 'VERBOSE')

# Deliberately untouched: AllowTcpForwarding (ssh -L to the Proxmox UI on 8006 uses
# it), GatewayPorts (verify no ssh -R workflow depends on it first), and the
# ClientAlive pair, whose two-hour tolerance is what keeps a session alive over a
# flaky mobile tunnel.

text = '\n'.join(out)
open(path, 'w').write(text if text.endswith('\n') else text + '\n')
PY

echo "--- effective settings after the edit ---"
grep -nE '^(ListenAddress|AllowUsers|X11Forwarding|AllowAgentForwarding|PermitTunnel|MaxAuthTries|LoginGraceTime|LogLevel|Port)' "$CONFIG" | sed 's/^/  /'

if ! sshd -t; then
  echo
  echo "error: sshd rejected the new configuration. Restoring $BACKUP — nothing was applied." >&2
  cp -a "$BACKUP" "$CONFIG"
  exit 1
fi
echo "sshd -t: configuration is valid"

systemctl reload ssh 2>/dev/null || systemctl reload sshd
echo "sshd reloaded — existing sessions are unaffected"

echo
echo "NOTE: SIGHUP makes sshd re-exec itself, so the new ListenAddress binds now —"
echo "      established sessions survive as separate processes. If the bind had"
echo "      failed, no NEW connection would be possible; that is what the LAN_ADDR"
echo "      check above prevents. Confirm the listeners with 'ss -tln'."
echo
echo "verify:      make check-tunnel-ssh"
echo "revert with: sudo cp -a $BACKUP $CONFIG && sudo systemctl reload ssh"
