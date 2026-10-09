#!/usr/bin/env bash
#
# Create the read-only Proxmox identity the in-cluster pve-exporter scrapes with: a
# pve-exporter@pve user holding the built-in PVEAuditor role, and a token with
# privilege separation ON. See-the-cluster, design D3, task 3.3.
#
# Runs against the API rather than pveum, so it needs no root and no TTY. It needs an
# administrative token to bootstrap. tofu/terraform.tfvars holds the scoped provisioning
# token, which cannot create users by design, so the admin token is always passed in:
#
#   PVE_ADMIN_TOKEN='root@pam!x=uuid' ./scripts/create-exporter-user.sh
#
# root@pam holds no tokens day to day; scripts/create-bootstrap-token.sh makes one for
# exactly this kind of step, and its output says to delete it afterwards.
#
# Re-runnable: the user and ACLs are updated in place if they already exist.

set -euo pipefail

ROLE="PVEAuditor"
USER_ID="pve-exporter@pve"
TOKEN_ID="metrics"
ACL_PATH="/"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TFVARS="$REPO_ROOT/tofu/terraform.tfvars"
OUT="$REPO_ROOT/tofu/observability.auto.tfvars"

# PVEAuditor is built in and read-only. On this host (PVE 9.2, read 2026-10-08):
# Datastore.Audit, Mapping.Audit, Pool.Audit, SDN.Audit, Sys.Audit, VM.Audit,
# VM.GuestAgent.Audit. It is what prometheus-pve-exporter documents, and it
# is enough for node, storage and per-VM metrics.
#
# A custom role was considered and not made. Every privilege in PVEAuditor is an Audit
# privilege, so narrowing it would trade a role anyone can look up for one that has to
# be explained, to save read access to pools and SDN that this host barely has.
#
# Granted at / because the exporter reads the whole tree: every node, VM and datastore.
# Read-only at the root is narrower than it sounds; the negative test in task 4.1 is
# what shows it.

die() { echo "error: $*" >&2; exit 1; }

[[ $EUID -eq 0 ]] && die "do not run this as root; it uses the API, not pveum"
[[ -f "$TFVARS" ]] || die "missing $TFVARS (the endpoint is read from it)"

ENDPOINT=$(sed -n 's/^proxmox_endpoint *= *"\(.*\)"/\1/p' "$TFVARS")
[[ -n "$ENDPOINT" ]] || die "could not read proxmox_endpoint from $TFVARS"

ADMIN_TOKEN="${PVE_ADMIN_TOKEN:-}"
[[ -n "$ADMIN_TOKEN" ]] || die "no admin token. The scoped token in terraform.tfvars cannot create users.
       Run with an administrative token:
         PVE_ADMIN_TOKEN='root@pam!<id>=<secret>' $0"
[[ "$ADMIN_TOKEN" == terraform@pve* ]] \
  && die "PVE_ADMIN_TOKEN is the scoped provisioning token, which cannot create users (that is the point)"

api() {  # token method path [curl args...]
  local token=$1 method=$2 path=$3; shift 3
  curl -sk -X "$method" -H "Authorization: PVEAPIToken=$token" \
       -w '\n%{http_code}' "${ENDPOINT}api2/json${path}" "$@"
}

check() {  # method path description [curl args...]
  local method=$1 path=$2 desc=$3; shift 3
  local out code body
  out=$(api "$ADMIN_TOKEN" "$method" "$path" "$@")
  code=${out##*$'\n'}; body=${out%$'\n'*}
  case "$code" in
    2*) echo "  ok    $desc" ;;
    *)  echo "  FAIL  $desc (http $code)"; echo "        $body" >&2; return 1 ;;
  esac
}

echo "Creating read-only exporter identity on $ENDPOINT"

# 1. The user. No password: this identity authenticates by token only.
if api "$ADMIN_TOKEN" GET "/access/users/$USER_ID" | tail -1 | grep -q '^2'; then
  echo "  ok    user $USER_ID already exists"
else
  check POST "/access/users" "user $USER_ID created" \
    --data-urlencode "userid=$USER_ID" \
    --data-urlencode "comment=pve-exporter in the k3s cluster. Read-only ($ROLE)."
fi

# 2. Grant the role to the user.
check PUT "/access/acl" "$ROLE granted to user at $ACL_PATH" \
  --data-urlencode "path=$ACL_PATH" --data-urlencode "roles=$ROLE" \
  --data-urlencode "users=$USER_ID"

# 3. The token, privilege separated. It starts with nothing and gets only what is
#    granted to it below, so widening the user later does not widen the token.
if api "$ADMIN_TOKEN" GET "/access/users/$USER_ID/token/$TOKEN_ID" | tail -1 | grep -q '^2'; then
  echo "  --    token $TOKEN_ID already exists; its secret is shown only at creation."
  echo "        Delete it first if you need a new secret:"
  echo "          curl -sk -X DELETE -H \"Authorization: PVEAPIToken=\$PVE_ADMIN_TOKEN\" \\"
  echo "            \"${ENDPOINT}api2/json/access/users/$USER_ID/token/$TOKEN_ID\""
  SECRET=""
else
  out=$(api "$ADMIN_TOKEN" POST "/access/users/$USER_ID/token/$TOKEN_ID" \
        --data-urlencode "privsep=1" \
        --data-urlencode "comment=pve-exporter. Privilege separated; $ROLE only.")
  code=${out##*$'\n'}; body=${out%$'\n'*}
  [[ "$code" == 2* ]] || die "token creation failed (http $code): $body"
  SECRET=$(printf '%s' "$body" | python3 -c 'import json,sys; print(json.load(sys.stdin)["data"]["value"])')
  echo "  ok    token $TOKEN_ID created with privsep=1"
fi

check PUT "/access/acl" "$ROLE granted to the token itself" \
  --data-urlencode "path=$ACL_PATH" --data-urlencode "roles=$ROLE" \
  --data-urlencode "tokens=${USER_ID}!${TOKEN_ID}"

echo
if [[ -z "$SECRET" ]]; then
  echo "Nothing written: the token already existed and its secret is not retrievable."
  unset ADMIN_TOKEN
  exit 0
fi

# 4. Prove the new token reads before writing it anywhere. The negative half (it cannot
#    write) is check-privileges' job, task 4.1, so it is asserted on every run rather
#    than once here.
TOKEN="${USER_ID}!${TOKEN_ID}=${SECRET}"
code=$(api "$TOKEN" GET "/cluster/resources" -o /dev/null | tail -1)
[[ "$code" == 2* ]] || die "the new token cannot read /cluster/resources (http $code); not written"
echo "  ok    the token reads the cluster"

# 5. Written, never printed. A secret echoed to a terminal survives in scrollback, in
#    shell history, and in any transcript of the session.
#
#    observability.auto.tfvars, not terraform.tfvars: that file is the scoped
#    provisioning credential and nothing else writes to it. Other lines in this file
#    (the Grafana Cloud values, task 3.2) are kept. Gitignored by *.auto.tfvars.
umask 077
touch "$OUT"
tmp=$(mktemp "$OUT.XXXXXX")
grep -v -E '^pve_exporter_token_(id|secret) *=' "$OUT" > "$tmp" || true
printf 'pve_exporter_token_id     = "%s"\n' "${USER_ID}!${TOKEN_ID}" >> "$tmp"
printf 'pve_exporter_token_secret = "%s"\n' "$SECRET" >> "$tmp"
mv "$tmp" "$OUT"
chmod 600 "$OUT"
echo "  ok    token written to tofu/$(basename "$OUT") (mode 600)"
git -C "$REPO_ROOT" check-ignore -q "$OUT" \
  && echo "  ok    git ignores it" \
  || echo "  WARN  git does NOT ignore tofu/$(basename "$OUT") — fix .gitignore before committing anything"
echo
echo "The variables are declared in task 5.1; until then tofu warns that they are undeclared."
echo "Delete the bootstrap admin token now if you made one for this."
unset SECRET TOKEN ADMIN_TOKEN
