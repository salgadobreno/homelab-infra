## Purpose

The public site describes the infrastructure serving it, from what that infrastructure
actually reports, so the description cannot drift away from the thing it describes without
something failing.

## ADDED Requirements

### Requirement: The description is generated, not written

The system SHALL produce the site's infrastructure description from the cluster's own
output by a repeatable command, and SHALL NOT accept a description composed by hand.

#### Scenario: The description is reproducible

- **WHEN** the generator is run twice against an unchanged cluster
- **THEN** it SHALL produce identical output both times

A generator whose output varies between runs makes the drift check below fire on noise,
and a check that cries wolf is a check people learn to skip.

#### Scenario: A hand-written description cannot be served

- **WHEN** the repository is searched for a stored diagram of the infrastructure that no
  command produces
- **THEN** none SHALL exist

The hand-drawn diagram this replaces named three technologies the project does not use. It
was accurate when written. Deleting it is part of the requirement, not tidying.

### Requirement: Disagreement with reality fails a check

The system SHALL provide a check that compares the committed description against the
cluster as it is now, SHALL fail when they differ, and that check SHALL be part of the
routine check suite.

#### Scenario: A change in the cluster fails the check

- **WHEN** something the description reports changes in the cluster
- **THEN** the check SHALL fail
- **AND** it SHALL name what differs
- **AND** the failure SHALL be resolvable by re-running the generator

#### Scenario: The check passes when the page is current

- **WHEN** the committed description matches what the generator would produce now
- **THEN** the check SHALL pass

This is what replaces a runtime renderer. The page can still be wrong; it cannot be wrong
*and* green.

### Requirement: The description stays within a stated disclosure boundary

The system SHALL publish shapes, versions, counts and sync state, and SHALL NOT publish
network addresses, storage paths, or account names. The boundary SHALL be enforced by a
command rather than by review.

#### Scenario: A forbidden value cannot reach the page

- **WHEN** the generated description is checked against the disclosure boundary
- **THEN** no network address, storage path or account name SHALL appear
- **AND** the check SHALL fail if one does

Written down before it is built, because "what is safe to show" decided after the fact is
decided by whatever happens to already be on the page.
