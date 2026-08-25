# A Helm release cannot contain an instance of a CRD it installs

`[301]` · cost a rebuild, and left the cluster with no reconciler at all

## What was tried

ArgoCD gets everything from Git, but something has to tell it *where* Git is. That one
`Application` object has to arrive some other way.

The tidy-looking answer: ship it inside ArgoCD's own Helm release. The chart has an
`extraObjects` list for exactly this kind of thing, and the release installs the
`Application` CRD, so the CRD and its first instance would arrive together.

```yaml
extraObjects:
  - apiVersion: argoproj.io/v1alpha1
    kind: Application
    metadata: {name: site, namespace: argocd}
```

## What happened

```
Error: INSTALLATION FAILED: unable to build kubernetes objects from release manifest:
resource mapping not found for name: "site" namespace: "argocd" from "":
no matches for kind "Application" in version "argoproj.io/v1alpha1"
ensure CRDs are installed first
```

Nothing installed. Not a partial install — the whole release failed, so the cluster came
up with no ArgoCD, and the install job looping on a failure that would never clear.

## Why the obvious reasoning is wrong

Helm sorts resources by kind when it applies them, and `CustomResourceDefinition` sorts
near the front while custom kinds sort last. So the ordering *is* right.

The failure is not in the apply phase. **Helm resolves every object in a release against
the API server's known kinds before applying any of them** — it builds the whole manifest
first, and building requires mapping each `apiVersion`/`kind` to a real resource. At that
moment the CRD does not exist yet, so the mapping fails and the release is abandoned
before anything is created.

Ordering cannot fix a validation that happens before ordering matters.

## The general shape

**A release cannot contain an instance of a CRD that the same release installs.** This is
not specific to ArgoCD — it bites anyone installing an operator and its first custom
resource together, which is a very common thing to want.

The usual answers:

- **Two releases.** Install the operator, then the custom resources, as separate units.
- **A separate manifest applied by something that retries.** k3s applies each file in
  `/var/lib/rancher/k3s/server/manifests/` independently and retries failures, so a file
  that fails while the CRD is missing succeeds on a later pass. This is what worked here.
- **Helm's `crds/` directory**, when you control the chart. Helm installs those before
  templates are even rendered. Not available when consuming someone else's chart that
  puts its CRDs in `templates/`.

## Worth noticing

The bootstrap object is *meant* to be awkward. Everything else in the cluster arrives by
reconciliation; this one thing cannot, because it is what starts reconciliation. Trying to
make it look like everything else is what produced the failure.

A file that says "this is the exception, and here is why" is more honest than a
configuration that hides it — and the error message above is now in the manifest itself,
because the next person to try consolidating those two files will hit exactly it.

See also `../helm/101-basics.md` for why Helm resolves the whole release before
applying any of it.
