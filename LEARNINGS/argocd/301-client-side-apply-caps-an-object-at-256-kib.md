# Client-side apply caps an object at 256 KiB

`[301]` · 2026-08-25 · wedged the deploy for 25 minutes while the site looked fine

A 223 KB photo was added to the site's ConfigMap. kustomize base64s a binary file into
`binaryData`, which took the object to 309 KB. The sync failed:

```
ConfigMap "site-content-7dm2tdkc74" is invalid:
  metadata.annotations: Too long: may not be more than 262144 bytes
```

**The limit that binds is not etcd's 1 MiB object size.** ArgoCD syncs with client-side
apply, which writes the entire object into the
`kubectl.kubernetes.io/last-applied-configuration` annotation so a later apply can compute
a three-way merge. Annotations are capped at 256 KiB, and the object is now stored twice —
so the real ceiling is roughly half of what the object limit suggests, whichever is
smaller.

`ServerSideApply=true` in the Application's `syncOptions` removes the annotation entirely
— the API server tracks field ownership itself — and restores 1 MiB as the ceiling.

## The failure is deceptive, which is the actual lesson

The ConfigMap was rejected. **The Deployment was not.** So:

- the new ReplicaSet scaled up and its pod sat in `ContainerCreating` forever, on
  `MountVolume.SetUp failed ... configmap not found`;
- the *old* pod kept running and kept serving;
- `curl https://buzaga.com.br/` returned 200 throughout.

The site was healthy and the pipeline was dead. Nothing could deploy — not the photo, not
a text-only change — and the only outward sign was that pushes stopped having any effect.

A partially-applied sync is the general shape here: an apply is not a transaction. Some
objects land, some are rejected, and the ones that landed can reference the ones that did
not. Look at pod events (`FailedMount`, `ImagePullBackOff`) and at
`.status.operationState.message` on the Application, not at whether the site answers.

## The check that should have caught it caused it

`make check-configmap-size` was written in the same commit as the photo, specifically to
catch an opaque apply-time failure. It asserted **etcd's 1 MiB limit** and reported
`OK: 30%` on a payload that was already at **118%** of the limit that actually applied.

Reaching for the limit you already know rather than the one governing the path in front of
you is the whole of it. See `../ai-engineering/201-construct-validity.md`; this is that
note's sixth instance and the first where the wrong check produced the outage instead of
merely missing it.

## What ArgoCD does after a failed sync

Worth knowing so the recovery is not misread as a hang. Automated sync retried five times,
then the operation went to `Failed` — terminal — and the app sat `OutOfSync` / `Degraded`
on the broken revision, **with the fix already pushed to Git**. Reconciliation interval is
120 s, and it did not pick the fix up on the next tick.

It recovered on its own about ten minutes after the fix landed. No `kubectl delete pod`,
no hard refresh. Two things follow:

- **Do not delete the stuck pod.** It is owned by a ReplicaSet, which recreates it
  immediately against the same missing ConfigMap. The pod and its ReplicaSet are reaped
  automatically the moment a good Deployment applies.
- **A failed sync backs off.** `Failed` is terminal for that operation; a new revision
  starts a new one, but not necessarily on the next poll. If it needs forcing,
  `kubectl -n argocd annotate app <name> argocd.argoproj.io/refresh=hard --overwrite`.
