## Why

Everything this project has built is legible only by reading the repository. The public
site is a CV that happens to be served by a Kubernetes cluster, and nothing about it says
so.

This is the rung that shows the work to someone who will not read the repo — an
interviewer, a visitor, the operator's future self. It is also the first thing built here
whose audience is not the operator.

There is a hand-drawn diagram already in this repository showing `microk8s`, `ansible` and
a host called `buserver`. None of them exist. It was accurate once, which is the whole
argument: a picture that can disagree with reality eventually will, and a self-describing
site that lies is worse than one that says nothing.

## What Changes

- **The site renders what is actually running**, read from the Kubernetes API at request
  time rather than written into the repository. Nodes, workloads, and what ArgoCD last
  synced from which revision.
- **A read-only ServiceAccount** with a Role granting exactly the reads the page makes —
  M2's argument applied inside the cluster.
- **A sidecar renders it**, running a stock `kubectl` image, writing into a volume the
  existing nginx already serves. No image is built and no registry is introduced.
- **The page shows both halves** — what runs now, and the Compose-on-the-hypervisor
  arrangement it replaced. The delta is the point; the current state alone does not say
  what was learned.
- **A disclosure policy is written down and enforced by a check**: shapes, versions and
  counts are public; addresses, storage paths and account names are not.
- **`k8s/site/content/diagram.ascii` is deleted**, because it is the thing this rung
  exists to make impossible.

Explicitly **not** in this change:

- A dashboard. Text and ASCII, no chrome, no JavaScript framework, no metrics UI. That is
  M7 and it is a different job.
- Historical data. The page says what is true now. Anything about *change over time* is
  observability.
- Owning the whole page. This content later becomes a section of the operator's personal
  site, so it is built as a fragment that could be embedded.

## Capabilities

### New Capabilities

- `infrastructure/self-description`: the public site renders its own infrastructure from
  live cluster state, within a stated disclosure boundary, and cannot show a picture that
  disagrees with what is running.

### Modified Capabilities

None. `site-delivery` already requires the cluster to serve the site; this adds what the
site says, not how it is delivered.

## Impact

- **A new workload in the site's pod.** The first thing here that reads the Kubernetes API
  at runtime, and therefore the first that needs an identity inside the cluster.
- **RBAC.** A ServiceAccount, Role and RoleBinding — currently the cluster has none of the
  project's own making. Getting this wrong is how a public page becomes a way to read
  Secrets.
- **The public site's content.** Every previous change moved where the site was served
  from. This is the first that changes what a visitor sees.
- **`k8s/site/`** grows from four manifests to roughly seven, which is the point at which
  its structure stops being self-evident.
- **A new failure mode**: the renderer can fail while nginx keeps serving. A stale or
  empty panel that still looks like a page is exactly the kind of quiet wrongness the
  three broken checks in M2 were.
