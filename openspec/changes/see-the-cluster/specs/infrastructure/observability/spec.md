## Purpose

The cluster and the hypervisor under it can be watched from outside the cluster, with a
history that outlives any rebuild, so the operator answers "what is it doing, and what was
it doing" by looking rather than by running commands.

## ADDED Requirements

### Requirement: The cluster reports its state to a store outside it

The system SHALL send node metrics, Kubernetes object state, reconciler metrics and
workload logs to a telemetry store that does not run in the cluster.

#### Scenario: The operator sees the cluster without a command

- **WHEN** the operator opens the telemetry backend
- **THEN** node CPU, memory and disk for every cluster node SHALL be visible
- **AND** every workload's pods, restarts and resource use SHALL be visible
- **AND** the reconciler's sync and health state SHALL be visible
- **AND** the logs of the site's pods SHALL be searchable
- **AND** the operator SHALL NOT have run a command against the cluster to see any of it

### Requirement: The hypervisor is observed without running anything on it

The system SHALL report the hypervisor's CPU, memory, storage and per-VM resource use,
and SHALL NOT install an agent or open a listening port on the hypervisor to do so.

#### Scenario: Hypervisor state is visible

- **WHEN** the operator opens the telemetry backend
- **THEN** the hypervisor's CPU, memory and storage use SHALL be visible
- **AND** each VM's resource use SHALL be visible

#### Scenario: The hypervisor still serves nothing

- **WHEN** the routine check suite runs after this capability is in place
- **THEN** the assertion that the hypervisor serves no HTTP SHALL still pass

### Requirement: History survives a rebuild

The system SHALL keep telemetry recorded before a cluster rebuild, and SHALL resume
reporting after it without operator steps.

#### Scenario: A rebuild is a gap, not an erasure

- **WHEN** the operator destroys and rebuilds the cluster
- **THEN** telemetry from before the rebuild SHALL still be queryable
- **AND** the rebuild SHALL be visible as a gap followed by the node returning
- **AND** reporting SHALL resume without any command beyond the rebuild itself

This is the demonstration. The rebuild has been the acceptance test of every rung since
M1; this one makes it visible.

### Requirement: Telemetry volume stays inside a stated budget

The system SHALL keep the number of metric series the backend bills for under a budget
written in the repository, counting both how many series exist and how often each is
sent, and SHALL drop series outside it at the source rather than at the store.

#### Scenario: The series count is within budget

- **WHEN** the operator reads the active series count and the data points per minute
  from the telemetry backend
- **THEN** both SHALL be below the budget recorded in the repository

### Requirement: Arrival is checked, not assumed

The system SHALL provide a check that fails when a cluster node has not delivered
telemetry recently, and that check SHALL be part of the routine check suite.

#### Scenario: Silence fails the check

- **WHEN** the telemetry agent is stopped and the check runs after the freshness window
- **THEN** the check SHALL fail
- **AND** the failure SHALL name the node that went silent

#### Scenario: A rebuilt cluster passes without intervention

- **WHEN** the check runs after a rebuild has completed and the freshness window has
  passed
- **THEN** it SHALL pass
