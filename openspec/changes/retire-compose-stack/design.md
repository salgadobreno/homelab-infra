# Design

## Context

| Constraint | Detail |
|---|---|
| Serving today | `buzaga.com.br` and `www.buzaga.com.br` → Compose on the hypervisor; `k8s.buzaga.com.br` → the cluster |
| Compose stack | `buzaga-nginx` (`30000:80`, `443:443`), `buzaga-hit-counter`, `buzaga-redis`, all `restart: unless-stopped` |
| Hit counter state | ~67 visits in the `buzaga_redis-data` volume |
| Tunnel | token-based, so ingress rules are dashboard configuration — the seam M3 named and could not close |
| Edge caching | `cf-cache-status: DYNAMIC` — the apex is not cached, so a broken origin shows immediately rather than being masked |
| A loaded gun | `../buzaga-website.service` exists on disk, is **not** installed, and would resurrect the stack if anyone ever enabled it |

## Goals

- `buzaga.com.br` served by the cluster, and identifiable as such.
- The hypervisor serving no HTTP at all.
- No visible outage at any point.

## Non-Goals

- Porting the hit counter or Redis. Retired, per the ladder — a registry and a
  persistence story are real work for a component that is going away.
- Deleting the Compose definition, its content, or the Redis volume. Stopping a service
  and destroying its data are separate decisions and only the first is reversible.
- Removing `k8s.buzaga.com.br`. Two names reaching one place costs nothing, and every
  check in this repository already uses it.

## Decisions

### D1: Order the cutover so every step is individually reversible

The failure mode here is a visible outage on the most public thing this project owns, so
the sequence matters more than the mechanism:

1. **Record the before state.** First, because after the teardown it cannot be recovered
   — only remembered, which is the failure this step exists to prevent.
2. **Confirm the cluster copy serves the same content.** Already true and asserted by
   `make check-public`; re-run rather than assume.
3. **Repoint `buzaga.com.br` and `www.` at traefik.** Both origins are still running at
   this point. Reversible in the dashboard in seconds.
4. **Confirm the apex serves the cluster copy**, by marker.
5. **Only now stop Compose.** Reversible with `docker compose up -d`.
6. **Confirm the apex is unaffected** by the stop — which also proves step 3 actually
   took effect rather than the site having been served by the old origin all along.

Step 6 is the one worth being explicit about. If the repoint silently failed, steps 3-5
would all look fine and the site would go down at step 5 — attributing an outage to the
teardown when the cause was two steps earlier.

### D2: Stop and remove containers; keep volumes and files

`docker compose down` removes the containers and the network, leaves the named volume,
and leaves everything on disk. `restart: unless-stopped` only applies to containers that
exist, so removing them is what makes the stop survive a reboot — `docker compose stop`
would not.

The Redis volume stays. It holds a number this change has already written down, and
`down -v` is a one-word difference away from destroying data to no benefit.

### D3: The uninstalled unit file is named, not deleted

`../buzaga-website.service` would bring the whole stack back on boot. It is not installed
and not enabled, so it is inert — but it is inert by accident rather than by decision, and
"why did the old site come back" is an unpleasant thing to debug later.

It is outside this repository and belongs to the operator, so this change records what it
does rather than deleting it. The verification step asserts it is not installed, which is
what makes the record a check rather than a note.

### D4: `make check-public` inverts in step with the cutover, not before or after

It currently asserts that `buzaga.com.br` has **not** moved to the cluster. After this it
must assert that it has.

A check whose meaning inverts is dangerous during the change that inverts it: updated too
early it fails while the old state is still correct, and too late it passes while
asserting something no longer true. It changes in the same commit as the step that makes
the new meaning correct, and the old assertion is not deleted — it moves to the cluster's
own hostname, which should still be the cluster's copy afterwards.

### D5: `www` moves with the apex

Both currently serve the Compose copy. Moving one and not the other leaves two public
names disagreeing about what the site is, which is worse than either state.

## Risks

| Risk | Mitigation |
|---|---|
| Repoint fails silently and the outage is blamed on the teardown | Step 6 verifies after the stop, and step 4 verifies before it — the pair localises the fault |
| The site is down while the operator is asleep | Every step is reversible, and the last one is a single `docker compose up -d` |
| Someone later enables the stray unit and both origins serve | Asserted not-installed as part of the check |
| Redis data destroyed by a reflexive `down -v` | The volume is out of scope and the tasks say `down` without `-v`, explicitly |
| The hit counter's number is lost | Recorded in `README.md` before anything stops — that is task 1 |

## Open Questions

1. What does the tunnel's ingress currently name as the origin for `buzaga.com.br` —
   `http://127.0.0.1:30000` or something else? It determines what the new value replaces,
   and it can only be read in the dashboard.
2. Does anything else on the LAN depend on the hypervisor answering on `:30000` or
   `:443`? Both bindings disappear with the containers. `:443` currently accepts a
   connection and serves nothing, which suggests it is already vestigial.
