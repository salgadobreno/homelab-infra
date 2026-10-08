## Why

Nothing here can be watched. The only evidence that the cluster is healthy is a check
run by hand, and the only history is what a terminal scrolled past. The next rung, three
nodes on 13 GiB, is a memory bet, and it should be sized from measurements rather than
from guesses.

This is the rung that answers "I can see what the cluster is doing." It is pulled forward
from M7 to M6, ahead of multi-node, for that reason: the operator decided 2026-10-08,
the same move that brought `narrow-privileges` forward from rung 6 to rung 2.

## What Changes

- **The ladder is reordered.** M6 becomes observability (this change); multi-node moves
  to M7. `openspec/config.yaml` and `CLAUDE.md` change with it.
- **Telemetry leaves the cluster.** An in-cluster agent ships metrics and logs to a
  hosted Grafana stack (Grafana Cloud, free tier). Nothing is stored in the cluster, so
  history survives `make rebuild`.
- **The cluster is covered**: node, workloads, Kubernetes object state, ArgoCD, and pod
  logs.
- **The hypervisor is covered without installing anything on it**: an exporter in the
  cluster reads the Proxmox API with its own read-only credential.
- **ArgoCD bootstraps an app of apps.** The bootstrap `Application` points at
  `k8s/apps/` instead of `k8s/site`, and every Application, `site` included, lives in
  Git. A second app would otherwise mean a second bootstrap file in `tofu/`.
- **Two secrets reach the cluster through cloud-init**, from a gitignored file, the way
  the ArgoCD bootstrap does. Recorded as a known shortcut; a secret manager is its own
  rung.
- **`make check-observability`** asserts that the node's telemetry arrived recently.
  Wired into `make check`.

Explicitly **not** in this change:

- Self-hosted Prometheus, Loki or Grafana. They do not fit the node's 6 GiB beside
  ArgoCD, and a local store dies with every rebuild. A later rung, if RAM allows.
- An agent on the hypervisor. `make check` asserts the hypervisor serves no HTTP, and an
  exporter port would break that for data the Proxmox API already gives.
- Traces. Nothing here emits spans. The agent accepts OTLP so the first workload that
  does has somewhere to send.
- Alerting, SLOs, dashboards as code. The next rung: observability as code.
- Hypervisor journal logs, tunnel metrics.
- Metrics on the public site. If that ever happens, M5's disclosure boundary applies.

## Capabilities

### New Capabilities

- `infrastructure/observability`: the cluster and the hypervisor are observable from
  outside the cluster, history survives a rebuild, and arrival is checked rather than
  assumed.

### Modified Capabilities

- `infrastructure/gitops`: workloads are declared as Applications in Git, reached from a
  single bootstrap Application, so adding a workload never touches the provisioning
  layer.
- `infrastructure/credential-scoping`: the observability credentials are scoped
  (write-only to the telemetry backend, read-only to the hypervisor) and asserted by
  `make check-privileges`.

## Impact

- **`tofu/cloud-init/`**: the bootstrap Application changes target; a Secret manifest is
  added. A rebuild is needed for either to take effect, and is the acceptance test.
- **`k8s/`**: new `apps/` and `observability/` directories. `site` stops being the only
  thing ArgoCD manages.
- **Node memory**: the agent stack is the first workload beside the site. Budget in
  design.
- **The public page**: the generator lists every workload, so the new ones appear on
  `buzaga.com.br` and `check-diagram` goes red until `make diagram` is run. Workload
  names and images are inside the disclosure boundary.
- **A third party now holds data about this cluster**: metric labels and pod logs go to
  Grafana Cloud. Addresses appear in that data; it is private to the operator's account,
  not published.
- **The hypervisor gains a user**: a read-only Proxmox account for the exporter.
