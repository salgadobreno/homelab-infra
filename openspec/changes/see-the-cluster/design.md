# Design

## Context

| Constraint | Detail |
|---|---|
| Node | `k3s-server-1`, 4 vCPU, 6 GiB, local-lvm. ArgoCD and the site already in it; 1,969 MiB used (2026-10-08) |
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

*Limits accepted.* From grafana.com/pricing, read 2026-10-08; task 3.1 confirms them on
the stack itself:

| Free tier | Limit | Retention |
|---|---|---|
| Metrics | 10k series / month | 14 days |
| Logs | 50 GB ingested / month | 14 days |
| Traces | 50 GB ingested / month | 14 days |
| Kubernetes Monitoring | 2,232 host hours, 37,944 container hours / month | |
| Users | 3 | |

Three things in that table are not what they look like:

- **The metrics cap is on billable series, not active series.** Grafana bills
  `max(active series, DPM)`, with 1 data point per minute included per series. A 60 s
  scrape keeps the two equal; a 15 s scrape, the Prometheus default, makes every series
  cost four. A user hit this the week of writing: ~7,900 active series billed as ~26,000
  and warned off the free tier. The scrape interval is therefore part of the budget, not a
  tuning knob (D6).
- **Host hours are three hosts.** 2,232 h is 3 × 744 h, a month of three nodes running
  continuously. M7's three nodes fill it exactly; a fourth node, or a node counted twice
  across a rebuild, goes over. Whether the hypervisor, scraped through its API, counts as a
  host is to be read off the usage page after task 9.
- **Container hours are about 51 containers**, running all month. The cluster has 13 pods
  today; this change adds about six.

Retention is the one that shapes the demo: a rebuild older than 14 days is gone.

### D2: Grafana Alloy through the `k8s-monitoring` Helm chart

Alloy is Grafana's distribution of the OpenTelemetry Collector. One agent covers
Prometheus-style scraping, log shipping, and an OTLP receiver. The `grafana/k8s-monitoring`
chart bundles it with kube-state-metrics and node-exporter, preconfigured for the hosted
stack's Kubernetes views.

What the chart is, at the pinned version (**4.5.2**, 2026-09-11; 4.5.3 was a day old when
this was written):

- **Nothing is on by default.** Features (`clusterMetrics`, `hostMetrics`,
  `podLogsViaLoki`, ...), the telemetry services (`kube-state-metrics`, `node-exporter`)
  and the Alloy instances (`collectors`) are each declared in values. This repo's
  `values.yaml` is therefore the complete list of what runs.
- **Alloy instances are run by an operator.** The chart installs the Alloy Operator
  (subchart `alloy-operator` 0.7.1) and its `Alloy` CRD, then declares each collector as
  an `Alloy` resource the operator turns into a Deployment or DaemonSet. ArgoCD sees the
  `Alloy` resources, not the pods' owners directly. The CRD arrives in the same sync as the
  resources that use it, the ordering problem the bootstrap Application already hit
  (`argocd-app-site.yaml.tftpl`); a sync wave or ArgoCD's retry settles it, and task 9.2
  watches for it.
- **Two collectors, not four**: `alloy-metrics` (singleton preset: one node, nothing to
  cluster) and `alloy-logs` (DaemonSet, reads pod logs from the node). The OTLP receiver
  is a third collector and is **not deployed in v0**: nothing emits OTLP yet, and an idle
  receiver is memory the node does not have to spare. Adding it is one `collectors` entry
  when the first workload needs it.
- **Each feature has a default metric allow-list** (`metricsTuning.useDefaultAllowList`,
  on by default), matched to the hosted Kubernetes views. The series budget (D6) starts
  from these rather than from hand-written drop rules.

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

**Memory.** Measured 2026-10-08 with `kubectl top`: the node uses **1,969 MiB of 6 GiB
(33%)**. Pods account for ~630 MiB of it (ArgoCD ~300, traefik 121, metrics-server 78,
coredns 70, the site 10); the rest is k3s and the OS. About 4 GiB is free.

The agent stack gets at most **1 GiB of limits**, set per component:

| Component | Request | Limit | Source of the figure |
|---|---|---|---|
| `alloy-metrics` | 128 Mi | 384 Mi | chart's `small` preset is 128/512 Mi; trimmed, see below |
| `alloy-logs` | 64 Mi | 192 Mi | log volume here is one nginx pod and the system pods |
| Alloy Operator | 64 Mi | 128 Mi | chart's own resource example |
| kube-state-metrics | 32 Mi | 64 Mi | chart's own resource example |
| node-exporter | 30 Mi | 64 Mi | chart's example is 30/50 Mi; rounded up |
| pve-exporter | 64 Mi | 128 Mi | estimate; Python process, a handful of VMs |
| **Total** | **382 Mi** | **960 Mi** | |

The sizing for Alloy comes from Grafana's resource guidance: about 11 GiB per million
active series, so ~11 KiB per series, so ~55 MiB for the 5,000-series budget below, on top
of the process's own baseline. Logs cost ~120 MiB per MiB/s ingested, and this cluster
logs a small fraction of that. `384 Mi` leaves the metrics collector several times its
expected working set; the `small` preset's 512 Mi is sized for clusters up to ~50 nodes.

Expected after the change: ~2.4-2.6 GiB used of 6 GiB, still under half. Task 2.1
records the baseline, task 10.1 the real figure. If the stack does not fit, the first cut
is log collection, not metrics.

**Series.** Budget **5,000 billable series**: half the free tier, leaving room for two more
nodes at M7. Billable, not active (D1), so the budget holds three rules:

- **The scrape interval stays at 60 s.** The chart's default (`global.scrapeInterval`),
  and 1 DPM per series, so billable equals active. Shortening it, globally or for one job,
  multiplies that job's cost and is a budget change, decided as one.
- **The default allow-lists stay on** for cluster metrics, kubelet, cAdvisor and
  kube-state-metrics. They are the families the hosted Kubernetes views use. Host metrics
  use the Linux-node integration's allow-list (`useIntegrationAllowList`).
- **Additions are named.** Anything beyond the allow-lists goes in
  `metricsTuning.includeMetrics` with a comment saying which view needs it. ArgoCD and
  pve-exporter are scraped with explicit include lists, not wholesale.

The budget lives in `values.yaml` as a comment next to these settings. Task 10.2 reads
both numbers back from the backend: active series, and DPM from
`grafanacloud_instance_samples_per_second × 60` in the `grafanacloud-usage` data source.
If DPM exceeds the active count, an interval somewhere is shorter than 60 s.

### D7: Arrival is a check against the backend

`make check-observability` queries the hosted Prometheus API for the age of the newest
sample per node and fails when any node is older than **5 minutes**, naming it. It uses a
separate read-only token, kept on the operator host in `.grafana-read-token` (gitignored,
mode 600) and never sent to the cluster. The agent's token cannot read, by spec.

It is the second check in `make check` that fails because the world moved rather than the
repository (after `check-diagram`), and it depends on a third party being up. Both are
accepted; the failure message says which it was.

## Risks / Trade-offs

- [The series budget is blown by a default nobody read, or by a short scrape interval] →
  allow-lists on and the 60 s interval kept (D6); task 10.2 reads back both active
  series and DPM, since the free tier caps the higher of the two.
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
