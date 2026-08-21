# Untrusted command output is untrusted input

`[hit]` · 2026-08-20

The Makefile read the node address with `$(shell tofu output -raw node_address)`.
With no outputs defined yet, `tofu` printed a *warning* on stdout, and that warning
text contains `` `tofu refresh` `` in backticks — which the shell then executed. The
first `make help` hung for two minutes running a refresh nobody asked for.

Fundamental: text from a tool is data, not code. It is now filtered through a strict
IP match before use. This is the same class of bug as shell injection, arriving from
an unexpected direction.
