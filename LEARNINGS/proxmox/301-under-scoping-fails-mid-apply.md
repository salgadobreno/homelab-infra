# Under-scoping fails mid-apply, after the destroy has already happened

`[hit]` · 2026-08-21

A scoped provisioning role passed `tofu plan` cleanly, and passed a read-only probe of
every API path the configuration touches. It still failed on the first real rebuild:

```
proxmox_download_file.ubuntu_cloud_image: Creating...
Error: Error initiating file download
  received an HTTP 403 response - Reason: Permission check failed
```

The missing privilege was `Sys.AccessNetwork`. Before downloading an image, the node
queries the source URL for metadata, and *that* call is gated separately from every
storage privilege. Nothing in the plan output hinted at it, because plan never
downloads anything.

**The cost was a destroyed cluster.** `make rebuild` is `destroy && apply`. The destroy
succeeded on the scoped token; the apply died on its second resource. State went from
three managed resources to one, and the cluster stayed down until the privilege was
added and apply re-run.

Two things generalise.

**A plan that succeeds does not prove a credential is sufficient.** Plan performs reads.
Apply performs writes, and some writes reach paths that reads never touch. The only
honest test of a provisioning credential is a full apply — which is exactly why the task
list made an unattended rebuild the acceptance test rather than a passing plan.

**Sequence destructive verification so failure is cheap.** Running `destroy && apply`
as one command means a permission gap discovered during apply leaves nothing running.
Applying into an empty state first, or verifying against a throwaway resource, would
have found the same 403 with nothing torn down. The disposable cluster made this
recoverable in about two minutes; on something that mattered it would not have been.

The underlying error is treating "I derived the privileges carefully" as equivalent to
"I verified them". Under-scoping fails loudly, which is the good property — but *when*
it fails loudly is a choice you make when sequencing the test.
