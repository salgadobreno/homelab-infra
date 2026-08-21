# Queue

Topics marked as worth understanding. Nothing here has been worked through; these are
placeholders so they are not forgotten, not summaries.

When one is expanded it becomes a file under the relevant subject folder, at whatever
depth fits, and leaves this list.

Short entries that may or may not be expanded. Nothing here has been worked through.

- `[open]` **kubeconfig structure** — clusters, contexts, users, and why they are three
  separate things rather than one.
- `[open]` **Thin provisioning** — the node claims 20 GiB from a 130 GiB pool that could
  be oversubscribed. What happens at 100%, and why it belongs in monitoring.
- `[open]` **Idempotence** — why `apply` twice is safe, and what "no drift" is really
  asserting when `make check-drift` passes.
- `[open]` **Reading a tool to find out what it does** — the provider links an SFTP
  library, so I concluded snippet uploads were SFTP. `source_raw` pipes through `tee`
  instead. What a dependency proves versus what a code path does, and why the check I
  wrote agreed with my error rather than catching it.
- `[open]` **PVE cleans up a volume's parent directory** — `free_image` calls `rmdir` on
  the parent after deleting a volume. Harmless for `images/<vmid>/`, and it silently
  reverted the snippet directory's ownership on every destroy.
- `[open]` **`make -n` is not always a dry run** — a recipe line containing `$(MAKE)`
  executes regardless, so make can propagate `-n` into sub-makes. It destroyed a live
  cluster.
