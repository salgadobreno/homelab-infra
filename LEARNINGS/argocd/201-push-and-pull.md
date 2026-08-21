# Push and pull: GitOps next to GitHub Actions

`[201]` · how deployment differs, and what each model costs

## They are not alternatives

The first thing to get straight, because the question is usually asked as though it were
a choice between two tools:

**GitHub Actions and GitLab CI are CI systems that many people also use for CD. GitOps
replaces only the CD half.** You still need a CI system to run tests and build images.
ArgoCD does neither — it deploys manifests and nothing else.

So the comparison is not "Actions or ArgoCD". It is: **at the deploy step, does something
outside push in, or does something inside pull out?**

## Push

```
git push → CI: test → build image → push to registry
                                  → kubectl apply / helm upgrade
```

The CI runner holds credentials for the cluster and reaches into it. A deployment is a
**job that runs once and exits**.

What follows from that shape:

- **Cluster write access lives outside the cluster**, in CI, usable by anything that can
  trigger a pipeline.
- **CI must be able to reach the cluster.** Fine for a public API endpoint. Not possible
  for a cluster with no inbound path.
- **Drift is invisible.** Nothing is comparing between pipeline runs. A `kubectl edit`
  during an incident survives until a later deploy happens to overwrite it — or never, if
  it touched a field the manifests do not set.
- **"What is running in production?" is answered from pipeline logs**, by finding the last
  successful run and reading what it deployed.

**The credential objection has a modern answer.** OIDC federation lets the runner exchange
a short-lived workload identity for cloud or cluster access, so there is no stored
kubeconfig. Anyone who presents "push means long-lived credentials in CI" as though it
were unanswerable is a few years out of date. What OIDC does *not* fix is reachability or
drift.

## Pull

```
git push → CI: test → build image → push to registry
                                  → write the new tag into a Git repo
                                               ↓
                       an agent inside the cluster notices, applies, and keeps applying
```

Nothing reaches in. The agent reaches out.

- **No cluster credentials outside the cluster.** CI's most dangerous permission becomes
  "write to a Git repo".
- **The cluster needs only outbound network.** This is why GitOps is common on edge and
  on-prem clusters — and why it suits a cluster reachable only through an outbound tunnel.
- **Reconciliation is continuous, not an event.** The controller re-compares every few
  minutes forever, so drift is detected and (with `selfHeal`) reverted.
- **"What is running?" is `git log`.** The repository is the state rather than a
  description of it.

## The seam: how does the image tag get into Git?

The question that finds the hole in most people's mental model. If CI no longer deploys,
something still has to record *which version* to run. Three answers, in increasing order
of machinery:

| Approach | Trade-off |
|---|---|
| A human commits the tag | Fine for infrastructure. Tedious for an app that ships ten times a day. |
| CI commits the tag | Most common. But CI now has write access to a repo that auto-deploys — the trust boundary moved rather than disappeared. |
| An image-updater watches the registry and commits | Removes CI's write access. Adds a component that can itself be wrong. Argo Image Updater; Flux has it built in. |

A related convention: keep the **application repo separate from the manifests repo**, so a
tag bump does not retrigger the build that produced it.

## Where push is genuinely better

Worth knowing properly. The caveats are more convincing than the enthusiasm.

- **Feedback is synchronous.** A pipeline turns red on the pull request. With GitOps,
  `git push` succeeds and the failure appears later, in a different system, to whoever is
  looking.
- **Ephemeral per-PR environments** are natural in CI and awkward in GitOps —
  `ApplicationSet` can do it, but it is more moving parts.
- **Non-Kubernetes targets.** ArgoCD applies Kubernetes manifests. A Lambda, a VM fleet, a
  database migration: that is CI's job.
- **Ordered imperative steps.** "Migrate the database, then deploy, then warm the cache"
  is a pipeline. GitOps is declarative and converges in dependency order; forcing sequence
  needs sync waves and hooks, which is working against the model.
- **Secrets.** They cannot be committed, so GitOps needs Sealed Secrets, External Secrets
  or SOPS. CI simply injects them.

## What most places actually run

```
GitHub Actions / GitLab CI  →  test, build, scan, push image, bump the tag in Git
ArgoCD / Flux               →  reconcile the cluster to Git, continuously
```

The dividing line is **the cluster boundary**. CI owns everything up to producing an
artifact and recording the intent. The in-cluster agent owns everything after.

## Saying it under pressure

> CI is the same either way. The difference is whether deployment is a push from a runner
> holding cluster credentials, or a pull by an agent inside the cluster that keeps
> reconciling. Push makes deploys events; pull makes them a continuously enforced state —
> which is what gives you drift correction and takes cluster credentials out of CI.

Then expect the follow-up, which is almost always **"so how does the image tag get into
Git?"**

*Basics — the Application object, sync versus health, and why `selfHeal` and `prune` are
off by default — are in [101 · basics](101-basics.md).*
