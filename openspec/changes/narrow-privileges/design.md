# Design

## Context

| Constraint | Detail |
|---|---|
| Hypervisor | Proxmox VE 9.2.2, single node `pve` at 192.168.0.21 |
| Current API auth | `root@pam!tofu`, privilege separation **off** — unbounded |
| Current tunnel | `cloudflared` as **root**, token in `argv`, `/proc/<pid>/cmdline` readable by uid 1000 (verified 2026-08-21) |
| Current host SSH | key-based **root** login on port 4444, used only for snippet uploads |
| Blast radius | The tunnel is live and serving. The cluster is disposable and rebuilds in 433s |
| Operator access | No passwordless sudo, no TTY in agent sessions — every privileged step is operator-run |

## Goals

- Each credential holds only what its job needs, demonstrated by a refusal.
- `make rebuild CONFIRM=yes` still completes unattended afterwards.
- Three entries move out of "known shortcuts" in `README.md` and `CLAUDE.md`.

## Non-Goals

- A secrets manager. Storage of secrets is a separate problem from their scope.
- Auditing Cloudflare ingress rules and Access policies — dashboard configuration,
  belongs with the ingress milestone.
- Hardening Samba/rpcbind. Real, but not a credential-scoping problem.

## Decisions

### D1: A custom Proxmox role, not a built-in one

Built-in roles are convenient and too broad — `PVEVMAdmin` carries VM privileges the
provider never exercises. A custom role listing exactly the privileges used makes the
scope self-documenting: reading the role definition tells you what the automation does.

The privileges must be derived from what the provider actually calls, not guessed.
Under-scoping shows up as a failed apply, which is cheap and obvious; over-scoping shows
up as nothing at all, which is the failure mode being fixed.

*Alternatives:* `PVEVMAdmin` plus storage roles (rejected: broader, and hides the
question); `Administrator` scoped to a path (rejected: same unbounded privileges, only
relocated).

### D2: Privilege separation on, so the token is narrower than its user

The token gets its own privileges rather than inheriting the user's. Privilege
separation is off today, which is what makes the current token equivalent to root.

### D3: The tunnel token moves to a systemd `EnvironmentFile`, not a rewritten tunnel

Two ways to get the token out of `argv`. Converting to a locally-managed tunnel with a
credentials JSON and a local `config.yml` is the fuller answer — it also brings ingress
rules onto the host where they can be reviewed. It also means recreating the tunnel that
is currently serving the internet.

An `EnvironmentFile` at mode 600 read by the systemd unit, supplying `TUNNEL_TOKEN`,
removes the exposure without touching the tunnel itself: `/proc/<pid>/environ` is
readable only by the process owner and root, unlike `cmdline` which is world-readable.
Take that first. Revisit the locally-managed conversion at the ingress milestone, when
the tunnel is being reconfigured anyway.

*Trade-off accepted:* the token remains recoverable by root and by the service account.
That is inherent — the process must be able to read its own credential.

### D4: Snippet uploads move to a dedicated non-root SSH account

Root SSH exists only because `/var/lib/vz/snippets` is root-owned. A dedicated account
owning that directory removes the reason. Whether the `bpg` provider performs any other
SSH-side operation that assumes root is **not yet established** — see Open Questions.
If it does, the fallback is a narrowly targeted `sudoers` entry for that specific
command rather than restoring root login.

### D5: Sequence by blast radius, tunnel last

The Proxmox token is replaceable with a rebuild as the test and no user-visible impact.
The SSH account affects provisioning only. The tunnel is the only component currently
serving the internet, so it changes last, when the pattern is established.

## Risks

| Risk | Mitigation |
|---|---|
| Under-scoped role breaks provisioning subtly | The acceptance test is a full unattended rebuild, not a plan |
| Provider needs root over SSH for something undiscovered | Targeted sudoers entry for that command; root login still withdrawn |
| Tunnel restart drops the live site | Change last; restart is seconds; site is a placeholder and may go down |
| Losing hypervisor access by withdrawing root SSH | The operator has console and physical access; withdrawal is a config change, reversible |
| Negative test is skipped because it is awkward | It is a spec requirement, not a task — a scope never shown to refuse anything is unproven |

## Open Questions

1. Which exact Proxmox privileges does `bpg/proxmox` exercise for this configuration —
   VM create/destroy, disk allocation on `local-lvm`, file upload to `local`, cloud-init
   drive management? Derive empirically: start minimal, rebuild, add on failure.
2. Does the provider perform SSH-side operations that require root beyond writing to the
   snippet directory?
3. Does `cloudflared`'s systemd unit as shipped support `EnvironmentFile` cleanly, or
   does the token argument need removing from `ExecStart` by hand?

## Answers

### Open Question 2 — does the provider need root over SSH? **No, not for this configuration.**

Established 2026-08-21 from two independent sources, before changing anything.

**The provider's SSH channel is SFTP, not a shell.** The binary links
`github.com/pkg/sftp`, and the snippet upload is a plain file write into the datastore's
path. A file write needs write permission on the directory and nothing more.

**Only one code path in the provider escalates**, and this configuration does not take
it. Two command templates in the binary are wrapped in the provider's `try_sudo` helper:

```
imported_disk=$(try_sudo /usr/sbin/qm disk import $vm_id $source_image $datastore_id_target ...)
try_sudo /usr/sbin/qm set $vm_id -${disk_interface} $disk_id
```

Both belong to importing a disk from a **file path**. Our `disk.import_from` points at a
`proxmox_download_file` in an `import`-content datastore, which the provider passes to
the API as `qmcreate`'s `import-from` parameter instead.

**Confirmed against the hypervisor's own task log** (`/var/log/pve/tasks/index`), which
records every privileged operation and the identity that requested it. A full destroy
and rebuild produces exactly:

```
qmshutdown / qmdestroy / imgdel / download / qmcreate / resize / qmstart   terraform@pve!tofu
```

Seven tasks, all attributed to the API token. No `imgcopy`, no task attributed to
`root@pam` from the CLI — so nothing in the lifecycle runs as a root shell.

**Consequence:** task 4.3 is not needed. No sudoers entry, targeted or otherwise. The
account owning the snippet directory can be an ordinary unprivileged user.

**Caveat worth keeping:** this is a property of *this* configuration, not of the
provider. Switching `import_from` to a file path, or adding a resource that shells out,
re-opens the question — and it would fail loudly at apply, which is the cheap direction.

### Incidental finding: `sshd_config` weakens password policy on the LAN

`PasswordAuthentication no` globally, then:

```
Match Address 192.168.0.*
	PasswordAuthentication yes
```

Any LAN host may authenticate by password. Not part of this change's scope — recorded so
group 5 does not withdraw root SSH while believing key-only is enforced. Also note
`PermitRootLogin` is not set at all; the effective value is the default
`prohibit-password`.
