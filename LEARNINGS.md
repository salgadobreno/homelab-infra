# Learning log

A record of fundamentals this project actually ran into — not a syllabus.

**How this file is written.** An entry is added *after the fact*, when something was
hit in practice: a failure, a surprising default, a decision that turned out to matter
later. Entries are short. If a topic deserves more than a paragraph it goes to the
queue at the bottom and gets expanded deliberately, not automatically.

**What this file is not.** It is not a summary of what the agent did, and it is not a
list of lessons generated because a session ended. Nothing goes in unless there was
friction behind it. Reading an entry is not the same as having learned it — entries
carry a marker:

- `[hit]` — encountered, recorded, not yet examined properly
- `[worked]` — gone through deliberately; could explain it unprompted
- `[open]` — flagged as worth understanding, not yet touched

---

## 2026-08-20 — Milestone 1: first cluster from code

### `[hit]` A saved plan is bound to a specific state, not just to the config

`tofu apply tfplan` failed with "Saved plan is stale". The config had not changed —
the *state* had, because `apply` refreshes before it acts and that bumped the serial
from 3 to 4.

Fundamental: a plan file is a promise about a known world. Terraform records which
state version it was computed against and refuses to apply against a different one.
That is what stops an hour-old plan from deleting something created since.

### `[hit]` Proxmox content types are per-datastore opt-ins

Two failures, same root cause. `local` rejected the cloud image until the file was
named `.qcow2`, and rejected the cloud-init snippet until `snippets` was added to its
content list with `pvesm set local --content ...`.

Fundamental: a Proxmox datastore advertises which *kinds* of things it will hold.
Being a directory with free space is not sufficient. `make storage` shows the list.

### `[hit]` The bpg provider talks over two channels, not one

The API token is enough for almost everything, but **snippet uploads go over SSH** —
PVE exposes no API endpoint for them. This surfaced as a confusing "unable to
authenticate user" error at apply time, long after the token had been proven working.

Fundamental: a Terraform provider's credentials are not necessarily one thing. Worth
asking of any provider: what does it need, and for which operations?

### `[worked]` Static addressing is what made the kubeconfig simple

k3s writes a kubeconfig pointing at `127.0.0.1`, useless off-node, with a certificate
valid only for that name. Because the address was decided at *plan* time rather than
discovered afterwards, `--tls-san 192.168.0.30` could be passed at install, so the
certificate matches the address the kubeconfig will use.

Fundamental: deciding a value up front instead of discovering it removes a whole class
of ordering problems. The alternative — boot, query the guest agent, then rewrite —
makes `apply` depend on the agent reporting in.

### `[hit]` Untrusted command output is untrusted input

The Makefile read the node address with `$(shell tofu output -raw node_address)`.
With no outputs defined yet, `tofu` printed a *warning* on stdout, and that warning
text contains `` `tofu refresh` `` in backticks — which the shell then executed. The
first `make help` hung for two minutes running a refresh nobody asked for.

Fundamental: text from a tool is data, not code. It is now filtered through a strict
IP match before use. This is the same class of bug as shell injection, arriving from
an unexpected direction.

---

## Worked topics

Explored deliberately on 2026-08-20, against this project's own artifacts. Markers stay
`[hit]` until you can explain them unprompted — promoting to `[worked]` is yours to do.

### `[hit]` The dependency graph is inferred from references, not declared

Nothing in `main.tf` says "build the image first". The VM resource merely *mentions*
the other two:

```hcl
import_from       = proxmox_download_file.ubuntu_cloud_image.id
user_data_file_id = proxmox_virtual_environment_file.cloud_init.id
```

Terraform reads those expressions and derives the edges. Confirmed two ways — the graph
has exactly two edges, and the state records the result:

```
proxmox_download_file.ubuntu_cloud_image        depends_on: (none)
proxmox_virtual_environment_file.cloud_init     depends_on: (none)
proxmox_virtual_environment_vm.k3s_server       depends_on: [ubuntu_cloud_image, cloud_init]
```

Three consequences worth carrying:

- **Parallelism is free.** The image download and the snippet upload have no edge
  between them, so Terraform runs them concurrently. The VM waits for both.
- **Destroy walks the graph backwards.** The VM must go before the image it was
  imported from. This is why `tofu destroy` ordering is not simply reverse-of-creation
  by timestamp.
- **`depends_on` is the escape hatch, not the norm.** It exists for dependencies the
  config cannot see — an ordering that only matters because of a side effect. Reaching
  for it when a reference would do hides the relationship from the graph.

The practical skill: reading a plan and predicting what a change drags with it. If a
value feeding `import_from` changes, everything downstream is implicated.

### `[hit]` State is a cache, a ledger, and a liability

`serial` increments on every write. It went 4 → 6 across the failed and successful
applies, and the stale-plan error was exactly this: the plan was computed against one
serial and `apply` found another.

`lineage` is a UUID identifying *this* state's history — `15971339-…` here, identical
in `terraform.tfstate.backup`. It exists so Terraform can refuse to apply a plan
computed against a completely different state file, rather than silently doing damage.

`terraform.tfstate.backup` holds the previous serial (4 while current is 6): a one-step
automatic undo, not a backup strategy.

**The liability part is concrete.** State stores full resource attributes, so the
entire cloud-init body — 1674 characters, SSH public key included — sits in the state
file in plaintext. A public key is harmless. The principle is not: anything a provider
returns lands here, including values declared `sensitive`, which are redacted in *plan
output* but not in state. That is why `*.tfstate` is gitignored, and why remote state
in a real team means an encrypted backend, not just a shared file.

Which also sharpens what `make check-drift` asserts: refresh reality, compare against
state, compare state against config. "No drift" means all three agree — not that
nothing has been touched.

### `[hit]` k3s is one binary, and five of its seven pods are opinions

Two separate questions hide behind "what did k3s install": how the control plane is
*arranged*, and what got deployed *on top*.

**The arrangement.** A kubeadm cluster runs the apiserver, scheduler, controller-manager
and etcd as static pods — you can see them in `kube-system`. Here:

```
$ kubectl get pods -n kube-system | grep -E 'apiserver|etcd|scheduler|controller-manager'
NONE - no control-plane pods at all
```

They are all goroutines inside a single 82 MB `/usr/local/bin/k3s`, along with kubelet,
containerd and flannel. That is the whole trick: same components, same APIs, packed into
one process instead of orchestrated as pods. Certified-conformant, so `kubectl` cannot
tell the difference — but `systemctl restart k3s` restarts the entire control plane at
once, which a kubeadm cluster would never do.

**The datastore is sqlite, not etcd** — `/var/lib/rancher/k3s/server/db/state.db`, 11 MB
with a 6 MB write-ahead log. This is the D10 storage argument made concrete: that WAL is
fsync-bound, which is why node disks live on the NVMe. Milestone 5 swaps it for embedded
etcd, and the requirement gets stricter, not looser.

**What got deployed on top.** Seven manifests in
`/var/lib/rancher/k3s/server/manifests/` are applied automatically at first boot:

| Component | Kubernetes proper? |
|---|---|
| coredns | Yes — every conformant cluster needs cluster DNS |
| metrics-server | Standard addon, but not core; `kubectl top` depends on it |
| flannel (CNI) | Upstream makes you *choose* a CNI; k3s chose for you |
| traefik | k3s's opinion — upstream ships no default ingress controller |
| local-path-provisioner | k3s's opinion — upstream ships no default StorageClass |
| svclb / klipper-lb | k3s's opinion — fakes LoadBalancer with a hostPort DaemonSet |
| ccm | k3s's stub cloud-controller-manager |

Traefik arrives through a `HelmChart` custom resource, served from the apiserver itself
(`https://%{KUBERNETES_API}%/static/charts/…`) rather than the internet — k3s embeds a
Helm controller so a cluster can bootstrap offline.

**Forward-looking consequence, worth knowing before milestone 7:** klipper-lb already
claims `Service type=LoadBalancer`. Installing MetalLB alongside it means two controllers
answering for the same thing. k3s must be started with `--disable servicelb`, which is a
change to the cloud-init `runcmd` and therefore to the *provisioning* layer — not
something that can be fixed from inside the cluster with GitOps. Same likely applies to
`--disable traefik` if ingress is managed declaratively later.


### `[hit]` One character in a rendered file replaced the whole cluster

Adding a `k3s_disable` variable with an empty default should have been a no-op. It was
not: `${disable_flags}` rendered as `""` but left a space before the closing quote, so
the cloud-init file differed by one byte. `make check-drift` reported:

```
Plan: 2 to add, 0 to change, 2 to destroy
  # proxmox_virtual_environment_file.cloud_init must be replaced
  # proxmox_virtual_environment_vm.k3s_server   must be replaced
```

The snippet has no in-place update path, so it is replaced; the VM references it, so
the VM is replaced too. **A trailing space would have destroyed a running cluster.**

Fixed by putting the space *inside* each list element and joining with `""`, so an
empty list renders as the empty string.

Two things generalise. First, the blast radius came from the dependency graph — the
change was to the snippet, but the damage propagated to everything referencing it.
Second, `create_before_destroy` and replacement semantics are worth knowing *before*
a plan proposes destroying something you care about. The plan said so plainly; the
only real risk was not reading it.


### `[hit]` Verifying recovery means proving the disruption happened first

Twice now, a readiness check has passed without waiting for anything.

The cloud-init gate ran `kubectl wait --for=condition=Ready node --all` before the node
object existed. `wait` does not block for a resource to *appear* — it errors instantly
with `no matching resources found`, and cloud-init wrote its completion marker anyway.

The reboot check made the same mistake from the other end: it polled for "2 ready
replicas" immediately after issuing the reboot, matched the *pre-reboot* state, and
declared recovery in 27 seconds while the deployment was actually at 0/2.

Fundamental: a check for "is it healthy" is not a check for "did it recover". The
second needs a fact that could only be true after the disruption — node boot time,
a restart count, a resource UID. Here the honest evidence was `uptime -s` moving and
`/proc/uptime` reading 57 seconds.

Adjacent trap from the same session: the node runs UTC and the host UTC−03, so
`date -d "$(ssh node uptime -s)"` produced a recovery time of −10764 seconds. Compare
instants, not wall-clock strings, across machines.


### `[hit]` cloud-init runs once per *instance*, and the VM's identity is a file

**Four stages, four systemd units**, ordered by what is available yet:

| Unit | Has | Does |
|---|---|---|
| `cloud-init-local` | no network | finds the datasource, writes network config |
| `cloud-init` | network up | disks, filesystems, growpart |
| `cloud-config` | full config | most config modules |
| `cloud-final` | everything | `runcmd`, user scripts |

`runcmd` lands in the last stage, which is why k3s installs after the network exists
and the filesystem has been grown. `cloud-init status: done` means *cloud-final*
finished — not that anything it started succeeded.

**The datasource here is `NoCloud` on a config-disk**, `/dev/sr0`:

```
/dev/sr0: LABEL="cidata" TYPE="iso9660"
  meta-data  network-config  user-data  vendor-data
```

Proxmox builds that ISO and attaches it as a CD-ROM — the `ide2 = local-lvm:
vm-100-cloudinit,media=cdrom` line in the VM config. The provider's `initialization`
block becomes `network-config`; the snippet becomes `user-data`.

**Identity comes from `instance-id` in `meta-data`.** On boot, cloud-init compares it
against `/var/lib/cloud/data/instance-id`. Differ → new instance, per-instance modules
run. Match → skipped. Here:

```
meta-data:               instance-id: 1ba785bd…
/var/lib/cloud/instance -> /var/lib/cloud/instances/1ba785bd…
```

**This is what separates the reboot test from the rebuild test**, and the difference is
easy to miss:

- **Reboot (8.3).** Same disk, same `instance-id`, so `runcmd` did *not* re-run. k3s
  came back because systemd had enabled the unit — nothing was reinstalled. The test
  proved the OS-level service survives, and nothing about cloud-init.
- **Rebuild (9.2).** New disk, empty `/var/lib/cloud`, so everything ran from scratch.
  Only one instance directory exists on the node, because the previous instance's state
  died with its disk.

The practical consequence: **editing `user-data` on a running VM does nothing.** Without
a new `instance-id`, cloud-init skips per-instance modules on the next boot. That is why
Terraform *replaces* the VM when the snippet changes rather than updating it in place —
and why one trailing space proposed destroying the cluster. Replacement is not the
provider being dramatic; it is the only thing that actually works.


---

## Queue — marked for exploration

Short entries that may or may not be expanded. Nothing here has been worked through.

- `[open]` **kubeconfig structure** — clusters, contexts, users, and why they are three
  separate things rather than one.
- `[open]` **Thin provisioning** — the node claims 20 GiB from a 130 GiB pool that could
  be oversubscribed. What happens at 100%, and why it belongs in monitoring.
- `[open]` **Idempotence** — why `apply` twice is safe, and what "no drift" is really
  asserting when `make check-drift` passes.
