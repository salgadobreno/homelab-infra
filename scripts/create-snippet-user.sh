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
# Why this account needs a real shell: sshd spawns the sftp subsystem through the
# user's login shell (`Subsystem sftp /usr/lib/openssh/sftp-server` in
# /etc/ssh/sshd_config). /usr/sbin/nologin would refuse the upload. The account is
# still password-locked, so the shell is reachable only with the key below.
#
# Why no sudoers entry: the provider talks SFTP, not a shell, and this configuration
# never takes its one escalating code path. See design.md, Open Question 2.

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
find "$SNIPPET_DIR" -maxdepth 1 -type f ! -user "$USER_NAME" \
  -exec chown "$USER_NAME:$USER_NAME" {} + -print | sed 's/^/  re-owned: /'

echo
echo "done. Verify from the operator account, with the agent loaded:"
echo "  ssh -p 4444 ${USER_NAME}@192.168.0.21 'id -un; touch ${SNIPPET_DIR}/.probe && rm ${SNIPPET_DIR}/.probe && echo writable'"
