# Testing what you cannot predict

`[101]` · written to be read cold, no project knowledge assumed

## The problem it solves

Ordinary software testing rests on an assumption so basic it is rarely stated: **the same
input produces the same output**. Given that, a test is an equality check. Run the
function, compare against the expected value, done.

A system built around a language model breaks that assumption at the foundation. The same
prompt produces different text on Tuesday than it did on Monday. Both may be correct.
Neither is the string you wrote in the test file.

So the question that defines this field is: *how do you assert on output you cannot
predict?* Everything below is an answer to it.

## Evals

An **eval** is a test for output that cannot be matched exactly. Instead of comparing
against an expected value, it grades against a rubric.

The word covers a wide range of strictness, and the range is the useful part.

### The ladder

| Rung | Method | Cost |
|---|---|---|
| 1 | **Exact match** — byte-for-byte diff | Cheapest and strongest. Requires determinism. |
| 2 | **Canonicalised match** — normalise the noise away, then diff | Requires knowing every source of variation |
| 3 | **Property assertions** — check invariants, not the string | Tolerates rewording. Cannot see whether it is *good*. |
| 4 | **LLM-as-judge** — a model scores the output against a rubric | Expensive, and the judge is itself nondeterministic |
| 5 | **Human review** | Does not scale. Never wrong. |

Rung 3 is worth an example, because it is where most people first arrive. If a function
returns a summary, you cannot assert the text. You *can* assert that it is under 200
words, mentions every input document, and contains no URL. Those are properties. They are
weaker than equality and enormously stronger than nothing.

### The discipline

**Climb no higher than you must, and spend effort climbing back down.**

Every rung up buys tolerance and pays in precision. A rung-4 judge will happily approve
output a rung-1 diff would have caught, because a judge reads for plausibility and a diff
reads for truth.

This is why canonicalisation is real engineering rather than a workaround. If output
varies only because it contains a timestamp and an unsorted list, then removing the
timestamp and sorting the list moves you from rung 3 to rung 1 — and you get back the
strongest assertion available. Teams spend serious effort on exactly this.

The general form: **a nondeterministic system is usually a deterministic one with a few
identifiable sources of noise.** Find them and name them, and most of the problem
disappears. What remains is the part that genuinely needs judging.

### Where evals go wrong

An eval is a *measurement*, and measurements can be valid or invalid independently of
whether they pass. A green eval that measures something adjacent to what you care about is
worse than no eval, because it manufactures confidence. That failure has a name and its
own note — see `201-construct-validity.md`.

## Guardrails

An eval runs in your test suite. A **guardrail** runs *in the path* — it inspects input or
output as the system operates, and blocks what it rejects.

The distinction that matters:

- an eval tells you the system was wrong, afterwards, in aggregate;
- a guardrail stops one specific bad output from getting out.

Typical guardrails: refusing input that looks like a prompt injection; scanning output for
credentials, personal data, or internal hostnames before it is returned; requiring output
to parse as valid JSON against a schema before it is accepted.

### Allow-list, not deny-list

A deny-list enumerates what is known bad today. It is checked against a generator that
will produce something new tomorrow. An allow-list states what may pass and rejects
everything else — it fails safe as the system grows, which is the direction systems go.

Where a full allow-list is impractical, the next best thing is to **match shapes rather
than values**: reject anything matching the pattern of an IP address, rather than
maintaining a list of the IP addresses you currently have.

### Placement, or "shift left"

Every guardrail sits somewhere in the pipeline, and where it sits decides what it can
save you from.

```
generate → write → check → commit → publish → the world
     ↑                                   ↑
 cheapest to catch              point of no return
```

The further right it sits, the more has already happened when it fires. A guardrail after
publication is an incident report. The same check, placed at generation, is a prevention.

**Shifting left** is moving a check earlier — the same logic, run sooner, so the failure
is cheap. It is the highest-leverage change you can usually make to a guardrail, because
it costs nothing to relocate a check you have already written.

The complement is **failing closed**: when a guardrail cannot run — the service is down,
the credential is missing — it must block rather than wave the output through. A guardrail
that silently disables itself under load is not a guardrail.

## Hooks

A **hook** is deterministic code that fires on an event, without being asked.

They are the mechanism guardrails are usually built from, because they cannot be forgotten
or skipped. A check you have to remember to run is advice. The same check bound to an
event is enforcement.

In agent tooling, hooks typically fire on tool use — before a command runs, after a file
is written — and a non-zero exit becomes feedback the agent must deal with rather than a
message nobody reads.

The pattern generalises well beyond AI: a git pre-commit hook and an output guardrail are
the same idea, which is **deterministic scaffolding around a nondeterministic actor.** In
one case the unpredictable actor is a language model. In the other it is a person.

## How the three fit together

They are not alternatives. They cover different moments:

| | When it runs | What it does on failure |
|---|---|---|
| **Eval** | In the test suite, over many cases | Reports a score; tells you the system regressed |
| **Guardrail** | In the path, on one output | Blocks that output |
| **Hook** | On an event | Fires the guardrail so nobody has to remember to |

A useful way to hold it: the eval tells you whether the system is good, the guardrail
keeps a bad instance from escaping, and the hook makes sure the guardrail actually runs.
