## Purpose

A running Kubernetes cluster hosted on homelab-provisioned virtual machines, reachable
by the operator, that serves as the deployment target for all homelab workloads once
they are migrated off the hypervisor.

## ADDED Requirements

### Requirement: A provisioned node runs a ready Kubernetes cluster

The system SHALL install and start a Kubernetes distribution on each provisioned
cluster node as part of that node's first boot, with no operator-run installation
steps after provisioning completes.

#### Scenario: Cluster becomes ready unattended

- **WHEN** an operator applies configuration that declares a cluster node
- **AND** the node completes its first boot
- **THEN** a Kubernetes control plane is running on that node
- **AND** the node reports `Ready` status without further operator action

#### Scenario: Workloads can be scheduled

- **WHEN** the cluster reports a ready node
- **AND** an operator submits a workload to the cluster
- **THEN** the workload is scheduled and reaches a running state

#### Scenario: Cluster survives node reboot

- **WHEN** a cluster node is rebooted
- **THEN** the Kubernetes control plane restarts automatically
- **AND** previously scheduled workloads return to a running state

### Requirement: Cluster credentials are delivered to the operator

The system SHALL make the cluster's administrative credentials available to the
operator after provisioning, addressed such that they work from the operator's
workstation rather than only from inside the node.

#### Scenario: Operator gains cluster access

- **WHEN** provisioning completes
- **THEN** the operator obtains a kubeconfig without manually copying files off the node
- **AND** commands issued with that kubeconfig reach the cluster

#### Scenario: Credentials target the node's declared address

- **WHEN** a kubeconfig is delivered to the operator
- **THEN** it targets the node's declared address rather than a loopback address

#### Scenario: Kubeconfig address survives a rebuild

- **WHEN** the cluster is destroyed and recreated from the same configuration
- **THEN** a kubeconfig obtained before the rebuild still names the correct address
- **AND** re-fetching the credentials for that address SHALL require no manual editing

The certificate authority is regenerated on every install, so the client certificate in
an older kubeconfig will not authenticate against the rebuilt cluster. That is a
property of a disposable cluster, not a defect: pinning a CA to make credentials
outlive the thing they authenticate to would work against the design. What the address
plan buys is that recovery is one command with nothing to look up or edit.

#### Scenario: Credentials are excluded from version control

- **WHEN** provisioning writes cluster credentials to disk
- **THEN** the written path is excluded from version control

### Requirement: Cluster membership does not depend on address discovery

The system SHALL configure cluster nodes to reach the control plane at an address known
at configuration time, so that a node rejoining after a reboot or rebuild requires no
lookup or operator intervention.

#### Scenario: Node rejoins unattended after reboot

- **WHEN** a cluster node reboots
- **THEN** it reaches the control plane at its configured address
- **AND** it rejoins the cluster without operator intervention

### Requirement: The cluster is disposable

The system SHALL treat cluster nodes as replaceable. Recovering from a destroyed
cluster SHALL require only re-applying configuration.

#### Scenario: Cluster is rebuilt from scratch

- **WHEN** an operator destroys the cluster and re-applies the same configuration
- **THEN** a ready Kubernetes cluster is available again
- **AND** the operator runs no manual installation or repair steps

### Requirement: Cluster resource footprint is bounded

The cluster SHALL operate within the homelab's documented memory budget, leaving the
Proxmox host and its existing services functional while the cluster runs.

#### Scenario: Host remains functional under cluster load

- **WHEN** the cluster is running and idle
- **THEN** the Proxmox host retains sufficient free memory to keep its web interface and existing services responsive

#### Scenario: Footprint is declared

- **WHEN** an operator inspects the configuration
- **THEN** the memory and CPU allocated to each cluster node is stated explicitly
