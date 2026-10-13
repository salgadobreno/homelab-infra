# Baseline

The node before anything in this change is added, so the agent stack's cost is a
difference between two readings rather than an impression. Task 10.1 takes the second.

## Memory and CPU

`make top`, 2026-10-08 21:28 -03:00. Working-set memory from metrics-server.

| | CPU | Memory |
|---|---|---|
| Node `k3s-server-1` (6 GiB) | 79m (1%) | **1,988 Mi (33%)** |
| All pods | | 648 Mi |
| k3s and the OS (node minus pods) | | ~1,340 Mi |

| Namespace | Pod | CPU | Memory |
|---|---|---|---|
| argocd | argocd-application-controller-0 | 4m | 227 Mi |
| kube-system | traefik | 1m | 121 Mi |
| kube-system | metrics-server | 4m | 78 Mi |
| kube-system | coredns | 2m | 70 Mi |
| kube-system | local-path-provisioner | 1m | 46 Mi |
| argocd | argocd-repo-server | 1m | 38 Mi |
| argocd | argocd-redis | 2m | 29 Mi |
| argocd | argocd-server | 1m | 27 Mi |
| web | site | 1m | 10 Mi |
| kube-system | svclb-traefik | 0m | 2 Mi |

An earlier reading the same day, used in design D6, was 1,969 Mi. The ~20 Mi spread is
the ArgoCD application controller, the noisiest pod here. Treat the node figure as
±25 Mi.

Ten pods. Design D1's container-hours headroom is counted from this.

## The check suite

`make check`, same session. **Not green**, so task 2.2 is open.

| Check | Result |
|---|---|
| `check-secrets` | OK |
| `check-disclosure` | OK |
| `check-configmap-size` | OK |
| `check-privileges` | **FAIL** in `check-tunnel-ssh`: the tunnel's SSH hostname answers an unauthenticated request with HTTP 200 and the SSH banner. No Access challenge. Everything else inside `check-privileges` passed |
| `check-updates` | OK (run on its own, since `make check` stopped above) |
| `check-site` | OK |
| `check-diagram` | OK, once the shell's `KUBECONFIG` is unset. It failed first because the operator's shell exports a path from before the repository moved, and `generate-diagram.sh` lets the environment win. Not a repository fault |
| `check-drift` | OK, no drift |

The `check-tunnel-ssh` failure is not caused by this change and is not fixed by it. It comes
from the Cloudflare Access configuration, which lives outside this repository.
It is recorded here because a red suite at the start of a change has to be explained,
or every later failure inherits the doubt.

**Known and accepted, operator decision 2026-10-08.** The operator turned Access off: it
was slow, and sometimes unresponsive from mobile networks. Restoring it is on the
backlog, not in this change. The check stays red on purpose rather than being weakened.
sshd is still key-only, so the path has one gate instead of two.

Consequence for this change: `make check` stops at `check-privileges`, so the checks after
it never run. Until Access is back, run `make -k check` and read past that one failure.
Task 2.2 is satisfied on that basis: every other check is green.

## Spike: Grafana's own onboarding, 2026-10-08

The operator ran Grafana Cloud's Kubernetes onboarding command by hand, before the
GitOps install exists. Operator decision: keep it a day as a measurement, then remove it
(tasks 2.3-2.5). It is not the deliverable: it is installed by `helm`, not ArgoCD, and is
gone on the next rebuild.

| | |
|---|---|
| Releases (ns `monitoring`) | `grafana-cloud` (k8s-monitoring 4.5.3), `grafana-cloud-alloy-daemon` (alloy chart 1.13.0, Alloy v1.20.0) |
| Pipeline config | Fleet Management: Alloy pulls its configuration from Grafana Cloud, not from values in Git |
| Collector | one `alloy-daemon` DaemonSet, presets `large, root, host-storage, host-network, host-cgroup, clustered, service-discovery, filesystem-log-reader, daemonset` |
| Privileges | privileged, root, `hostPID`, `hostNetwork`; hostPath `/var/log`, `/var/lib/docker/containers`, `/var/lib/alloy`, `/sys/fs/cgroup` |
| Also deployed | alloy-operator, kube-state-metrics, node-exporter, Beyla k8s cache (eBPF auto-instrumentation on) |
| Alloy resources | request 1 Gi / 500m, limit 2 Gi / 2 CPU (`large` preset) |
| Cluster name | `default` |

Memory a few minutes after install: node **2,633 Mi (44%)**, up 645 Mi from the
baseline. Alloy 511 Mi, operator 40, kube-state-metrics 16, node-exporter 8, Beyla
cache 7.

What it differs from the design on, and why it is not kept: config outside Git (D2,
observability as code), privileges and Beyla (not needed for v0's scope), the `large`
preset's 1 Gi request alone exceeding the 960 Mi budget (D6).

What it is good for: the series, DPM and memory of Grafana's default, measured on this
node. Recorded here after a day (task 2.4).

### After the day (task 2.4), 2026-10-13

Read on day five, not day one: the spike ran 112.5 h with no restarts (Alloy up since
2026-10-08 21:14, read 2026-10-13 16:26 -03:00). Memory from `make top`. Series and DPM
from Alloy's own `/metrics` (hostPort 12345 on the node), not from the `grafanacloud-usage`
data source: that needs the read token from task 3.2, which does not exist yet. Alloy's
figures are what it sends, so they bound what is billed. Task 10.2 reads the backend.

**Memory.**

| | Day 0 | Day 5 |
|---|---|---|
| Node `k3s-server-1` | 2,633 Mi (44%) | **2,833 Mi (47%)** |
| All pods | | 1,257 Mi |
| `alloy-daemon` (alloy container) | 511 Mi | 537 Mi (+6 config-reloader) |
| alloy-operator | 40 | 40 |
| kube-state-metrics | 16 | 18 |
| node-exporter | 8 | 10 |
| Beyla k8s cache | 7 | 8 |

Namespace `monitoring`: ~620 Mi. Node: +845 Mi over the baseline's 1,988.

Inside Alloy: live Go heap 105 Mi (133 in use), Go runtime total 430 Mi, RSS 451 Mi. The
gap is the runtime keeping freed memory: the `large` preset's 2 Gi limit sets
`GOMEMLIMIT` to 1,843 Mi, so the collector has no reason to give memory back. The working
set adds the WAL's page cache on top. Beyla's eBPF instrumentation runs in the same
process, so the 105 Mi includes it.

**Series and DPM.**

| Remote write | Active series | Samples/min |
|---|---|---|
| `grafana_cloud_metrics` (the Kubernetes pipeline) | **1,454** | **1,453** |
| `default`, Fleet's `ihub_kubernetes_survey` | 49 | 49 |
| `default`, Fleet's `ihub_kubernetes_survey_k8s_monitoring` | 49 | 49 |

At most ~1,550 active series and ~1,550 DPM (the two survey pipelines may write the same
49 series). DPM equals active series: every job scrapes at 60 s. No failed samples.

Where the 1,453 come from, scraped versus kept by the default allow-lists:

| Source | Scraped/min | Sent/min |
|---|---|---|
| kubelet | 41,064 | 200 |
| cAdvisor | 2,879 | 252 |
| kube-state-metrics | 1,613 | 808 |
| node-exporter | 1,089 | 189 |
| kubelet resources | 139 | 4 |
| **Total** | **46,784** | **1,453** |

The allow-lists keep 3% of what is scraped. Without them the kubelet alone is ~41,000
series: eight times the 5,000 budget, four times the free tier.

**Logs.** None. The Fleet configuration has no `loki.write` component: the spike sent
metrics only, so it says nothing about the `alloy-logs` row in D6.

**Host and container hours.** Not read: they exist only in the backend. Task 10.2.

**What it changes in D6.**

- Series: the budget holds. One node on Grafana's defaults is ~1,500. Three nodes at M7
  stay under 5,000 if the per-node part (node-exporter, kubelet, cAdvisor, ~640 here) is
  what grows. No change.
- Memory: the 384 Mi limit for `alloy-metrics` stands. The spike's 537 Mi is a 2 Gi limit
  used lazily, not a working set: the live heap is 105 Mi, with Beyla in it. A 384 Mi
  limit puts `GOMEMLIMIT` near 345 Mi and the collector collects sooner. Task 10.1 checks
  it under the real limit.
- Logs: unmeasured. The `alloy-logs` row stays an estimate until 10.1.

### Removed (task 2.5), 2026-10-13

`helm uninstall grafana-cloud -n monitoring`. That one release is enough: the
`alloy-daemon` release is rendered by the Alloy Operator from an `Alloy` resource that
`grafana-cloud` owns, and the resource's finalizer uninstalls it. Uninstalling
`grafana-cloud-alloy-daemon` directly does not stick: the operator recreates it at once.

| | Baseline | After removal |
|---|---|---|
| Node `k3s-server-1` | 1,988 Mi | 2,234 Mi (37%) |
| All pods | 648 Mi | 644 Mi |

The pods are back to the baseline. The node is ~250 Mi above it, outside any pod: page
cache, most likely from Alloy's WAL, which sits in a hostPath (`/var/lib/alloy`) the
uninstall does not clean. It is the node's disk and goes with the next rebuild. `make top`
again before 10.1 compares against it. `check-diagram` green.

Left: the empty `monitoring` namespace and the `alloys.collectors.grafana.com` CRD (Helm
never deletes CRDs). The namespace does not collide: the GitOps install uses
`observability`. The CRD might: if the chart ships it as a template rather than under
`crds/`, an existing CRD not owned by the release is refused. Both deleted by hand the
same day (`kubectl delete`), and the operator revoked the Fleet Management token. Nothing
of the spike is left in the cluster.
