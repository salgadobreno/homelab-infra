# Tasks

Ordered so every step is individually reversible (design D1). The two steps that touch
the public site are separated by a verification, so a fault is localised to one of them
rather than discovered at the end.

## 1. Record what is about to be destroyed

- [x] 1.1 Record the Compose arrangement in `README.md` — the three containers, what each did, the ports, and the hit counter's final number — as the evergreen "before" that M5 will show
- [x] 1.2 Capture the hit counter's last reading and the site's response size, so the record is a measurement rather than a description
- [ ] 1.3 Answer design Open Question 1: what the tunnel currently names as the origin for `buzaga.com.br` — operator, from the dashboard

## 2. Confirm the destination before moving anything

- [ ] 2.1 Run `make check-public` and confirm it passes in its current meaning: the cluster's hostname is the cluster, the apex is still Compose
- [ ] 2.2 Confirm the cluster's copy serves the same content the apex does, allowing for the marker and for Cloudflare's edge rewriting
- [ ] 2.3 Confirm `make check` is green, so the cluster is not carrying a fault into the cutover

## 3. Move the hostnames

- [ ] 3.1 Repoint `buzaga.com.br` at `http://192.168.0.30:80` in the Cloudflare dashboard (design D5) — operator action
- [ ] 3.2 Repoint `www.buzaga.com.br` the same way, so the two names do not disagree
- [ ] 3.3 Confirm both serve the cluster's copy, by marker — `site-delivery` "The public hostname serves the cluster copy"
- [ ] 3.4 Confirm the site answered 200 throughout — `site-delivery` "The cutover does not take the site down"

## 4. Stop the old origin

- [ ] 4.1 `docker compose down -v` — containers, network and the Redis volume removed; files on disk left alone (design D2, amended: the operator authorised `-v` once the counter's value was recorded). **Only after 3.1-3.4**: with the apex still pointing at Compose, any `down` takes the public site offline
- [ ] 4.2 Confirm nothing listens on the hypervisor's `:30000` or `:443` any more
- [ ] 4.3 Confirm the apex is unaffected by the stop — this is what proves 3.1 actually took effect rather than the old origin having served it all along
- [ ] 4.4 Confirm the containers do not return after a reboot, or assert the equivalent: they are removed, not merely stopped — `site-delivery` "The hypervisor no longer serves the site"
- [ ] 4.5 Confirm `../buzaga-website.service` is still not installed (design D3)

## 5. Invert the check

- [ ] 5.1 Update `make check-public` so it asserts the apex **is** the cluster's copy, in the same commit as the step that makes that true (design D4)
- [ ] 5.2 Confirm it fails if the apex serves something without the marker — `site-delivery` "The check fails if the primary hostname is not the cluster's copy"
- [ ] 5.3 Decide whether `check-public` now belongs in `make check` — it did not before, because it asserted a temporary arrangement; now it asserts the permanent one

## 6. Prove it survives

- [ ] 6.1 Run `make rebuild CONFIRM=yes` and confirm `buzaga.com.br` serves again with no step beyond the rebuild — the site now depends on the cluster, which is a stronger claim than M3's
- [ ] 6.2 Record the time from rebuild to the public site answering, and update `README.md` if it has moved

## 7. Close the record

- [ ] 7.1 Update `README.md`, `CLAUDE.md` and `openspec/config.yaml`: the hypervisor serves nothing, and the cluster serves the site
- [ ] 7.2 Record what became of the hit counter and Redis, so "we retired it" is a decision on the record rather than an absence someone has to reconstruct
- [ ] 7.3 Record in `LEARNINGS/` anything the cutover taught — an entry only if something was learned the hard way
