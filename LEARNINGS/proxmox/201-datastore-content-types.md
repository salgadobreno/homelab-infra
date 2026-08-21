# Proxmox content types are per-datastore opt-ins

`[hit]` · 2026-08-20

Two failures, same root cause. `local` rejected the cloud image until the file was
named `.qcow2`, and rejected the cloud-init snippet until `snippets` was added to its
content list with `pvesm set local --content ...`.

Fundamental: a Proxmox datastore advertises which *kinds* of things it will hold.
Being a directory with free space is not sufficient. `make storage` shows the list.
