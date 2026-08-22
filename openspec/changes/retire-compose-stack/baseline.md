# Baseline

Measured 2026-08-22, before anything was moved or stopped.

## What is serving

```
buzaga.com.br        HTTP 200  2878B  marker absent   -> Compose
www.buzaga.com.br    HTTP 200         marker absent   -> Compose
k8s.buzaga.com.br    HTTP 200  2902B  marker present  -> the cluster
127.0.0.1:30000      HTTP 200  2648B                  -> Compose, at the origin
```

The three sizes differ for two separate reasons, and both matter when reading a check:
Cloudflare's edge adds its email-obfuscation script (2648 → 2878), and the cluster's copy
additionally carries the `served-by: k3s` marker (2878 → 2902).

`cf-cache-status: DYNAMIC` on the apex — nothing is cached at the edge, so a broken
origin will show immediately rather than being masked by a stale copy. The verification
steps in group 3 and group 4 depend on that being true.

## The stack being retired

```
buzaga-nginx        nginx:latest        30000:80, 443:443   started 2026-08-06
buzaga-hit-counter  buzaga-hit-counter  local build         started 2026-08-06
buzaga-redis        redis:7-alpine      buzaga_redis-data   started 2026-08-06
```

Final hit counter reading:

```
$ curl -s http://127.0.0.1:30000/api/hits
{"state":"first","total":69,"returning":6}

$ docker exec buzaga-redis redis-cli --scan
hits:total
hits:returning
```

69 at the cutover, against 65 when this project's second milestone began. Two keys, and
that is the entire persistent state of the thing being retired.

## Why the hit counter could not simply have been moved

```
$ docker image inspect buzaga-hit-counter --format '{{.RepoDigests}}'
[]
```

Empty. The image was built on this host and never pushed anywhere, so there is nothing
for a cluster to pull. Porting it meant building and hosting an image first — which is
exactly the registry work the ladder decided not to schedule for a component that is
going away.

That empty list is also the clearest single statement of what was wrong with the old
arrangement: the running service existed in one place, with no way to reproduce it
elsewhere.

## Port bindings that disappear with it

```
0.0.0.0:30000 -> 80    serving
0.0.0.0:443   -> 443   accepts a connection and serves nothing
```

`:443` is published by the container but nothing inside listens on it — `nginx.conf` only
declares `listen 80`. It is already vestigial, which answers half of design Open
Question 2.

## The thing that would undo this

```
$ systemctl list-unit-files | grep -i buzaga
(nothing)
```

`../buzaga-website.service` exists on disk and runs `docker compose up -d` on boot. It is
not installed and not enabled, so it is inert — by accident rather than by decision.
Task 4.5 asserts it stays that way.

## How to re-measure

```bash
make check-public                                 # which copy each hostname serves
curl -s http://127.0.0.1:30000/api/hits           # the counter, while it exists
docker compose -f ../docker-compose.yml ps        # the stack
systemctl list-unit-files | grep -i buzaga        # the unit that would bring it back
```

## The cutover, and the outage it caused

**`site-delivery` "The cutover does not take the site down" was not met.** Recorded as a
failure rather than ticked, because it is the only requirement in this change that had a
chance of failing and it did.

When the apex was repointed at traefik, it arrived carrying `Host: buzaga.com.br`. The
`Ingress` listed only `k8s.buzaga.com.br`, so traefik matched no rule and answered 404.
Both public names returned 404 until the Ingress was corrected and reconciled — a few
minutes.

The cause was in M3's work, not in the repoint. The Ingress was written when exactly one
public name reached the cluster, and nothing made that assumption visible; a second name
arriving was all it took. Design D1 sequenced the cutover so a fault would be caught
before the teardown, and it was — the outage happened at step 3 and the teardown was not
attempted until step 4 passed.

What the ordering did buy: the Compose stack was still running and one dashboard edit
from being live again for the whole window.

**The diagnosis to keep.** A wrong origin port gives a 502 from Cloudflare, because
nothing accepts the connection. A 404 means something accepted it and had no route. That
distinction pointed straight at traefik rather than at the tunnel configuration, and it
is the first thing to check next time.

## The teardown

```
$ curl -s http://127.0.0.1:30000/api/hits
{"state":"first","total":72,"returning":6}
$ docker compose down -v
  ... 3 containers removed, volume buzaga_redis-data removed, network removed
```

Immediately after:

```
buzaga.com.br        HTTP 200      <- unaffected, which proves the repoint took effect
www.buzaga.com.br    HTTP 200
k8s.buzaga.com.br    HTTP 200

127.0.0.1:30000      no answer
127.0.0.1:443        no answer
docker ps -a         no buzaga containers exist
docker volume ls     0 buzaga volumes
systemd              0 installed buzaga units
```

The apex answering 200 *after* the stack stopped is what proves step 3 actually took
effect. Had the repoint silently failed, everything would have looked correct until this
moment and the site would have gone down here — with the teardown blamed for a fault
introduced two steps earlier.

## A check that outlived what it was checking

`make check` failed immediately after the teardown:

```
FAIL: origin returned 000
make: *** [check-tunnel] Error 1
```

`check-tunnel` asserts that the tunnel's origin still answers, and its origin was
hardcoded as `http://127.0.0.1:30000/` — the Compose stack, written in M2 when that was
what the tunnel dialled. M4 moved the origin to traefik and the assertion kept checking
the old address.

It is now `http://192.168.0.30/` with the site's `Host` header, which is what the tunnel
actually dials.

Worth recording because the check behaved correctly: it failed, loudly, at the moment its
subject changed. The alternative — an assertion loose enough to keep passing — would have
left `make check` green while silently testing nothing. A check that breaks when the
system changes underneath it is doing its job; the cost is remembering that changing the
system means changing its checks.
