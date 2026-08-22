# Construct validity: the check that measures the wrong thing

`[hit]` · 2026-08-22

## The idea

**Construct validity** is the question of whether a measurement measures the thing you
believe it measures. It comes from the social sciences, where you cannot observe
"intelligence" or "job satisfaction" directly and have to build a proxy for it — and where
the entire risk is that the proxy drifts away from the thing while continuing to produce
tidy numbers.

It transfers exactly to testing, and it is the failure mode that dominates evals.

A test has two independent properties:

- **Reliability** — it gives the same answer under the same conditions.
- **Validity** — the answer is about what you think it is about.

Testing culture is preoccupied with the first and mostly silent about the second. A
flaky test is loud and gets fixed. **An invalid test is quiet, green, and load-bearing.**

## Why it dominates evals specifically

At rung 1 of the eval ladder — a byte diff — validity is nearly free. The assertion *is*
the thing. There is no proxy to drift.

Every rung up introduces a proxy, and the proxy is where validity leaks:

| Rung | The proxy | How it goes invalid |
|---|---|---|
| 2 · canonicalised match | your normalisation rules | you normalise away something that mattered |
| 3 · property assertions | the properties you thought to check | the output satisfies all of them and is still wrong |
| 4 · LLM-as-judge | the rubric, and the judge's reading of it | the judge rewards fluency; you wanted correctness |

Rung 4 is the notorious one. A judge model scores plausibility well and correctness
poorly, so a rubric asking "is this answer good?" quietly becomes "does this read like a
good answer?" Those diverge precisely where it matters — a confident wrong answer scores
above a hedged right one.

**The cost of climbing the ladder is not just precision. It is that each rung gives you a
new way to be confidently wrong.** That is the real argument for spending effort on
determinism.

## The general shape

An invalid check is almost never obviously broken. It is a check of something *adjacent*:

- it tests a **mechanism you assumed** rather than the one in use;
- it tests **reachability** rather than function;
- it tests a **precondition** rather than the outcome;
- it tests **an address, path, or name** that used to be right;
- it observes a state that would have been true **whether or not the thing worked**.

The last one is the most dangerous, because it produces a green result with no causal
connection to the property at all.

## Instances in this project

This repository has produced five, which is why it is written down.

**The SFTP probe.** The provider links an SFTP library, so snippet uploads were assumed to
be SFTP; the check verified SFTP reachability. `source_raw` pipes through `tee` over a
shell exec. The check was built from the same wrong belief as the bug, so it agreed with
the error instead of catching it. *A check written from your model of the system inherits
that model's mistakes.*

**The `buzaga` login probe.** `check-root-ssh` tested `ssh buzaga@pve` — from `pve`, where
`buzaga`'s key is not in `buzaga`'s own `authorized_keys`. It could not have passed. It
reported `FAIL` on correctly hardened sshd, and a correct hardening was reverted because
of it. *Invalidity is not only false green. A false red destroys real work.*

**The sleep-then-read selfHeal test.** Scale the Deployment, `sleep 3`, read `replicas`,
see `1`, conclude ArgoCD reverted it. It never established that the drift existed. `1` was
the expected value at the start, at the end, and if nothing had happened at all. Redone by
tracking `metadata.generation` across 4→5→6 plus the scale events — evidence of the
transition, not of the resting state.

**The stale `ORIGIN_URL`.** `check-tunnel` pointed at `127.0.0.1:30000` for as long as
that was where the origin lived. M4 moved the origin. The check went on measuring an
address nothing served. *A check hardcodes the world as it was on the day it was written,
and nothing tells it the world moved.*

**The hardcoded token-file path.** Same shape, same cause.

## The requirement-level version

The same failure occurs one level up, where it is harder to see.

`k8s/site/content/diagram.ascii` was a hand-drawn picture naming three technologies that
did not exist in the system. Every check passed. Nothing was measuring the property "this
description is true", so nothing could go red.

And when M5 was first designed, "generated from live state" was read as "rendered at
request time", producing a design with a sidecar, a ServiceAccount, a Role and a
RoleBinding. It was well built. Every check would have passed on it. It was the wrong
artifact — invalidity in the requirement rather than in the test.

*A green suite says the properties you thought to assert hold. It says nothing about the
properties you did not think of, and nothing at all about whether you built the right
thing.*

## What to do about it

Three questions, in order of how much they catch:

1. **Would this check ever go red?** Construct it to fail before trusting it to pass. Task
   2.3 of `show-the-machine` exists for this reason: a check never seen to fail is not a
   check.
2. **Could the green result have arisen without the property holding?** If yes, it is
   measuring a resting state, not a transition. Establish the precondition explicitly.
3. **Where did the values in this check come from?** Anything hardcoded — an address, a
   path, a name — is a snapshot of a world that has since moved. Derive it, or assert it
   separately.

The structural defence is the ladder itself: **spend the effort to get back to rung 1.**
An exact diff against generated output has almost no room to measure the wrong thing,
because there is no proxy in it. That is what makes determinism worth paying for, and it
is the direct reason `show-the-machine` treats the generator's reproducibility as a
requirement rather than a convenience.

See also `../practice/301-guardrails-arrive-too-late.md`, which is what happens to a check
that is valid but placed where it cannot help.
