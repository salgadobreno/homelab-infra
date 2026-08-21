#!/usr/bin/env bash
# Creates a temporary administrative API token, used once to bootstrap the scoped
# provisioning credential on a fresh host. It is not the token OpenTofu runs with.
#
# The chain is three steps, and the third is not optional:
#
#   ./scripts/create-bootstrap-token.sh                        # this script
#   PVE_ADMIN_TOKEN="$(cat tofu/.bootstrap-token)" \
#     ./scripts/create-terraform-user.sh                       # writes terraform.tfvars
#   sudo pveum user token remove root@pam bootstrap            # and delete this one
#
# Run as your normal user, NOT under sudo — the script calls sudo only for pveum, so
# the file it writes ends up owned by you rather than by root.
#
# It deliberately does not touch terraform.tfvars. That file holds the scoped
# terraform@pve token, and an admin token landing there would undo the whole of the
# narrow-privileges change without anything appearing to break.
set -euo pipefail

TOKEN_USER="${TOKEN_USER:-root@pam}"
TOKEN_ID="${TOKEN_ID:-bootstrap}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$REPO_ROOT/tofu/.bootstrap-token"
RECREATE=0
FORCE=0

usage() {
  cat <<'USAGE'
usage: create-bootstrap-token.sh [--recreate] [--force]

  --recreate  Delete an existing token of the same name and issue a new one.
              The old secret stops working immediately.
  --force     Overwrite tofu/.bootstrap-token if it already exists.

Environment overrides: TOKEN_USER (default root@pam), TOKEN_ID (default bootstrap).
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --recreate) RECREATE=1 ;;
    --force)    FORCE=1 ;;
    -h|--help)  usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

die() { echo "error: $*" >&2; exit 1; }

[ "${EUID:-$(id -u)}" -ne 0 ] || die "run as your normal user, not under sudo (see header)"

PVEUM="$(command -v pveum || echo /usr/sbin/pveum)"
[ -x "$PVEUM" ] || die "pveum not found — is this the Proxmox host?"

# Detect the node name and API endpoint rather than hardcoding them.
NODE="$(hostname -s)"
HOST_IP="$(ip -4 -o addr show vmbr0 2>/dev/null | awk '{print $4}' | cut -d/ -f1)"
[ -n "$HOST_IP" ] || die "could not determine the vmbr0 address"
ENDPOINT="https://${HOST_IP}:8006/"

echo "node:     $NODE"
echo "endpoint: $ENDPOINT"
echo "token:    ${TOKEN_USER}!${TOKEN_ID}"
echo

# Guard the output file before creating anything, so a refusal here does not leave an
# orphaned token behind.
if [ -s "$OUT" ] && [ "$FORCE" -eq 0 ]; then
  die "$OUT already exists — pass --force to overwrite, or delete it once it has been used"
fi

echo "requesting sudo for pveum..."
sudo -v || die "sudo authentication failed"

token_exists() {
  sudo "$PVEUM" user token list "$TOKEN_USER" --output-format json 2>/dev/null \
    | python3 -c "import json,sys;print(any(t.get('tokenid')==sys.argv[1] for t in json.load(sys.stdin)))" "$TOKEN_ID" \
    2>/dev/null | grep -q True
}

if token_exists; then
  [ "$RECREATE" -eq 1 ] || die "token ${TOKEN_USER}!${TOKEN_ID} already exists (its secret cannot be re-read) — pass --recreate to replace it"
  echo "removing existing token ${TOKEN_USER}!${TOKEN_ID}"
  sudo "$PVEUM" user token remove "$TOKEN_USER" "$TOKEN_ID" >/dev/null
fi

# --privsep 0 is essential: with privilege separation on (the default) the token
# inherits no permissions and every API call fails with a 403 that reads like a bad
# secret. This is the most common way this step goes wrong.
echo "creating token..."
TOKEN_JSON="$(sudo "$PVEUM" user token add "$TOKEN_USER" "$TOKEN_ID" --privsep 0 --output-format json)"

read -r FULL_ID SECRET PRIVSEP <<<"$(printf '%s' "$TOKEN_JSON" | python3 -c "
import json,sys
d=json.load(sys.stdin)
info=d.get('info') or {}
if isinstance(info,str): info=json.loads(info)
print(d.get('full-tokenid',''), d.get('value',''), info.get('privsep','?'))
")"

[ -n "$FULL_ID" ] && [ -n "$SECRET" ] || die "could not parse the token from pveum output"
[ "$PRIVSEP" = "0" ] || die "token was created with privilege separation enabled (privsep=$PRIVSEP) — remove it and re-run"

# Write with a restrictive umask so the secret is never briefly world-readable, and to
# a file rather than to stdout: a credential echoed into a terminal outlives the command
# in scrollback and in any transcript of the session.
mkdir -p "$(dirname "$OUT")"
( umask 077; printf '%s=%s' "$FULL_ID" "$SECRET" > "$OUT" )
chmod 600 "$OUT"

# Task 2.3: prove the token works against the API before OpenTofu is involved, so an
# auth failure cannot be mistaken for a provider problem. --insecure because the host
# serves its own certificate.
echo "verifying token against the API..."
HTTP_CODE="$(curl -sS --insecure -o /dev/null -w '%{http_code}' \
  -H "Authorization: PVEAPIToken=${FULL_ID}=${SECRET}" \
  "${ENDPOINT}api2/json/nodes" || true)"

unset SECRET TOKEN_JSON

case "$HTTP_CODE" in
  200) echo "  OK — API returned 200" ;;
  401) die "API returned 401: the token was rejected" ;;
  403) die "API returned 403: token authenticated but lacks permissions — check privsep" ;;
  000) die "could not reach ${ENDPOINT} — is the Proxmox API listening?" ;;
  *)   die "unexpected HTTP status $HTTP_CODE from the API" ;;
esac

echo
echo "wrote $OUT (mode 600)"
git -C "$REPO_ROOT" check-ignore -q "$OUT" \
  && echo "confirmed: git ignores it" \
  || echo "WARNING: git does NOT ignore $OUT — do not commit"

cat <<NEXT

This is an administrative credential with privilege separation off. It exists to create
the scoped one, and should not outlive that:

  PVE_ADMIN_TOKEN="\$(cat $OUT)" ./scripts/create-terraform-user.sh
  sudo pveum user token remove ${TOKEN_USER} ${TOKEN_ID}
  shred -u $OUT

Then confirm what is left:  make check-privileges
NEXT
