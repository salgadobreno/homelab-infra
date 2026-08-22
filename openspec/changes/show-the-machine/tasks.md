# Tasks

The disclosure boundary and the drift check are built before the page they govern, so the
first generated output is inside the boundary rather than retrofitted into it.

## 1. Establish the baseline

- [x] 1.1 Record what the site says today, and the raw `kubectl` output the page will be made from, so "generated" can be compared against a known input
- [x] 1.2 Confirm `make check` and `make check-public` are green before anything is added

## 2. The boundary, before the thing it bounds

- [x] 2.1 Write the disclosure allow-list into the repository as the authority the check reads (design D4)
- [x] 2.2 Add `make check-disclosure`, failing on an IPv4 address, an absolute path, or a known account name in the generated fragment
- [x] 2.3 Confirm it fails on a fixture containing each forbidden shape — a check never seen to fail is not a check
- [x] 2.4 Move the guardrail left: fire `check-disclosure` from a `PostToolUse` hook in `.claude/settings.json` on writes under `k8s/site/`, so a forbidden value is refused at the write rather than reported after the commit. Confirm the hook blocks a deliberate violation

## 3. The generator

- [x] 3.1 Answer design Open Question 2 and decide where the generated fragment lives — a separate file, `k8s/site/content/machine.html`, so the drift diff is over a file that is entirely generated
- [x] 3.2 Write `scripts/generate-diagram.sh`, reading the cluster and emitting the fragment, with the determinism rules from D3 applied deliberately rather than discovered
- [x] 3.3 Add `make diagram`
- [x] 3.4 Run it twice against an unchanged cluster and confirm byte-identical output — `self-description` "The description is reproducible"
- [x] 3.5 Confirm the output is inside the disclosure boundary — `self-description` "A forbidden value cannot reach the page"

## 4. The drift check

- [x] 4.1 Add `make check-diagram`: regenerate into a temporary file, diff against what is committed, fail on any difference (design D2)
- [x] 4.2 Confirm it fails when the cluster changes — change something the page reports and watch the check name it. Scaling `site` cannot demonstrate this: ArgoCD selfHeal reverts it in ~310 ms, measured, faster than the generator can read the cluster. Done instead by scaling `argocd-applicationset-controller` 0→1, which no Application manages — `self-description` "A change in the cluster fails the check"
- [x] 4.3 Confirm the failure is resolved by `make diagram` and nothing else
- [x] 4.4 Confirm it passes when the page is current — `self-description` "The check passes when the page is current"

## 5. The page

- [x] 5.1 Generate the current-state half and commit it; confirm it reaches the public site through ArgoCD with no command run against the cluster
- [x] 5.2 Write the "before" half from the record M4 made, labelled as history rather than as a reading (design D5) — `self-description` "The two halves are not presented as equivalent"
- [x] 5.3 Decide Open Question 3: whether the page names the commit it was generated from — no, and it cannot: see the fixpoint argument in `generate-diagram.sh` and design D3
- [x] 5.4 Confirm nothing hand-written describes the system: `diagram.ascii` was already gone (commit `6bfba43`) and the dead `/api/hits` call is removed. Made enforceable rather than confirmed once — `make check-handwritten` fails if served hand-written content names a technology, proven on a fixture — `self-description` "A hand-written description cannot be served"
- [x] 5.5 Read the finished page as someone who has never seen this repository. The audience test, and the only one here that cannot be automated

## 6. Prove it survives

- [ ] 6.1 Wire `check-diagram` and `check-disclosure` into `make check`
- [ ] 6.2 Run `make rebuild CONFIRM=yes` and confirm the page returns and still matches the cluster — a rebuilt cluster reports the same shapes, so the check should stay green without regeneration
- [ ] 6.3 Confirm `make check` fails if the page is deliberately edited by hand, which is the whole point

## 7. Close the record

- [ ] 7.1 Update `README.md`, `CLAUDE.md` and `openspec/config.yaml`
- [ ] 7.2 Record in `LEARNINGS/` anything the rung taught, if it was earned
