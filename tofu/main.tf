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

  file_name               = "ubuntu-24.04-server-cloudimg-amd64.img"
  overwrite               = false
  overwrite_unmanaged     = true
  decompression_algorithm = null
}
