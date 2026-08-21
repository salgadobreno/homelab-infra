#!/usr/bin/env bash
#
# Run the Cloudflare tunnel as an unprivileged account, with its token in a mode-600
# file instead of the command line. Operator-run: it creates an account and rewrites a
# systemd unit.
#
#   TUNNEL_TOKEN='<new token from the Cloudflare dashboard>' sudo -E ./scripts/harden-cloudflared.sh
#
# Rotate the token first. The current one is world-readable on this host — it is in
# `/proc/<pid>/cmdline` and in a mode-644 unit file — and it has been printed into a
# session transcript. Hardening the storage of a token that is already known is
# theatre. Zero Trust dashboard -> Networks -> Tunnels -> the tunnel -> Configure ->
# refresh the token.
#
# Reusing the existing token is possible for a dry test, but it is not the default:
#
#   REUSE_EXISTING_TOKEN=yes sudo ./scripts/harden-cloudflared.sh
#
# Re-runnable. Backs up the unit, and restores it if the tunnel does not come back.

set -euo pipefail

UNIT="/etc/systemd/system/cloudflared.service"
SERVICE_USER="${SERVICE_USER:-cloudflared}"
TOKEN_DIR="/etc/cloudflared"
TOKEN_FILE="${TOKEN_DIR}/token"
ORIGIN_URL="${ORIGIN_URL:-http://127.0.0.1:30000/}"
STAMP="$(date +%Y%m%d-%H%M%S)"

if [ "$(id -u)" -ne 0 ]; then
  echo "error: run this as root — it creates an account and rewrites $UNIT" >&2
  exit 1
fi

[ -f "$UNIT" ] || { echo "error: $UNIT not found" >&2; exit 1; }

# --- the token --------------------------------------------------------------------

if [ -n "${TUNNEL_TOKEN:-}" ]; then
  TOKEN="$TUNNEL_TOKEN"
  echo "using the token supplied in the environment"
elif [ "${REUSE_EXISTING_TOKEN:-}" = "yes" ]; then
  TOKEN="$(grep -oP '(?<=--token )\S+' "$UNIT" || true)"
  [ -n "$TOKEN" ] || { echo "error: no --token found in $UNIT to reuse" >&2; exit 1; }
  echo "WARNING: reusing the existing token. It is already readable by every local"
  echo "         user and has been printed into a transcript. Rotate it."
else
  cat >&2 <<'USAGE'
error: no token supplied.

  Rotate the tunnel token in the Cloudflare Zero Trust dashboard, then:

    TUNNEL_TOKEN='<new token>' sudo -E ./scripts/harden-cloudflared.sh

  To harden the plumbing without rotating first (the token stays compromised):

    REUSE_EXISTING_TOKEN=yes sudo ./scripts/harden-cloudflared.sh
USAGE
  exit 1
fi

# --- the account ------------------------------------------------------------------
#
# The tunnel dials out. It binds nothing, needs no home, and needs no shell.

if id -u "$SERVICE_USER" >/dev/null 2>&1; then
  echo "account $SERVICE_USER already exists — leaving it alone"
else
  useradd --system --no-create-home --home-dir /nonexistent \
          --shell /usr/sbin/nologin \
          --comment "Cloudflare tunnel" "$SERVICE_USER"
  echo "created $SERVICE_USER (system account, no shell, no home)"
fi
passwd --lock "$SERVICE_USER" >/dev/null

# --- the token file ---------------------------------------------------------------
#
# Written with the restrictive mode already in place, rather than written and then
# chmod'ed: between those two steps the token would be world-readable on disk.

install -d -m 750 -o root -g "$SERVICE_USER" "$TOKEN_DIR"
install -m 600 -o "$SERVICE_USER" -g "$SERVICE_USER" /dev/null "$TOKEN_FILE"
printf '%s' "$TOKEN" > "$TOKEN_FILE"
echo "wrote $TOKEN_FILE (mode 600, owned by $SERVICE_USER)"
unset TOKEN TUNNEL_TOKEN

# --- the unit ---------------------------------------------------------------------

BACKUP="${UNIT}.${STAMP}.bak"
cp -a "$UNIT" "$BACKUP"
chmod 600 "$BACKUP"          # the old unit still contains the old token
echo "backed up to $BACKUP (mode 600 — it still holds the old token)"

cat > "$UNIT" <<UNITFILE
[Unit]
Description=cloudflared
After=network-online.target
Wants=network-online.target

[Service]
TimeoutStartSec=0
Type=notify
User=${SERVICE_USER}
Group=${SERVICE_USER}

# --token-file rather than --token: argv holds a path, and the environment holds
# nothing. /proc/<pid>/cmdline is world-readable, so a token on the command line is
# readable by every local user.
ExecStart=/usr/bin/cloudflared --no-autoupdate tunnel run --token-file ${TOKEN_FILE}

Restart=on-failure
RestartSec=5s

# The tunnel dials out and reads one file. Nothing here is needed for that, and each
# is a step available to a compromised process.
NoNewPrivileges=yes
PrivateTmp=yes
ProtectSystem=strict
ProtectHome=yes
ProtectKernelTunables=yes
ProtectControlGroups=yes
RestrictSUIDSGID=yes

[Install]
WantedBy=multi-user.target
UNITFILE
chmod 644 "$UNIT"            # no secret in it any more
echo "rewrote $UNIT"

# --- apply, and roll back if the tunnel does not come back ------------------------

systemctl daemon-reload
systemctl restart cloudflared

echo -n "waiting for the tunnel to register"
for _ in $(seq 1 30); do
  if systemctl is-active --quiet cloudflared \
     && journalctl -u cloudflared --since "-60s" --no-pager 2>/dev/null \
        | grep -qiE 'registered tunnel connection|connection.*registered'; then
    echo " — up"
    break
  fi
  echo -n "."
  sleep 2
done

if ! systemctl is-active --quiet cloudflared; then
  echo
  echo "error: cloudflared is not running. Restoring $BACKUP." >&2
  cp -a "$BACKUP" "$UNIT"
  chmod 644 "$UNIT"
  systemctl daemon-reload
  systemctl restart cloudflared
  echo "restored. The tunnel is back on the previous configuration." >&2
  exit 1
fi

echo
echo "origin still answering: $(curl -s -o /dev/null -w '%{http_code}' "$ORIGIN_URL")"
echo
echo "verify from the operator account:  make check-tunnel"
echo "revert with:                       sudo cp -a $BACKUP $UNIT && sudo systemctl daemon-reload && sudo systemctl restart cloudflared"
echo
echo "once you are satisfied, delete the backup — it still holds the old token:"
echo "  sudo shred -u $BACKUP"
