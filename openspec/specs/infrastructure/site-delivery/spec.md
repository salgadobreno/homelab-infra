# infrastructure/site-delivery Specification

## Purpose
The static site is served by the cluster and reachable from the internet, so the cluster
does something observable from outside the house rather than only describing itself.

## Requirements

### Requirement: The site is served by the cluster

The system SHALL serve the static site from a workload running in the cluster, and the
site content SHALL be declared in the repository rather than mounted from a path on the
hypervisor.

#### Scenario: The site answers from inside the cluster

- **WHEN** a request is made to the site's service within the cluster
- **THEN** the response SHALL be the site's index page with status 200

#### Scenario: The site survives a rebuild

- **WHEN** the cluster is destroyed and rebuilt
- **THEN** the site SHALL be serving again with no operator step beyond the rebuild
- **AND** no content SHALL have been copied from the hypervisor by hand

The content living in Git rather than on a host path is what makes the node disposable.
A bind mount would work and would quietly reintroduce a pet.

### Requirement: The cluster-served site is reachable from the internet

The system SHALL expose the cluster-served site through the existing outbound tunnel at
its own public hostname, without opening an inbound port on the network.

#### Scenario: The public hostname serves the cluster copy

- **WHEN** a request is made to the cluster's public hostname from outside the network
- **THEN** the response SHALL be the site served by the cluster
- **AND** the existing hostname SHALL continue to serve the pre-existing deployment,
  unaffected

Running both at once is deliberate. A cutover performed the same day as the migration
proves the new path works only by removing the ability to compare it with the old one.

### Requirement: Site delivery is verified by command

The system SHALL provide a command that asserts the site is being served, and that
command SHALL be part of the routine check suite.

#### Scenario: The check fails when the site does not serve

- **WHEN** the site's workload is unavailable
- **THEN** the check SHALL fail and name what did not answer
- **AND** the failure SHALL be distinguishable from the cluster being unreachable
