# A saved plan is bound to a specific state, not just to the config

`[hit]` · 2026-08-20

`tofu apply tfplan` failed with "Saved plan is stale". The config had not changed —
the *state* had, because `apply` refreshes before it acts and that bumped the serial
from 3 to 4.

Fundamental: a plan file is a promise about a known world. Terraform records which
state version it was computed against and refuses to apply against a different one.
That is what stops an hour-old plan from deleting something created since.
