# Tasks

The disclosure check is built before the thing it checks, so the first rendered output is
already inside the boundary rather than being retrofitted into it.

## 1. Establish the baseline

- [ ] 1.1 Record what the site says today, and what the cluster would report — the raw `kubectl` output the page will be made from, so "generated" can be compared against a known input
- [ ] 1.2 Confirm the cluster has no ServiceAccount, Role or RoleBinding of this project's making, so what this change adds is the whole of it
- [ ] 1.3 Confirm `make check` and `make check-public` are green before anything is added

## 2. The boundary, before the thing it bounds

- [ ] 2.1 Write the disclosure allow-list into the repository as the authority the check reads (design D3)
- [ ] 2.2 Add `make check-disclosure`, which fails on an IPv4 address, an absolute path, or a known account name in the rendered output
- [ ] 2.3 Confirm it fails on a fixture containing each forbidden shape — a check never seen to fail is not a check

## 3. An identity that can read almost nothing

- [ ] 3.1 Add a ServiceAccount, Role and RoleBinding granting exactly the reads the page makes, and nothing else
- [ ] 3.2 Confirm the identity is refused a Secret read — `self-description` "The renderer cannot read secrets"
- [ ] 3.3 Confirm the identity is refused every write — `self-description` "The renderer cannot write"
- [ ] 3.4 Add `make check-renderer-scope` so both refusals are a command rather than a memory

## 4. Render it

- [ ] 4.1 Add the sidecar to the site Deployment: stock `kubectl` image pinned, writing into an `emptyDir` nginx already serves (design D1, D2)
- [ ] 4.2 Answer design Open Question 1 — what the sidecar needs in `securityContext` to write to the shared volume while the site container stays read-only
- [ ] 4.3 Answer design Open Question 2 and set the refresh interval deliberately
- [ ] 4.4 Confirm the rendered output appears and is inside the disclosure boundary — `self-description` "A forbidden value cannot reach the page"

## 5. Make it true rather than plausible

- [ ] 5.1 Change something the page reports, and confirm the page follows without any edit to the repository — `self-description` "The description follows a change in the cluster"
- [ ] 5.2 Stop the renderer and confirm the page says it is stale rather than showing old data as current — `self-description` "A failed renderer is visible rather than silent"
- [ ] 5.3 Confirm a dead renderer does not take the site down

## 6. Both halves

- [ ] 6.1 Write the "before" — the Compose arrangement — as static content, labelled as a story rather than a reading (design D5)
- [ ] 6.2 Delete `k8s/site/content/diagram.ascii` — `self-description` "A hand-written description cannot be served"
- [ ] 6.3 Decide Open Question 3: whether the page shows which node and pod served the request
- [ ] 6.4 Confirm the page reads as one thing to someone who has never seen this repository — the audience test, and the only one that cannot be automated

## 7. Prove it survives

- [ ] 7.1 Run `make rebuild CONFIRM=yes` and confirm the page returns, rendering current state, with no step beyond the rebuild
- [ ] 7.2 Wire `check-disclosure` and `check-renderer-scope` into `make check`

## 8. Close the record

- [ ] 8.1 Update `README.md`, `CLAUDE.md` and `openspec/config.yaml`
- [ ] 8.2 Record what the RBAC actually needed versus what was guessed — the same gap M2 found, one layer up
- [ ] 8.3 Record in `LEARNINGS/` anything the rung taught, if it was earned
