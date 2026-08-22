## Why

`buzaga.com.br` still resolves to a Docker Compose stack on the hypervisor. Everything
this project has built — the provisioned node, the scoped credentials, the reconcile loop
— sits alongside the thing it was built to replace, and the address that matters still
points at the old one.

The cluster has been serving the same content at `k8s.buzaga.com.br` since M3, so the
question is no longer whether it works. It is whether the project finishes the sentence.

## What Changes

- **`buzaga.com.br` is repointed** from the Compose stack to traefik on the node. The
  origin moves; the site does not pause.
- **The Compose stack is stopped and disabled**, and the hypervisor stops serving HTTP.
- **The hit counter and Redis are retired, not ported** — operator decision, recorded on
  the ladder. `index.html` already hides the counters when the API is absent, and the
  cluster copy has served it that way since M3, so the post-cutover behaviour is already
  observable in production today.
- **The "before" state is recorded before it is destroyed** — the Compose arrangement and
  its live hit count — in `README.md`, as part of this change rather than afterwards.
- **`make check-public` changes meaning**: it currently asserts that `buzaga.com.br` has
  *not* moved to the cluster. After this it must assert the opposite.

Explicitly **not** in this change:

- An image registry and durable storage. They were only ever needed to port the hit
  counter, which is not happening. Not deferred — unscheduled, until a workload makes
  the case.
- Removing `k8s.buzaga.com.br`. Two names reaching the same place costs nothing, and one
  of them is the name every check in this repository already uses.
- Deleting the Compose definition or its content from disk. Stopping a service and
  destroying its data are different decisions, and only the first is reversible.

## Capabilities

### Modified Capabilities

- `infrastructure/site-delivery`: the requirement currently says the pre-existing
  hostname continues to serve the pre-existing deployment. That was correct while both
  copies ran and stops being correct here — the apex must serve the cluster, and the
  hypervisor must no longer serve the site at all.

### New Capabilities

None. This change retires an implementation; it does not introduce a capability.

## Impact

- **The public site.** The only change so far that a visitor could notice. The failure
  mode is a visible outage on the project's most public surface, so the cutover has to be
  ordered to be reversible at every step.
- **`/mnt/sda8/Projects/buzaga/docker-compose.yml`** — outside this repository, and
  operated by hand. What this change does to it must be written down here, because
  nothing else records it.
- **The hit counter's data.** Roughly 67 recorded visits in a Redis volume. Retiring the
  service abandons the counter; the number itself is worth keeping as a fact, which is
  what recording the before state is for.
- **`make check-public`** inverts. A check whose meaning changes is a check that can pass
  for the wrong reason during the change, so it has to be updated in step with the
  cutover, not before or after.
- **The Cloudflare dashboard**, again — repointing a hostname is dashboard configuration,
  the same seam M3 named and could not close.
