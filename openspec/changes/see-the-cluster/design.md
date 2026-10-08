# Design

## Context

| Constraint | Detail |
|---|---|
| Node | `k3s-server-1`, 4 vCPU, 6 GiB, local-lvm. ArgoCD and the site already in it |
| Host RAM | 13 GiB total; the ~10 GiB all-VMs ceiling in `config.yaml` still binds, and M7 (three nodes) has to fit under it after this |
| Lifetime | the cluster is disposable; `make rebuild` destroys everything not in Git |
| Network | outbound only, through the Cloudflare tunnel; nothing inbound |
| Hypervisor | serves no HTTP, asserted by `make check` |
| Secrets | files on disk, no manager (`CLAUDE.md`, Known shortcuts) |
| Bootstrap | one `Application` (`site`) in `tofu/cloud-init/`, applied by k3s from its manifests dir |
| The page | `scripts/generate-diagram.sh` lists every workload in every namespace |

See `proposal.md` for why, and the three spec deltas for what must hold.

## Goals / Non-Goals

**Goals:**

- Telemetry stored off the node, so a rebuild is a visible gap, not lost history.
- One agent for metrics, logs, and later traces. OpenTelemetry-compatible, so the
  vocabulary carries over to any employer's stack.
- A memory cost that is written down before it is spent.

**Non-Goals:**

- Dashboards as code, alerting, SLOs. The next rung. v0 uses the backend's stock
  Kubernetes views and community dashboards, imported by hand and named as such.
- High availability of the agent. One node.

## Decisions

### D1: Grafana Cloud free tier, not a self-hosted stack

Operator decision, 2026-10-08.

Self-hosted (`kube-prometheus-stack` plus Loki and Grafana) costs roughly 2-3 GiB in a
6 GiB node already carrying ArgoCD, and its TSDB is destroyed by every rebuild unless it
lives on the NFS tier: an HDD on a host with 161 unsafe shutdowns out of 197 power cycles.
Both problems disappear when the store is somewhere else.

The hosted stack is pushed to, which suits a network with no inbound path. It is also the
shape most employers run: an agent in the cluster, a managed backend.

*What self-hosting would have bought:* fluency operating Prometheus and Loki themselves,
and no third party holding the data. Both are real. They are a later rung, when a second
disk or more RAM makes them affordable, not something v0 should spend its budget on.

*Limits accepted* (free tier, to be confirmed at signup and recorded in task 3): about
10k active metric series, 50 GB logs, 14-day retention. Retention is the one that shapes
the demo: a rebuild older than 14 days is gone.

### D2: Grafana Alloy through the `k8s-monitoring` Helm chart

Alloy is Grafana's distribution of the OpenTelemetry Collector. One agent covers
Prometheus-style scraping, log shipping, and an OTLP receiver. The `grafana/k8s-monitoring`
chart bundles it with kube-state-metrics and node-exporter, preconfigured for the hosted
stack's Kubernetes views.

*Alternative considered:* the upstream OpenTelemetry Collector plus a separate
node-exporter and kube-state-metrics, wired by hand. Same result, more YAML, and the
hosted Kubernetes views expect the chart's label conventions. Rejected for v0; worth
knowing it is the same pipeline underneath, which is the interview answer.

The chart version is pinned. ArgoCD installs it as a multi-source Application: the chart
from Grafana's Helm repository, values from `k8s/observability/values.yaml` in this repo.

### D3: The hypervisor is read through its API, from inside the cluster

`prometheus-pve-exporter` runs as a Deployment in the cluster and queries the Proxmox API
at the host's address. It reports host CPU, memory, storage, and per-VM usage.

*Alternative considered:* `node-exporter` on the hypervisor. Richer (disk I/O, NVMe
temperature, swap pressure), but it is a listening port on the host, which `make check`
forbids, and it is software on the hypervisor outside both `tofu/` and `k8s/`, the
configuration-management layer this project declined. Deferred, by name, to whichever
rung first needs per-device disk metrics.

The exporter authenticates as a dedicated user with the built-in `PVEAuditor` role,
which can read and not change. A privilege-separated API token on that user, created by
an operator-run script on the pattern of `scripts/create-terraform-user.sh`.

### D4: App of apps

Today `tofu/cloud-init/argocd-app-site.yaml.tftpl` is the only Application, and it points
at `k8s/site`. Adding observability the same way means a second bootstrap file, a second
template variable, and a rebuild for every future workload: the provisioning layer would
grow with the application layer, which is exactly the boundary `CLAUDE.md` keeps.

Instead the bootstrap Application becomes `root`, pointing at `k8s/apps/`. That
directory holds one Application per workload: `site.yaml`, `observability.yaml`. Adding
a workload is then a commit under `k8s/`, never a change in `tofu/`.

`root` keeps `selfHeal` and `prune`. The child Applications carry the resources
finalizer, so pruning an Application also prunes what it deployed rather than orphaning
it.

*Alternative considered:* an `ApplicationSet` generating Applications from directories.
Less YAML per app, but it is the next abstraction, and two apps do not justify it.

### D5: Secrets arrive through cloud-init, from a gitignored file

Operator decision, 2026-10-08. A known shortcut, recorded as one.

Two secrets have to reach the cluster: the Grafana Cloud write token and the exporter's
Proxmox token. They are declared as `sensitive` OpenTofu variables, set in
`tofu/observability.auto.tfvars` (gitignored by the existing `*.auto.tfvars` rule, mode
600), and rendered by cloud-init into one manifest in k3s's manifests directory: the
`observability` Namespace and two Secrets. k3s applies it at startup, before ArgoCD
syncs, so the chart finds its credentials on the first pass.

`terraform.tfvars` is not used. It is the scoped provisioning credential, and nothing else
writes to it.

Where the secret values now exist, written down because that is the cost of the shortcut:

- `tofu/observability.auto.tfvars`, mode 600, operator's account.
- `tofu/terraform.tfstate`, gitignored, already holds material of this kind.
- The rendered snippet on the hypervisor's `local` datastore, owned by `tofu-snippets`.
- The node's manifests directory, root-only, `0600` like the ArgoCD manifests.
- The cluster's Secrets, readable by anything with `get secrets` in `observability`.

*Alternatives considered:* SOPS or Sealed Secrets, which put encrypted secrets in Git and
remove every copy above except the cluster's. That is the correct answer and its own rung,
not something to learn inside this one. A `kubectl create secret` by hand is rejected
outright: it does not survive a rebuild, and violates the GitOps spec.

A secret change needs a rebuild to reach the cluster, since the manifests directory is
written once at boot. Acceptable at the rate tokens rotate here.

### D6: Budgets, stated before spending

**Memory.** The agent stack gets at most **1 GiB of limits** on the node: Alloy (metrics,
logs), kube-state-metrics, node-exporter, pve-exporter. Each component has requests and
limits set in values. Task 2 measures the node before anything is added; task 9 measures
after, and the difference is recorded against this number. If the stack does not fit,
the first cut is log collection, not metrics.

**Series.** Budget **5,000 active series**, half the free tier, leaving room for two more
nodes at M7. Drop rules sit in the agent, not the backend: cAdvisor and kubelet metrics
are kept only for the families the stock Kubernetes views use, and histogram buckets are
dropped where only averages are shown. The budget lives in `values.yaml` as a comment
next to the rules, and task 9 reads the real count back.

### D7: Arrival is a check against the backend

`make check-observability` queries the hosted Prometheus API for the age of the newest
sample per node and fails when any node is older than **5 minutes**, naming it. It uses a
separate read-only token, kept on the operator host in `.grafana-read-token` (gitignored,
mode 600) and never sent to the cluster. The agent's token cannot read, by spec.

It is the second check in `make check` that fails because the world moved rather than the
repository (after `check-diagram`), and it depends on a third party being up. Both are
accepted; the failure message says which it was.

## Risks / Trade-offs

- [The series budget is blown by a default nobody read] → drop rules written before the
  first sync; task 9 reads the real count back; the free tier stops ingesting rather than
  billing.
- [The agent stack starves the site on a 6 GiB node] → limits on every component, a
  measured baseline first, and logs as the first thing cut.
- [A third party holds addresses and logs] → private account, operator-only. Nothing from
  the backend is published. Revisit if the data or the audience changes.
- [The token file is the weakest copy of the secret] → mode 600, gitignored,
  `check-secrets` extended to cover it. The real fix is the secret-manager rung.
- [The app-of-apps cutover takes the site down] → it lands through a rebuild, which
  already costs ~190 s of public outage; `site` keeps its name and content, so the cutover
  is the rebuild and nothing more.
- [The public page grows the observability workloads] → expected; `make diagram` after
  the first sync. Names and images are inside the disclosure boundary; `check-disclosure`
  confirms.
- [Grafana Cloud free tier changes terms] → the agent's destination is one block of
  values; self-hosting is the documented fallback (D1).

## Migration Plan

1. Measure the baseline (no change).
2. Create the backend stack and both tokens, and the exporter user (operator steps).
3. Commit `k8s/apps/`, `k8s/observability/`, and the `tofu/` changes in one push.
   The running cluster does not change: its bootstrap is still the old `site`
   Application, which ignores `k8s/apps/`.
4. `make rebuild CONFIRM=yes`. The new node boots with `root`, the Secrets, and every
   Application; ArgoCD brings up the site and the agent.
5. `make verify-rebuild`, `make diagram`, `make check`.

Rollback: revert the commit and rebuild. The backend keeps whatever arrived.

## Open Questions

- Which community dashboards to import for the hypervisor. Cosmetic; does not change the
  agent, the specs, or the tasks.
