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
   │                                                                          │
   └──────────────────────────────────────────────────────────────────────────┘
```

Terraform is told none of the ordering. The VM references the image and the snippet, so
the dependency graph is inferred; the two upstream resources have no edge between them
and are built concurrently.

## Quick start

Requires an ssh-agent: cloud-init snippets upload over SSH, because Proxmox exposes no
API endpoint for them.

```bash
scripts/bootstrap.sh                      # tofu + kubectl, pinned, no root needed
scripts/create-proxmox-token.sh           # writes tofu/terraform.tfvars, mode 600

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
| `make check` | no secrets tracked, and reality still matches configuration |
| `make cluster` | k3s and cloud-init state, read from the node |
| `make rebuild CONFIRM=yes` | timed destroy and recreate |

## Rebuild time: 105 seconds, and why the number moves

A full `destroy` → `apply` → node reporting Ready, with no manual steps:

| Step | Time |
|---|---|
| cloud-init snippet upload | 1s |
| Ubuntu image re-download (596 MB) | 30s |
| VM creation | 46s |
| boot → k3s `Ready` | 47s |
| **total** | **105s** |

An earlier run of the same command took 433s. Nothing changed between them except
network throughput on that 596 MB download, which `tofu destroy` removes and `apply`
fetches again. **The rebuild time is dominated by a variable neither the configuration
nor the hardware controls**, so quote it as a range, or quote the part that does not
move.

The stable figure is **boot to a node reporting `Ready`: 45-47 seconds** across every
rebuild measured. That is the one worth citing, because it measures this project's
work rather than an Ubuntu mirror's throughput.

Both numbers are only trustworthy because the readiness gate was fixed first. It
originally ran `kubectl wait --for=condition=Ready node --all` before the node object
existed; `wait` does not block for a resource to appear, so it failed instantly and
cloud-init wrote the completion marker regardless. See
`LEARNINGS/practice/301-verifying-recovery.md`.

## Deliberately deferred

Recorded as decisions, not oversights. Each has a milestone attached.

**Local state, not remote** (design D8). Remote state solves collaboration and locking
problems a single operator does not have. The cost of being wrong is one `tofu init`
with a backend block. Note that state holds resource attributes in plaintext — the full
cloud-init body, SSH public key included — which is why `*.tfstate` is gitignored rather
than merely untidy to commit.

**A `root@pam` API token with privilege separation off** (design D4). A scoped
`terraform@pve` user with only the roles the provider needs is the correct answer and
belongs to the secrets milestone. The token is real credentials in `terraform.tfvars`,
gitignored and mode 600; `make check-secrets` asserts it has never reached a commit.

**Key-based root SSH on a non-default port.** The provider needs it for snippet uploads
and `/var/lib/vz/snippets` is root-owned. It widens the attack surface and narrows with
the same scoped-user work.

**No configuration management.** Nodes are immutable: cloud-init bootstraps them and
everything above the OS is reconciled by GitOps. Bootstrap is about fifteen lines of
`runcmd`. If that grows past what fits on a screen, that is the signal to reconsider —
not a reason to add Ansible pre-emptively.

**One node.** Multi-node and embedded etcd arrive at milestone 5, at which point the
datastore stops being sqlite and the fsync argument behind putting disks on the NVMe
(design D10) gets stricter, not looser.

## Layout

```
openspec/       Planning: config.yaml is authoritative project context
tofu/           OpenTofu root module — flat and unmodularised on purpose
scripts/        Toolchain bootstrap and Proxmox token creation
Makefile        Operator console
LEARNINGS/      Notes, by subject and depth — 101 basics, 201 how it works, 301 what bit us
```

`tofu/` stays flat until there is more than one node to abstract over. Extracting
modules is a later exercise, not an oversight.
