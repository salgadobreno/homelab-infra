# Baseline

Measured 2026-08-21, before anything was added. Each section states what the change is
supposed to move, so "after" has a "before" to be compared against.

## 1. What serves today

The public site is **`buzaga.com.br`** (and `www.`), fronted by Cloudflare and served by
the Compose stack on the hypervisor:

```
$ curl -sI https://buzaga.com.br/
HTTP/2 200
server: cloudflare
cf-ray: a2ec89317ad56d40-GIG
```

```
buzaga-nginx        nginx:latest        static site + /api/ proxy   :30000, :443
buzaga-hit-counter  buzaga-hit-counter  locally built, no registry
buzaga-redis        redis:7-alpine      named volume, persistent
```

The hit counter works and holds real state, which is the reason it is not in this slice:

```
$ curl -s http://127.0.0.1:30000/api/hits
{"state":"first","total":65,"returning":6}
```

**Target:** this hostname is still serving this stack, unchanged, when the change is done.

### The public copy is not byte-identical to the origin

Worth recording before a check is written against it. The public response is 2878 bytes;
the origin's is 2648. The whole difference is Cloudflare rewriting the page at the edge:

```
< <li>breno@buzaga.com.br</li>
> <li><a href="/cdn-cgi/l/email-protection" class="__cf_email__" ...>[email protected]</a></li>
> <script data-cfasync="false" src="/cdn-cgi/scripts/.../email-decode.min.js"></script>
```

Scrape Shield's email obfuscation. **A check that compares a hash of the public response
against the origin will never pass**, and one written by hashing the public response will
break whenever Cloudflare changes its injection. Task 6.1 must assert on something stable
— a status code and a marker string in the page — not on equality.

### One local asset assumption in the design was wrong

`design.md` D3 describes the content as self-contained. There are no *local* assets to
bundle, which is what the ConfigMap approach needs, but the pages do reference
`cdn.tailwindcss.com` at render time. The distinction does not change D3; it does mean
the site is not viewable without egress, which matters if the check is ever pointed at a
rendered result rather than the HTML.

## 2. Memory headroom

The binding constraint, and the reason D2 trims the ArgoCD install.

```
node, allocatable      6067392Ki   (~5.8 GiB)
node, in use            885Mi      (14%) — control plane and bundled addons only
node, free (guest)     2822 MiB free, 4774 MiB available
requests committed      140Mi      (2%)  — almost nothing declares requests

hypervisor             13896 MiB total, 5714 MiB available
```

The node has roughly **4.7 GiB available** with the cluster idle. The hypervisor has
5.7 GiB available while running both the Compose stack and this VM.

Note that committed *requests* are 140 MiB against 885 MiB actually in use: the bundled
addons largely do not declare requests, so the scheduler's view and reality diverge by a
factor of six. Anything this change adds should declare requests, or the same gap grows.

**Target:** ArgoCD settles inside this headroom, measured at task 2.4 rather than assumed.

## 3. Rebuild is known-good

```
$ make rebuild CONFIRM=yes
REBUILD COMPLETE in 98s
```

Unattended, on the scoped credential, with `make check` green afterwards and
`https://buzaga.com.br/` still answering 200 throughout — the cluster and the live site
are genuinely independent today, which is the property this change is about to couple.

A freshly built node, settled:

```
k3s-server-1   1006m CPU (25%)   822Mi (13%)
coredns / local-path-provisioner / metrics-server / traefik / svclb-traefik   Running
helm-install-traefik-crd / helm-install-traefik                               Completed
```

### helm-controller already does what D1 proposes, on this node, every rebuild

The two `helm-install-*` jobs are the mechanism ArgoCD would be installed by. They are
not a hypothetical: k3s runs them on every boot from the manifests directory, and they
complete in well under a minute.

```
helm-install-traefik-crd   started 20:57:41   completed 20:58:11   (30s)
helm-install-traefik       started 20:57:41   completed 20:58:24   (43s)
```

That is a chart of modest size on 2 vCPU. ArgoCD's chart is considerably larger, so this
bounds the question rather than answering it — but it establishes that the path works and
gives a number to compare task 2.3's result against.

### `make kubeconfig` is required after every rebuild, and nothing says so

A rebuilt cluster has a new CA, so the saved kubeconfig fails with
`x509: certificate signed by unknown authority`. `make check` passes regardless, because
nothing in it talks to the Kubernetes API. Once a workload exists, a check that does talk
to the API will hit this — and "the site is down" and "your kubeconfig is stale" must not
look the same. Task 6.1 says the check has to distinguish them; this is why.

## How to re-measure

```bash
make status                                    # host, VMs, state, progress
make check                                     # secrets, privileges, drift
kubectl top node                               # what the cluster is using
curl -sI https://buzaga.com.br/                # the existing public copy
curl -s  http://127.0.0.1:30000/api/hits       # the hit counter's state
```

## Group 2: the reconciler, measured

### Open Question 2 — answered: helm-controller installs the chart cleanly

No pinning workaround needed, no timeout raise needed in practice, on a fresh rebuild:

```
helm-install-argocd   started 21:07:21   completed 21:08:03   (42s)
```

For comparison, the same node's bundled charts: traefik-crd 30s, traefik 43s. ArgoCD's
chart is much larger and installed in the same time, so chart size was not the risk it
looked like. The `timeout: 10m` in the manifest stays — it costs nothing and the default
300s leaves no margin on a node that is also installing traefik at the same moment.

Rebuild time moved from **98s to 106s**. The extra 8s is the manifest being written; the
chart install happens after cloud-init's readiness marker, so it does not block the
rebuild — the node reports Ready while ArgoCD is still coming up, and is fully settled
about a minute later.

### Open Question 1 — answered: ArgoCD costs about 350 MiB at the node level

```
node before   822Mi (13%)
node after   1176Mi (19%)          → ~354Mi

argocd-server              38Mi
argocd-application-controller  23Mi
argocd-repo-server         21Mi
argocd-redis                5Mi
                        ------
                           87Mi   at the pod level, idle
```

The two numbers differ because the node figure includes the container images' page cache
and the kubelet's own accounting; the pod figure is what the workloads are using. Both
are worth having: 87Mi is what ArgoCD does, 354Mi is what installing it cost the node.

Against 4.7 GiB of headroom, no further trimming is needed. **D2's trim is not the
reason it fits** — it is roughly 100 MiB of savings on a node with gigabytes spare. The
honest justification for the trim is that dex, notifications and applicationset are
components with no purpose here, not that the node could not hold them.

### The trim needed a correction the chart's values did not advertise

`applicationSet.enabled: false` does nothing in chart 10.3.3. The component's Deployment
template has no `enabled` guard at all — the value is accepted, ignored, and the
controller runs anyway. Reading the chart's templates rather than assuming the convention
found it before the rebuild rather than after:

```
$ grep -rn 'if .Values.applicationSet' templates/    # no Deployment guard
$ grep -n replicas templates/argocd-applicationset/deployment.yaml
22:  replicas: {{ .Values.applicationSet.replicas }}
```

So it is scaled to zero instead, and the result is visible:

```
argocd-applicationset-controller   0/0
```

`dex.enabled` and `notifications.enabled` are real guards — those two components have no
Deployment at all now.

### Requests are declared, and are deliberately above idle

The chart declares no resource requests for any component. The node now commits:

```
cpu     425m (10%)     memory  716Mi requests / 2090Mi limits
```

against 87Mi of actual idle usage. That gap is intentional — requests should cover a
repo-server cloning and rendering manifests, not an idle controller — but it is a gap,
and it is recorded rather than left for someone to discover as "why is 716Mi reserved for
something using 87".

## Groups 3-4: the reconcile loop, proved

### A cluster from nothing arrives serving the site

```
$ make rebuild CONFIRM=yes
REBUILD COMPLETE in 106s
...
site   Synced   Healthy   bd93fb91c4a8b1ae8834c29f589a08d6e3abbf9c
```

Synced and Healthy about 180s after the node reported Ready, with no operator step. The
Deployment, Service, Ingress and ConfigMap in `web` were created by ArgoCD, not applied.

### The host rule matches, and the absence of it does not

```
curl -H 'Host: k8s.buzaga.com.br' http://192.168.0.30/   ->  200, 2648B
curl                              http://192.168.0.30/   ->  404
```

The second line is the one worth keeping. A catch-all Ingress would have answered both,
and the check would have passed whether or not the tunnel was sending the right name.
The bytes match `k8s/site/content/index.html` exactly.

### A push reaches the cluster with nothing run against it

Committing a marker into `index.html` and pushing, then touching nothing:

```
ConfigMap   site-content-4f6t4khgtb  ->  site-content-fh5m885fch
Pod         site-7f6cfc8d9c-n8p5v    ->  site-9777694f5-74nf9
Revision                                 e270be09a940c1259e2774d070d994b720f47795
served                                   after 230s
```

230s is ArgoCD's default poll interval of 180s plus render and rollout. A webhook would
make it immediate; polling is the right default for a repository nothing else can reach.

The ConfigMap name moving is the mechanism, not a side effect — the Deployment's volume
reference changed with it, which is what rolled the pods. A hand-written ConfigMap would
have updated in place and kept serving the old content.

### selfHeal reverts an out-of-band edit

```
before scale : replicas=1 generation=4
after  scale : replicas=3 generation=5     <- kubectl scale landed
8s later     : replicas=1 generation=6     <- ArgoCD undid it

ScalingReplicaSet  Scaled up   replica set site-9777694f5 from 1 to 3
ScalingReplicaSet  Scaled down replica set site-9777694f5 from 3 to 1
```

The generation moving twice is the evidence. A first attempt at this test read the value
after a `sleep 3` and saw `replicas=1`, which proves nothing — it cannot distinguish "the
edit was reverted" from "the edit never applied". Reading immediately, and checking
`metadata.generation`, distinguishes them.

## Group 6: the check, and what it refuses to conflate

`make check-site`, wired into `make check`:

```
OK: the node answers and the API accepts this kubeconfig
OK: traefik serves k8s.buzaga.com.br (HTTP 200)
OK: it is the cluster's copy (marker present)
OK: ArgoCD reports the app Synced and Healthy
```

Three different failures, three different answers — which is the requirement, not a
nicety, because the baseline found that a rebuilt cluster's new CA looks exactly like an
outage:

```
$ make check-site NODE_IP=192.168.0.99
UNREACHABLE: 192.168.0.99 does not answer — the node is down, not the site

$ make check-site KUBECONFIG_PATH=<stale>
UNREACHABLE: the Kubernetes API rejected us. If the cluster was rebuilt,
             its CA changed — run 'make kubeconfig'.

$ make check-site SITE_HOST=nosuchsite.example
FAIL: nosuchsite.example returned 404 — the cluster is up and the site is not
```

**It asserts a marker, not a hash.** Cloudflare rewrites the page at its edge — 2878
bytes public against 2648 at the origin — so equality can never hold end to end, and
hashing the public response would break whenever that rewriting changed. `served-by: k3s`
survives both, and distinguishes the cluster's copy from the Compose copy, which a status
code alone does not.

**The last assertion is not redundant.** A 200 with the marker proves something is being
served; `Synced/Healthy` proves it is *current*. Without it, an ArgoCD that had stopped
reconciling would look identical to one working perfectly, for as long as the last-served
page kept answering.

### Testing the failure had to route around selfHeal

The obvious way to prove the check fails is to scale the Deployment to zero. That does
not work here: `selfHeal` reverts it within seconds, so the check races the controller
and the result depends on timing. Overriding `SITE_HOST` and `NODE_IP` exercises the same
assertions deterministically.

Worth noticing rather than working around — it is the same property task 4.3 demonstrates,
met from the other direction. Once a cluster self-heals, "break it and see" stops being
a repeatable test.

## Group 7: it comes back from nothing

```
$ make rebuild CONFIRM=yes
REBUILD COMPLETE in 107s
  site serving again 190s after the rebuild began
$ make check-site
OK: the node answers and the API accepts this kubeconfig
OK: traefik serves k8s.buzaga.com.br (HTTP 200)
OK: it is the cluster's copy (marker present)
OK: ArgoCD reports the app Synced and Healthy
```

Destroy to serving, unattended: **190 seconds**. The node reports Ready at ~106s; the
remaining ~85s is the ArgoCD chart installing and its first reconcile, neither of which
blocks the node from being Ready. No content was copied from the hypervisor, and no
command was run against the cluster.

## What remains: group 5, and only group 5

The tunnel is token-based, so its ingress rules are dashboard configuration. Adding
`k8s.buzaga.com.br` as a public hostname pointing at `http://192.168.0.30:80` is the one
step in this chain that Git cannot describe, and it is the operator's.

Everything on this side of that seam is done and asserted by `make check`.
