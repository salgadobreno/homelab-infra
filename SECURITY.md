# Security posture

How administrative access to the hypervisor is gated, and which weaknesses are known and
accepted. This file is public. It therefore describes shapes rather than values — the
same boundary `scripts/disclosure-rules` draws for anything served from `k8s/site/`.

## What gates the host

Two independent credentials, in series:

| Layer | Gates | Credential |
|---|---|---|
| Cloudflare Access | the network path to the tunnel hostname | an identity — one-time PIN to one of two external mailboxes |
| OpenSSH | the account | a private key in `authorized_keys` |

Neither alone gets in. A stolen laptop key is useless without the Access identity, and an
Access session still meets `PasswordAuthentication no`.

**This is defence in depth, not two-factor authentication.** The distinction matters:
2FA means two factors proving one identity in a single login, and an attacker who
compromises the operator's mailbox has passed the Access layer completely. For true MFA,
raise it at the identity provider behind Access — Access's own one-time PIN is
email-possession only. Recorded so the table above is not mistaken for more than it is.

Access sessions last 24 hours, after which the browser login repeats per device.

## What the tunnel does and does not do

`cloudflared` dials outbound to Cloudflare's edge. That genuinely buys:

- **no inbound ports** — no router forward, nothing to find by scanning the WAN address
- **origin IP hiding** — the hostname resolves to Cloudflare anycast addresses
- **DDoS absorption** and encrypted edge-to-origin transport

It does **not** buy authorisation. A tunnel is a transport. A public hostname on a tunnel
is public: the edge accepts a connection from anyone and pipes it to the origin service
without asking who they are. Until an Access policy was attached, an unauthenticated
`curl` against the SSH hostname returned the origin's SSH banner — from anywhere on the
internet, complete with the exact OpenSSH and Debian build string.

Read that as the general rule: **reachability is not authorisation.** Access is what
supplies the second half.

## Why `fail2ban` is deliberately absent

Considered and rejected, for different reasons on each of the two paths into `sshd`.

**Through the tunnel, it is blind.** Every connection `cloudflared` makes arrives from
`127.0.0.1`, so there is no client address to ban. `fail2ban` ships with
`ignoreip = 127.0.0.1/8 ::1`, so by default it would ignore tunnel traffic entirely — no
benefit, no harm. Removing that default to make it "work" is worse than leaving it: an
attacker past Access could deliberately fail authentication until `127.0.0.1` is banned,
severing the tunnel for everyone including the operator. Inert, or a self-inflicted
denial of service. Never a gain.

**On the LAN, it sees real addresses but guards nothing.** With
`PasswordAuthentication no` there is nothing to guess: a client without a private key is
refused indefinitely, and the ten-thousandth attempt fails exactly as the first did.
`fail2ban` exists to stop password brute-force; against key-only authentication it blocks
attacks that cannot succeed. Against that near-zero benefit stands a real cost — the LAN
address is the only non-tunnel path in, so a ban triggered by a stale agent or a wrong
key locks the operator out of the rescue path, leaving the Proxmox console.

**The throttles that matter are already in `sshd_config`:** `MaxAuthTries 3` caps attempts
per connection, `LoginGraceTime 30` caps how long an unauthenticated connection may
linger, and the default `MaxStartups 10:30:100` sheds new unauthenticated connections
past ten concurrent.

The structural point: moving to a tunnel did not delete the IP-based control, it
**relocated** it. Cloudflare's edge still sees the real client address and can rate limit
there. `fail2ban` would be a second, blinder copy of a control that already exists,
installed where it cannot see.

Revisit this if password authentication is ever re-enabled, or if `sshd` is exposed
directly to the internet again. Neither is true today.

**What the `127.0.0.1` source address does cost is the audit trail.** `sshd` therefore
runs at `LogLevel VERBOSE`, which records the fingerprint of the key that authenticated.
That fingerprint is the only per-device attribution left.

**The residual risk `fail2ban` would not have covered** is a pre-authentication `sshd`
vulnerability, reachable by anyone who gets past Access. Patching addresses that; banning
addresses does not. Automatic security updates are the control that belongs here.

## What deliberately stays out of this repository

Two values live in `local.mk`, which `.gitignore` covers; `local.mk.example` carries
placeholders for both.

**The tunnel's SSH hostname.** It is deliberately unguessable, and the wildcard
certificate Cloudflare serves means it does not appear in Certificate Transparency
logs — so the name is not discoverable by the usual passive route.

That is worth something only while it stays unpublished. **Committing it to this public
repository would void it entirely.** The LAN address and SSH port in the `Makefile` are
RFC1918 and stay there; an internet-reachable name is a different class of value.

**The authorised-key fingerprints.** `SSH_KEEP_FINGERPRINTS` is the allow-list
`scripts/prune-authorized-keys.sh` enforces. These are not secret — a fingerprint is a
hash of a public key, and GitHub publishes its users' public keys outright — but an
inventory of exactly which devices hold access to the hypervisor is a shape worth not
publishing, on the same principle the disclosure boundary applies to the served site.

Obscurity is not a control, and none of the above is load-bearing. Access is.

## `sshd`

Applied by `scripts/harden-sshd.sh` and `scripts/harden-sshd-listen.sh`; asserted by
`make check-root-ssh` and `make check-tunnel-ssh`.

- `PermitRootLogin no`, and root holds no authorised keys
- `PasswordAuthentication no` with `KbdInteractiveAuthentication no` beside it — the
  latter matters because `UsePAM yes` can otherwise still collect a password
- non-default port, and no `Match` block re-enabling passwords for the LAN
- `ListenAddress` limited to loopback, the LAN address, and `::1` — the wildcard listener
  is gone, so nothing answers a router forward that may still exist
- `AllowUsers` limited to the operator and the snippet-upload account
- `X11Forwarding`, `AllowAgentForwarding` and `PermitTunnel` off; `MaxAuthTries 3`,
  `LoginGraceTime 30`

Left enabled on purpose: `AllowTcpForwarding`, because `ssh -L` to the Proxmox UI needs
it, and the `ClientAlive` pair, whose generous tolerance is what keeps a session alive
over a mobile tunnel.

`sshd_config` has no `Include` line, so `/etc/ssh/sshd_config.d/` is **not read**. A
drop-in placed there is silently ignored. Edit the main file, as both scripts do.

`ListenAddress` naming a fixed LAN address means `sshd` cannot bind if that address ever
changes. `systemctl reload` sends SIGHUP, on which `sshd` re-executes itself and re-binds
immediately — established sessions survive as separate processes, but a failed bind means
no *new* connection succeeds. `harden-sshd-listen.sh` checks the address is present
before writing; the Proxmox console is the backstop.

## Authorised keys

`authorized_keys` holds exactly the devices in use. `scripts/prune-authorized-keys.sh`
enforces this by **fingerprint allow-list**, not by removing known-bad entries: a key
reinstalled from another machine returns with a different comment, and a deny-list of
today's comments would silently re-admit it. The list itself is `SSH_KEEP_FINGERPRINTS`
in `local.mk`.

Because the list is an allow-list, add a device's fingerprint *before* installing its
key, or the next run removes it. The script refuses to act on a missing, empty, or
malformed list rather than treating "matches nothing" as "remove everything".

The list previously accumulated ten keys, including two former colleagues, a former
employer, a retired laptop, and one exact duplicate. Each was a credential that still
worked from anywhere in the world. Prune when a device is retired, not eventually.

## Keeping the base system patched

Applied by `scripts/setup-unattended-upgrades.sh`; asserted by `make check-updates`.

Access decides *who* may reach `sshd`. It cannot help with a flaw in `sshd` reached
*before* authentication — anyone who passes Access reaches that code, and regreSSHion
(CVE-2024-6387) was exactly that shape. Patching is the control for it. This is also why
`fail2ban` is not a substitute: banning an address does nothing about a vulnerable
binary.

**Only the Debian security origin upgrades unattended.** Four repositories are enabled on
this host, and the rest are excluded on purpose:

| Origin | Unattended | Why |
|---|---|---|
| `Debian-Security` | yes | where `openssh-server` and the base system patch |
| Debian stable / `-updates` | no | point releases and non-security fixes; churn without urgency |
| Proxmox | no | `pve-manager`, QEMU and the kernel ship in one suite with no security-only channel; upgrading them can want a reboot or disturb running VMs |
| Docker, cloudflared | no | third party, no security-only channel, and cloudflared is the path in |

**Nothing reboots automatically.** `Automatic-Reboot` is false, because a reboot here
stops every VM including the node serving the public site. A kernel or libssl update
therefore waits for the operator, and `needrestart` reports what is still running old
code. The trade is deliberate: unattended *patching*, attended *restarting*.

A package blocklist covers `proxmox-ve`, `pve-manager` and the kernel packages as well.
The origin list already excludes them; the blocklist is there so that widening the origins
later does not quietly start upgrading the virtualisation stack.

## Known gaps

Recorded deliberately — do not read these as oversights.

- **The tunnel token has never been rotated** since its storage was hardened, so its value
  is known to anyone who has read it. Rotating is a write to the token file and a restart.
- **A WARP private network would be stronger** than a public hostname plus Access: it
  removes the public DNS record altogether, leaving nothing to scan or guess. Not adopted
  because it requires enrolling WARP on every client including Android. The current design
  trades that for zero client rework.
- **Third-party repositories patch by hand.** Docker and cloudflared ship no
  security-only channel, so their packages upgrade only when the operator runs
  `apt upgrade`. cloudflared is the path in, and changing it unattended is worse than
  the delay.
- **Other services listen on the wildcard** — the Proxmox UI, SMB, rpcbind, and a proxy
  port — and the host has no firewall rules in effect. Whether any is reachable from the
  internet depends on router forwards, which cannot be determined from inside the NAT.
  This is a real gap and is not addressed by anything above, which covers SSH only.

## Verifying

```bash
make check-privileges    # includes check-root-ssh, check-tunnel and check-tunnel-ssh
make check-tunnel-ssh    # the SSH path specifically
```

`check-tunnel-ssh` asserts the three properties that can regress independently: the
hostname does not serve an SSH banner to an unauthenticated request, `sshd` holds no
wildcard listener, and `authorized_keys` matches the allow-list exactly.
