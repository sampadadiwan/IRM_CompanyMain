# Spec Delta

## Purpose

Enforces NDA acceptance expiry (time-based and version-based) on Data Room folders, automatically invalidating stale acceptances and requiring LPs to re-accept when the NDA document changes or the validity period elapses.

## ADDED Requirements

### Requirement: NDA gate checks version match

The system SHALL reject an acceptance whose `nda_version` does not match the current `NdaConfig.version`, redirecting the LP to the NDA acceptance screen.

#### Scenario: Acceptance at current version passes gate

- **WHEN** an LP navigates to an NDA-protected folder
- **AND** the LP's latest acceptance has `nda_version` equal to the NDA config's `version`
- **AND** the acceptance has not expired
- **THEN** the system shows the folder contents without interruption

#### Scenario: Acceptance at old version is rejected by gate

- **WHEN** an LP navigates to an NDA-protected folder
- **AND** the LP's latest acceptance has `nda_version` less than the NDA config's `version`
- **THEN** the system redirects the LP to the NDA acceptance screen with a reason indicating version mismatch

#### Scenario: Version check order in gate

- **WHEN** a non-GP, non-exempt LP navigates to an NDA-protected folder
- **THEN** the gate checks in order: (1) GP bypass, (2) exemption, (3) acceptance exists and accepted, (4) version match, (5) time expiry
- **AND** the first failing check determines the redirect reason

### Requirement: NDA gate checks time-based expiry

The system SHALL reject an acceptance that has exceeded the NDA config's validity period, redirecting the LP to the NDA acceptance screen or the lapsed NDA page.

#### Scenario: Fixed-period acceptance not yet expired

- **WHEN** an LP navigates to an NDA-protected folder with `validity_type = fixed_period` and `validity_days = 90`
- **AND** the LP's latest acceptance was created 89 days ago
- **THEN** the system shows the folder contents without interruption

#### Scenario: Fixed-period acceptance expired

- **WHEN** an LP navigates to an NDA-protected folder with `validity_type = fixed_period` and `validity_days = 90`
- **AND** the LP's latest acceptance was created 91 days ago
- **THEN** the system redirects the LP to the NDA acceptance screen with a reason indicating expiry

#### Scenario: Specific-date not yet reached

- **WHEN** an LP navigates to an NDA-protected folder with `validity_type = specific_date` and `validity_date` is in the future
- **AND** the LP's latest acceptance is at the current NDA version
- **THEN** the system shows the folder contents without interruption

#### Scenario: Specific-date has passed — lapsed NDA

- **WHEN** an LP navigates to an NDA-protected folder with `validity_type = specific_date` and `validity_date` is in the past
- **THEN** the system shows the lapsed NDA page (not the acceptance screen)
- **AND** no Accept or Decline buttons are available

#### Scenario: Until-revoked acceptance never expires

- **WHEN** an LP navigates to an NDA-protected folder with `validity_type = until_revoked`
- **AND** the LP's latest acceptance is at the current NDA version
- **THEN** the system shows the folder contents regardless of how old the acceptance is

### Requirement: Lapsed NDA page for specific-date expiry

The system SHALL display a dead-end page when an NDA's specific expiry date has passed, informing the LP that the NDA has expired and directing them to contact the fund manager.

#### Scenario: Lapsed NDA page content

- **WHEN** the lapsed NDA page is shown to an LP
- **THEN** the page displays the folder name, the expiry date, a message that the NDA has expired, the GP's contact email (if configured), and a "Back to Data Rooms" link
- **AND** no Accept or Decline buttons are shown

#### Scenario: Lapsed NDA page without contact email

- **WHEN** the lapsed NDA page is shown and the NDA config has no contact email
- **THEN** the contact email line is not displayed

#### Scenario: Lapsed NDA page uses minimal layout

- **WHEN** the lapsed NDA page is rendered
- **THEN** it uses the same minimal layout as the acceptance and decline screens

### Requirement: Auto-increment version on NDA document replacement

The system SHALL automatically increment `NdaConfig.version` when the GP uploads a new NDA PDF document. Version SHALL NOT change for any other field update.

#### Scenario: New PDF upload increments version

- **WHEN** a GP uploads a new NDA PDF document in the NDA Settings modal and saves
- **THEN** the NDA config's `version` increments by 1 (e.g. from 1 to 2)
- **AND** the new version number is displayed in the modal

#### Scenario: Settings change without new PDF does not increment version

- **WHEN** a GP changes the validity type, acceptance method, contact email, or notification emails without uploading a new PDF
- **AND** saves the NDA settings
- **THEN** the NDA config's `version` remains unchanged

#### Scenario: Re-uploading same filename still increments version

- **WHEN** a GP uploads a PDF with the same filename as the existing document
- **THEN** the NDA config's `version` increments (the system treats any new upload as a new document)

### Requirement: GP confirmation warning before version bump

The system SHALL display a warning in the NDA Settings modal when the GP is about to replace the NDA document, showing how many currently accepted investors will need to re-accept.

#### Scenario: Warning shown when new PDF selected

- **WHEN** a GP selects a new NDA PDF file in the upload field
- **AND** there are currently accepted investors for this NDA config
- **THEN** a warning banner appears: "Uploading a new document will require X accepted investors to re-accept the NDA."

#### Scenario: No warning when no accepted investors

- **WHEN** a GP selects a new NDA PDF file in the upload field
- **AND** there are no currently accepted investors
- **THEN** no warning banner is shown

#### Scenario: Warning disappears when new file removed

- **WHEN** a GP removes the newly selected PDF file (reverts to the existing document)
- **THEN** the warning banner disappears

### Requirement: Re-acceptance resets fixed-period expiry clock

The system SHALL use the new acceptance's `accepted_at` as the start of the validity period when an LP re-accepts after expiry.

#### Scenario: Re-acceptance after fixed-period expiry

- **WHEN** an LP's acceptance expired (accepted 91 days ago, validity_days=90)
- **AND** the LP re-accepts the NDA today
- **THEN** the new acceptance's `accepted_at` is today
- **AND** the new acceptance expires 90 days from today (not from the original acceptance date)

#### Scenario: Re-acceptance after version bump

- **WHEN** an LP re-accepts the NDA after a version bump
- **THEN** the new acceptance's `nda_version` matches the current NDA config `version`
- **AND** the new acceptance's `accepted_at` is set to the current time
- **AND** if the NDA has fixed-period validity, the period starts from the new `accepted_at`

### Requirement: Exempt investors bypass version and expiry checks

The system SHALL skip version match and time expiry checks for exempt investors, so that exemption remains a complete bypass of all NDA gate logic.

#### Scenario: Exempt investor after version bump

- **WHEN** an exempt investor's user navigates to an NDA-protected folder
- **AND** the NDA version has been bumped since the investor's last acceptance
- **THEN** the system shows the folder contents without interruption

#### Scenario: Exempt investor after fixed-period expiry

- **WHEN** an exempt investor's user navigates to an NDA-protected folder
- **AND** the investor's last acceptance is older than the validity period
- **THEN** the system shows the folder contents without interruption

### Requirement: Pending investors unaffected by version bump

The system SHALL not change the status of investors who have never accepted (Pending) when a version bump occurs. They remain Pending.

#### Scenario: Pending investor after version bump

- **WHEN** an investor has no NdaAcceptance record for an NDA config
- **AND** the GP uploads a new NDA document (version bumps)
- **THEN** the investor's status on the dashboard remains "Pending"
