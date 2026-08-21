# ArgoCD basics

`[101]` · written to be read cold, no project knowledge assumed

## The problem it solves

You have a Kubernetes cluster and some YAML describing what should run on it. The
straightforward way to connect the two is to run `kubectl apply` yourself.

That works, and it has three problems that grow with time.

**Nobody knows what is actually deployed.** The YAML in the repository is what someone
*intended*. What is running is whatever was last applied, by whoever last applied it,
possibly from a laptop, possibly a version that was never committed.

**Changes need a person with credentials.** Whoever deploys needs write access to the
cluster. That is a credential, on a laptop, that can do anything.

**Drift is invisible.** Someone edits a Deployment directly to debug an incident and
forgets to undo it. Nothing detects the difference. The repository quietly stops
describing reality, and you find out during the next deploy.

## The idea: pull, not push

Instead of a person pushing changes into the cluster, a program **inside** the cluster
pulls them.

It watches a Git repository, compares what is described there against what is actually
running, and corrects the difference. Continuously — not once at deploy time.

That inversion is what "GitOps" means, and the consequences fall out of it:

- **Git is the record of what is deployed**, not of what was intended. If it is in the
  main branch, it is running, or the reconciler is telling you why it is not.
- **Deploying is committing.** No cluster credentials needed for the person deploying.
- **Drift is corrected**, or at minimum reported. A hand-edit gets reverted.
- **Rollback is `git revert`.** The previous state is a previous commit.

ArgoCD is one implementation of this. Flux is the other common one.

## The one object you write

An **Application** tells ArgoCD "keep this bit of Git in that bit of the cluster":

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-site
  namespace: argocd
spec:
  source:
    repoURL: https://github.com/someone/their-repo
    path: k8s/site          # the directory holding the manifests
    targetRevision: main    # branch, tag, or commit
  destination:
    server: https://kubernetes.default.svc
    namespace: web          # where to put them
  syncPolicy:
    automated:
      selfHeal: true        # revert manual changes
      prune: true           # delete what was removed from Git
```

The Application itself is a Kubernetes resource, so ArgoCD's own configuration is
Kubernetes objects. There is no separate database.

## Sync and health, the two words the UI uses

ArgoCD reports every Application against two independent axes, and confusing them is the
usual beginner mistake:

| | Question it answers |
|---|---|
| **Sync status** | Does the cluster match Git? `Synced` / `OutOfSync` |
| **Health status** | Is the running thing actually working? `Healthy` / `Progressing` / `Degraded` |

They are genuinely independent. `Synced` + `Degraded` means Git was applied faithfully
and the result is broken — the manifests are the problem. `OutOfSync` + `Healthy` means
something is running fine but is not what Git says it should be.

## Automated sync is off by default, and so are its two useful halves

Out of the box ArgoCD *detects* differences and waits for you to press Sync.
`syncPolicy.automated` makes it act. Two flags sit under it, both off unless set:

- **`selfHeal`** — revert changes made directly against the cluster. Without it, a manual
  `kubectl edit` survives, and ArgoCD shows `OutOfSync` indefinitely.
- **`prune`** — delete resources removed from Git. Without it, deleting a file leaves the
  resource running forever.

Neither is on by default because both delete things, and both are what make the
repository authoritative rather than advisory.

## What is actually running

Four components, and it helps to know why each exists:

| Component | Job |
|---|---|
| **repo-server** | Clones Git, runs Helm or kustomize, produces plain YAML |
| **application-controller** | Compares desired against live, applies the difference |
| **server** | The API and web UI |
| **redis** | A shared cache between the other three |

The Redis surprises people, because a cache looks like a database. It is not: persistence
is switched off, there is no volume, and everything in it has an expiry. Rendering
manifests and walking the cluster are expensive, and three separate processes need the
same answers, so the results are memoised somewhere all three can reach.

Losing it costs a cold cache and a slower first reconcile. There is nothing in it to back
up.

## What it does not do

- **It does not build images.** ArgoCD deploys manifests. Something else builds and
  pushes the image; ArgoCD notices the tag changed in Git.
- **It does not template for you** — but it runs the templating engine. Point it at a
  Helm chart or a kustomize directory and it renders them itself.
- **It does not watch your image registry.** A new image tag reaches the cluster when
  something writes that tag into Git.

That last one is the shape of the whole tool: **if it is not in Git, it does not happen.**
