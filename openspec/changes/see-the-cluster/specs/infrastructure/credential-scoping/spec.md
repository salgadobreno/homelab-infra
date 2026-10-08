## ADDED Requirements

### Requirement: Observability credentials can read or write telemetry and nothing else

The system SHALL give the hypervisor exporter a dedicated account that can only read,
and SHALL give the telemetry agent a backend credential that can only write telemetry.
Both SHALL be covered by the single privilege-verification command.

#### Scenario: The exporter cannot change the hypervisor

- **WHEN** the exporter's credential is used to attempt a change, such as starting a VM
  or modifying a user
- **THEN** the hypervisor SHALL refuse the action
- **AND** the refusal SHALL be recorded as evidence that the scope is real

#### Scenario: The agent credential cannot read back or administer

- **WHEN** the agent's backend credential is used to query stored telemetry or to manage
  the backend account
- **THEN** the backend SHALL refuse the request

#### Scenario: Neither credential is tracked by Git

- **WHEN** the secret-tracking check runs
- **THEN** neither credential value SHALL appear in any tracked file
