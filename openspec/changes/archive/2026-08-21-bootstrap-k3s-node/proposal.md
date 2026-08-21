## Why

The homelab runs Proxmox VE with zero VMs and zero LXC containers, while the actual
workload (nginx, a hit-counter, redis) runs as Docker containers directly on the
hypervisor. Nothing is declared as code, so the environment cannot be rebuilt,
reviewed, or reasoned about — and two previous attempts at fixing this stalled
because they were structured layer-by-layer and produced nothing observable until
the final layer.

This change establishes the first end-to-end vertical slice: a Kubernetes node that
Terraform created. It is deliberately the smallest scope that ends in a working,
demonstrable system.

## What Changes

- Introduce an OpenTofu/Terraform root module that authenticates to the Proxmox VE
  API and manages VM lifecycle declaratively.
- Provision a single Ubuntu LTS VM from an upstream cloud image, configured by
  cloud-init. No hand-built golden image template.
- Install k3s on that VM via cloud-init, producing a single-node Kubernetes cluster.
- Expose the cluster's kubeconfig as a Terraform output so `kubectl` works from the
  Proxmox host without manual file copying.
- Establish repository layout (`tofu/`) and the operating conventions that later
  milestones build on.

### Explicitly out of scope

- Migrating the running Docker workload to Kubernetes (next change).
- ArgoCD and GitOps reconciliation.
- Multi-node cluster, scheduling, node drain.
- Secrets management beyond "do not commit plaintext credentials".
- Observability (Prometheus, Grafana).

### Decisions pinned by this change

These are recorded here so later work does not relitigate them:

- **No Ansible.** Nodes are immutable and disposable. Cloud-init handles bootstrap;
  everything above the OS will be declared in Git and reconciled by GitOps. There is
  no long-lived host state for a config-management tool to converge.
- **Local Terraform state.** This is a single-operator project. A remote backend
  solves collaboration and locking problems that do not exist here.
- **Single node first.** Growing to a multi-node cluster is a later change, and
  performing that migration (hardcoded resource → `for_each` → module) is itself the
  intended Terraform learning exercise.
- **Static addressing, not DHCP.** Cluster nodes take fixed addresses from an address
  plan in configuration. The LAN has no local DNS, so a floating address cannot be
  hidden behind a hostname, and the destroy/recreate cycle this project depends on is
  exactly what would churn a DHCP lease.
- **The existing website is disposable.** It is a placeholder and may break during
  this work.

## Capabilities

### New Capabilities

- `infrastructure/vm-provisioning`: Declarative lifecycle management of Proxmox VE
  virtual machines through Terraform — creation from cloud images, cloud-init
  configuration, network attachment, and reproducible destroy/recreate.
- `infrastructure/k3s-cluster`: A reachable single-node Kubernetes cluster running on
  a provisioned VM, with credentials surfaced to the operator.

### Modified Capabilities

None. This is the first change in the repository; no existing specs.

## Impact

- **New**: `tofu/` root module, provider configuration, cloud-init templates.
- **New tooling required on the Proxmox host**: `tofu` (or `terraform`) and
  `kubectl`. Neither is currently installed, and neither is available from Debian
  apt repositories.
- **Proxmox**: a new API token and an API user/role; one VM consuming roughly 6 GiB
  RAM and 20-40 GiB of disk. Storage location must be chosen deliberately —
  `/mnt/sda8` is 86% full with ~59 GiB free, while `pve-root` has ~49 GiB free.
- **Unaffected**: the running Docker Compose stack and the Cloudflare tunnel both
  continue operating untouched. Nothing is decommissioned by this change.
- **Risk**: Proxmox API token ACLs and cluster networking are the two known time
  sinks. Cloud-image download via the provider is used specifically to avoid the
  hand-built-template rabbit hole.
