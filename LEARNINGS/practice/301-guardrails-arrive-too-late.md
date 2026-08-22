# Every guardrail here is placed after the damage

`[hit]` · 2026-08-22

Noticed while designing the disclosure check for `show-the-machine`, and it turned out
not to be about that check.

## The observation

This repository has unusually good *detective* controls. `make check` asserts privilege
scoping, secret storage, what the site serves, and that the hypervisor has not started
serving again. Each one was written after something went wrong, and each is a real
assertion rather than a description.

Every one of them runs **after the thing it guards has already happened**, and only if
someone runs it.

There are almost no *preventive* controls. The distinction is the whole note:

- **Detective** — tells you it happened. `make check`.
- **Preventive** — stops it happening. Nothing, mostly.

## Where the rules actually live

The safety rules for this project are prose in `CLAUDE.md`:

> Never run `tofu apply`, `tofu destroy`, `kubectl apply` … unless the operator
> explicitly asks for that specific action.

> `tofu/terraform.tfvars` … Nothing else should write it.

> Do not `kubectl apply` anything under `k8s/`.

These are instructions to a nondeterministic actor, holding no force beyond that actor's
compliance. In AI-engineering terms they are **prompt-level guardrails**, the weakest
category there is — they fail exactly when the actor misreads the situation, which is the
only case where a guardrail matters.

Nothing enforces any of them. `.claude/settings.json` contained a permissions allow-list
for seven read-only `tofu` subcommands, and no hooks at all.

## The two that were not hypothetical

**The tunnel token was disclosed.** `systemctl cat cloudflared` was run to inspect the
unit, and it printed the token into the transcript. No rule was broken — the rule about
credentials is about *committing* them. The damage was done at the moment of reading, and
the only remedy is rotation, which was declined. The value is still live and still known.

A `PreToolUse` hook matching commands that read known credential paths could have refused
or redacted it. The check would have been trivial. It sat nowhere, so it sat too late to
exist.

**`make -n rebuild` destroyed the cluster.** The recipe contained `$(MAKE) forget-node-key`,
and make executes recipe lines containing `$(MAKE)` even under `-n`. The safety rule
against `tofu destroy` was in force and was not violated in spirit — the command was
believed to be a dry run.

That is the case prose cannot cover. A rule addressed to intent does not fire when the
intent is correct and the mechanism is not. A hook matching `tofu destroy` on the command
line would have fired regardless of what anyone believed they were running.

## The one that is placed correctly

`.gitignore` covering `*.tfstate`, kubeconfigs and `terraform.tfvars` is the exception,
and it is instructive. It is preventive, fails closed, requires nobody to remember it, and
sits exactly at the boundary it protects. `git check-ignore` verifies it rather than
assuming.

It works because it is bound to the event, not to anyone's intention at the time.

## The uncovering

**Detective controls accumulate naturally and preventive ones do not.** Every check here
was born from a failure — the failure supplies the motivation, and by then you are already
writing something that describes the past. Prevention has to be chosen in advance, against
a failure that has not happened, which is why it is the half that stays empty.

The result is a repository that can prove any property after the fact and stop almost
nothing as it occurs. For a single-operator lab that is a defensible trade for most
things. It is not defensible for the irreversible ones — a disclosed credential and a
destroyed cluster are both past the point of no return by the time `make check` could run.

The rule that falls out: **an irreversible action needs a preventive control; everything
else can be detective.** Sorting the existing rules by that test is a short exercise, and
it puts credential reads, `destroy`, and writes to `terraform.tfvars` in the first group
and nearly everything else in the second.

`show-the-machine` task 2.4 is the first one moved: the disclosure check fires from a
`PostToolUse` hook on writes under `k8s/site/`, rather than waiting for `make check` after
the commit. Publication is irreversible in the same way — the page reaches the public
internet, and a value withdrawn afterwards has still been served.

See also `../ai-engineering/101-evals-and-guardrails.md` for the placement argument in
general, and `../ai-engineering/201-construct-validity.md` for the failure of a check that is
placed correctly and measures the wrong thing.
