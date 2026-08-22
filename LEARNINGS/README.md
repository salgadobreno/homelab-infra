# Learning

Notes from building this homelab, arranged so the file tree answers questions on its own.

## How to read the tree

Folders are subjects. The number prefix is depth:

| Prefix | Means |
|---|---|
| `101` | What this is and why it exists. Readable cold, assumes no project knowledge. |
| `201` | Working knowledge. How the thing behaves, and why it behaves that way. |
| `301` | A sharp edge hit in practice. Something broke, or nearly did. |

So `terraform/301-one-byte-replaced-the-cluster.md` tells you the subject, the depth,
and roughly what happened before you open it.

**Gaps are meant to be visible.** A subject with three `301` files and no `101` says
the sharp edges were met before the basics were written down. That is worth seeing in
the tree rather than discovering later.

## How entries are written

An entry is added **after the fact**, when something was hit in practice: a failure, a
surprising default, a decision that turned out to matter later. `101` entries are the
exception — they are written when the operator asks for the basics of something, and
they must not narrate this project's history. An explanation that needs you to have
followed the work is not a fundamental.

Nothing goes in because a session ended. No entry is generated to look thorough.

Each entry carries a marker:

- `[hit]` — encountered, recorded, not yet examined properly
- `[worked]` — gone through deliberately; could be explained unprompted
- `[open]` — flagged as worth understanding, not yet touched

`[worked]` is the operator's to claim. Reading an explanation is not the same as being
able to give one, and nobody else can assert that on their behalf.

## Index

### cloud-init
- [101 · basics](cloud-init/101-basics.md) — what it is, what you write, when it runs
- [201 · instance identity](cloud-init/201-instance-identity.md) — why a reboot and a rebuild are different tests

### terraform
- [101 · basics](terraform/101-basics.md) — resources, the plan/apply loop, state, and why replacement happens
- [201 · dependency graph](terraform/201-dependency-graph.md) — ordering is inferred from references, not declared
- [201 · state internals](terraform/201-state-internals.md) — serial, lineage, and why state is a liability
- [301 · stale plans](terraform/301-stale-plans.md) — a plan is a promise about a known world
- [301 · one byte replaced the cluster](terraform/301-one-byte-replaced-the-cluster.md) — a trailing space proposed a teardown

### proxmox
- [201 · datastore content types](proxmox/201-datastore-content-types.md) — storage advertises what it will hold
- [301 · the provider uses two channels](proxmox/301-provider-uses-two-channels.md) — API for most things, SSH for snippets
- [301 · ACL paths override, not add](proxmox/301-acl-paths-override-they-do-not-add.md) — a deeper grant replaces the inherited one
- [301 · under-scoping fails mid-apply](proxmox/301-under-scoping-fails-mid-apply.md) — after the destroy already happened
- [301 · the role you guess is not the role you need](proxmox/301-the-role-you-guess-is-not-the-role-you-need.md) — three privileges, three different ways of being invisible

### argocd
- [101 · basics](argocd/101-basics.md) — pull instead of push, and what Git being the record actually buys
- [201 · push and pull](argocd/201-push-and-pull.md) — where GitOps sits next to GitHub Actions, and what each model costs
- [301 · a release cannot contain its own CRD](argocd/301-a-release-cannot-contain-its-own-crd.md) — Helm validates before it orders

### kubernetes
- [301 · a 404 from the ingress is not a missing site](kubernetes/301-a-404-from-the-ingress-is-not-a-missing-site.md) — host rules encode an assumption about who will call

### k3s
- [201 · one binary, five opinions](k3s/201-one-binary-five-opinions.md) — what k3s bundles, and what is Kubernetes proper

### ai-engineering
- [101 · evals and guardrails](ai-engineering/101-evals-and-guardrails.md) — how you test output you cannot predict, and where a check should sit
- [201 · construct validity](ai-engineering/201-construct-validity.md) — the green check that measures something adjacent

### practice
- [201 · decide values up front](practice/201-decide-values-up-front.md) — deciding beats discovering
- [301 · tool output is untrusted](practice/301-tool-output-is-untrusted.md) — a warning message executed itself
- [301 · verifying recovery](practice/301-verifying-recovery.md) — prove the disruption happened first
- [301 · rebuilt hosts change identity](practice/301-rebuilt-hosts-change-identity.md) — fresh VM, fresh SSH host keys
- [301 · guardrails arrive too late](practice/301-guardrails-arrive-too-late.md) — every control here detects, almost none prevent

## Queued

Topics marked as worth understanding, not yet written: [queue.md](queue.md)
