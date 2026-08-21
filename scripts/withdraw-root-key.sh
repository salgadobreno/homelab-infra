#!/usr/bin/env bash
#
# Remove the provisioning key from /root/.ssh/authorized_keys, so withdrawing root
# SSH is a removed credential rather than a toggle someone can flip back.
# Operator-run: only root can read that file.
#
#   sudo ./scripts/withdraw-root-key.sh              # remove the operator's key
#   sudo PURGE=all ./scripts/withdraw-root-key.sh    # remove every key root holds
#
# `PermitRootLogin no` already refuses these keys. This matters because that line is
# one edit away from being undone, and a key left in place is a credential that still
# works the moment it is. Task 5.4.
#
# Re-runnable. Backs the file up first, and prints what is left rather than assuming
# the file held only what we put there.

set -euo pipefail

KEYS="${ROOT_AUTHORIZED_KEYS:-/root/.ssh/authorized_keys}"
PUBKEY_PATH="${PUBKEY_PATH:-/home/buzaga/.ssh/id_ed25519.pub}"
STAMP="$(date +%Y%m%d-%H%M%S)"

if [ "$(id -u)" -ne 0 ]; then
  echo "error: run this as root — only root can read $KEYS" >&2
  exit 1
fi

if [ ! -e "$KEYS" ]; then
  echo "$KEYS does not exist — nothing to withdraw"
  exit 0
fi

BEFORE="$(grep -c '^[^#]' "$KEYS" 2>/dev/null || true)"
echo "$KEYS holds $BEFORE key(s) before this runs"

BACKUP="${KEYS}.${STAMP}.bak"
cp -a "$KEYS" "$BACKUP"
chmod 600 "$BACKUP"
echo "backed up to $BACKUP"

if [ "${PURGE:-}" = "all" ]; then
  : > "$KEYS"
  echo "removed every key"
else
  if [ ! -r "$PUBKEY_PATH" ]; then
    echo "error: cannot read $PUBKEY_PATH — set PUBKEY_PATH, or use PURGE=all" >&2
    exit 1
  fi
  # Match on the key body alone. The comment field and any prefixed options differ
  # between how a key was installed and how it reads now, so matching whole lines
  # would silently remove nothing.
  BODY="$(awk '{print $2}' "$PUBKEY_PATH")"
  if ! grep -qF -- "$BODY" "$KEYS"; then
    echo "the operator key is not present — nothing to withdraw"
    rm -f "$BACKUP"
    exit 0
  fi
  grep -vF -- "$BODY" "$KEYS" > "${KEYS}.new"
  mv -f "${KEYS}.new" "$KEYS"
  chmod 600 "$KEYS"
  echo "removed the operator key"
fi

AFTER="$(grep -c '^[^#]' "$KEYS" 2>/dev/null || true)"
echo "$KEYS now holds $AFTER key(s)"
if [ "$AFTER" -gt 0 ]; then
  echo
  echo "still authorised for root — decide whether each should stay:"
  awk '/^[^#]/ {print "  " $1 " ..." substr($2, length($2)-15) " " $3}' "$KEYS"
  echo
  echo "remove them all with:  sudo PURGE=all $0"
fi

echo
echo "verify from the operator account:  make check-root-ssh"
echo "revert with:                       sudo cp -a $BACKUP $KEYS"
