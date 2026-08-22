## MODIFIED Requirements

### Requirement: The cluster-served site is reachable from the internet

The system SHALL serve the site's primary public hostname from the cluster, through the
existing outbound tunnel, without opening an inbound port on the network. The hypervisor
SHALL NOT serve the site.

#### Scenario: The public hostname serves the cluster copy

- **WHEN** a request is made to the site's primary public hostname from outside the
  network
- **THEN** the response SHALL be the site served by the cluster
- **AND** it SHALL be identifiable as the cluster's copy by a marker in the response,
  not by status code alone

Both copies return 200. A check that distinguishes them only by success distinguishes
nothing.

#### Scenario: The hypervisor no longer serves the site

- **WHEN** the host's previously serving ports are requested directly
- **THEN** nothing SHALL answer
- **AND** the previously serving containers SHALL NOT be running
- **AND** they SHALL NOT return after the host reboots

Stopped and disabled are different states. A service that comes back on reboot has not
been retired; it has been paused.

#### Scenario: The cutover does not take the site down

- **WHEN** the primary hostname is moved from the old origin to the cluster
- **THEN** it SHALL continue to answer 200 throughout
- **AND** at no point SHALL both origins be stopped

The milestone is the origin moving, not the site pausing. The new origin is proven
serving the same content before the old one stops.

### Requirement: Site delivery is verified by command

The system SHALL provide a command that asserts the site is being served, and that
command SHALL be part of the routine check suite. A separate command SHALL assert which
copy each public hostname serves.

#### Scenario: The check fails when the site does not serve

- **WHEN** the site's workload is unavailable
- **THEN** the check SHALL fail and name what did not answer
- **AND** the failure SHALL be distinguishable from the cluster being unreachable

#### Scenario: The check fails if the primary hostname is not the cluster's copy

- **WHEN** the primary public hostname serves a response without the cluster's marker
- **THEN** the check SHALL fail
- **AND** it SHALL say that the hostname is not being served by the cluster

This scenario is the inverse of the one it replaces, which asserted that the primary
hostname had *not* moved to the cluster. A check whose meaning inverts during a change
can pass for the wrong reason at every point in between, so it changes in step with the
cutover rather than before or after it.
