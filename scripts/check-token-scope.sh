#!/usr/bin/env bash
#
# Prove the provisioning token cannot exceed its purpose.
#
# A credential that has never been shown to be refused anything has not been
# demonstrated to be narrow, so this asserts the refusals rather than reporting them.
# Every DENY below is an action the old root@pam token could perform.
#
# Read-only in effect: each denied call is expected to change nothing, and the two
# ALLOW checks are reads.
#
#   ./scripts/check-token-scope.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TFVARS="$REPO_ROOT/tofu/terraform.tfvars"

ENDPOINT=$(sed -n 's/^proxmox_endpoint *= *"\(.*\)"/\1/p' "$TFVARS")
TOKEN=$(sed -n 's/^proxmox_api_token *= *"\(.*\)"/\1/p' "$TFVARS")
[[ -n "$ENDPOINT" && -n "$TOKEN" ]] || { echo "cannot read $TFVARS" >&2; exit 1; }

USER_ID="${TOKEN%%!*}"
fails=0

probe() {  # expect method path description [curl args...]
  local expect=$1 method=$2 path=$3 desc=$4; shift 4
  local code
  code=$(curl -sk -o /dev/null -w '%{http_code}' -X "$method" \
         -H "Authorization: PVEAPIToken=$TOKEN" "${ENDPOINT}api2/json${path}" "$@")
  if [[ "$expect" == DENY ]]; then
    if [[ "$code" == 403 || "$code" == 401 ]]; then
      printf '  refused (%s)  %s\n' "$code" "$desc"
    elif [[ "$code" == 501 || "$code" == 400 ]]; then
      printf '  BADTEST (%s)  %s   <-- probe is malformed, not a scope result\n' "$code" "$desc"
      fails=$((fails+1))
    else
      printf '  ALLOWED (%s)  %s   <-- SCOPE REGRESSION\n' "$code" "$desc"; fails=$((fails+1))
    fi
  else
    if [[ "$code" == 2* ]]; then
      printf '  ok      (%s)  %s\n' "$code" "$desc"
    else
      printf '  BROKEN  (%s)  %s   <-- provisioning would fail\n' "$code" "$desc"; fails=$((fails+1))
    fi
  fi
}

echo "Scope of $USER_ID against $ENDPOINT"
echo
echo "Must be refused — things provisioning never does:"
probe DENY POST   /access/users   "create a host account" \
  --data-urlencode "userid=scopetest@pve"
probe DENY POST   /access/roles   "define a new role" \
  --data-urlencode "roleid=ScopeTest" --data-urlencode "privs=Sys.Modify"
probe DENY PUT    /access/password "change a user's password" \
  --data-urlencode "userid=root@pam" --data-urlencode "password=scope-test-not-applied"
probe DENY DELETE "/access/users/root@pam/token/tofu" "delete the administrator's credential"
probe DENY POST   /storage        "create a datastore" \
  --data-urlencode "storage=scopetest" --data-urlencode "type=dir" --data-urlencode "path=/tmp/scopetest"
probe DENY DELETE /storage/local  "remove a datastore"
probe DENY POST   /nodes/pve/qemu/100/agent/exec "run a command inside the guest" \
  --data-urlencode "command=id"
probe DENY PUT    /access/acl     "grant itself more privileges" \
  --data-urlencode "path=/" --data-urlencode "roles=Administrator" \
  --data-urlencode "tokens=${TOKEN%%=*}"

echo
echo "Must keep working — things provisioning does:"
probe ALLOW GET /nodes/pve/storage/local/content     "list storage content (incl. snippets)"
probe ALLOW GET /nodes/pve/qemu/100/config           "read the VM configuration"

echo
if (( fails )); then
  echo "FAIL: $fails check(s) did not behave as required"; exit 1
fi
echo "OK: the token is refused everything outside provisioning, and retains what it needs"
