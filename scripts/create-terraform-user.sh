#!/usr/bin/env bash
#
# Create the scoped Proxmox identity OpenTofu provisions with: a custom role holding
# only the privileges the provider exercises, a terraform@pve user, and a token with
# privilege separation ON.
#
# Runs against the API rather than pveum, so it needs no root and no TTY. It needs an
# existing administrative token to bootstrap; by default it reads the one already in
# tofu/terraform.tfvars.
#
# Re-runnable: the role and user are updated in place if they already exist.
#
#   ./scripts/create-terraform-user.sh
#   PVE_ADMIN_TOKEN='root@pam!x=uuid' ./scripts/create-terraform-user.sh

set -euo pipefail

ROLE="TerraformProvisioner"
USER_ID="terraform@pve"
TOKEN_ID="tofu"
ACL_PATH="/"
SNIPPET_ROLE="TerraformSnippetStore"
SNIPPET_PATH="/storage/local"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TFVARS="$REPO_ROOT/tofu/terraform.tfvars"

# The privileges the bpg/proxmox provider actually exercises for this configuration.
# Derived from the operations performed, then confirmed by an unattended rebuild:
#
#   Sys.Audit                   the nodes data source
#   Datastore.Audit             reading storage before writing to it
#   Datastore.AllocateTemplate  downloading the cloud image (content type "import")
#   Datastore.AllocateSpace     the VM disk and the cloud-init drive
#   SDN.Use                     attaching the VM to vmbr0 (required from PVE 8)
#   VM.Allocate                 creating and destroying the VM
#   VM.Audit                    reading VM config during plan
#   VM.Config.*                 the properties this configuration sets
#   VM.PowerMgmt                starting the VM after creation
#   VM.GuestAgent.Audit         reading guest-agent state (ipv4_addresses etc.)
#
# Deliberately absent, and each is a thing provisioning must never do:
#   Datastore.Allocate  creating or removing datastores
#   Sys.Modify          changing host configuration
#   VM.Console          shell access to guests
#   VM.GuestAgent.FileWrite, VM.GuestAgent.Unrestricted  running commands in guests
#   VM.Backup, VM.Clone, VM.Snapshot
#   User.Modify, Permissions.Modify, Realm.*, Group.*
PRIVS="Sys.Audit,Datastore.Audit,Datastore.AllocateTemplate,Datastore.AllocateSpace,SDN.Use,VM.Allocate,VM.Audit,VM.Config.CDROM,VM.Config.CPU,VM.Config.Cloudinit,VM.Config.Disk,VM.Config.HWType,VM.Config.Memory,VM.Config.Network,VM.Config.Options,VM.PowerMgmt,VM.GuestAgent.Audit"

die() { echo "error: $*" >&2; exit 1; }

[[ $EUID -eq 0 ]] && die "do not run this as root; it uses the API, not pveum"
[[ -f "$TFVARS" ]] || die "missing $TFVARS"

ENDPOINT=$(sed -n 's/^proxmox_endpoint *= *"\(.*\)"/\1/p' "$TFVARS")
[[ -n "$ENDPOINT" ]] || die "could not read proxmox_endpoint from $TFVARS"

ADMIN_TOKEN="${PVE_ADMIN_TOKEN:-$(sed -n 's/^proxmox_api_token *= *"\(.*\)"/\1/p' "$TFVARS")}"
[[ -n "$ADMIN_TOKEN" ]] || die "no admin token: set PVE_ADMIN_TOKEN or populate $TFVARS"

# Once tfvars holds the scoped token, it can no longer create roles — by design.
# Say so plainly rather than letting the first API call fail with a bare 403.
if [[ "$ADMIN_TOKEN" == "$USER_ID"* ]]; then
  die "$TFVARS now holds the scoped token, which cannot create roles (that is the point).
       Re-run with an administrative token:
         PVE_ADMIN_TOKEN='root@pam!<id>=<secret>' $0"
fi

api() {
  local method=$1 path=$2; shift 2
  curl -sk -X "$method" -H "Authorization: PVEAPIToken=$ADMIN_TOKEN" \
       -w '\n%{http_code}' "${ENDPOINT}api2/json${path}" "$@"
}

check() {  # method path description [curl args...]
  local method=$1 path=$2 desc=$3; shift 3
  local out code body
  out=$(api "$method" "$path" "$@")
  code=${out##*$'\n'}; body=${out%$'\n'*}
  case "$code" in
    2*) echo "  ok    $desc" ;;
    *)  echo "  FAIL  $desc (http $code)"; echo "        $body" >&2; return 1 ;;
  esac
}

echo "Creating scoped provisioning identity on $ENDPOINT"

# 1. The role. PUT updates an existing role; POST creates it.
if api GET "/access/roles/$ROLE" | tail -1 | grep -q '^2'; then
  check PUT "/access/roles/$ROLE" "role $ROLE updated" --data-urlencode "privs=$PRIVS"
else
  check POST "/access/roles" "role $ROLE created" \
    --data-urlencode "roleid=$ROLE" --data-urlencode "privs=$PRIVS"
fi

# 2. The user. No password: this identity authenticates by token only.
if api GET "/access/users/$USER_ID" | tail -1 | grep -q '^2'; then
  echo "  ok    user $USER_ID already exists"
else
  check POST "/access/users" "user $USER_ID created" \
    --data-urlencode "userid=$USER_ID" \
    --data-urlencode "comment=OpenTofu provisioning. Scoped by role $ROLE."
fi

# 3. Grant the role to the user.
check PUT "/access/acl" "role granted to user at $ACL_PATH" \
  --data-urlencode "path=$ACL_PATH" --data-urlencode "roles=$ROLE" \
  --data-urlencode "users=$USER_ID"

# 4. The token, with privilege separation ON. A privsep token starts with no
#    privileges of its own, so the role must be granted to the token as well —
#    that is the point: the token can never exceed what is granted here, even if
#    the user is later given more.
if api GET "/access/users/$USER_ID/token/$TOKEN_ID" | tail -1 | grep -q '^2'; then
  echo "  --    token $TOKEN_ID already exists; its secret is shown only at creation."
  echo "        Delete it first if you need a new secret:"
  echo "          curl -sk -X DELETE -H \"Authorization: PVEAPIToken=\$PVE_ADMIN_TOKEN\" \\"
  echo "            \"${ENDPOINT}api2/json/access/users/$USER_ID/token/$TOKEN_ID\""
  SECRET=""
else
  out=$(api POST "/access/users/$USER_ID/token/$TOKEN_ID" \
        --data-urlencode "privsep=1" \
        --data-urlencode "comment=OpenTofu. Privilege separated; scoped by $ROLE.")
  code=${out##*$'\n'}; body=${out%$'\n'*}
  [[ "$code" == 2* ]] || die "token creation failed (http $code): $body"
  SECRET=$(printf '%s' "$body" | python3 -c 'import json,sys; print(json.load(sys.stdin)["data"]["value"])')
  echo "  ok    token $TOKEN_ID created with privsep=1"
fi

check PUT "/access/acl" "role granted to the token itself" \
  --data-urlencode "path=$ACL_PATH" --data-urlencode "roles=$ROLE" \
  --data-urlencode "tokens=${USER_ID}!${TOKEN_ID}"

# 5. Snippets need Datastore.Allocate on the storage that holds them — Proxmox treats
#    snippet listing as privileged, because a snippet can contain hook scripts. Without
#    it the provider cannot see the cloud-init file it wrote, concludes it is missing,
#    and proposes replacing the VM on every plan.
#
#    Granted on /storage/local alone, never at the root. At this path it permits
#    managing that datastore's content; it does not permit creating or deleting
#    datastores, which is verified by the negative tests in task 3.2.
#
#    Both roles must be named here. A Proxmox ACL at a more specific path REPLACES the
#    inherited one rather than adding to it, so granting only the snippet role at
#    /storage/local silently removes Datastore.Audit and Datastore.AllocateSpace there.
if api GET "/access/roles/$SNIPPET_ROLE" | tail -1 | grep -q '^2'; then
  check PUT "/access/roles/$SNIPPET_ROLE" "role $SNIPPET_ROLE updated" \
    --data-urlencode "privs=Datastore.Allocate"
else
  check POST "/access/roles" "role $SNIPPET_ROLE created" \
    --data-urlencode "roleid=$SNIPPET_ROLE" --data-urlencode "privs=Datastore.Allocate"
fi

check PUT "/access/acl" "both roles granted to user at $SNIPPET_PATH" \
  --data-urlencode "path=$SNIPPET_PATH" --data-urlencode "roles=$ROLE,$SNIPPET_ROLE" \
  --data-urlencode "users=$USER_ID"

check PUT "/access/acl" "both roles granted to the token at $SNIPPET_PATH" \
  --data-urlencode "path=$SNIPPET_PATH" --data-urlencode "roles=$ROLE,$SNIPPET_ROLE" \
  --data-urlencode "tokens=${USER_ID}!${TOKEN_ID}"

echo
if [[ -n "$SECRET" ]]; then
  # Written, never printed. A secret echoed to a terminal survives in scrollback,
  # in shell history, and in any transcript of the session.
  NEW_LINE="proxmox_api_token = \"${USER_ID}!${TOKEN_ID}=${SECRET}\""
  umask 077
  cp -p "$TFVARS" "$TFVARS.bak"
  grep -v '^proxmox_api_token' "$TFVARS.bak" > "$TFVARS"
  printf '%s\n' "$NEW_LINE" >> "$TFVARS"
  chmod 600 "$TFVARS"
  echo "  ok    token written to tofu/$(basename "$TFVARS")"
  echo "        previous token kept as $(basename "$TFVARS").bak — delete it once the new one is verified"
  echo
  echo "Next: make plan"
else
  echo "Nothing written: the token already existed and its secret is not retrievable."
fi
unset SECRET ADMIN_TOKEN NEW_LINE
