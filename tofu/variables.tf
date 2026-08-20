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
