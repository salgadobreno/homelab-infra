#!/usr/bin/env bash
#
# Assert the properties this change exists to establish, for the Proxmox credential.
# The host-side properties — root SSH, the tunnel, the snippet account — are asserted
# by their own make targets; `make check-privileges` runs all of them together.
#
#   ./scripts/check-privileges.sh
#
# Read-only. Every call is a GET.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TFVARS="$REPO_ROOT/tofu/terraform.tfvars"

# The privileges the provisioning role is supposed to hold, derived empirically in
# group 2 and confirmed by a rebuild. The assertion is equality, not containment: a
# privilege appearing that is not on this list is a widening, and a privilege
# disappearing breaks provisioning. Both should be noticed.
EXPECTED="Datastore.Allocate Datastore.AllocateSpace Datastore.AllocateTemplate
Datastore.Audit SDN.Use Sys.AccessNetwork Sys.Audit VM.Allocate VM.Audit
VM.Config.CDROM VM.Config.CPU VM.Config.Cloudinit VM.Config.Disk VM.Config.HWType
VM.Config.Memory VM.Config.Network VM.Config.Options VM.GuestAgent.Audit VM.PowerMgmt"

# Privileges that would let the credential grow its own reach or reach into a guest.
# Listed separately from the equality check so a regression says *why* it matters.
FORBIDDEN="Permissions.Modify Sys.Modify User.Modify Realm.Allocate Realm.AllocateUser
Group.Allocate Sys.PowerMgmt VM.Console VM.Monitor Datastore.AllocateSpace.Root"

ENDPOINT=$(sed -n 's/^proxmox_endpoint *= *"\(.*\)"/\1/p' "$TFVARS")
TOKEN=$(sed -n 's/^proxmox_api_token *= *"\(.*\)"/\1/p' "$TFVARS")
[[ -n "$ENDPOINT" && -n "$TOKEN" ]] || { echo "cannot read $TFVARS" >&2; exit 1; }

USER_ID="${TOKEN%%!*}"
REST="${TOKEN#*!}"
TOKEN_ID="${REST%%=*}"
fails=0

pass() { printf '  OK    %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; fails=$((fails+1)); }
note() { printf '  ..    %s\n' "$1"; }

echo "Provisioning credential: ${USER_ID}!${TOKEN_ID}"
echo

# 1. Not root ----------------------------------------------------------------------

case "$USER_ID" in
  root@*) fail "the token belongs to $USER_ID" ;;
  *)      pass "the token belongs to $USER_ID, not root" ;;
esac

# 2. What it can actually do -------------------------------------------------------
#
# /access/permissions with no userid returns the *effective* permissions of the
# credential making the call, which is the thing worth asserting: it accounts for
# privilege separation, role membership and path inheritance at once.

# PERMISSIONS_FIXTURE exists so the regression case can be exercised without widening
# the live role. Task 7.2 asks for proof that this check fails when a property is
# regressed, and modifying the real role to prove it would mean granting the very
# privileges the check exists to forbid.
if [[ -n "${PERMISSIONS_FIXTURE:-}" ]]; then
  PERMS_JSON=$(cat "$PERMISSIONS_FIXTURE")
  echo "  ..    reading permissions from fixture $PERMISSIONS_FIXTURE, not the API"
else
  PERMS_JSON=$(curl -sk -H "Authorization: PVEAPIToken=$TOKEN" \
               "${ENDPOINT}api2/json/access/permissions")
fi

HELD=$(printf '%s' "$PERMS_JSON" | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)["data"]
except Exception:
    sys.exit(1)
print("\n".join(sorted({p for privs in data.values() for p in privs})))
') || { fail "could not read the effective permissions"; HELD=""; }

if [[ -n "$HELD" ]]; then
  want=$(printf '%s\n' $EXPECTED | sort)
  got=$(printf '%s\n' $HELD | sort)

  extra=$(comm -13 <(echo "$want") <(echo "$got"))
  missing=$(comm -23 <(echo "$want") <(echo "$got"))

  if [[ -z "$extra" && -z "$missing" ]]; then
    pass "holds exactly the $(echo "$want" | wc -l) privileges the role was scoped to"
  else
    [[ -n "$extra" ]]   && fail "holds privileges it was not scoped for: $(echo $extra)"
    [[ -n "$missing" ]] && fail "lost privileges provisioning needs: $(echo $missing)"
  fi

  danger=$(comm -12 <(printf '%s\n' $FORBIDDEN | sort) <(echo "$got"))
  if [[ -n "$danger" ]]; then
    fail "holds privileges that would let it grow its own reach: $(echo $danger)"
  else
    pass "holds nothing that grants access, alters users, or reaches into a guest"
  fi
fi

# 3. Privilege separation ----------------------------------------------------------
#
# Not assertable with this credential, and saying so beats asserting something
# adjacent and calling it proof. Reading a token's privsep flag needs User.Modify on
# /access/users/<user>, which this token is refused — correctly.

PRIVSEP_CODE=$(curl -sk -o /dev/null -w '%{http_code}' \
  -H "Authorization: PVEAPIToken=$TOKEN" \
  "${ENDPOINT}api2/json/access/users/${USER_ID}/token/${TOKEN_ID}")

if [[ "$PRIVSEP_CODE" == 2* ]]; then
  privsep=$(curl -sk -H "Authorization: PVEAPIToken=$TOKEN" \
    "${ENDPOINT}api2/json/access/users/${USER_ID}/token/${TOKEN_ID}" \
    | python3 -c 'import json,sys; print(json.load(sys.stdin)["data"].get("privsep"))')
  [[ "$privsep" == "1" ]] && pass "privilege separation is on" \
                          || fail "privilege separation is off (privsep=$privsep)"
else
  note "privilege separation: not readable by this token (http $PRIVSEP_CODE), which is"
  note "      itself correct — reading it needs User.Modify. Check it with an admin"
  note "      credential: GET ${ENDPOINT}api2/json/access/users/${USER_ID}/token/${TOKEN_ID}"
fi

# 4. Where it holds them -----------------------------------------------------------
#
# Reported, not asserted. The role is granted at "/", so the privilege set is narrow
# while the path is the whole tree. That is a deliberate, recorded position rather
# than an oversight — narrowing the path is a separate exercise.

PATHS=$(printf '%s' "$PERMS_JSON" | python3 -c '
import json, sys
try:
    print(" ".join(sorted(json.load(sys.stdin)["data"])))
except Exception:
    pass
')
[[ -n "$PATHS" ]] && note "granted at: $PATHS"

echo
if (( fails )); then
  echo "FAIL: $fails property/properties are not what this change established"
  exit 1
fi
echo "OK: the provisioning credential is scoped as recorded"
