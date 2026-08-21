variable "proxmox_endpoint" {
  description = "Proxmox VE API endpoint, including scheme, port and trailing slash."
  type        = string

  validation {
    condition     = can(regex("^https://.+:[0-9]+/$", var.proxmox_endpoint))
    error_message = "Endpoint must look like https://<host>:8006/ (trailing slash required)."
  }
}

variable "proxmox_api_token" {
  description = "API token in the form USER@REALM!TOKENID=SECRET. Supplied via the gitignored terraform.tfvars; never commit a value."
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("^[^@]+@[^!]+![^=]+=.+$", var.proxmox_api_token))
    error_message = "Token must be USER@REALM!TOKENID=SECRET, e.g. root@pam!tofu=<uuid>."
  }
}

variable "proxmox_node" {
  description = "Name of the Proxmox node that hosts the cluster VMs."
  type        = string
}

variable "proxmox_tls_insecure" {
  description = "Skip TLS verification. True because the host serves a self-signed certificate."
  type        = bool
  default     = true
}

# --- Base image -------------------------------------------------------------------
#
# Ubuntu 24.04 LTS (noble) rather than 26.04 (resolute), which is also published. This
# is a learning environment: noble has two years of ecosystem behind it, so k3s
# guidance and error messages match what is documented publicly. 26.04 is four months
# old at time of writing. Supported to 2029, well beyond this project's horizon.
#
# Pinned to a dated build rather than "current" so the base is reproducible; the
# checksum makes a moved or tampered image fail loudly instead of silently changing.

variable "ubuntu_image_url" {
  description = "URL of the Ubuntu cloud image used as the node base image."
  type        = string
  default     = "https://cloud-images.ubuntu.com/releases/noble/release-20260814/ubuntu-24.04-server-cloudimg-amd64.img"
}

variable "ubuntu_image_checksum" {
  description = "SHA256 of ubuntu_image_url, from the build's SHA256SUMS."
  type        = string
  default     = "6e40c07ae715f744f84af0bec76415cc1987dd115b4b8de437818561f01a3733"
}

variable "image_datastore" {
  description = "Datastore holding the downloaded cloud image. 'local' is a dir store advertising the 'import' content type."
  type        = string
  default     = "local"
}

# --- Address plan (design D7) -----------------------------------------------------
#
# The single source of truth for LAN addressing. The router's DHCP pool starts at
# .100; everything this project allocates sits strictly below that boundary, which is
# what makes static addressing safe here. Ranges are declared even when nothing uses
# them yet, so later milestones do not have to re-address a running cluster.
#
#   192.168.0.1       router / gateway
#   192.168.0.21      Proxmox host (existing, not managed here)
#   192.168.0.30-.32  k3s nodes — .30 server, .31/.32 agents at M5
#   192.168.0.40-.50  reserved for MetalLB LoadBalancer addresses (M7)
#   192.168.0.100+    DHCP pool — never allocated by this project

variable "network_gateway" {
  description = "LAN default gateway."
  type        = string
  default     = "192.168.0.1"
}

variable "network_cidr_bits" {
  description = "Prefix length of the LAN subnet."
  type        = number
  default     = 24
}

variable "network_dns_servers" {
  description = "Resolvers for cluster nodes. Public rather than local: the LAN runs no DNS service, which is also why addressing is static (design D7)."
  type        = list(string)
  default     = ["8.8.8.8", "1.1.1.1"]
}

variable "k3s_server_address" {
  description = "Static address of the k3s server node. Known at plan time so the kubeconfig can be rewritten without waiting on the guest agent (design D7)."
  type        = string
  default     = "192.168.0.30"

  validation {
    condition     = can(regex("^192\\.168\\.0\\.(3[0-2])$", var.k3s_server_address))
    error_message = "Server address must be within the .30-.32 node range of the D7 address plan."
  }
}

variable "metallb_address_range" {
  description = "Reserved for LoadBalancer addresses at M7. Carved out now, while free, so the cluster is not re-addressed later. Unused by this change."
  type        = string
  default     = "192.168.0.40-192.168.0.50"
}

# --- Node -------------------------------------------------------------------------

variable "node_hostname" {
  description = "Hostname of the k3s server node."
  type        = string
  default     = "k3s-server-1"
}

variable "operator_user" {
  description = "Unprivileged account created by cloud-init for operator SSH access."
  type        = string
  default     = "buzaga"
}

variable "operator_ssh_public_key_path" {
  description = "Path to the public key installed on the node. A path rather than the key itself so nothing identifying is committed, while a fresh clone still reproduces the build."
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "node_vcpu" {
  description = "vCPU count for the server node."
  type        = number
  default     = 4
}

variable "node_memory_mib" {
  description = "RAM for the server node, in MiB."
  type        = number
  default     = 6144
}

variable "node_disk_gib" {
  description = "Thin-provisioned disk size for the server node, in GiB."
  type        = number
  default     = 20
}

variable "vm_datastore" {
  description = "Datastore for VM disks. Must be the NVMe thin pool: the k8s datastore is fsync-latency-bound and the HDD cannot meet it (design D10)."
  type        = string
  default     = "local-lvm"
}

variable "network_bridge" {
  description = "Proxmox bridge the node attaches to."
  type        = string
  default     = "vmbr0"
}

variable "k3s_version" {
  description = "k3s release installed by cloud-init. Pinned rather than tracking 'stable' so a rebuild produces the same cluster; matches the kubectl version pinned in scripts/bootstrap.sh, keeping client and server free of version skew."
  type        = string
  default     = "v1.36.3+k3s1"
}

variable "snippet_datastore" {
  description = "Datastore holding the cloud-init snippet. Must advertise the 'snippets' content type; see README for enabling it."
  type        = string
  default     = "local"
}

# --- Host SSH (snippet uploads only) ----------------------------------------------

variable "proxmox_node_address" {
  description = "Address the provider opens SSH to for snippet uploads. Separate from proxmox_endpoint because the API and SSH run on different ports."
  type        = string
  default     = "192.168.0.21"
}

variable "proxmox_ssh_port" {
  description = "SSH port on the Proxmox host. Non-default: sshd is hardened onto 4444."
  type        = number
  default     = 4444
}

variable "proxmox_ssh_username" {
  description = "SSH user for snippet uploads. An unprivileged account owning /var/lib/vz/snippets — the provider writes the cloud-init file over SFTP and needs nothing else on the host. Created by scripts/create-snippet-user.sh."
  type        = string
  default     = "tofu-snippets"
}

variable "argocd_chart_version" {
  description = "argo-cd Helm chart version installed by k3s at boot. Pinned so a rebuild produces the same cluster; chart 10.3.3 is ArgoCD v3.5.1."
  type        = string
  default     = "10.3.3"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.argocd_chart_version))
    error_message = "Pin an exact chart version, e.g. 10.3.3 — a range or empty value makes each rebuild a different cluster."
  }
}

variable "k3s_disable" {
  description = <<-EOT
    k3s bundled components to disable at install time, e.g. ["servicelb", "traefik"].

    These are startup flags, so they live in the provisioning layer and only take
    effect on a rebuild — a running cluster cannot be corrected from inside by GitOps.
    Relevant at M7: klipper-lb (servicelb) already claims Service type=LoadBalancer,
    so MetalLB needs "servicelb" listed here or two controllers answer for the same
    resource. Empty by default, which keeps k3s's own defaults.
  EOT
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for c in var.k3s_disable :
      contains(["coredns", "servicelb", "traefik", "local-storage", "metrics-server"], c)
    ])
    error_message = "Only k3s's own bundled components can be disabled: coredns, servicelb, traefik, local-storage, metrics-server."
  }
}
