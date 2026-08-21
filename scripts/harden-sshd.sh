#!/usr/bin/env bash
#
# Withdraw administrative and password-based SSH from the hypervisor.
# Operator-run: this edits /etc/ssh/sshd_config and reloads sshd.
#
#   sudo ./scripts/harden-sshd.sh
#
# Two changes, both from narrow-privileges group 5:
#
#   PermitRootLogin no        root SSH existed only so the provider could write
#                             cloud-init snippets. It writes them as tofu-snippets
#                             now, so nothing needs it (task 5.1).
#
#   drop the Match block      sshd_config sets `PasswordAuthentication no` and then
#                             re-enables it for `Match Address 192.168.0.*`. Any LAN
#                             host may authenticate by password, so the global
#                             setting is not the effective one (task 5.1a).
#
# Reload, not restart: existing sessions survive, so a mistake here does not
# disconnect the operator mid-repair. `sshd -t` runs first and aborts on a syntax
# error, before anything is applied.
#
# Reverting: the timestamped backup path is printed at the end.

set -euo pipefail

CONFIG="${SSHD_CONFIG:-/etc/ssh/sshd_config}"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${CONFIG}.${STAMP}.bak"

if [ "$(id -u)" -ne 0 ]; then
  echo "error: run this as root — it edits $CONFIG and reloads sshd" >&2
  exit 1
fi

# Refuse to lock everyone out. Withdrawing root login is only safe if some other
# account can still get in by key.
ADMIN_USER="${ADMIN_USER:-buzaga}"
ADMIN_KEYS="$(getent passwd "$ADMIN_USER" | cut -d: -f6)/.ssh/authorized_keys"
if [ ! -s "$ADMIN_KEYS" ]; then
  echo "error: $ADMIN_USER has no authorised keys at $ADMIN_KEYS." >&2
  echo "       Withdrawing root login and password auth would leave only the console." >&2
  echo "       Set ADMIN_USER, or authorise a key first." >&2
  exit 1
fi
echo "$ADMIN_USER keeps key access ($(grep -c . "$ADMIN_KEYS") entries in authorized_keys)"

cp -a "$CONFIG" "$BACKUP"
echo "backed up to $BACKUP"

python3 - "$CONFIG" <<'PY'
import re, sys

path = sys.argv[1]
lines = open(path).read().split('\n')

# Drop the Match block that re-enables password authentication on the LAN. A Match
# block runs to the next Match or to end of file, so remove its indented body too
# rather than only the header — leaving the body behind would attach those settings
# to whatever block precedes it.
out, dropping = [], False
for line in lines:
    if re.match(r'^\s*Match\s+Address\s+192\.168\.0\.\*\s*$', line):
        dropping = True
        out.append('# Match Address 192.168.0.* removed by scripts/harden-sshd.sh:')
        out.append('# it re-enabled password authentication for LAN clients, overriding')
        out.append('# the global PasswordAuthentication no above.')
        continue
    if dropping:
        if line.strip() == '' or line.startswith((' ', '\t')):
            continue          # still inside the block body
        dropping = False      # a new top-level directive ends it
    out.append(line)

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
        result.append(f'{key} {value}')
    return result

# Explicit rather than relying on the default. The default is prohibit-password,
# which still accepts a key — reading the file must tell you what is allowed.
out = set_directive(out, 'PermitRootLogin', 'no')

# PasswordAuthentication alone is not the whole story: with UsePAM yes,
# keyboard-interactive can still collect a password. The file sets the deprecated
# spelling (ChallengeResponseAuthentication); state the current one beside it so the
# two are read together rather than one being found and the other missed.
if not any(re.match(r'^\s*KbdInteractiveAuthentication\s', l, re.I) for l in out):
    for i, line in enumerate(out):
        if re.match(r'^\s*#?\s*ChallengeResponseAuthentication\s', line, re.I):
            out.insert(i + 1, 'KbdInteractiveAuthentication no')
            break
    else:
        out.append('KbdInteractiveAuthentication no')
else:
    out = set_directive(out, 'KbdInteractiveAuthentication', 'no')

text = '\n'.join(out)
open(path, 'w').write(text if text.endswith('\n') else text + '\n')
PY

echo "--- effective settings after the edit ---"
grep -nE '^(PermitRootLogin|PasswordAuthentication|KbdInteractiveAuthentication|ChallengeResponseAuthentication|Match)' "$CONFIG" | sed 's/^/  /'

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
echo "verify from the operator account:  make check-root-ssh"
echo "revert with:                       sudo cp -a $BACKUP $CONFIG && sudo systemctl reload ssh"
