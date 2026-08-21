## Context

See `proposal.md` — Why. The constraints that shape this design:

| Constraint | Value | Consequence |
|---|---|---|
| Host RAM | 13 GiB total, ~3.2 GiB in use | Single node, 6 GiB, is comfortable; a 3-node cluster later will not be |
| Host CPU | Ryzen 5 3400G, 4c/8t | Not a constraint at this scale |
| Disk | NVMe (WD 240 GB): `pve-root` 49 GiB free plus a **130 GiB empty LVM-thin pool** (`local-lvm`). HDD (1 TB 7200rpm): `/mnt/sda8` 59 GiB free, 86% used | VM disks go on `local-lvm`; the HDD is bulk storage only (D10) |
| Proxmox | VE 9.2.2 on Debian 13, zero VMs, zero LXC | Greenfield; no existing templates or storage conventions to honour |
| Operator time | ~10 h/week | Rabbit-hole avoidance is a first-class design goal |
| Prior attempts | Two, both stalled | Structure must produce observable results early |
| Network | `vmbr0` on `192.168.0.0/24`, host static at `.21`, DHCP pool from `.100`, no local DNS | Nodes are statically addressed (D7); hostnames are not resolvable |

The operator is learning Terraform, Kubernetes, and ArgoCD for interview readiness.
That makes *industry-standard* choices preferable to *homelab-clever* ones even when
the clever option is cheaper on resources.

## Goals / Non-Goals

**Goals:**

- One `tofu apply` takes a bare Proxmox host to a `Ready` Kubernetes node.
- Every rabbit hole with a known cheap bypass is bypassed, explicitly and on the record.
- The layout established here absorbs milestones 2–6 without restructuring.
- The operator can explain each decision in an interview.

**Non-Goals:**

- Production-grade security posture. Credential handling here is "not committed",
  not "properly managed" — that is a later change.
- Elegance in the Terraform. The first version is deliberately hardcoded; refactoring
  it into modules is the intended lesson of a later milestone.
- High availability, backups, or disaster recovery.

## Decisions

### D1: OpenTofu over Terraform

Same language, same providers, open governance, and `tofu` is packaged more
conveniently. Employers say "Terraform" and mean the language; fluency transfers
completely. If `tofu` installation proves awkward, HashiCorp Terraform is a drop-in
substitute and this decision does not cascade.

*Alternatives:* Terraform (fine, license concerns irrelevant at this scale);
Pulumi (real language, but a smaller share of job postings).

### D2: `bpg/proxmox` provider over `Telmate/proxmox`

`bpg/proxmox` is actively maintained, has first-class cloud-image and cloud-init
support, and can download an image to Proxmox storage itself. `Telmate/proxmox` is
the older provider most blog posts use and it effectively requires a pre-built VM
template — which is precisely the rabbit hole this design avoids.

*Alternatives:* Telmate (rejected: template prerequisite, maintenance lag);
Proxmox API via `http` provider or scripts (rejected: no state, defeats the purpose).

### D3: Download the cloud image via the provider; never hand-build a template

The classic failure mode here is spending a weekend crafting a golden image by hand,
producing an artifact nobody can reproduce. The provider downloads the Ubuntu LTS
cloud image directly to Proxmox storage, and the VM is created from it. The image
URL and checksum live in configuration, so the base is pinned and reproducible.

*Alternatives:* Packer-built image (correct at team scale, an entire extra tool here
— revisit only if VM boot time becomes painful); manual template (rejected outright).

### D4: `root@pam` API token now; a scoped API role later

Proxmox ACL configuration is fiddly and produces confusing permission errors that
consume hours. Since this host is a single-operator homelab behind a Cloudflare
tunnel with no inbound exposure of the API, an over-privileged token is an acceptable
short-term trade. A scoped `terraform@pve` user with a minimal role is deferred to
the secrets milestone, where it belongs alongside SOPS.

This is a deliberate, time-boxed shortcut and is recorded as such so it is not
mistaken for an oversight.

*Alternatives:* Scoped role now (correct, but front-loads a time sink onto the
milestone whose entire purpose is producing early momentum).

### D5: k3s over kubeadm, k0s, or microk8s

k3s is a certified-conformant Kubernetes distribution — the API, manifests, and
`kubectl` skills transfer to any managed cluster. It installs from a single script,
fits comfortably in the RAM budget, and supports multi-node join for milestone 5.

`microk8s` appears in the operator's earlier `../ansible/microk8s-setup.yml` but is
snap-based, which is friction on Debian and less common in employment contexts.
`kubeadm` teaches more about cluster internals but costs several hours of setup and
is not what the operator is being hired to do.

*Alternatives:* kubeadm (rejected: time cost against a momentum-first milestone);
microk8s (rejected: snap dependency, prior attempt already stalled on this path);
k0s (fine, smaller community).

### D6: k3s installs from cloud-init `runcmd`, not from a configuration management tool

Per the proposal's pinned decisions, there is no Ansible. Bootstrap is roughly fifteen
lines of `runcmd`. This holds only while bootstrap stays trivial; if it grows past
what is readable inline, that is the signal to reconsider — not a reason to
pre-emptively add a tool.

*Alternatives:* Ansible (rejected: see proposal); Terraform `remote-exec` (rejected:
couples provisioning to SSH reachability and makes `apply` flaky).

### D7: Static addressing declared in configuration, not DHCP

Cluster nodes receive static addresses set by cloud-init, from an address plan held in
`variables.tf`. The Proxmox host is already statically addressed at `192.168.0.21`, and
the LAN has no local DNS — `/etc/resolv.conf` points at `8.8.8.8`, and `pve.lan`
resolves only through a hand-written `/etc/hosts` entry. The usual DHCP mitigation
("reference the hostname, not the address") is therefore unavailable without first
standing up a DNS service, which is out of scope.

Address plan, with the router's DHCP pool starting at `.100`:

| Range | Use |
|---|---|
| `192.168.0.1` | Router / gateway |
| `192.168.0.21` | Proxmox host (existing, unchanged) |
| `192.168.0.30-.32` | k3s nodes — `.30` server, `.31`/`.32` agents at M5 |
| `192.168.0.40-.50` | Reserved for LoadBalancer addresses (MetalLB, M7) |
| `192.168.0.100+` | DHCP pool — never allocated by this project |

The MetalLB range is carved out now, while it is free, so the cluster does not have to
be re-addressed later.

k3s writes a kubeconfig pointing at `127.0.0.1`, which is useless off-node. With the
address known at plan time, it is substituted from a variable rather than discovered —
simpler than the guest-agent lookup, and it removes `apply`'s dependency on the agent
reporting in.

`qemu-guest-agent` is still installed, for graceful shutdown and Proxmox UI integration.
Nothing depends on it for addressing.

This matters most at milestone 5. Agents receive `K3S_URL=https://<server>:6443` in
their cloud-init at creation time; if the server's address could move, an agent that
reboots cannot rejoin, and the cluster half-works in a way that is tedious to diagnose.
It matters at milestone 4 too: `tofu destroy && tofu apply` builds a VM with a fresh
MAC, so under DHCP the rebuild demo — the one intended to be run repeatedly — is
precisely what churns the address.

*Alternatives:* Pure DHCP with guest-agent discovery (rejected: no local DNS to fall
back on, and the destroy/apply cycle changes the address); DHCP with the MAC pinned in
Terraform (workable, keeps the identifier in version control, but depends on unobservable
router lease behaviour and is harder to explain than static addressing); DHCP reservation
on the router (rejected: moves configuration into router state, outside version control);
static plus a local DNS service (correct long-term, but adds a service to build and
operate for no present benefit).

*Trade-off accepted:* static addressing makes IP conflicts possible where DHCP would not.
Mitigated by allocating strictly below the `.100` pool boundary and recording the plan
above as the single source of truth.

### D10: VM disks on `local-lvm` (NVMe thin pool); the HDD is a separate bulk tier

The host has two very different devices, and the distinction is functional rather than
a preference:

- **NVMe** — 222 GiB LVM. Beyond `pve-root`, it carries a 129.8 GiB thin pool
  (`pve-data`, exposed by Proxmox as `local-lvm`) that is currently empty because the
  host has no VMs. This is the standard Proxmox VM storage and the target for node disks.
- **HDD** — 1 TB 7200rpm Barracuda, holding `/mnt/sda8`. Bulk and dump storage.

The Kubernetes datastore — sqlite for single-node k3s, etcd from milestone 5 — is
fsync-latency-bound, not throughput-bound. A 7200rpm drive delivers roughly 10-15 ms
fsync where etcd expects sub-millisecond. The failure mode is not a clean refusal: the
cluster starts, appears healthy, then produces apiserver timeouts and leader-election
churn under load, which presents as a networking problem. **Node disks therefore go on
the NVMe. This is a requirement, not an optimisation.**

Node disks are 20 GiB thin-provisioned, so three nodes at milestone 5 consume far less
than the 130 GiB pool. Thin pools that reach 100% turn read-only and can corrupt
guests, so pool usage belongs in milestone 7's monitoring.

An earlier revision of this design targeted `pve-root`. That was based on reading `df`,
which cannot see an unmounted thin pool, and understated available NVMe capacity.

*Storage tiering, for later milestones:*

| Tier | Device | Backing | Survives `tofu destroy`? |
|---|---|---|---|
| VM OS + k8s datastore | NVMe | `local-lvm` | No — declared in config, rebuilt |
| Fast ephemeral PVCs | NVMe | k3s `local-path` | No — caches and scratch only |
| Durable bulk PVCs | HDD | NFS export from `/mnt/sda8` | **Yes** — lives outside the cluster |

The third tier is what keeps the disposable-cluster property honest: a PVC on node-local
disk dies with the node, so anything worth keeping must live off-node. `nfs-kernel-server`
is currently inactive, so that tier is real work and is deferred to the first milestone
with data worth keeping. Introducing it here would be scope creep.

*Upgrade path:* the NVMe is nearly fully allocated (8 + 65.5 + 131 of 222 GiB), so the
thin pool cannot grow without another disk. Choosing `local-lvm` does not foreclose
anything — Proxmox migrates VM disks between storages online, so a future second NVMe
can be set up as ZFS (snapshots, send/receive, compression, integrity checking) and the
nodes moved onto it without a rebuild. Converting the existing layout to ZFS now would
require reinstalling Proxmox and is not justified. Separately, the HDD holds roughly
475 GiB of reclaimable space (`sda4`, 246.8 GiB NTFS; `sda6`, 228.2 GiB ext4 and
unmounted) which can grow the bulk tier without touching the NVMe or the cluster.

*Alternatives:* VM disk as a file on `pve-root` (rejected: bypasses purpose-built
storage and competes with the host OS for the same 65 GiB); node disks on the HDD
(rejected: datastore latency, as above); ZFS now (rejected: requires reinstalling
Proxmox); Ceph (rejected: needs three physical hosts).

### D8: Local state file, gitignored

Single operator, single machine. A remote backend solves locking and sharing problems
that do not exist here, and every backend option costs setup time. The state file
contains secrets and must be gitignored. The README should note *why* remote state was
skipped and when it would be required — an interviewer is more likely to ask about
the reasoning than the mechanism.

*Alternatives:* S3/R2 backend (defer); Terraform Cloud (free tier viable, adds an
external dependency and account for no present benefit).

### D9: Repository layout

```
tofu/
  main.tf          providers, image download, VM resource
  variables.tf     node sizing, image URL, credentials
  outputs.tf       node address, kubeconfig path
  cloud-init.yaml  guest agent, SSH key, k3s install
  terraform.tfvars.example
```

Flat, single root module. Deliberately *not* pre-split into modules — extracting a
module in milestone 5, once there is a second and third node to justify it, teaches
more than starting with an abstraction over one resource.

`k8s/` and `argocd/` directories arrive with the changes that need them.

## Risks / Trade-offs

| Risk | Mitigation |
|---|---|
| Proxmox API token ACL errors consume hours | D4: `root@pam` token; scope it later |
| Cloud-init fails silently; VM boots but no k3s | Verification task inspects `/var/log/cloud-init-output.log` before declaring success |
| Static address collides with another host | Allocate only from the D7 plan, strictly below the `.100` DHCP pool boundary; ping the address before first apply |
| Address plan drifts from reality as nodes are added | The D7 table is the single source of truth; update it in the same change that adds a node |
| Unclean shutdown corrupts the datastore | SMART reports 161 unsafe shutdowns of 197 power cycles — abrupt power loss is this host's normal failure mode. Tolerable at M1-M4 because the cluster is disposable and rebuilt from configuration. Becomes serious for etcd at M5 and for durable NFS data later; a UPS or a backup story is required before Tier 2 holds anything of value |
| Thin pool exhaustion turns guests read-only | 20 GiB thin disks against a 130 GiB pool leaves wide margin at three nodes; pool usage is a monitoring target at M7 |
| Datastore placed on the HDD by accident | Storage is named explicitly in the VM resource and verified in task 8.7; symptoms would present as networking faults (D10) |
| Over-privileged token normalised and forgotten | Recorded as a dated shortcut here and carried as an explicit task in the secrets milestone |
| Scope creep into "while I'm here, let me also…" | Non-goals above are binding. Ideas go to a later change, not this one |

**Accepted trade-off:** the first Terraform will be unidiomatic — hardcoded, flat, no
modules, no workspaces. That is intentional. Writing it correctly on the first attempt
teaches less than performing the refactor later against working infrastructure, and it
would slow the milestone whose entire purpose is producing early momentum.

## Migration Plan

Nothing is migrated by this change. The Docker Compose stack and Cloudflare tunnel
keep running untouched on the host; the VM is additive and consumes only spare
capacity. The workload migration is the next change, and it is the point at which
rollback matters.

**Rollback:** `tofu destroy`. The host returns to its current state. Because nothing
depends on the cluster yet, rollback is free — which is exactly why this milestone is
first.

## Open Questions

- Which Ubuntu LTS — 24.04 or 22.04? Either satisfies the specs; pick at
  implementation time based on which cloud image k3s currently certifies against.
- Does the Proxmox host's `local` storage accept `import` content type for the
  downloaded image, or does it need enabling? Discoverable in the first ten minutes
  of implementation; does not affect the approach.
