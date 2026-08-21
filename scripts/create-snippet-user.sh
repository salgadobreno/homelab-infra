#!/usr/bin/env bash
#
# Create the unprivileged account that owns the cloud-init snippet directory, so
# OpenTofu no longer needs root over SSH. Operator-run: this needs root, and agent
# sessions on this host have neither passwordless sudo nor a TTY.
#
#   sudo ./scripts/create-snippet-user.sh
#
# Re-runnable. Creates nothing that already exists and never removes a key it did
# not add.
#
# Why this account needs a real shell: the provider writes a `source_raw` snippet by
# piping the content through `tee` over an SSH exec, so the login shell runs. The
# account is still password-locked, so that shell is reachable only with the key below.
#
# Why no sudoers entry: `tee` writes as the account. Nothing in the lifecycle
# escalates. See design.md, Open Question 2 and its correction.

set -euo pipefail

USER_NAME="${SNIPPET_USER:-tofu-snippets}"
HOME_DIR="/var/lib/${USER_NAME}"
SNIPPET_DIR="${SNIPPET_DIR:-/var/lib/vz/snippets}"
PUBKEY_PATH="${PUBKEY_PATH:-/home/buzaga/.ssh/id_ed25519.pub}"

if [ "$(id -u)" -ne 0 ]; then
  echo "error: run this as root — it creates a host account and changes directory ownership" >&2
  exit 1
fi

if [ ! -d "$SNIPPET_DIR" ]; then
  echo "error: $SNIPPET_DIR does not exist. The 'local' datastore must advertise the" >&2
  echo "       snippets content type before this account has anything to own." >&2
  exit 1
fi

if [ ! -r "$PUBKEY_PATH" ]; then
  echo "error: cannot read $PUBKEY_PATH — set PUBKEY_PATH to the key OpenTofu presents" >&2
  exit 1
fi
PUBKEY="$(cat "$PUBKEY_PATH")"

# --- the account ------------------------------------------------------------------

if id -u "$USER_NAME" >/dev/null 2>&1; then
  echo "account $USER_NAME already exists — leaving it alone"
else
  useradd --system \
          --home-dir "$HOME_DIR" \
          --create-home \
          --shell /bin/sh \
          --comment "OpenTofu cloud-init snippet uploads" \
          "$USER_NAME"
  echo "created $USER_NAME (system account, no password)"
fi

# useradd leaves '!' in shadow, which already refuses password authentication.
# Assert it rather than assume it, since a re-run may meet an account someone else made.
passwd --lock "$USER_NAME" >/dev/null
echo "password authentication locked"

# --- the key ----------------------------------------------------------------------
#
# 'restrict' switches off port forwarding, agent forwarding, X11 and pty allocation.
# None of them are needed to write a file, and each is a way out of this account.

AUTH_KEYS="${HOME_DIR}/.ssh/authorized_keys"
install -d -m 700 -o "$USER_NAME" -g "$USER_NAME" "${HOME_DIR}/.ssh"
touch "$AUTH_KEYS"

KEY_BODY="$(awk '{print $2}' "$PUBKEY_PATH")"
if grep -qF -- "$KEY_BODY" "$AUTH_KEYS"; then
  echo "key already authorised for $USER_NAME"
else
  printf 'restrict %s\n' "$PUBKEY" >> "$AUTH_KEYS"
  echo "authorised the operator key for $USER_NAME"
fi
chown "$USER_NAME:$USER_NAME" "$AUTH_KEYS"
chmod 600 "$AUTH_KEYS"

# --- the directory ----------------------------------------------------------------
#
# Ownership, not 777. Proxmox itself reads this directory as root and is unaffected.

chown "$USER_NAME:$USER_NAME" "$SNIPPET_DIR"
chmod 755 "$SNIPPET_DIR"
echo "$SNIPPET_DIR is now owned by $USER_NAME"

# Existing snippets were written by root and would be unwritable by the new owner,
# which surfaces as a rebuild failing to replace a file it is meant to own.
find "$SNIPPET_DIR" -maxdepth 1 -type f ! -name .keep ! -user "$USER_NAME" \
  -exec chown "$USER_NAME:$USER_NAME" {} + -print | sed 's/^/  re-owned: /'

# --- the sentinel -----------------------------------------------------------------
#
# PVE::Storage::Plugin::free_image calls rmdir() on a volume's parent directory after
# deleting it, to clean up empty per-VM image directories. A snippet's parent is this
# directory, so `tofu destroy` removing the last snippet takes the directory with it —
# and storage activation recreates it root-owned, undoing the chown above on every
# rebuild.
#
# rmdir only removes an empty directory. This file keeps it non-empty. It is a
# dot-file because PVE enumerates snippets with glob '*', which does not match them,
# so it never appears as a phantom volume in the storage listing. Design D6.

KEEP="${SNIPPET_DIR}/.keep"
if [ ! -e "$KEEP" ]; then
  cat > "$KEEP" <<MARKER
Keeps this directory non-empty.

PVE removes a volume's parent directory when it becomes empty, which would drop the
ownership that lets OpenTofu upload cloud-init snippets without root. Deleting this
file re-introduces that failure on the next rebuild.

Created by scripts/create-snippet-user.sh in homelab-infra.
MARKER
  chmod 644 "$KEEP"
  echo "placed $KEEP so PVE cannot rmdir the directory on destroy"
else
  echo "sentinel $KEEP already present"
fi

echo
echo "done. Verify from the operator account, with the agent loaded:"
echo "  make check-snippet-user"
