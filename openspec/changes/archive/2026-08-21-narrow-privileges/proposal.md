# Narrow standing privileges

## Why

Three credentials in this system are wider than the job they do, and all three were
recorded as deliberate shortcuts with a milestone attached. This is that milestone.

- The Proxmox API token belongs to `root@pam` with privilege separation off. It can do
  anything the root account can, including destroying every VM on the host, and it sits
  in a file OpenTofu reads on every plan.
- `cloudflared` runs as root and takes its tunnel token as a command-line argument.
  Verified on 2026-08-21: `/proc/<pid>/cmdline` is readable by uid 1000, so any local
  shell can read the token. A tunnel token is the credential for running a connector —
  someone holding it can attach their own connector to the tunnel, and Cloudflare
  balances traffic across connectors, so they receive a share of real requests.
- The Proxmox host accepts key-based root SSH, added so the provider could upload
  cloud-init snippets to a root-owned directory.

None of these is an emergency. The API has no inbound exposure, the tunnel is
outbound-only, and this is a single-operator LAN. They matter because the standing
privilege is unnecessary in every case, and because "what does this credential actually
need to do" is the question the operator should be able to answer out loud.

## What changes

- A `terraform@pve` user with a custom role holding only the privileges the provider
  uses, replacing the `root@pam` token.
- `cloudflared` running as a dedicated unprivileged user, reading its token from a
  credentials file at mode 600 rather than from `argv`.
- Snippet uploads over SSH as a non-root user with write access to the snippet
  directory, so key-based root SSH can be withdrawn.
- A `make check-privileges` target that asserts all of the above, so the property is
  verified rather than remembered.

## Out of scope

- A secrets manager (Vault, SOPS, sealed-secrets). Credentials stay in gitignored files
  on the host. Managing the *storage* of secrets is a different problem from narrowing
  *what they can do*, and mixing them makes both harder to explain.
- Cloudflare Access policies and tunnel ingress rules. Worth auditing, but that is
  configuration in Cloudflare's dashboard rather than in this repository, and it belongs
  with the ingress milestone.
- Rotating the existing credentials. Replacement supersedes rotation here.
- The Samba and rpcbind services listening on all interfaces. Real, unrelated to
  credentials, and pre-existing.

## Pinned decisions

- **Replace, do not rotate.** Each credential is superseded by a narrower one and the
  old one is deleted.
- **Verify by demonstration, not by inspection.** Every claim ends in a command that
  passes or fails, including a negative test: the scoped token must be shown to be
  *unable* to do something the root token could.
- **Do not touch the live tunnel until the cluster work is stable.** The tunnel is the
  only thing currently serving the internet.
- **The cluster must rebuild unattended afterwards.** If narrowing a privilege breaks
  `make rebuild CONFIRM=yes`, the narrowing is wrong, not the rebuild.

## Capabilities

- `infrastructure/credential-scoping` — credentials hold only the privileges their job
  requires, and that property is verifiable.

## Impact

- `tofu/terraform.tfvars`, `scripts/create-proxmox-token.sh`, the provider `ssh` block
- The `cloudflared` systemd unit on the host
- `Makefile` — a new `check-privileges` target
- `README.md` and `CLAUDE.md` — three entries move from "known shortcuts" to "done"
