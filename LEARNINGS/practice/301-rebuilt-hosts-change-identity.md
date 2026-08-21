# Rebuilt hosts change identity, and tooling must expect it

`[hit]` · 2026-08-21

A `make rebuild` target destroyed the VM, recreated it, then polled over SSH until the
node reported ready. It hung until the ten-minute timeout killed it.

The rebuild had actually worked. The node was up, k3s was `Ready`, and the readiness
marker had been written 45 seconds after boot. What failed was the polling:

```
WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!
Offending ECDSA key in /home/buzaga/.ssh/known_hosts:147
```

A fresh VM generates fresh SSH host keys. The address was unchanged, so `known_hosts`
still held the old machine's key for `192.168.0.30`, and SSH refused to connect. The
loop could never succeed.

**`StrictHostKeyChecking=accept-new` does not cover this.** It accepts hosts it has
never seen. A host whose key has *changed* is precisely the case it is designed to
refuse, because that is what a machine-in-the-middle looks like.

Fundamental: destroying and recreating a machine changes its identity even when its
address does not. Anything automated that connects to it has to be told the change was
legitimate. The fix belongs in the tool that caused the change:

```make
$(TOFU) -chdir=$(TF_DIR) apply -auto-approve && \
{ ssh-keygen -f "$$HOME/.ssh/known_hosts" -R $(NODE_IP) >/dev/null 2>&1 || true; } && \
until ssh ... 'test -f /run/cloud-init-k3s-complete'; do sleep 5; done
```

Two things worth carrying beyond this bug.

**Blanket-disabling host key checking is the wrong fix.** `StrictHostKeyChecking=no`
would have made the symptom disappear and thrown away the protection permanently.
Removing the specific key, at the moment the tool knowingly replaced that host, keeps
verification intact everywhere else.

**The braces are load-bearing.** `ssh-keygen -R` exits non-zero when there is no entry
to remove, so it needs tolerating — but writing it as `ssh-keygen ... ;` breaks the
`&&` chain, and the wait loop would then run even if `apply` had failed, hanging forever
on a node that was never created. `{ ...; || true; } && ...` tolerates the exit code
without severing the chain.
