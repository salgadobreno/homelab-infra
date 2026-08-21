# State is a cache, a ledger, and a liability

`[hit]` · 2026-08-21

`serial` increments on every write. It went 4 → 6 across the failed and successful
applies, and the stale-plan error was exactly this: the plan was computed against one
serial and `apply` found another.

`lineage` is a UUID identifying *this* state's history — `15971339-…` here, identical
in `terraform.tfstate.backup`. It exists so Terraform can refuse to apply a plan
computed against a completely different state file, rather than silently doing damage.

`terraform.tfstate.backup` holds the previous serial (4 while current is 6): a one-step
automatic undo, not a backup strategy.

**The liability part is concrete.** State stores full resource attributes, so the
entire cloud-init body — 1674 characters, SSH public key included — sits in the state
file in plaintext. A public key is harmless. The principle is not: anything a provider
returns lands here, including values declared `sensitive`, which are redacted in *plan
output* but not in state. That is why `*.tfstate` is gitignored, and why remote state
in a real team means an encrypted backend, not just a shared file.

Which also sharpens what `make check-drift` asserts: refresh reality, compare against
state, compare state against config. "No drift" means all three agree — not that
nothing has been touched.
