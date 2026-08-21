# Design

## Context

| Constraint | Detail |
|---|---|
| Node | `k3s-server-1`, 192.168.0.30, 2 vCPU, ~5.8 GiB allocatable, rebuilt in ~105s |
| Bundled | traefik (LoadBalancer on 192.168.0.30:80/443), local-path, coredns, metrics-server, **helm-controller** |
| Ingress | Cloudflare tunnel, outbound only, **remotely managed** — ingress rules live in the dashboard, not on the host |
| Repository | `salgadobreno/homelab-infra`, public: anonymous clone returns 200 |
| Live workload | nginx + hit-counter + redis on Compose, serving today, untouched |
| Content | `../plain_site/`, 7 HTML files, 132 KiB total, no external assets |

## Goals

- A public URL serving the site from the cluster, alongside the existing one.
- A `git push` changes what is served, with no command run against the cluster.
- A rebuild restores all of it unattended, so the node stays disposable.

## Non-Goals

- Cutting the existing hostname over. Deliberately a separate decision — see D6.
- The hit counter and Redis. They need a registry and a persistence story; both are
  their own slice, and neither is needed to prove the reconcile loop.
- TLS inside the cluster. The tunnel terminates TLS at Cloudflare's edge and dials the
  origin over the LAN; adding cert-manager here would secure a hop that never leaves the
  house.
- An `ApplicationSet` or app-of-apps hierarchy. One Application is enough to demonstrate
  reconciliation, and a hierarchy with one leaf teaches nothing.

## Decisions

### D1: ArgoCD is installed by cloud-init as a k3s `HelmChart`, not by a Terraform provider

k3s watches `/var/lib/rancher/k3s/server/manifests/` and applies what it finds, and its
own helm-controller turns a `HelmChart` resource into an installed chart. This is not a
homelab trick — it is how k3s installs traefik on this very node:

```yaml
apiVersion: helm.cattle.io/v1
kind: HelmChart
metadata: {name: traefik, namespace: kube-system}
```

Writing an ArgoCD `HelmChart` into that directory from cloud-init means the reconciler is
part of node bootstrap. A rebuilt node arrives with ArgoCD already running, which is what
the `gitops` spec requires, and it is true by construction rather than by a step someone
has to remember.

*Alternative rejected — the `helm` or `kubernetes` Terraform providers.* Both must be
configured with a kubeconfig that does not exist until the VM those providers depend on
has been created. Terraform evaluates provider configuration before it knows resource
outputs, so this is the classic two-stage apply problem: it works on the second run and
fails on a fresh one. Solving it means `terraform_data` shims or splitting into two root
modules — real complexity, to reach a worse place than a file k3s already watches.

*Alternative rejected — `kubectl apply` once, by hand.* The reconciler becomes the one
thing in the cluster that is not reproducible, and the node stops being disposable at
exactly the layer that is supposed to make it disposable.

*Cost accepted:* installing the reconciler is coupled to node bootstrap, so changing
ArgoCD's own configuration means a rebuild rather than a push. That is the right way
round — the thing that applies changes should not be changed by the thing it applies.

### D2: The ArgoCD install is trimmed to what a single node can hold

The default chart runs seven components. This node has ~5.8 GiB and already carries the
control plane. Dropping `dex` (external identity, when there is one operator),
`notifications` (no Slack to notify), and `applicationset` (see Non-Goals) leaves the
controller, repo-server, redis and the API server.

The API server and its UI stay. This project's second goal is being able to explain the
stack in an interview, and "I have used the ArgoCD UI" is worth more than the ~100 MiB it
costs.

### D3: Site content ships as a kustomize `configMapGenerator`

The content is 132 KiB of HTML with no local assets — comfortably under the 1 MiB
ConfigMap limit, and nothing to bundle alongside it. (The pages do pull
`cdn.tailwindcss.com` at render time, which is the browser's problem, not the
ConfigMap's.) Kustomize is built into ArgoCD, and
`configMapGenerator` appends a hash of the content to the ConfigMap name, so editing an
HTML file produces a new ConfigMap name, which changes the Deployment's pod spec, which
rolls the pods.

That is the mechanism by which `git push` becomes a deployment, and it is visible: the
ConfigMap name changes. A hand-written ConfigMap would update in place and leave the old
content served until something restarted the pods — the demonstration would appear to
work, then intermittently not.

*Alternative rejected — a PVC, or a bind mount from the hypervisor.* Both put the content
somewhere `tofu destroy` does not reach, which is the definition of a pet.

*Boundary recorded:* this approach stops working when the site grows binary assets or
passes ~1 MiB. That is the signal to build an image and need a registry — the same
requirement the hit counter already has, which is why they belong in one later slice.

### D4: No repository credential

The repository is public, so ArgoCD reads it anonymously. This is worth stating rather
than leaving implicit: it is the reason this change adds no secret, immediately after a
milestone spent removing them. When a private repository arrives, so does a deploy key,
and that is a credential with the same rules as the others.

### D5: The tunnel hostname is an operator action, and that seam is named

The tunnel is token-based, so its ingress rules live in the Cloudflare dashboard. Nothing
in this repository can declare "this hostname routes to traefik on 192.168.0.30". The
operator adds it once.

This is the one link in the chain Git does not describe, and pretending otherwise is
worse than recording it. Converting to a locally-managed tunnel with a `config.yml` on
the host would bring it into version control, and was already deferred once during
`narrow-privileges` for the same reason it is deferred here: it means recreating the
tunnel that is currently serving.

### D6: Both copies run; no cutover in this change

The new hostname points at the cluster. The existing hostname keeps pointing at Compose.

A cutover on the same day as the migration removes the ability to compare the two exactly
when comparison is most useful — the failure mode is discovering a difference with no
working copy left to diff against. The Compose stack also still owns the hit counter,
which the cluster copy does not serve yet, so cutting over now would be a regression in
function as well as in safety.

### D7: `selfHeal` and `prune` are on from the start

The `gitops` spec requires that an out-of-band `kubectl` edit is reverted. That is
`syncPolicy.automated.selfHeal: true`; `prune: true` is its counterpart for deletions.
Both default to off, and turning them on later is the change nobody makes.

## Risks

| Risk | Mitigation |
|---|---|
| ArgoCD does not fit the memory budget | Measure before declaring the milestone done; the trim in D2 is the first lever, and `metrics-server` is already installed to measure with |
| The chart install exceeds helm-controller's job timeout on 2 vCPU | Observable in the `helm-install-argocd` job's logs; the fallback is pinning a chart version and raising the timeout in the `HelmChart` spec |
| ArgoCD reconciles this repo's `k8s/` while `tofu/` also describes cluster state | Nothing in `k8s/` is managed by OpenTofu, and nothing OpenTofu creates is in `k8s/`. The boundary is the directory, and it is worth keeping obvious |
| A rebuild wipes ArgoCD's state | It should — its state is derived from Git. This is the property being demonstrated, not a risk to mitigate |
| The site appears to serve because Compose is answering | The check must assert the *cluster's* copy specifically, by hostname or by querying the Service directly, not just that something answered on port 80 |

## Open Questions

1. What does ArgoCD actually consume on this node once settled, and does the trim in D2
   need to go further?
2. Does k3s's helm-controller install the ArgoCD chart cleanly, given its size and CRDs,
   or does it need a pinned version and a raised timeout?
3. Should the site's `Ingress` match on hostname or on path? Hostname is the honest
   shape for a second public name, but it means the LAN cannot reach it without a `Host`
   header or a hosts entry — which affects how the check in `site-delivery` is written.
