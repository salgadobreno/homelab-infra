## Purpose

The public site describes the infrastructure serving it, from what that infrastructure
actually reports, so the description cannot drift away from the thing it describes.

## ADDED Requirements

### Requirement: The description is generated from live state

The system SHALL render the site's infrastructure description from state read from the
cluster at runtime, and SHALL NOT serve a description stored as content in the repository.

#### Scenario: The description follows a change in the cluster

- **WHEN** something the description reports changes in the cluster
- **THEN** the rendered description SHALL reflect the change without any edit to the
  repository
- **AND** the change SHALL appear within the renderer's stated refresh interval

#### Scenario: A hand-written description cannot be served

- **WHEN** the repository is searched for a stored diagram or description of the
  infrastructure
- **THEN** none SHALL exist

The hand-drawn diagram this replaces named three technologies the project does not use.
It was accurate when written. Deleting it is part of the requirement, not tidying.

### Requirement: The renderer reads only what the page shows

The system SHALL give the renderer an identity scoped to the reads the page makes, and
that identity SHALL be refused anything else.

#### Scenario: The renderer cannot read secrets

- **WHEN** the renderer's identity is used to read a Secret, or to read across namespaces
  it does not render
- **THEN** the cluster SHALL refuse it
- **AND** the refusal SHALL be recorded as evidence, not assumed

#### Scenario: The renderer cannot write

- **WHEN** the renderer's identity is used to modify any resource
- **THEN** the cluster SHALL refuse it

A page that reads the cluster is a way into the cluster. The negative test is the
requirement, exactly as it was for the provisioning credential.

### Requirement: The description stays within a stated disclosure boundary

The system SHALL publish shapes, versions, counts and sync state, and SHALL NOT publish
network addresses, storage paths, or account names. The boundary SHALL be enforced by a
command rather than by review.

#### Scenario: A forbidden value cannot reach the page

- **WHEN** the rendered description is checked against the disclosure boundary
- **THEN** no network address, storage path or account name SHALL appear
- **AND** the check SHALL fail if one does

Written down before it is built, because "what is safe to show" decided after the fact is
decided by what happens to already be on the page.

### Requirement: A failed renderer is visible rather than silent

The system SHALL make a stale or failed description evident on the page itself, and SHALL
NOT present unavailable data as though it were current.

#### Scenario: The renderer stops and the page says so

- **WHEN** the renderer has not produced fresh output within its refresh interval
- **THEN** the page SHALL say the description is stale, and as of when
- **AND** it SHALL NOT display the last successful reading as if it were current

nginx will keep serving whatever file is there. A panel that looks right and is hours old
is worse than an error, because nothing prompts anyone to look.
