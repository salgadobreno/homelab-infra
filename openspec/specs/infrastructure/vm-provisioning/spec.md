# infrastructure/vm-provisioning Specification

## Purpose
Declarative lifecycle management of Proxmox VE virtual machines, so that the homelab's
compute can be created, destroyed, and recreated reproducibly from version-controlled
configuration rather than from clicks in a web UI or undocumented manual steps.

## Requirements

### Requirement: Virtual machines are declared as version-controlled configuration

The system SHALL define every managed virtual machine's desired state — CPU, memory,
disk size, storage location, network attachment, and base image — in configuration
files committed to version control. No managed VM attribute SHALL require manual
configuration through the Proxmox web interface.

#### Scenario: Declared VM is created

- **WHEN** an operator applies configuration declaring a virtual machine that does not exist
- **THEN** a virtual machine matching every declared attribute exists on the Proxmox host
- **AND** the operator is told which resources were created

#### Scenario: Configuration matches reality

- **WHEN** an operator requests a plan and no configuration or infrastructure has changed since the last apply
- **THEN** the plan reports that no changes are required

#### Scenario: Drift is detected

- **WHEN** a managed VM attribute is altered outside of the declared configuration
- **AND** an operator requests a plan
- **THEN** the plan reports the difference between declared and actual state

### Requirement: Provisioning is reproducible and reversible

The system SHALL support destroying all managed infrastructure and recreating it from
the same configuration, yielding a functionally equivalent environment without manual
intervention.

#### Scenario: Full teardown

- **WHEN** an operator destroys the managed infrastructure
- **THEN** every managed virtual machine is removed from the Proxmox host
- **AND** no orphaned disks or network interfaces belonging to managed VMs remain

#### Scenario: Rebuild after teardown

- **WHEN** an operator applies the same configuration after a full teardown
- **THEN** an environment functionally equivalent to the original is produced
- **AND** the operator performs no manual configuration steps to reach that state

### Requirement: Base images are obtained from upstream, not hand-built

The system SHALL provision virtual machines from an upstream-published cloud image
identified in configuration. It SHALL NOT depend on a virtual machine template that
was constructed through manual, unrecorded steps.

#### Scenario: Provisioning on a host with no prepared template

- **WHEN** configuration is applied on a Proxmox host that has no pre-existing VM templates
- **THEN** provisioning succeeds using the upstream cloud image named in configuration

#### Scenario: Base image is pinned

- **WHEN** an operator inspects the configuration
- **THEN** the specific operating system image and version in use is identifiable from the configuration alone

### Requirement: First-boot configuration is declared, not applied by hand

The system SHALL configure a newly provisioned virtual machine's initial state —
hostname, network address, operator SSH access, and bootstrap commands — through
automated first-boot configuration supplied at creation time.

#### Scenario: Operator access after creation

- **WHEN** a virtual machine finishes provisioning
- **THEN** the operator can open an SSH session to it using their declared key
- **AND** no password authentication step is required

#### Scenario: Network address is declared, not negotiated

- **WHEN** a virtual machine is provisioned
- **THEN** it comes up on the address declared for it in configuration
- **AND** that address is reachable from the Proxmox host without discovery

#### Scenario: Address survives destroy and recreate

- **WHEN** a virtual machine is destroyed and recreated from the same configuration
- **THEN** it returns on the same address as before

### Requirement: Credentials are never committed

The system SHALL source Proxmox API credentials from the operator's environment or a
file excluded from version control. Applying configuration SHALL fail with an
actionable message when credentials are absent.

#### Scenario: Missing credentials

- **WHEN** an operator applies configuration without credentials available
- **THEN** the operation fails before contacting the Proxmox API
- **AND** the message names which credential is missing and how to supply it

#### Scenario: Repository contains no secrets

- **WHEN** the repository contents are inspected
- **THEN** no API token, password, or private key appears in any committed file

### Requirement: Network addresses are allocated from a declared plan

The system SHALL allocate every managed virtual machine's address from an address plan
recorded in configuration. Allocated addresses SHALL NOT fall within the range the
network's DHCP server may assign.

#### Scenario: Address plan is discoverable

- **WHEN** an operator inspects the configuration
- **THEN** the address assigned to each managed machine is stated, along with the ranges reserved for future use and for DHCP

#### Scenario: No overlap with dynamic allocation

- **WHEN** an address is allocated to a managed machine
- **THEN** that address lies outside the DHCP server's assignable pool
