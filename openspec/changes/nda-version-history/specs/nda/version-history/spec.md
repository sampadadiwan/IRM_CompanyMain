# Spec Delta

## Purpose

Tracks every NDA PDF version with metadata (uploader, timestamp, resign decision), gives GPs control over whether a version bump invalidates existing acceptances, and provides a downloadable version history view.

## ADDED Requirements

### Requirement: Version history record is created on every PDF change

The system SHALL create a version history record each time the NDA PDF is replaced on an existing NDA config. The record SHALL store the version number, a reference to the uploaded PDF file, the user who uploaded it, the timestamp, and whether re-signing is required. Version history records SHALL be immutable once created.

#### Scenario: GP uploads a new PDF on an existing NDA config

- **WHEN** a GP user uploads a new NDA PDF and saves the NDA settings
- **THEN** the system creates a version history record with the new version number, PDF file reference, uploading user, current timestamp, and the GP's resign choice

#### Scenario: GP creates a new NDA config (first version)

- **WHEN** a GP user saves NDA settings for the first time on a folder
- **THEN** the system creates a version 1 history record with the uploaded PDF, the GP user, and `resign_required: false` (not applicable for first version)

### Requirement: GP controls whether a version bump requires re-signing

The system SHALL present a toggle to the GP when uploading a new PDF on an existing NDA config, allowing them to choose whether existing accepted investors must re-sign. The toggle SHALL default to "required" (checked). The toggle SHALL NOT appear on first NDA creation or when no new PDF is being uploaded.

#### Scenario: GP uploads new PDF with resign required (default)

- **WHEN** a GP user uploads a new PDF with the "Require existing signatories to re-sign" toggle checked
- **THEN** the system increments the version, records `resign_required: true`, and existing accepted investors must re-sign on next folder access

#### Scenario: GP uploads new PDF without resign required

- **WHEN** a GP user uploads a new PDF with the "Require existing signatories to re-sign" toggle unchecked
- **THEN** the system increments the version, records `resign_required: false`, and existing accepted investors retain folder access without re-signing

#### Scenario: GP edits NDA settings without uploading a new PDF

- **WHEN** a GP user changes NDA settings (contact email, validity, etc.) without uploading a new PDF
- **THEN** the system does not create a version history record and does not show the resign toggle

### Requirement: Acceptance check respects resign decisions across versions

The system SHALL treat an existing acceptance as valid if no version between the acceptance's version (exclusive) and the current version (inclusive) has `resign_required: true`. If any intermediate version required resign, the acceptance SHALL be treated as stale and the LP SHALL be redirected to the acceptance screen (if signatory) or blocked page (if non-signatory).

#### Scenario: LP accesses folder after non-resign version bump

- **WHEN** an LP user whose investor accepted at version 2 visits a folder where the current version is 3 and version 3 has `resign_required: false`
- **THEN** the system grants access to the folder

#### Scenario: LP accesses folder after resign-required version bump

- **WHEN** an LP user whose investor accepted at version 2 visits a folder where the current version is 3 and version 3 has `resign_required: true`
- **THEN** the system redirects the LP to the acceptance screen (signatory) or blocked page (non-signatory) with a version mismatch reason

#### Scenario: LP accesses folder with mixed resign history

- **WHEN** an LP user whose investor accepted at version 2 visits a folder where version 3 has `resign_required: false` and version 4 has `resign_required: true`
- **THEN** the system treats the acceptance as stale (version 4 required resign) and redirects accordingly

#### Scenario: LP accesses folder with all non-resign versions since acceptance

- **WHEN** an LP user whose investor accepted at version 2 visits a folder where versions 3, 4, and 5 all have `resign_required: false`
- **THEN** the system grants access to the folder

### Requirement: Version change notifications are conditional on resign decision

The system SHALL send version change notifications (to LP users and GP notification emails) only when the GP chose `resign_required: true` for that version bump. When `resign_required: false`, no version change notifications SHALL be sent.

#### Scenario: Resign-required version bump triggers notifications

- **WHEN** a GP saves a new PDF with resign required
- **THEN** the system sends version change notifications to all affected LP users and GP notification emails

#### Scenario: Non-resign version bump does not trigger notifications

- **WHEN** a GP saves a new PDF without resign required
- **THEN** the system does not send any version change notifications

### Requirement: GP can view version history on the NDA Status Dashboard

The system SHALL display a version history section on the NDA Status Dashboard showing all versions of the NDA config. Each entry SHALL show the version number, upload date, uploading user's name, whether resign was required, and a download link for that version's PDF. Versions SHALL be ordered newest first, with the current version marked.

#### Scenario: GP views version history with multiple versions

- **WHEN** a GP user views the NDA Status Dashboard for an NDA config with versions 1, 2, and 3
- **THEN** the system displays all three versions newest first, with version 3 marked as current, each with a downloadable PDF link

#### Scenario: GP downloads a historical version's PDF

- **WHEN** a GP user clicks the download link for a previous version in the version history
- **THEN** the system serves that version's PDF file for download

### Requirement: Existing NDA configs are backfilled with version 1 history

The system SHALL create a version 1 history record for every existing NDA config that has a document uploaded. The backfill SHALL use the NDA config's `created_by` as the uploader, `created_at` as the timestamp, and the current `nda_document_data` as the PDF reference. `resign_required` SHALL be `false` for backfilled records.

#### Scenario: Existing NDA config after migration

- **WHEN** the backfill migration runs on an existing NDA config with version 1 and an uploaded PDF
- **THEN** the system creates one version history record with version 1, the config's creation metadata, and `resign_required: false`
