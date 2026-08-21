# Privilege baseline

Recorded 2026-08-21, before anything was narrowed (task 1.1). This is the "before" half
of the evidence; every claim here should be false by the time the change is archived.

Measured from an unprivileged shell (uid 1000), which is the threat model that matters:
a local user with no administrative rights.

## 1. Proxmox API token — unbounded

```
user:     root@pam
token id: tofu
privsep:  0          # token inherits the full privileges of root@pam
```

**Correction, 2026-08-21.** This section originally cited `GET /access/users -> 200` as
evidence of over-privilege. That was a poor test: Proxmox permits that read broadly, and
the *scoped* token returns 200 for it too (seeing only `root@pam` and itself). A read
that everyone is allowed to make proves nothing about privilege.

The meaningful evidence is what the credential can **write**. With the root token every
one of these succeeds; the target is that every one is refused:

```
POST   /access/users                      create a host account
POST   /access/roles                      define a new role
PUT    /access/password                   change any user's password
DELETE /access/users/root@pam/token/tofu  delete the administrator's own credential
DELETE /storage/local                     remove a datastore
POST   /storage                           create a datastore
```

**Target:** `terraform@pve` with a custom role, privilege separation on, and all six
refused with 403.

## 2. cloudflared — running as root

```
pid 21768  user root
```

A network-facing process holding full administrative rights on the hypervisor that hosts
everything, including the cluster.

**Target:** a dedicated unprivileged account with no password-less escalation.

## 3. Tunnel token — readable by any local user

```
/proc/21768/cmdline   -r--r--r--    185-byte token value present
/proc/21768/environ   not readable by uid 1000
```

The token is passed as a command-line argument, and `cmdline` is world-readable. Any
local shell can recover it — no root required. A tunnel token is the credential for
running a connector, so whoever holds it can attach their own connector and receive a
share of real traffic.

The contrast in those two lines is the whole basis of design D3: `environ` is restricted
to the process owner and root, so moving the token into a systemd `EnvironmentFile`
closes the exposure without recreating the live tunnel. **Assumption verified, not
assumed.**

**Target:** no credential recoverable from either `cmdline` or `environ`.

## 4. Root SSH — accepted

```
$ ssh -p 4444 root@192.168.0.21 'id -un'
root
```

Key-based root login succeeds. It exists only so the provider can write cloud-init
snippets into a root-owned directory.

**Target:** refused, with provisioning still succeeding unattended.

## Outcome, sections 1-4a

Section 1 is closed. `root@pam!tofu` was deleted on 2026-08-21 and returns 401; `root@pam`
now holds no API tokens at all. OpenTofu authenticates as `terraform@pve` with privilege
separation on, and `make check-scope` asserts all six writes above are refused, plus
guest command execution and self-granting privileges.

Sections 2, 3 and 4 remain open — they are groups 4 to 6.

## How to re-measure

Task 7.1 turns these four checks into `make check-privileges`, so the "after" state is
verified by command rather than by repeating this by hand. Until then the commands above
are the record.
