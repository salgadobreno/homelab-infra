# homelab-infra

Infrastructure-as-code for a single-host Proxmox VE homelab: a k3s cluster provisioned
with OpenTofu, reconciled by ArgoCD, serving `buzaga.com.br`. Built to be destroyed and
rebuilt on demand.

## Design

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

## Destroying and recreating the cluster

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
