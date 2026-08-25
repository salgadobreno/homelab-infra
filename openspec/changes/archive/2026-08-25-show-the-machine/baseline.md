# Baseline

Recorded 2026-08-22, before anything in this change was built. Task 1.1 and 1.2.

The point of this file is that "generated" can be checked later against a known input:
the raw cluster output below is what the page must be derivable from, and the page below
is what it replaced.

## 1.2 · The suite is green first

`make check` — all green: token scope (five refusals, two permissions retained), the
snippet account, administrative SSH, the tunnel, the origin, traefik serving
`k8s.buzaga.com.br`, the cluster's marker present, the hypervisor serving nothing, ArgoCD
`Synced`/`Healthy`, no drift.

`make check-public` — all three hostnames serve the cluster's copy over HTTPS.

Nothing added by this change is being built on top of an existing failure.

## 1.1a · What the site says today

`k8s/site/content/index.html`, ~2.7 KB, the only file in `content/`. It says, in full:
who the operator is, that the site is served from the homelab, an email address, and a
visitor counter.

It describes the system in exactly one place — `<!-- served-by: k3s -->`, an HTML comment
no visitor sees, which exists for `make check-site` rather than for a reader. **A visitor
today learns nothing about what is serving them.** That is the gap this change closes.

### The page still calls a service that no longer exists

Found while recording this, not previously known:

```js
fetch("/api/hits")
  .then(...)          // sets Visitors / Returning
  .catch(() => {      // blanks both counters
```

`/api/hits` was the Compose stack's hit counter. It was destroyed at M4 with `down -v`.
Today `https://buzaga.com.br/api/hits` returns **404**, the `catch` fires, and the counter
spans are set to the empty string. The page degrades silently and looks fine.

So the markup still contains `Visitors: … · Returning: …` labels for a service that has
not existed since M4, and nothing detects it. This is the same disease as `diagram.ascii`
— the page describing a system that is not there — surviving in a form nobody thought to
look at, because it fails invisibly rather than loudly.

It is in scope for this change: a page whose subject is what actually runs cannot ship
with a dead call to a retired service in it. Handled at task 5.1.

### `diagram.ascii` is already gone

Task 5.4 says to delete it. It was removed at commit `6bfba43` ("Serve only index.html
from the cluster; the CVs were personal"), so the deletion has already happened. The
requirement it maps to — *a hand-written description cannot be served* — is satisfied by
the file's absence, but the requirement is about the boundary, not the file: the task
becomes *confirm nothing hand-written describes the system*, and the dead counter above is
the reason that is not a formality.

## 1.1b · The raw input the page will be made from

Captured with `KUBECONFIG=$(CURDIR)/kubeconfig`. Verbatim, unsorted, as `kubectl` returned
it — the un-normalised form D3 has to reduce.

```
$ kubectl get nodes -o wide
NAME           STATUS   ROLES           AGE    VERSION        INTERNAL-IP    EXTERNAL-IP   OS-IMAGE             KERNEL-VERSION              CONTAINER-RUNTIME
k3s-server-1   Ready    control-plane   107m   v1.36.3+k3s1   192.168.0.30   <none>        Ubuntu 24.04.4 LTS   6.8.0-137-generic (amd64)   containerd://2.3.2-k3s2

$ kubectl get node -o jsonpath=...
k3s-server-1  v1.36.3+k3s1  4  6067388Ki  Ubuntu 24.04.4 LTS  containerd://2.3.2-k3s2

$ kubectl get deploy,sts,ds -A
argocd        argocd-applicationset-controller   0/0    106m
argocd        argocd-redis                       1/1    106m
argocd        argocd-repo-server                 1/1    106m
argocd        argocd-server                      1/1    106m
kube-system   coredns                            1/1    107m
kube-system   local-path-provisioner             1/1    107m
kube-system   metrics-server                     1/1    107m
kube-system   traefik                            1/1    107m
web           site                               1/1    106m
argocd        sts/argocd-application-controller  1/1    106m
kube-system   ds/svclb-traefik-df1a854e          1/1    107m

$ kubectl get application -n argocd
site   Synced   Healthy   48f7281   https://github.com/salgadobreno/homelab-infra   k8s/site

$ kubectl get ingress -A
web   site   buzaga.com.br,www.buzaga.com.br,k8s.buzaga.com.br
```

Images, desired replicas:

```
web           site                              1  nginxinc/nginx-unprivileged:1.31.4-alpine
kube-system   traefik                           1  rancher/mirrored-library-traefik:3.7.8
kube-system   coredns                           1  rancher/mirrored-coredns-coredns:1.14.6
kube-system   metrics-server                    1  rancher/mirrored-metrics-server:v0.9.0
kube-system   local-path-provisioner            1  rancher/local-path-provisioner:v0.0.36
argocd        argocd-server                     1  quay.io/argoproj/argocd:v3.5.1
argocd        argocd-repo-server                1  quay.io/argoproj/argocd:v3.5.1
argocd        argocd-redis                      1  ecr-public.aws.com/docker/library/redis:8.6.4-alpine
argocd        argocd-applicationset-controller  0  quay.io/argoproj/argocd:v3.5.1
```

## What this input tells the design

**Non-determinism is confined to four fields**, which is better than D3 assumed:

| Field | Behaviour | D3 treatment |
|---|---|---|
| `AGE` (`107m`, `106m`) | changes every run | drop entirely |
| `READY` (`1/1`) | flaps during a restart | report desired, not current |
| Row order | not guaranteed | sort explicitly |
| `svclb-traefik-df1a854e` | hash regenerated per rebuild | exclude, or strip the suffix |

Everything else — node name, `Ready`, kubelet version, capacity, workload names, desired
counts, image tags, sync status, hostnames — is stable across runs and across a rebuild.
**Rung 1 of the eval ladder is reachable**, so the drift check can be a byte diff rather
than a set of property assertions.

`svclb-traefik-df1a854e` deserves a note: the hash is derived from the Service, so it
survives a pod restart but not a rebuild. Task 6.2 expects `make check` to stay green
across `make rebuild` without regeneration — that holds only if this DaemonSet is excluded
or its suffix stripped. It is the single value that would turn 6.2 red for a reason that
has nothing to do with the property being tested.

**Disclosure**: the raw output contains `192.168.0.30`, an absolute-path-shaped
`containerd://…`, and `ecr-public.aws.com`. All three are inside the input and outside the
boundary in D4. The check greps the generated fragment, not this file.

## Open Question 1, answered by observation

The generator reads with `$(CURDIR)/kubeconfig` — the same file every other target uses,
mode 600, fetched by `make kubeconfig`, gitignored, and pointing at `192.168.0.30:6443`
with the CA verified. `make diagram` therefore works only from this host, which is correct
for a single-operator project and consistent with every other check in the Makefile.

Worth stating explicitly because it is a rung on the disclosure argument: the generator
holds cluster-admin. It is the operator's own credential, running on the operator's own
machine, writing a file the operator reads before committing. Nothing new is granted, and
that is the whole reason D1 is worth its constraints — the runtime version needed a
credential *inside* the cluster that nobody would ever read the output of.
