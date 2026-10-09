# Tasks

The baseline is measured before anything is added, and the secret path is proven before
the agent depends on it, so the cost of this rung is a number and not an impression.

## 1. The ladder

- [x] 1.1 Reorder the milestone ladder in `openspec/config.yaml`: M6 = `see-the-cluster` ("I can see what the cluster is doing."), M7 = three nodes. Add a line to the numbering history: pulled forward 2026-10-08, operator decision, so multi-node is sized from measurements
- [x] 1.2 Update `CLAUDE.md` "M6 is next" and anything else that names the old order

## 2. Baseline

- [x] 2.1 Add `make top` (node and pod memory/CPU from the cluster) if no target already gives it, and record the node's used memory and the per-pod figures before anything is added. A first reading is in design D6 (1,969 MiB, 2026-10-08); re-measure on the day work starts
- [x] 2.2 Confirm `make check` is green, so a later failure is attributable to this change. **Green except `check-tunnel-ssh`, red on purpose** (Access off by operator decision 2026-10-08, restoring it is backlog). Use `make -k check` until then. See `baseline.md`

- [ ] 2.3 Spike, operator decision 2026-10-08: Grafana Cloud's own Kubernetes onboarding (`helm`, k8s-monitoring 4.5.3 + Fleet Management, ns `monitoring`) runs for a day as a measurement, not as the deliverable. What it installed is recorded in `baseline.md`
- [ ] 2.4 After a day: read the spike's active series, DPM, and host/container hours from the `grafanacloud-usage` data source, and Alloy's memory from `make top`; record them in `baseline.md` and revise the budgets in design D6 if the numbers say so
- [ ] 2.5 Remove the spike: `helm uninstall grafana-cloud-alloy-daemon` and `grafana-cloud` in `monitoring`, then the namespace; confirm `make top` is back near the baseline and `check-diagram` green. Revoke the Fleet Management token in Grafana Cloud if it is not reused. Must be done before 9.1, or the GitOps install collides with it

## 3. Backend and credentials (operator steps)

- [x] 3.1 Create the Grafana Cloud stack. Confirm the free-tier table in design D1 against the stack's own usage page, and correct D1 where it differs
- [ ] 3.2 Create an access policy with `metrics:write` and `logs:write` only, and a token on it for the agent. Create a second policy with `metrics:read` only for the check; store its token in `.grafana-read-token`, mode 600, and add that file to `.gitignore`
- [ ] 3.3 Write `scripts/create-exporter-user.sh` on the pattern of `create-terraform-user.sh`: a dedicated Proxmox user with `PVEAuditor` on `/` and a privilege-separated token; output goes to `tofu/observability.auto.tfvars`, mode 600. Runs against the API, not as root: the operator runs it with a bootstrap admin token (`make exporter-user` prints how), then deletes that token. **Script written 2026-10-08; not yet run**
- [ ] 3.4 Confirm both files are ignored with `git check-ignore`, not by reading `.gitignore`

## 4. Credentials are scoped, and the check says so

- [ ] 4.1 Extend `make check-privileges`: the exporter token is refused a write (start a VM, or modify a user), and the refusal is recorded — `credential-scoping` "The exporter cannot change the hypervisor"
- [ ] 4.2 Show the agent token is refused a query against stored metrics — `credential-scoping` "The agent credential cannot read back or administer"
- [ ] 4.3 Extend `make check-secrets` to fail if either token value appears in a tracked file, and confirm it fails on a fixture — `credential-scoping` "Neither credential is tracked by Git"

## 5. Secrets through cloud-init (design D5)

- [ ] 5.1 Declare the sensitive variables in `tofu/variables.tf` (Grafana Cloud endpoints, user IDs, agent token; exporter token ID and secret)
- [ ] 5.2 Add `tofu/cloud-init/observability-secrets.yaml.tftpl`: the `observability` Namespace and two Secrets, written to the k3s manifests directory as root-only `0600`
- [ ] 5.3 `make plan` and read it: the snippet changes, the VM is replaced, and no secret value is printed in the plan output

## 6. App of apps (design D4)

- [ ] 6.1 Create `k8s/apps/site.yaml`: the `site` Application, unchanged in name, path and sync policy, with the resources finalizer
- [ ] 6.2 Replace `tofu/cloud-init/argocd-app-site.yaml.tftpl` with `argocd-app-root.yaml.tftpl`: Application `root`, path `k8s/apps`, `selfHeal` and `prune` kept. Update `main.tf` and the comment that explains why this one object lives outside `k8s/`
- [ ] 6.3 Update the `gitops` wording in `CLAUDE.md` and `config.yaml` ("the single exception is the bootstrap Application") to name `root`

## 7. The agent (design D2, D6)

- [ ] 7.1 `k8s/observability/values.yaml` for `grafana/k8s-monitoring`, chart pinned at 4.5.2 (design D2): `clusterMetrics`, `hostMetrics`, `podLogsViaLoki`; `kube-state-metrics` and `node-exporter` deployed; collectors `alloy-metrics` (singleton) and `alloy-logs` (DaemonSet), no OTLP receiver. Destinations read the Secrets from 5.2. Requests and limits per the table in design D6, summing to at most 1 GiB
- [ ] 7.2 Series budget in the same file, written next to the settings that hold it (design D6): 60 s scrape interval, default allow-lists on, Linux-node integration allow-list for host metrics, explicit include lists for ArgoCD and pve-exporter
- [ ] 7.3 `k8s/observability/pve-exporter.yaml`: Deployment and Service for `prometheus-pve-exporter`, pinned image, token from the Secret, scrape target the hypervisor's API; scraped by the agent
- [ ] 7.4 `k8s/apps/observability.yaml`: multi-source Application (chart from Grafana's repo, values from this repo), plus the exporter manifests

## 8. The check (design D7)

- [ ] 8.1 Add `make check-observability`: query the hosted Prometheus API with the read token, fail when any node's newest sample is older than 5 minutes, name the node, and say whether the backend itself was unreachable
- [ ] 8.2 Wire it into `make check` after `check-site`

## 9. Land it through a rebuild

- [ ] 9.1 Commit and push 5-8 together. Confirm the running cluster did not change (its bootstrap still points at `k8s/site`)
- [ ] 9.2 `make rebuild CONFIRM=yes`, then `make verify-rebuild`. **Operator-run: needs an ssh-agent and a TTY.** Confirm `root`, `site` and `observability` are Synced/Healthy and nothing was registered by hand — `gitops` "A rebuilt cluster arrives with every workload"
- [ ] 9.3 Confirm the site is served on every hostname: `make check-public`
- [ ] 9.4 In Grafana: node, pods, ArgoCD, hypervisor and VM stats, site logs — `observability` "The operator sees the cluster without a command", "Hypervisor state is visible"
- [ ] 9.5 `make check` still asserts the hypervisor serves no HTTP — `observability` "The hypervisor still serves nothing"
- [ ] 9.6 `make diagram`, read the new rows on the page, `make check-disclosure`; commit the page

## 10. Prove the budgets and the checks

- [ ] 10.1 `make top` again; record each component's real memory against its row in the design D6 table, and the node total against the ~2.4-2.6 GiB expected
- [ ] 10.2 Read active series and DPM (`grafanacloud_instance_samples_per_second × 60`) from the `grafanacloud-usage` data source; record both against the 5,000 budget. DPM above active series means a scrape interval under 60 s somewhere. Also read host and container hours, and note whether the hypervisor counts as a host (design D1) — `observability` "The series count is within budget"
- [ ] 10.3 Scale the agent to zero, wait past 5 minutes, watch `check-observability` fail and name the node; ArgoCD selfHeal will race this, so suspend the Application's auto-sync for the test and restore it after — `observability` "Silence fails the check"

## 11. The demo

- [ ] 11.1 `make rebuild CONFIRM=yes` a second time with telemetry already flowing. In Grafana: history before, the gap, the node returning. Screenshot it — `observability` "A rebuild is a gap, not an erasure"
- [ ] 11.2 `make check-observability` green after the rebuild with no other command run — `observability` "A rebuilt cluster passes without intervention"

## 12. Close the record

- [ ] 12.1 Update `README.md`, `CLAUDE.md` (current state, the new Known shortcut from D5) and `openspec/config.yaml` (current state)
- [ ] 12.2 Put `LEARNINGS/` candidates to the operator; record only the ones claimed
