# A deeper Proxmox ACL replaces the inherited one, it does not add to it

`[hit]` · 2026-08-21

A scoped provisioning role was granted at `/`, which worked. Adding a second, narrower
grant at `/storage/local` — intending to *add* one privilege there — broke reads that
had been working:

```
before:  GET /nodes/pve/storage/local/content   200
after:   GET /nodes/pve/storage/local/content   403
         Permission check failed (/storage/local, Datastore.Audit|Datastore.AllocateSpace)
```

The grant at `/` carried `Datastore.Audit` and `Datastore.AllocateSpace`. The new grant
at `/storage/local` carried only `Datastore.Allocate`. Proxmox resolves permissions by
the **most specific matching path**, so at `/storage/local` the new entry replaced the
inherited set rather than unioning with it.

The fix is to name every role that must apply at that path:

```
path=/storage/local  roles=TerraformProvisioner,TerraformSnippetStore
```

Fundamental: path-based ACLs in Proxmox are not additive by depth. Adding a privilege
to a sub-path means restating everything that should still apply there. Worth checking
for any permission system before assuming inheritance accumulates — some union, some
override, and the failure mode of guessing wrong is a permission *loss* that looks like
an unrelated bug.

## The other surprise in the same session

Listing snippets requires `Datastore.Allocate`, not `Datastore.Audit`. Proxmox treats
snippet content as privileged because a snippet can contain hook scripts that run on the
host. Without it, the Terraform provider could not see the cloud-init file it had just
written, concluded it was missing, and proposed replacing the VM on every plan — a
permanent, self-inflicted drift.

Granting it at `/storage/local` rather than `/` keeps it from meaning "manage
datastores": creating and deleting datastores is refused at that scope, verified rather
than assumed.
