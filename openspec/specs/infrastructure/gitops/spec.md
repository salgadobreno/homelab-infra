# infrastructure/gitops Specification

## Purpose
Cluster state is a consequence of what is committed, not of what was last typed. A
reconciler runs inside the cluster, continuously compares the repository against reality,
and corrects the difference — so the repository is the record of what is deployed rather
than a description of it.

## Requirements

### Requirement: A reconciler runs in the cluster and is itself declared

The system SHALL run a GitOps reconciler inside the cluster, and that reconciler SHALL be
installed by the provisioning layer rather than by hand, so a cluster rebuilt from nothing
arrives with reconciliation already running.

#### Scenario: A rebuilt cluster reconciles without operator steps

- **WHEN** an operator destroys the cluster and rebuilds it
- **THEN** the reconciler SHALL be running without any manual installation step
- **AND** the workloads declared in the repository SHALL be present afterwards
- **AND** the operator SHALL NOT have run a deployment command to make that happen

This is the requirement that distinguishes GitOps from a one-time `kubectl apply`. A
reconciler installed by hand is a pet, and the cluster stops being disposable.

### Requirement: Committed changes reach the cluster without a deployment command

The system SHALL apply a change to the declared workloads as a consequence of that change
being committed and pushed, and SHALL NOT require an operator to run a command against
the cluster to deploy it.

#### Scenario: A change to the site reaches the running cluster

- **WHEN** an operator commits and pushes a change to the declared site content
- **THEN** the reconciler SHALL detect the change
- **AND** the running workload SHALL reflect it
- **AND** the only human action SHALL have been the push

### Requirement: Manual changes to reconciled resources are corrected

The system SHALL treat the repository as authoritative for resources it manages: a change
made directly against the cluster SHALL be reverted rather than preserved.

#### Scenario: An out-of-band edit does not survive

- **WHEN** an operator edits a reconciled resource directly with `kubectl`
- **THEN** the reconciler SHALL restore the state described in the repository
- **AND** the difference SHALL have been visible as drift before it was corrected

Stated as a requirement because it is the property that makes the repository trustworthy,
and the one most likely to be quietly disabled the first time it is inconvenient.
