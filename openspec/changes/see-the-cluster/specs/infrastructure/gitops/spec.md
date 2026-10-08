## ADDED Requirements

### Requirement: Workloads are declared in Git, not in the bootstrap

The system SHALL declare every reconciled workload as an object in the repository's
reconciled tree, reached from a single bootstrap object, so the provisioning layer holds
exactly one pointer to Git regardless of how many workloads exist.

#### Scenario: Adding a workload does not touch provisioning

- **WHEN** an operator adds a new workload to the cluster
- **THEN** the change SHALL be confined to the reconciled tree
- **AND** no file in the provisioning layer SHALL change
- **AND** the workload SHALL be deployed by the push alone

#### Scenario: A rebuilt cluster arrives with every workload

- **WHEN** an operator destroys and rebuilds the cluster
- **THEN** every workload declared in the reconciled tree SHALL be present afterwards
- **AND** the operator SHALL NOT have registered any of them by hand
