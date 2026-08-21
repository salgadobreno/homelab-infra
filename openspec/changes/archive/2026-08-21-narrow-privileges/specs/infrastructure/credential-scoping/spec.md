## Purpose

Every credential the homelab uses holds only the privileges its job requires, and that
narrowness is demonstrable on demand rather than asserted from memory.

## ADDED Requirements

### Requirement: Automation credentials are scoped to the work they perform

The system SHALL authenticate automation against the hypervisor using a dedicated
non-root account holding only the privileges that automation exercises, and SHALL NOT
use an account whose privileges are unbounded.

#### Scenario: Provisioning succeeds with the scoped credential

- **WHEN** an operator runs a full destroy and rebuild using the scoped credential
- **THEN** the cluster is recreated and reports `Ready` without operator intervention
- **AND** no step falls back to a broader credential

#### Scenario: The scoped credential cannot exceed its purpose

- **WHEN** the scoped credential is used to attempt an action outside provisioning,
  such as modifying host users or altering storage configuration
- **THEN** the hypervisor SHALL refuse the action
- **AND** the refusal SHALL be recorded as evidence that the scope is real

The negative test is the requirement. A credential that has never been shown to be
refused anything has not been demonstrated to be narrow.

### Requirement: Credentials are not exposed through process arguments

The system SHALL supply credentials to long-running services through files readable
only by the service account, and SHALL NOT pass them as command-line arguments.

#### Scenario: A local user cannot read a service credential

- **WHEN** an unprivileged local user reads the process table and the process
  environment of a credential-bearing service
- **THEN** no credential value is recoverable
- **AND** the file holding the credential is not readable by that user

### Requirement: Services run as accounts without standing administrative rights

The system SHALL run network-facing services under dedicated accounts that hold no
administrative privileges on the host.

#### Scenario: A service compromise does not yield host administration

- **WHEN** the operator inspects the owning account of a network-facing service
- **THEN** that account SHALL NOT be root
- **AND** that account SHALL NOT hold password-less administrative escalation

#### Scenario: Administrative remote access is withdrawn once unnecessary

- **WHEN** provisioning no longer requires administrative remote access to the host
- **THEN** administrative remote login SHALL be refused
- **AND** provisioning SHALL continue to succeed unattended

### Requirement: Privilege narrowness is verified, not remembered

The system SHALL provide a single command that checks every credential-scoping property
and fails if any has regressed.

#### Scenario: A regression is caught by the check

- **WHEN** a credential is widened, a service is returned to an administrative account,
  or a credential is moved back into process arguments
- **THEN** the verification command SHALL fail
- **AND** the failure SHALL name the property that regressed
