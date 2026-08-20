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

---

## Queue — marked for exploration

Short entries that may or may not be expanded. Nothing here has been worked through.

- `[open]` **cloud-init's boot stages** — why it runs once per *instance* rather than
  once per boot, and what identifies an "instance". Directly relevant to the
  destroy/rebuild demo at task 9.2.
- `[open]` **What k3s actually installed** — traefik, coredns, local-path-provisioner,
  metrics-server, svclb. Which are Kubernetes proper and which are k3s's opinions.
- `[open]` **kubeconfig structure** — clusters, contexts, users, and why they are three
  separate things rather than one.
- `[open]` **Thin provisioning** — the node claims 20 GiB from a 130 GiB pool that could
  be oversubscribed. What happens at 100%, and why it belongs in monitoring.
- `[open]` **Idempotence** — why `apply` twice is safe, and what "no drift" is really
  asserting when `make check-drift` passes.
