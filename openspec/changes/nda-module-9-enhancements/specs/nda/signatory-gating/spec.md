# Spec Delta

## Purpose

Restricts NDA accept/decline actions to users designated as NDA signatories, shows a blocked page to non-signatories, warns GPs about investors with zero signatories, and guides GPs to tag signatories after first NDA creation.

## ADDED Requirements

### Requirement: Only designated signatories can accept an NDA

The system SHALL allow only users who have an `NdaSignatory` record for the relevant `NdaConfig` to submit an NDA acceptance. A user without a signatory designation for that NDA config SHALL be prevented from accepting, regardless of their investor access status.

#### Scenario: Signatory accepts NDA successfully

- **WHEN** an LP user who is a designated signatory for the NDA config submits an acceptance
- **THEN** the system creates an NdaAcceptance record with status "accepted" for the user's investor, and the user is redirected to the folder

#### Scenario: Non-signatory attempts to accept NDA

- **WHEN** an LP user who is NOT a designated signatory for the NDA config attempts to submit an acceptance
- **THEN** the system rejects the request and does not create an NdaAcceptance record

### Requirement: Only designated signatories can decline an NDA

The system SHALL allow only users who have an `NdaSignatory` record for the relevant `NdaConfig` to submit an NDA decline. A user without a signatory designation SHALL be prevented from declining.

#### Scenario: Signatory declines NDA

- **WHEN** an LP user who is a designated signatory for the NDA config submits a decline
- **THEN** the system creates an NdaAcceptance record with status "declined" for the user's investor

#### Scenario: Non-signatory attempts to decline NDA

- **WHEN** an LP user who is NOT a designated signatory for the NDA config attempts to submit a decline
- **THEN** the system rejects the request and does not create an NdaAcceptance record

### Requirement: Non-signatories see a blocked page when NDA is pending

The system SHALL display a blocked page to LP users who are not designated signatories when they access an NDA-protected folder where no signatory has accepted the NDA for their investor. The blocked page SHALL display the entity logo, folder name, a message stating that a designated signatory must accept, and a contact email if configured. The blocked page SHALL NOT display the NDA PDF document or accept/decline buttons.

#### Scenario: Non-signatory visits NDA-protected folder with pending NDA

- **WHEN** a non-signatory LP user navigates to a folder protected by an NDA that has not been accepted for their investor
- **THEN** the system displays the blocked page with message "Please ensure that the authorised signatory has signed the NDA to access the documents."

#### Scenario: Non-signatory visits NDA-protected folder after signatory has accepted

- **WHEN** a non-signatory LP user navigates to a folder protected by an NDA that has been accepted by a signatory for their investor
- **THEN** the system grants access to the folder (standard stakeholder-level access)

### Requirement: Signatory gating respects NDA exemption

The system SHALL bypass signatory gating entirely for investors marked as exempt from NDA. Exempt investors' users SHALL access the folder without any NDA screen, regardless of signatory designation.

#### Scenario: Exempt investor user accesses NDA-protected folder

- **WHEN** an LP user whose investor has `exempt_from_nda: true` navigates to an NDA-protected folder
- **THEN** the system grants access to the folder without showing any NDA acceptance screen or blocked page

### Requirement: Signatories see acceptance screen for re-acceptance scenarios

The system SHALL show the standard NDA acceptance screen to designated signatories when re-acceptance is required (version mismatch, expiry, or revocation). Non-signatories SHALL see the blocked page in these scenarios as well.

#### Scenario: Signatory sees acceptance screen after version bump

- **WHEN** a designated signatory visits an NDA-protected folder and their investor's acceptance is at an older NDA version
- **THEN** the system displays the NDA acceptance screen with the version mismatch contextual note

#### Scenario: Non-signatory sees blocked page after version bump

- **WHEN** a non-signatory LP user visits an NDA-protected folder and their investor's acceptance is at an older NDA version
- **THEN** the system displays the blocked page, not the acceptance screen

### Requirement: Default signatories are auto-tagged on first NDA creation

The system SHALL automatically tag the first (oldest by `InvestorAccess.created_at`) approved user of each investor as the default NDA signatory when a new NDA config is created. Auto-tagging SHALL NOT occur on updates or version bumps. The GP SHALL be able to change or add signatories from the NDA Status Dashboard afterward.

#### Scenario: GP creates first NDA config on a folder

- **WHEN** a GP user saves NDA settings for the first time on a folder (creating a new NdaConfig)
- **THEN** the system creates NdaSignatory records for the oldest approved user of each investor with InvestorAccess to this entity, and the modal closes normally with tree icon updated

#### Scenario: GP updates existing NDA settings

- **WHEN** a GP user updates an existing NDA config (edit, PDF replacement, setting changes)
- **THEN** the system responds with the standard turbo stream modal update and does NOT auto-tag any signatories

### Requirement: Dashboard warns about investors with zero signatories

The system SHALL display a warning indicator next to any investor on the NDA Status Dashboard that has no designated signatories tagged. The warning SHALL include a tooltip explaining that no one can accept the NDA for that investor.

#### Scenario: Investor with zero signatories on dashboard

- **WHEN** a GP views the NDA Status Dashboard and an investor has no users tagged as signatories for this NDA config
- **THEN** the system displays a warning icon with tooltip "No signatories tagged — no one can accept the NDA for this investor" in the investor's row

#### Scenario: Investor with at least one signatory on dashboard

- **WHEN** a GP views the NDA Status Dashboard and an investor has at least one user tagged as signatory
- **THEN** the system does NOT display the zero-signatory warning for that investor

### Requirement: Acceptance by any signatory opens access for all investor users

The system SHALL maintain the existing stakeholder-level access model: when any signatory accepts the NDA on behalf of an investor, all users under that investor gain folder access. Signatory gating does not change who benefits from an accepted NDA.

#### Scenario: Non-signatory gains access after signatory accepts

- **WHEN** a designated signatory accepts the NDA for their investor
- **AND** a non-signatory user under the same investor subsequently visits the NDA-protected folder
- **THEN** the system grants the non-signatory access to the folder
