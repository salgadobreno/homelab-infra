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

## D6 verified by accident, 2026-08-21

A dry run of the rebuild recipe executed for real — a recipe line containing `$(MAKE)`
runs even under `make -n`, and the whole destroy-then-apply chain is one continued shell
line. The cluster was destroyed unintentionally.

It happened to be the exact test D6 needed. Before the sentinel, `tofu destroy` removed
`/var/lib/vz/snippets` along with the last snippet, and the directory came back
root-owned. After it:

```
drwxr-xr-x 2 tofu-snippets tofu-snippets  /var/lib/vz/snippets
-rw-r--r-- 1 root          root           .keep          (15:06, before the destroy)
-rw-rw-r-- 1 tofu-snippets tofu-snippets  k3s-server-1-user-data.yaml  (15:13, after)
```

The `.keep` file predates the destroy and survived it, so PVE's `rmdir` failed as
intended, the directory kept its owner, and the following apply wrote the snippet as
`tofu-snippets` with no root SSH involved. Node Ready 71 seconds after apply began.

`rebuild` no longer calls another `make` target; it inlines the same command, so a dry
run stays dry.

## Section 4a closed, 2026-08-21

`make rebuild CONFIRM=yes` → **REBUILD COMPLETE in 108s**, unattended, with no root
involved on either channel:

```
qmshutdown / qmdestroy / imgdel / imgdel / download / qmcreate / resize / qmstart
                                                             terraform@pve!tofu

-rw-rw-r-- 1 tofu-snippets tofu-snippets  k3s-server-1-user-data.yaml
-rw-r--r-- 1 root          root           .keep    (15:06 — older than the destroy)
```

The API work is the scoped token's; the snippet is the unprivileged account's; the
sentinel is older than the destroy that ran through it. Root SSH is still *accepted* —
withdrawing it is group 5 — but nothing uses it any more.

## 5. Password authentication on the LAN — accepted (before)

`sshd_config` sets `PasswordAuthentication no` globally and then overrides it:

```
Match Address 192.168.0.*
	PasswordAuthentication yes
```

What the server offers a LAN client, before any change:

```
$ ssh -o PreferredAuthentications=password -o PubkeyAuthentication=no \
      -o NumberOfPasswordPrompts=0 -p 4444 nosuchuser@192.168.0.21 true
nosuchuser@192.168.0.21: Permission denied (publickey,password).
```

`password` in that list is the finding: the global setting is not the effective one, so
"this host is key-only" was not true. `PermitRootLogin` is also unset, leaving the
default `prohibit-password`.

**Target:** `(publickey)` alone, `PermitRootLogin no` stated explicitly, and `buzaga`
still reaching the host by key.

## First attempt at 5.1/5.1a — reverted on a false alarm

The hardening applied cleanly and did exactly what it should:

```
OK: root SSH is refused
OK: password authentication is not offered (publickey)
FAIL: buzaga can no longer log in — revert before continuing
```

The third line was wrong, and it was my check's fault. It tried to SSH `buzaga@pve`
*from pve*, and `buzaga`'s own public key is not in `buzaga`'s `authorized_keys` — there
is no reason it would be. Those ten authorised keys belong to the machines the operator
connects **from**, and none of them can be exercised from the host itself. The probe was
failing before the change too; it was simply never run until the change had been made.

So a correct hardening was reverted because a check asserted something it had no way to
observe. The check now asserts only what is verifiable here:

- root SSH is refused;
- the offered method list is `publickey` and does not contain `password`;
- key authentication still works end to end, proved by logging in as `tofu-snippets`,
  whose key does live on this host;
- and it prints, rather than claims, that whether the operator's own client machine is
  among the authorised keys can only be checked from that machine.

The lesson is the shape of the earlier SFTP mistake repeated: a check that tests a
different thing from the one that matters is worse than no check, because it is trusted.
