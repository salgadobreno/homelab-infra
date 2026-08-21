# The dependency graph is inferred from references, not declared

`[hit]` · 2026-08-21

Nothing in `main.tf` says "build the image first". The VM resource merely *mentions*
the other two:

```hcl
import_from       = proxmox_download_file.ubuntu_cloud_image.id
user_data_file_id = proxmox_virtual_environment_file.cloud_init.id
```

Terraform reads those expressions and derives the edges. Confirmed two ways — the graph
has exactly two edges, and the state records the result:

```
proxmox_download_file.ubuntu_cloud_image        depends_on: (none)
proxmox_virtual_environment_file.cloud_init     depends_on: (none)
proxmox_virtual_environment_vm.k3s_server       depends_on: [ubuntu_cloud_image, cloud_init]
```

Three consequences worth carrying:

- **Parallelism is free.** The image download and the snippet upload have no edge
  between them, so Terraform runs them concurrently. The VM waits for both.
- **Destroy walks the graph backwards.** The VM must go before the image it was
  imported from. This is why `tofu destroy` ordering is not simply reverse-of-creation
  by timestamp.
- **`depends_on` is the escape hatch, not the norm.** It exists for dependencies the
  config cannot see — an ordering that only matters because of a side effect. Reaching
  for it when a reference would do hides the relationship from the graph.

The practical skill: reading a plan and predicting what a change drags with it. If a
value feeding `import_from` changes, everything downstream is implicated.
