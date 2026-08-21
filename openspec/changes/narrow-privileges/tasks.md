# Tasks

Ordered by blast radius, least first (design D5). Each group ends in something
demonstrable. The tunnel changes last because it is the only thing currently serving
the internet.

## 1. Establish the baseline

- [x] 1.1 Record today's privilege state as evidence: token user and privsep flag, `cloudflared` owning user, whether `/proc/<pid>/cmdline` leaks the tunnel token, and whether root SSH is accepted
- [x] 1.2 Confirm `make rebuild CONFIRM=yes` passes before anything is narrowed — this is the acceptance test for every step that follows, and it must be known-good first

## 2. A scoped Proxmox role

- [ ] 2.1 Derive the privileges `bpg/proxmox` actually exercises for this configuration (design Open Question 1) — start from VM create/destroy, disk allocation on `local-lvm`, and file upload to `local`
- [ ] 2.2 Create a custom role holding exactly those privileges, named so its purpose is obvious
- [ ] 2.3 Create a `terraform@pve` user, assign the role at the narrowest workable path, and issue a token with **privilege separation on** (design D2)
- [ ] 2.4 Extend `scripts/create-proxmox-token.sh` to create the scoped user and role rather than a `root@pam` token, keeping it re-runnable
- [ ] 2.5 Swap `terraform.tfvars` to the new token and confirm `tofu plan` authenticates

## 3. Prove the scope is real

- [ ] 3.1 Run `make rebuild CONFIRM=yes` on the scoped token; it must complete unattended — `credential-scoping` "Provisioning succeeds with the scoped credential"
- [ ] 3.2 Attempt an action outside provisioning with the scoped token — creating a host user, altering storage configuration — and record the refusal — `credential-scoping` "The scoped credential cannot exceed its purpose"
- [ ] 3.3 Delete the `root@pam!tofu` token and confirm provisioning still works, so the old credential is gone rather than merely unused

## 4. A non-root snippet upload account

- [ ] 4.1 Determine whether the provider needs root over SSH for anything beyond writing the snippet directory (design Open Question 2)
- [ ] 4.2 Create a dedicated account owning `/var/lib/vz/snippets`, and point the provider's `ssh` block at it
- [ ] 4.3 If 4.1 found a root-requiring operation, add a sudoers entry for that command alone — never a blanket rule
- [ ] 4.4 Rebuild to confirm snippet upload works as the new account

## 5. Withdraw root SSH

- [ ] 5.1 Set `PermitRootLogin no` and reload sshd — the operator has console access if this goes wrong
- [ ] 5.2 Confirm root SSH is refused — `credential-scoping` "Administrative remote access is withdrawn once unnecessary"
- [ ] 5.3 Rebuild once more to confirm provisioning is unaffected
- [ ] 5.4 Remove the root entry from `/root/.ssh/authorized_keys`, so withdrawal is not just a toggle

## 6. The tunnel

- [ ] 6.1 Create a dedicated unprivileged `cloudflared` account
- [ ] 6.2 Move the tunnel token into an `EnvironmentFile` at mode 600 owned by that account, and remove it from `ExecStart` (design D3, Open Question 3)
- [ ] 6.3 Run the service as that account; confirm the tunnel reconnects and the site still serves
- [ ] 6.4 Confirm an unprivileged user can no longer recover the token from `cmdline` or `environ` — `credential-scoping` "A local user cannot read a service credential"
- [ ] 6.5 Confirm the account is not root and holds no password-less escalation — `credential-scoping` "A service compromise does not yield host administration"

## 7. Make it verifiable

- [ ] 7.1 Add `make check-privileges` asserting: token user is not root, privsep is on, no credential in `cmdline` or `environ`, `cloudflared` is not root, root SSH refused
- [ ] 7.2 Confirm it fails when a property is deliberately regressed — a check never seen to fail is not a check — `credential-scoping` "A regression is caught by the check"
- [ ] 7.3 Wire it into `make check`

## 8. Close the record

- [ ] 8.1 Move the three entries out of "Known shortcuts" in `CLAUDE.md` and `README.md`, stating what replaced each
- [ ] 8.2 Record in `LEARNINGS/` what the scoped role actually needed versus what was guessed — the gap is the interesting part
- [ ] 8.3 Update `openspec/config.yaml`: secrets are no longer unmanaged
