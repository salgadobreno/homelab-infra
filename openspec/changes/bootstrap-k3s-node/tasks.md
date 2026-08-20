## 1. Toolchain

- [x] 1.1 Install OpenTofu on the Proxmox host and confirm `tofu version` runs (see design D1; Terraform is an acceptable substitute)
- [x] 1.2 Install `kubectl` and confirm `kubectl version --client` runs
- [x] 1.3 Add both to `homelab1/scripts/bootstrap.sh` or an equivalent script in this repo, so the toolchain is reproducible rather than ad hoc
- [x] 1.4 Create the repository skeleton from design D9: `tofu/` with empty `main.tf`, `variables.tf`, `outputs.tf`
- [x] 1.5 Add `.gitignore` covering `*.tfstate*`, `.terraform/`, `terraform.tfvars`, `*.kubeconfig`, and SSH private keys — before any credential exists on disk

## 2. Proxmox API access

- [x] 2.1 Create a `root@pam` API token in the Proxmox UI (design D4 — deliberately over-privileged, scoped later)
- [x] 2.2 Record the token in a gitignored `terraform.tfvars`, and commit a `terraform.tfvars.example` showing the shape without values
- [x] 2.3 Confirm the token works with a plain `curl` against the Proxmox API before involving Terraform — isolates auth failures from provider failures
- [x] 2.4 Verify `git status` shows no credential-bearing file as tracked or untracked-but-stageable

## 3. Provider wiring

- [x] 3.1 Declare the `bpg/proxmox` provider in `main.tf` with a pinned version constraint
- [x] 3.2 Declare variables for endpoint, API token, node name, and TLS verification behaviour
- [x] 3.3 Run `tofu init` and confirm the provider downloads
- [x] 3.4 Run `tofu plan` against empty configuration and confirm it authenticates with no errors — **this closes milestone 0**

## 4. Cloud image

- [ ] 4.1 Choose the Ubuntu LTS release (design Open Question 1) and record the choice and its reason in `variables.tf`
- [ ] 4.2 Declare a downloaded-file resource pulling the cloud image to Proxmox storage, pinning URL and checksum
- [ ] 4.3 Apply and confirm the image lands in Proxmox storage; if the storage rejects the content type, enable it and note the fix (design Open Question 2)

## 5. Cloud-init

- [ ] 5.1 Write `cloud-init.yaml`: set hostname, create the operator user, install the declared SSH public key
- [ ] 5.1a Configure the static address, gateway `192.168.0.1`, and a DNS server in cloud-init network config (design D7)
- [ ] 5.2 Add `qemu-guest-agent` installation and enablement in `runcmd` — for graceful shutdown and Proxmox UI integration; nothing depends on it for addressing
- [ ] 5.3 Add the k3s installation command to `runcmd` (design D6), keeping the block short enough to read at a glance
- [ ] 5.4 Wire the cloud-init file into the VM resource as a user-data file resource

## 6. The VM

- [ ] 6.1 Record the D7 address plan in `variables.tf` — node addresses, the reserved MetalLB range, and the `.100` DHCP boundary — as the single source of truth
- [ ] 6.1a `ping 192.168.0.30` and confirm nothing answers before claiming the address
- [ ] 6.2 Declare the VM resource: 6 GiB RAM, 4 vCPU, 20 GiB thin disk on `local-lvm` (NVMe — design D10, never the HDD), attached to `vmbr0`, static address `192.168.0.30`
- [ ] 6.3 Run `tofu plan`, read it line by line, and confirm it creates exactly what is intended before applying
- [ ] 6.4 Run `tofu apply` and wait for the VM to boot
- [ ] 6.5 SSH into the VM using the declared key, with no password prompt — satisfies `vm-provisioning` scenario "Operator access after creation"

## 7. Cluster access

- [ ] 7.1 Confirm cloud-init finished cleanly by reading `/var/log/cloud-init-output.log` on the node — do not infer success from the VM being up (design risk table)
- [ ] 7.2 Confirm `k3s` is running and `kubectl get nodes` on the node reports `Ready`
- [ ] 7.3 Add an output exposing the node's declared address
- [ ] 7.4 Template the node's kubeconfig with that address substituted for `127.0.0.1`, written to a gitignored path on the host
- [ ] 7.4a Pass the node address to k3s as a TLS SAN so the served certificate matches the address `kubectl` connects to
- [ ] 7.5 Run `kubectl get nodes` from the Proxmox host using that kubeconfig and see `Ready` — **this closes milestone 1**

## 8. Verify against the specs

- [ ] 8.1 Run `tofu plan` with no changes and confirm it reports no drift — `vm-provisioning`, "Configuration matches reality"
- [ ] 8.2 Deploy a throwaway workload and confirm it reaches running state — `k3s-cluster`, "Workloads can be scheduled"
- [ ] 8.3 Reboot the node; confirm k3s and the workload return unattended — `k3s-cluster`, "Cluster survives node reboot"
- [ ] 8.4 Check host free memory with the cluster idle and confirm the Proxmox UI stays responsive — `k3s-cluster`, "Host remains functional under cluster load"
- [ ] 8.5 Grep the repository for the API token value and confirm no match — `vm-provisioning`, "Repository contains no secrets"
- [ ] 8.6 Confirm the node's disk resides on the NVMe thin pool and not on `/mnt/sda8` — `lsblk` on the host, or Proxmox UI storage view (design D10)
- [ ] 8.7 Confirm every allocated address sits below `.100` and is stated in configuration — `vm-provisioning`, "Address plan is discoverable" and "No overlap with dynamic allocation"

## 9. Make it reproducible

- [ ] 9.1 Run `tofu destroy` and confirm the VM and its disk are gone from Proxmox
- [ ] 9.2 Run `tofu apply` again and confirm a `Ready` cluster returns with zero manual steps — `vm-provisioning` "Rebuild after teardown" and `k3s-cluster` "Cluster is rebuilt from scratch"
- [ ] 9.2a Confirm the rebuilt node came back on `192.168.0.30` and that the pre-existing kubeconfig still works untouched — `vm-provisioning` "Address survives destroy and recreate", `k3s-cluster` "Credentials remain valid across a rebuild"
- [ ] 9.3 Time that rebuild and record the number in the README — it is the milestone-4 demo, and it is worth having early
- [ ] 9.4 Write the README: architecture sketch, how to apply, and why remote state and a scoped API role were deliberately deferred (design D4, D8)
- [ ] 9.5 Push to GitHub — ArgoCD needs the repository reachable in the next milestone but two
