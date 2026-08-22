# Design

## Context

| Constraint | Detail |
|---|---|
| Serving | `buzaga.com.br`, `www.`, `k8s.` → traefik → the `site` Deployment; the hypervisor serves nothing |
| The pod today | one stock `nginx-unprivileged` container, content from a kustomize-generated ConfigMap |
| Available data | `k3s-server-1 Ready v1.36.3+k3s1 4 vCPU 6067388Ki`; `site Synced Healthy rev 842e3c6` |
| Registry | none, deliberately — M4 unscheduled it, and nothing here may reintroduce it |
| Disclosure | operator decision 2026-08-22: shapes, not addresses |
| The audience | someone who will not read this repository |

## Goals

- A visitor sees the machine that served them, current within a minute.
- The description cannot disagree with reality, by construction rather than by discipline.
- No image is built.

## Non-Goals

- A dashboard, metrics, or history. That is M7.
- Owning the page. This is a fragment that will later sit inside a `projects` section.
- Showing everything the cluster knows. See D3.

## Decisions

### D1: A sidecar running a stock `kubectl` image, not a service to be written

The obvious way to render live state is a small program that queries the API and emits
HTML. That means source, a build, an image, and somewhere to host it — the registry M4
deliberately did not schedule, reintroduced for a status panel.

Instead: a second container in the existing pod, running `rancher/kubectl` pinned, looping
`kubectl get ... -o custom-columns` into a file on a volume shared with nginx. nginx
already serves that directory. There is nothing to build.

*Alternative rejected — a CronJob writing a ConfigMap.* It works, and it puts a resource
ArgoCD does not manage next to resources it does, inside the same Application. `selfHeal`
and `prune` then have opinions about a file the cluster writes to itself. Keeping the
generated artefact out of the API entirely avoids the argument.

*Alternative rejected — client-side JavaScript against the API.* It would need the
cluster's API exposed publicly, which is the opposite of every decision made so far.

*Cost accepted:* rendering in shell is unpleasant beyond a certain complexity. That
unpleasantness is the signal to build a real service, and by then there will be a reason
for a registry.

### D2: `emptyDir`, not a PVC

The rendered file is derived data with a lifetime of one refresh interval. A PVC would
give it durability it does not want, on a storage class whose contents do not survive
`tofu destroy` anyway.

An `emptyDir` is shared between containers in a pod, which is exactly the scope needed:
the renderer writes, nginx reads, and both die together.

### D3: The disclosure boundary is an allow-list, enforced by a check

Operator decision: **shapes, not addresses.**

| Published | Withheld |
|---|---|
| node name, Ready state, kubelet version | node IP, MAC, hostname of the hypervisor |
| CPU and memory capacity | storage class, paths, volume names |
| workload names and ready counts | pod IPs, cluster IPs, namespace list beyond those rendered |
| ArgoCD sync status and revision | repository credentials of any kind |
| image names and tags | service account names, user names, token IDs |

A deny-list would be wrong here: it enumerates what is known to be sensitive today, and
the page renders whatever the cluster returns tomorrow. The check greps the rendered
output for the *shapes* of forbidden values — anything matching an IPv4 address, an
absolute path, or the known account names — and fails on a match.

That check is the requirement. "Be careful what you print" is not enforceable.

### D4: Staleness is rendered, not merely logged

nginx serves whatever file exists. If the renderer dies, the page keeps showing its last
output indefinitely, looking correct.

So the renderer writes a timestamp with every refresh, and the page shows the age. Beyond
the refresh interval the page says the description is stale rather than presenting old
data as current.

This is the same failure the M2 checks had three times over: something that looks right
and is testing nothing. Here it would be something that looks current and is describing a
cluster that no longer exists.

### D5: Both halves, with the old one static

What runs now is generated. What it replaced is not — the Compose stack is gone and
cannot be queried, so its description is content, written once, in the repository.

That asymmetry is honest and worth showing: the "before" is a story, the "after" is a
reading. They are labelled differently on the page for that reason.

## Risks

| Risk | Mitigation |
|---|---|
| RBAC too broad, and a public page becomes a way to read Secrets | The negative test is a spec requirement: the identity is used to attempt a Secret read and must be refused |
| A forbidden value reaches the page as the cluster grows | The check greps shapes, not known values, and runs in `make check` |
| The renderer fails and nobody notices | D4 renders staleness; the check asserts freshness |
| Shell rendering grows into a program in disguise | Named in D1 as the signal to stop and build a service properly |
| The sidecar's failure takes the site down | The renderer writes to a volume; nginx serves regardless. A dead renderer costs the panel, not the page |

## Open Questions

1. Does the pod need a `securityContext` change for the sidecar, given the site container
   runs read-only with all capabilities dropped and the sidecar must write to the shared
   volume?
2. What refresh interval is honest — often enough that "live" is not a lie, rarely enough
   that the API server is not being polled for a page nobody is reading?
3. Should the page show the request's own path — which node, which pod served it? It is
   the most striking part of the idea and the most likely to need a header that traefik
   does not set by default.
