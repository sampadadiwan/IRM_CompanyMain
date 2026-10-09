# Spec Delta

## Purpose

Automatic NDA signatory designation when investor access is approved and on NDA creation, scoped to folder-level access rights rather than entity-wide.

## ADDED Requirements

### Requirement: Auto-tag signatory on investor access approval

When an investor access record becomes approved (either created as approved or toggled from unapproved to approved), the system must check all NDA-enabled folders accessible to that investor. For each folder NDA where the investor has zero existing signatories, the approved user is automatically designated as a signatory.

#### Scenario: New investor access created as approved with folder NDA

- **WHEN** an investor access is created with `approved = true` AND the investor has folder-level access to a folder with an enabled NDA AND the investor has no existing signatory for that NDA
- **THEN** the system creates an NdaSignatory record for the approved user on that NDA config

#### Scenario: Existing investor access toggled to approved with folder NDA

- **WHEN** an unapproved investor access is toggled to `approved = true` AND the investor has folder-level access to a folder with an enabled NDA AND the investor has no existing signatory for that NDA
- **THEN** the system creates an NdaSignatory record for the approved user on that NDA config

#### Scenario: Investor already has a signatory for the folder NDA

- **WHEN** an investor access is approved AND the investor already has at least one signatory for the folder's NDA
- **THEN** no new signatory is created; the existing signatory is preserved

#### Scenario: Investor has no folder-level access to any NDA-protected folder

- **WHEN** an investor access is approved AND the investor has no folder-level access rights to any NDA-enabled folder
- **THEN** no signatory is created

#### Scenario: Concurrent approval race condition

- **WHEN** two investor access records for the same investor are approved simultaneously for the same folder NDA
- **THEN** only one signatory is created; the second attempt is silently skipped via the unique database constraint

### Requirement: Folder-scoped auto-tag on NDA creation

When an NDA is first created on a folder, the auto-tag logic must only consider investors with folder-level access rights (via AccessRight records on that folder), not all investors in the entity.

#### Scenario: NDA created on folder with folder-scoped investors

- **WHEN** a GP creates an NDA config on a folder AND the folder has access rights granted to specific investors
- **THEN** only investors with folder-level access rights are considered for auto-tagging, and the oldest approved user per qualifying investor is tagged as signatory

#### Scenario: Investor has entity access but no folder access

- **WHEN** a GP creates an NDA config on a folder AND an investor has entity-level access but no access right on that specific folder
- **THEN** that investor is not auto-tagged as a signatory

### Requirement: Idempotency

All auto-tag operations must be idempotent. Creating a signatory that already exists must not raise an error or create duplicates.

#### Scenario: Auto-tag called multiple times for same investor and NDA

- **WHEN** the auto-tag logic runs for an investor who already has a signatory for the NDA
- **THEN** no duplicate record is created and no error is raised
