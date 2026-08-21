# One character in a rendered file replaced the whole cluster

`[hit]` · 2026-08-21

Adding a `k3s_disable` variable with an empty default should have been a no-op. It was
not: `${disable_flags}` rendered as `""` but left a space before the closing quote, so
the cloud-init file differed by one byte. `make check-drift` reported:

```
Plan: 2 to add, 0 to change, 2 to destroy
  # proxmox_virtual_environment_file.cloud_init must be replaced
  # proxmox_virtual_environment_vm.k3s_server   must be replaced
```

The snippet has no in-place update path, so it is replaced; the VM references it, so
the VM is replaced too. **A trailing space would have destroyed a running cluster.**

Fixed by putting the space *inside* each list element and joining with `""`, so an
empty list renders as the empty string.

Two things generalise. First, the blast radius came from the dependency graph — the
change was to the snippet, but the damage propagated to everything referencing it.
Second, `create_before_destroy` and replacement semantics are worth knowing *before*
a plan proposes destroying something you care about. The plan said so plainly; the
only real risk was not reading it.
