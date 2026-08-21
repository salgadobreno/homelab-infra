# Static addressing is what made the kubeconfig simple

`[worked]` · 2026-08-20

k3s writes a kubeconfig pointing at `127.0.0.1`, useless off-node, with a certificate
valid only for that name. Because the address was decided at *plan* time rather than
discovered afterwards, `--tls-san 192.168.0.30` could be passed at install, so the
certificate matches the address the kubeconfig will use.

Fundamental: deciding a value up front instead of discovering it removes a whole class
of ordering problems. The alternative — boot, query the guest agent, then rewrite —
makes `apply` depend on the agent reporting in.
