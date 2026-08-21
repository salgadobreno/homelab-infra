## Why

The cluster has been provisioned, torn down and rebuilt a dozen times, and has never run
anything. Everything demonstrable so far is infrastructure describing itself. Meanwhile
the site that actually serves the internet is a Docker Compose stack on the hypervisor,
untouched since before M0 — the thing this project exists to replace is the one
thing it has not touched.

This is also the first change where GitOps appears. Until now "declared in Git" has meant
OpenTofu; from here it means a reconciler running inside the cluster, which is the half
of the stack the operator cannot yet speak to from experience.

## What Changes

- **ArgoCD runs in the cluster**, installed declaratively from `tofu/` so a rebuild
  restores it without manual steps, and reconciles from this repository.
- **The static site is declared as Kubernetes manifests in this repo** — Deployment,
  Service, Ingress, and the site content itself — and deployed by ArgoCD rather than by
  `kubectl apply`. A `git push` is the deployment mechanism.
- **The Cloudflare tunnel gains a second public hostname** pointing at traefik on the
  node, so the cluster-served copy is reachable from the internet alongside the existing
  one rather than instead of it.
- **`make` gains targets** for ArgoCD access and for asserting the site serves — from
  the cluster, and through the tunnel.

Explicitly **not** in this change, and each deferred for a reason recorded in design:

- The hit counter and Redis stay on Compose. They need an image registry and a
  persistence story respectively; both are their own slice.
- The existing public hostname keeps pointing at Compose. Cutting it over is a decision
  to make once the cluster-served copy has been observed working, not the same day.
- No TLS termination in the cluster. The tunnel terminates TLS at Cloudflare's edge, so
  traefik serves plain HTTP over the LAN.

## Capabilities

### New Capabilities

- `infrastructure/gitops`: what it means for cluster state to be reconciled from Git —
  that a reconciler runs in-cluster, survives a rebuild, and that manual changes are
  corrected rather than preserved.
- `infrastructure/site-delivery`: the static site is served by the cluster and reachable
  publicly, and a change committed to this repository reaches it without an operator
  running a deployment command.

### Modified Capabilities

None. `vm-provisioning`, `k3s-cluster` and `credential-scoping` keep their requirements:
this change adds workloads on top of the node rather than altering how the node is built
or how credentials are scoped.

## Impact

- **`tofu/`** gains ArgoCD as a managed resource. This is the first thing OpenTofu
  installs *inside* the cluster rather than provisioning around it, and the first use of
  a second provider.
- **A new `k8s/` directory** holds manifests that ArgoCD reads. It is deployed by being
  committed, so its correctness is no longer proven by `tofu plan`.
- **The Cloudflare dashboard** — the tunnel is remotely managed, so the hostname is an
  operator action rather than something this repo can declare. Recorded as the seam it
  is, since it is the one step in the chain that Git does not describe.
- **`make check`** gains an assertion that the site actually serves, which is the first
  check in this repo that tests a workload rather than infrastructure.
- **Memory**: ArgoCD is the largest thing yet placed on a 6 GiB node. Its footprint, and
  what to trim, is the first design question.
