# Root module for the homelab k3s cluster.
#
# Deliberately flat and unmodularised — see design.md D9. Extracting modules belongs to
# the milestone that adds the second and third node, where there is something to
# abstract over.

terraform {
  required_version = ">= 1.6"

  required_providers {
    proxmox = {
      # bpg/proxmox over Telmate/proxmox: actively maintained, and it can download a
      # cloud image itself rather than requiring a hand-built VM template (design D2/D3).
      source = "bpg/proxmox"
      # Pinned to a patch range: this provider is pre-1.0 and minor releases carry
      # breaking changes.
      version = "~> 0.111.0"
    }
  }
}

provider "proxmox" {
  endpoint  = var.proxmox_endpoint
  api_token = var.proxmox_api_token
  insecure  = var.proxmox_tls_insecure

  # Snippet uploads do not go through the API — PVE has no endpoint for the
  # "snippets" content type — so the provider writes them over SSH instead.
  # Only the cloud-init file needs this; everything else uses the API token.
  #
  # `agent = true` reads the key from ssh-agent rather than a path in config,
  # so no private key location is recorded in state or version control. This
  # means tofu must be run from a shell with an agent loaded.
  ssh {
    agent    = true
    username = var.proxmox_ssh_username

    node {
      name    = var.proxmox_node
      address = var.proxmox_node_address
      port    = var.proxmox_ssh_port
    }
  }
}

# Forces the provider to contact the API during plan. Without a data source or resource,
# `tofu plan` succeeds without ever authenticating, which would make task 3.4 prove
# nothing.
data "proxmox_virtual_environment_nodes" "available" {}

# The provider downloads the cloud image directly, so no hand-built VM template is
# needed — design D3. The checksum is verified on download.
resource "proxmox_download_file" "ubuntu_cloud_image" {
  content_type = "import"
  datastore_id = var.image_datastore
  node_name    = var.proxmox_node

  url                = var.ubuntu_image_url
  checksum           = var.ubuntu_image_checksum
  checksum_algorithm = "sha256"

  # Ubuntu publishes this as .img, but the file is QCOW2 and Proxmox\'s "import"

  # content type rejects the .img extension. Renaming on download is both

  # accurate and what PVE accepts.

  file_name               = "ubuntu-24.04-server-cloudimg-amd64.qcow2"
  overwrite               = false
  overwrite_unmanaged     = true
  decompression_algorithm = null
}

# --- Cloud-init -------------------------------------------------------------------
#
# Uploaded as a snippet rather than passed through the provider's `user_account`
# block, because the node needs `runcmd` to install k3s and the structured block
# cannot express that. Requires the datastore to advertise the "snippets" content
# type, which is not on by default.

resource "proxmox_virtual_environment_file" "cloud_init" {
  content_type = "snippets"
  datastore_id = var.snippet_datastore
  node_name    = var.proxmox_node

  source_raw {
    file_name = "${var.node_hostname}-user-data.yaml"
    data = templatefile("${path.module}/cloud-init/user-data.yaml.tftpl", {
      hostname       = var.node_hostname
      operator_user  = var.operator_user
      ssh_public_key = trimspace(file(pathexpand(var.operator_ssh_public_key_path)))
      k3s_version    = var.k3s_version
      node_address   = var.k3s_server_address

      # The ArgoCD manifest is rendered separately and carried in as a string, so
      # cloud-init stays short enough to read at a glance (its own header asks for
      # that) while the manifest stays a real YAML file rather than an escaped blob.
      argocd_manifest = templatefile("${path.module}/cloud-init/argocd.yaml.tftpl", {
        argocd_chart_version = var.argocd_chart_version
        repo_url             = var.gitops_repo_url
        repo_revision        = var.gitops_repo_revision
      })

      # Precomputed here rather than looped inside the template, so the template
      # stays readable YAML and the flag ordering is deterministic.
      # Leading space inside each element, joined with "": an empty list must render
      # as the empty string, not as a trailing space. A one-character difference in the
      # rendered file replaces the snippet, and the VM depends on it.
      disable_flags = join("", [for c in var.k3s_disable : " --disable ${c}"])
    })
  }
}

# --- The node ---------------------------------------------------------------------

resource "proxmox_virtual_environment_vm" "k3s_server" {
  name      = var.node_hostname
  node_name = var.proxmox_node

  # Cloud images boot from a serial console; without this the VM starts but shows
  # nothing in the Proxmox console, which reads as a boot failure.
  serial_device {}

  agent {
    enabled = true
  }

  cpu {
    cores = var.node_vcpu
    # "host" passes the physical CPU's flags through. Safe on a single-node
    # homelab with no live migration, and measurably faster than the default.
    type = "host"
  }

  memory {
    dedicated = var.node_memory_mib
  }

  disk {
    datastore_id = var.vm_datastore
    import_from  = proxmox_download_file.ubuntu_cloud_image.id
    interface    = "scsi0"
    size         = var.node_disk_gib
    discard      = "on"
    ssd          = true
  }

  network_device {
    bridge = var.network_bridge
  }

  operating_system {
    type = "l26"
  }

  initialization {
    datastore_id      = var.vm_datastore
    user_data_file_id = proxmox_virtual_environment_file.cloud_init.id

    # Static addressing, declared here rather than negotiated over DHCP (design D7).
    ip_config {
      ipv4 {
        address = "${var.k3s_server_address}/${var.network_cidr_bits}"
        gateway = var.network_gateway
      }
    }

    dns {
      servers = var.network_dns_servers
    }
  }
}
