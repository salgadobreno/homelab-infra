# homelab-infra

Infrastructure-as-code for a single-host Proxmox VE homelab: an OpenTofu-provisioned
k3s cluster, built to be thrown away and rebuilt on demand.

Two goals, both real — run a setup that would survive professional scrutiny, and build
hands-on fluency in Terraform, Kubernetes and ArgoCD. Where those conflict, the
industry-standard choice wins over the homelab-clever one.

## What exists today

```
                    Proxmox VE 9.2  ·  Ryzen 5 3400G  ·  13 GiB  ·  192.168.0.21
   ┌──────────────────────────────────────────────────────────────────────────┐
   │                                                                          │
   │   proxmox_download_file            Ubuntu 24.04 LTS cloud image          │
   │            │                       pinned by URL + SHA256                │
   │            │ import_from                                                 │
   │            ▼                                                             │
   │   proxmox_..._vm  ◄── user_data ──  proxmox_..._file  (cloud-init)       │
   │     k3s-server-1                      uploaded over SSH, not the API      │
   │     4 vCPU · 6 GiB · 20 GiB                                              │
   │     local-lvm (NVMe thin pool)                                           │
   │     192.168.0.30/24  ── static, declared, never DHCP                     │
   │            │                                                             │
   │            └── k3s v1.36.3+k3s1 · sqlite datastore · flannel · traefik   │
   │                     │                                                    │
   │                     └── ArgoCD ──► reconciles k8s/ from this repository   │
   │                                        │                                 │
   │                                        └── the static site, served       │
   │                                            at buzaga.com.br              │
   │                                                                          │
   └──────────────────────────────────────────────────────────────────────────┘
```

**That picture is hand-drawn, and nothing checks it.** It is accurate as of M5, and it is
accurate the way `diagram.ascii` was accurate right up until it was not. The site's own
**cluster snapshot** on [buzaga.com.br](https://buzaga.com.br) is the one that cannot
drift: it is generated from the cluster by `make diagram`, and `make check` fails if it
and the cluster disagree. When the two disagree, believe that one. Bringing
this diagram under the same check is unscheduled work, listed under *Deliberately
deferred*.

Nothing is deployed by hand. ArgoCD is installed by cloud-init as a k3s `HelmChart`, so
a cluster built from nothing arrives already reconciling; the site is a Deployment,
Service, Ingress and a kustomize-generated ConfigMap in `k8s/site/`. Editing a page and
pushing is the whole deployment — the ConfigMap's content hash changes, the Deployment's
reference follows it, and the pods roll.

Terraform is told none of the ordering. The VM references the image and the snippet, so
the dependency graph is inferred; the two upstream resources have no edge between them
and are built concurrently.

## The site describes itself, and the description is checked

The site is a single page. The top half is the architecture — hand-drawn, and it changes
when a decision changes. Below it is a **cluster snapshot**: the node, everything running
on it, and how it got there, none of which was typed. `scripts/generate-diagram.sh`
composes the page from `k8s/site/parts/` and a reading of the cluster, and the result is
committed and deployed like any other page.

```bash
make diagram          # regenerate from the cluster
make check-diagram    # fail if the committed page and the cluster disagree
make check-disclosure # fail if anything served crosses the disclosure boundary
```

Both run inside `make check`. The property they buy is narrow and worth stating
exactly: **the snapshot can be out of date, but it cannot be out of date and passing.**

Three things fell out of building it that were not obvious going in:

- **The page cannot name the commit it was generated from.** Publishing the synced
  revision means every push changes what the page should say, and the fix — regenerate
  and commit — is itself a new commit that changes it again. There is no fixpoint.
- **ArgoCD self-heal makes managed drift invisible to the check.** Scaling the site was
  reverted in ~310 ms, faster than the generator can read the cluster. The drift check's
  real subject is everything ArgoCD does *not* revert: kubelet version, node capacity,
  image tags, ingress hosts.
- **Determinism is the whole cost.** Ages, ready counts, row order and generated name
  suffixes all had to be suppressed deliberately, or the check fails at random and gets
  ignored — which is worse than not having it.

A rebuild is the sharpest test of that last point: the node is destroyed and recreated,
and the committed page still matches byte-for-byte, because everything it reports is a
shape rather than an instance. `make verify-rebuild` asserts exactly that.

## What this replaces

Recorded before it was switched off, because after that it could only be remembered.
This was the arrangement the project existed to replace, measured on 2026-08-22 while it
was still serving `buzaga.com.br`. It was retired the same day.

```
Docker Compose on the hypervisor  ·  /mnt/sda8/Projects/buzaga/docker-compose.yml
   buzaga-nginx        nginx:latest        30000:80, 443:443    up 16 days
   buzaga-hit-counter  buzaga-hit-counter  built locally        up 16 days
   buzaga-redis        redis:7-alpine      volume buzaga_redis-data
```

- **nginx** served `/mnt/sda8/Projects/buzaga/plain_site/` from a bind mount and proxied
  `/api/` to the hit counter.
- **The hit counter** was a Node service recording visits. Its final reading:
  `{"state":"first","total":72,"returning":6}` — two Redis keys, `hits:total` and
  `hits:returning`, read from Redis directly a second before the volume was destroyed.
- **Redis** held those two keys in a named volume.

Three properties of that setup are the whole argument for what replaced it:

**The content was a bind mount.** `plain_site/` lived on the hypervisor's disk. Nothing
described it, nothing versioned it, and a rebuilt host would not have had it.

**The image existed only on that machine.** `buzaga-hit-counter` was built locally and
never pushed: `RepoDigests: []`. There was nowhere to pull it from. Losing the host meant
rebuilding the image from source or losing the service.

**Bringing it back was a human procedure.** No declaration of what should be running —
`docker compose up -d` in the right directory, by someone who remembered.

The cluster version answers each of those: content in Git, stock images pinned by tag,
and a reconciler that restores the whole thing from an empty node in 190 seconds without
being asked.

The counter is gone rather than ported. Its 72 visits are recorded here, which is all
that survives it — and all that was worth surviving it.

## Quick start

Requires an ssh-agent: cloud-init snippets upload over SSH, because Proxmox exposes no
API endpoint for them.

```bash
scripts/bootstrap.sh                      # tofu + kubectl, pinned, no root needed

# Credentials, on a fresh host. The admin token exists only to create the scoped one.
scripts/create-bootstrap-token.sh                              # root@pam!bootstrap
PVE_ADMIN_TOKEN="$(cat tofu/.bootstrap-token)" \
  scripts/create-terraform-user.sh                             # -> terraform.tfvars
sudo pveum user token remove root@pam bootstrap && shred -u tofu/.bootstrap-token
sudo scripts/create-snippet-user.sh                            # owns the snippet dir

eval "$(ssh-agent)" && ssh-add ~/.ssh/id_ed25519
make plan                                 # read it before applying
make apply
make kubeconfig && export KUBECONFIG=$PWD/kubeconfig
make nodes
```

`make` on its own lists every operator command. Routine administration lives there
rather than in shell history, so the same instruments are available to everyone.

| | |
|---|---|
| `make status` | host, VMs, node reachability, state, task progress |
| `make check` | no secrets tracked, credentials still narrow, no drift |
| `make check-privileges` | thirty assertions across the token, SSH, and the tunnel |
| `make cluster` | k3s and cloud-init state, read from the node |
| `make rebuild CONFIRM=yes` | timed destroy and recreate |

## Rebuild time: 105 seconds to a node, 190 to the public site

A full `destroy` → `apply` → node reporting Ready, with no manual steps:

| Step | Time |
|---|---|
| cloud-init snippet upload | 1s |
| Ubuntu image re-download (596 MB) | 30s |
| VM creation | 46s |
| boot → k3s `Ready` | 47s |
| **total, node Ready** | **105s** |
| ArgoCD installed and the site Synced and serving | +85s |
| **total, `buzaga.com.br` answering again** | **190s** |

An earlier run of the same command took 433s. Nothing changed between them except
network throughput on that 596 MB download, which `tofu destroy` removes and `apply`
fetches again. **The rebuild time is dominated by a variable neither the configuration
nor the hardware controls**, so quote it as a range, or quote the part that does not
move.

The stable figure is **boot to a node reporting `Ready`: 45-47 seconds** across every
rebuild measured, and **190 seconds from `make rebuild` to `buzaga.com.br` answering again** — measured
across the destroy of a cluster the public site now depends on —
the extra time is the ArgoCD chart installing and its first reconcile, neither of which
blocks the node from reporting Ready. That is the one worth citing, because it measures this project's
work rather than an Ubuntu mirror's throughput.

Both numbers are only trustworthy because the readiness gate was fixed first. It
originally ran `kubectl wait --for=condition=Ready node --all` before the node object
existed; `wait` does not block for a resource to appear, so it failed instantly and
cloud-init wrote the completion marker regardless. See
`LEARNINGS/practice/301-verifying-recovery.md`.

## Credentials, and what each one can do

Three credentials ran with more authority than their job needed. Each was narrowed, and
each narrowing is asserted by `make check-privileges` rather than described here and
hoped for.

**Provisioning: `terraform@pve!tofu`, privilege separation on.** A custom role holding
nineteen privileges, derived by starting minimal and rebuilding until it stopped failing
— not by reading documentation and guessing. It is refused creating a host account,
defining a role, changing a password, altering storage configuration, running a command
inside a guest, and granting itself anything. `root@pam` holds no API tokens at all.

**Snippet uploads: `tofu-snippets`, an unprivileged account.** Cloud-init files go over
SSH because Proxmox exposes no API for the snippets content type, and the directory used
to be root-owned, which is the only reason root SSH existed. The account owns the
directory instead. No sudoers entry: the provider's write needs no privilege once the
directory is writable.

**Administrative SSH: withdrawn.** `PermitRootLogin no`, and root's `authorized_keys`
emptied rather than merely refused. A `Match Address 192.168.0.*` block was also
re-enabling password authentication for the whole LAN, so `PasswordAuthentication no`
had never been the effective setting; the server now offers `publickey` alone.

**The tunnel: `cloudflared`, unprivileged, token in a mode-600 file.** It ran as root
with the token in `ExecStart`, readable from `/proc/<pid>/cmdline` and from a mode-644
unit file by any local user. `--token-file` keeps it out of `argv` and out of the
environment; the service account has no shell and no privileged group.

The one thing not closed: that token was not rotated when the plumbing was hardened, so
anyone who had already read it still holds a working credential. A tunnel token
publishes to a hostname — it does not reach the host or the cluster — and rotating later
is a write and a restart. Recorded rather than quietly dropped.

## Deliberately deferred

Recorded as decisions, not oversights. Each has a milestone attached.

**Local state, not remote** (design D8). Remote state solves collaboration and locking
problems a single operator does not have. The cost of being wrong is one `tofu init`
with a backend block. Note that state holds resource attributes in plaintext — the full
cloud-init body, SSH public key included — which is why `*.tfstate` is gitignored rather
than merely untidy to commit.

**No configuration management.** Nodes are immutable: cloud-init bootstraps them and
everything above the OS is reconciled by GitOps. Bootstrap is about fifteen lines of
`runcmd`. If that grows past what fits on a screen, that is the signal to reconsider —
not a reason to add Ansible pre-emptively.

**The README's own diagram is unchecked.** The site's description is generated and
verified; the ASCII picture at the top of this file is drawn by hand and asserted by
nobody. It names the hypervisor and the address plan, which the disclosure boundary keeps
off the public page, so it cannot simply be replaced by the generated one. Bringing it
under a check means deciding what a repository-internal description is allowed to say
that a public one is not — worth doing, and not this milestone.

**The Cloudflare tunnel token is still the one that was disclosed.** Rotating it is a
write to `/etc/cloudflared/token` and a restart. Deferred at M2 by explicit decision, not
forgotten.

**One node.** Multi-node and embedded etcd arrive at M6, at which point the
datastore stops being sqlite and the fsync argument behind putting disks on the NVMe
(design D10) gets stricter, not looser.

## Layout

```
openspec/       Planning: config.yaml is authoritative project context
tofu/           OpenTofu root module — flat and unmodularised on purpose
k8s/            Manifests ArgoCD reconciles. Deployed by being committed, not applied
scripts/        Toolchain bootstrap, credential creation, host hardening
Makefile        Operator console
LEARNINGS/      Notes, by subject and depth — 101 basics, 201 how it works, 301 what bit us
```

`tofu/` stays flat until there is more than one node to abstract over. Extracting
modules is a later exercise, not an oversight.
