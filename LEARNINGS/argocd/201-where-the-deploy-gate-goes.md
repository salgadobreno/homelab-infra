# Where the deploy gate goes when CI does not deploy

`[201]` · why a failing test cannot stop a pull-based deploy, and what stops it instead

## The push-based case, where blocking is trivial

```
test ──▶ build ──▶ push image ──▶ kubectl apply
  ✗ stops here; the deploy step never executes
```

CI *performs* the deploy, so refusing to deploy is just not running a step. Nothing reaches
the cluster because nothing was sent. This is why the question rarely comes up in a
Jenkins or GitHub Actions pipeline: the gate and the deploy are the same program.

## The pull-based case, where it is not

A GitOps reconciler applies whatever is on the branch it watches. It does not ask CI's
permission, does not read CI's status, and does not know CI exists. **A failing test run
has no channel through which to stop it.**

So the gate moves to whatever puts content on that branch — in practice, the merge:

```
PR ──▶ CI ──▶ ✗ merge blocked ──▶ the branch never changes ──▶ nothing to sync
              ✓ merge allowed  ──▶ the branch changes      ──▶ reconciler syncs
```

Branch protection with required status checks is the standard answer. **The deploy gate
becomes a merge gate**, and the reconciler is left deliberately dumb — it applies the
branch, and the branch is trusted because of what it took to get there.

That inversion is worth sitting with. In push CI, the pipeline is the authority on what is
allowed to deploy. In GitOps, the *branch* is, and the pipeline's only job is deciding what
is allowed onto it.

## "Just don't push the image" is a different gate

It is the intuitive answer and it does prevent bad code from running, but it does not block
a deploy.

If a manifest names `myapp:v1.2.3` and CI never pushes that tag, the reconciler still
applies the Deployment. The pod goes `ImagePullBackOff`. That is not blocked — that is
**broken, in the cluster, in public**. The deploy happened and failed, which is strictly
worse than not deploying, because now there is a degraded workload to clean up.

The version that works inverts the order:

```
test ✓ ──▶ build ──▶ push image ──▶ write `image: myapp:v1.2.3` into the manifest repo
test ✗ ──▶ stop.  The manifest still names v1.2.2.  The reconciler has nothing to do.
```

**The gate is on updating the manifest, not on pushing the image.** The image is inert
until something references it; the write that references it is the deploy trigger, and
that write is what a failing test must prevent. This is what "image promotion" means, and
what tools like ArgoCD Image Updater, or a `kustomize edit set image` step, are doing.

## Gates on the reconciler side

Real, but a last line rather than the main one:

- **Sync windows** — refuse to sync outside an allowed period.
- **Manual sync** — turn off automated sync so a human triggers it. Honest, and it gives
  up the property that made GitOps worth adopting.
- **PreSync hooks** — a Job that must succeed before the sync proceeds; a failure aborts
  it. Useful for things only checkable against the live cluster, such as a migration
  dry-run.
- **Health checks** — do not gate the apply, but they decide whether a sync is reported
  healthy, which is what an automated rollback would key on.

None of these know anything about your tests. They gate on time, on a human, or on the
cluster's own state.

## What this costs

The honest trade: **a check that needs the cluster cannot run in hosted CI.** Anything
asserting against a live API server, a private node, or the real ingress is unreachable
from a hosted runner on someone else's network. That subset stays local — which means it
stays advisory unless something local enforces it, and the natural place is a pre-push
hook rather than a pipeline.

The subset that *can* run in hosted CI is the part that only needs the repository:
rendering the manifests, schema validation, policy checks, and any grep-shaped assertion
over what is about to be served. That is usually a smaller set than expected, and worth
enumerating deliberately rather than discovering when a required check turns out to be
unrunnable.
