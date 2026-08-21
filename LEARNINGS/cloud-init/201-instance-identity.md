# cloud-init runs once per instance, and the VM's identity is a file

`[hit]` · 2026-08-21

**Four stages, four systemd units**, ordered by what is available yet:

| Unit | Has | Does |
|---|---|---|
| `cloud-init-local` | no network | finds the datasource, writes network config |
| `cloud-init` | network up | disks, filesystems, growpart |
| `cloud-config` | full config | most config modules |
| `cloud-final` | everything | `runcmd`, user scripts |

`runcmd` lands in the last stage, which is why k3s installs after the network exists
and the filesystem has been grown. `cloud-init status: done` means *cloud-final*
finished — not that anything it started succeeded.

**The datasource here is `NoCloud` on a config-disk**, `/dev/sr0`:

```
/dev/sr0: LABEL="cidata" TYPE="iso9660"
  meta-data  network-config  user-data  vendor-data
```

Proxmox builds that ISO and attaches it as a CD-ROM — the `ide2 = local-lvm:
vm-100-cloudinit,media=cdrom` line in the VM config. The provider's `initialization`
block becomes `network-config`; the snippet becomes `user-data`.

**Identity comes from `instance-id` in `meta-data`.** On boot, cloud-init compares it
against `/var/lib/cloud/data/instance-id`. Differ → new instance, per-instance modules
run. Match → skipped. Here:

```
meta-data:               instance-id: 1ba785bd…
/var/lib/cloud/instance -> /var/lib/cloud/instances/1ba785bd…
```

**This is what separates the reboot test from the rebuild test**, and the difference is
easy to miss:

- **Reboot (8.3).** Same disk, same `instance-id`, so `runcmd` did *not* re-run. k3s
  came back because systemd had enabled the unit — nothing was reinstalled. The test
  proved the OS-level service survives, and nothing about cloud-init.
- **Rebuild (9.2).** New disk, empty `/var/lib/cloud`, so everything ran from scratch.
  Only one instance directory exists on the node, because the previous instance's state
  died with its disk.

The practical consequence: **editing `user-data` on a running VM does nothing.** Without
a new `instance-id`, cloud-init skips per-instance modules on the next boot. That is why
Terraform *replaces* the VM when the snippet changes rather than updating it in place —
and why one trailing space proposed destroying the cluster. Replacement is not the
provider being dramatic; it is the only thing that actually works.
