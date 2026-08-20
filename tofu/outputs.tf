# Outputs exist to be consumed, not admired: the Makefile reads node_address so the
# address plan has exactly one home (variables.tf) rather than being repeated in
# tooling. See the NODE_IP definition in the Makefile.

output "node_address" {
  description = "Static address of the k3s server node."
  value       = var.k3s_server_address
}

output "node_name" {
  description = "Hostname of the k3s server node."
  value       = proxmox_virtual_environment_vm.k3s_server.name
}

output "node_vm_id" {
  description = "Proxmox VM ID, for qm/pct commands on the host."
  value       = proxmox_virtual_environment_vm.k3s_server.vm_id
}

output "kubeconfig_hint" {
  description = "How to fetch a usable kubeconfig; k3s writes one pointing at 127.0.0.1, which is useless off-node."
  value       = "make kubeconfig  # rewrites the server address to ${var.k3s_server_address}"
}
