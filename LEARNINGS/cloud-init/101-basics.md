# cloud-init basics

`[101]` · written to be read cold, no project knowledge assumed

## The problem it solves

A cloud image — Ubuntu's, Debian's, anyone's — is one generic file. The same disk image
boots on every machine. But every machine needs to differ: its own hostname, its own
users, its own SSH keys, its own network address.

You could boot it and configure it by hand. cloud-init does that automatically on first
boot instead. It ships pre-installed in essentially every cloud image, which is why they
are called cloud images.

## How it gets your instructions

cloud-init looks for a **datasource** — somewhere configuration is waiting for it. On AWS
that is a metadata HTTP endpoint. On a local hypervisor it is usually a small virtual CD
attached to the VM. Either way the important file is **`user-data`**, which you write.

## What you write

`user-data` is YAML, and it must start with `#cloud-config`:

```yaml
#cloud-config
hostname: web-01

users:
  - name: alice
    groups: [sudo]
    shell: /bin/bash
    ssh_authorized_keys:
      - ssh-ed25519 AAAAC3Nza...

packages:
  - nginx
  - htop

runcmd:
  - systemctl enable --now nginx
```

That covers most day-to-day use:

| Key | Does |
|---|---|
| `hostname` | sets the hostname |
| `users` | creates accounts and installs their SSH keys |
| `packages` | installs packages |
| `write_files` | drops config files onto disk |
| `runcmd` | runs shell commands, near the end |

`runcmd` is the escape hatch: anything the structured keys cannot express goes there.

## When it runs

Early in the first boot, before you can log in. It is split into stages so things happen
in a sensible order — network configured before anything needs the network, disks
resized before anything writes to them, and `runcmd` last, once everything else is ready.

## Checking it worked

```bash
cloud-init status                     # running / done / error
cat /var/log/cloud-init-output.log    # what your commands printed
```

That log is where to look when a machine came up but something you asked for did not
happen.

## The one rule that surprises people

**cloud-init runs once, on a machine's first boot.** Not on every boot.

Reboot the VM and `runcmd` will not run again. Edit `user-data` on an existing VM and
nothing happens — it already considers that machine configured.

To apply changed `user-data` you build a **new** machine. This is the idea behind
immutable infrastructure: you do not reconfigure servers, you replace them.

*Deeper detail — how "first boot" is actually determined, and why it makes a reboot and a
rebuild test different things — is in
[201 · instance identity](201-instance-identity.md).*
