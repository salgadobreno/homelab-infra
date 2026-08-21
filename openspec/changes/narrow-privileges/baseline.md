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

Demonstrated rather than inferred — the provisioning token can enumerate host accounts,
which provisioning never needs to do:

```
GET /api2/json/access/users  ->  http 200
```

**Target:** `terraform@pve` with a custom role, privilege separation on, and this same
request returning 403.

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

## How to re-measure

Task 7.1 turns these four checks into `make check-privileges`, so the "after" state is
verified by command rather than by repeating this by hand. Until then the commands above
are the record.
