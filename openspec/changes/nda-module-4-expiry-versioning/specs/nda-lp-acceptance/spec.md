# Spec Delta

## MODIFIED Requirements

### Requirement: NDA gate intercepts folder access

The system SHALL redirect an LP to the NDA acceptance screen when the LP navigates to a Data Room folder that has an active effective NDA and the LP has not accepted that NDA, or the LP's acceptance is stale (version mismatch or time expiry). When the NDA's specific expiry date has passed, the system SHALL show a lapsed NDA page instead.

#### Scenario: LP without acceptance hits NDA-protected folder

- **WHEN** an LP navigates to a folder whose effective NDA config is enabled
- **AND** the LP has no acceptance record with status "accepted" for that NDA config
- **THEN** the system redirects the LP to the NDA acceptance screen for that NDA config

#### Scenario: LP with accepted NDA at current version accesses folder

- **WHEN** an LP navigates to a folder whose effective NDA config is enabled
- **AND** the LP's latest acceptance record for that NDA config has status "accepted" at the current version
- **AND** the acceptance has not expired per the NDA config's validity settings
- **THEN** the system shows the folder contents without interruption

#### Scenario: LP with accepted NDA at old version is redirected

- **WHEN** an LP navigates to a folder whose effective NDA config is enabled
- **AND** the LP's latest acceptance has `nda_version` less than the NDA config's current `version`
- **THEN** the system redirects the LP to the NDA acceptance screen with a reason parameter indicating version mismatch

#### Scenario: LP with expired fixed-period acceptance is redirected

- **WHEN** an LP navigates to a folder whose effective NDA config has `validity_type = fixed_period`
- **AND** the LP's latest acceptance's `accepted_at` plus `validity_days` is before the current time
- **THEN** the system redirects the LP to the NDA acceptance screen with a reason parameter indicating expiry

#### Scenario: LP hits lapsed specific-date NDA

- **WHEN** an LP navigates to a folder whose effective NDA config has `validity_type = specific_date`
- **AND** the `validity_date` is in the past
- **THEN** the system redirects the LP to the lapsed NDA page (not the acceptance screen)

#### Scenario: Folder has no active NDA

- **WHEN** an LP navigates to a folder that has no effective NDA config or whose effective NDA config is disabled
- **THEN** the system shows the folder contents without interruption

#### Scenario: GP employee bypasses NDA gate

- **WHEN** a GP employee navigates to an NDA-protected folder within their own entity
- **THEN** the system shows the folder contents without interruption (no NDA gate)

## ADDED Requirements

### Requirement: Contextual re-acceptance note on acceptance screen

The system SHALL display a brief contextual note at the top of the NDA acceptance screen when the LP is being asked to re-accept due to a version update or expiry.

#### Scenario: Version mismatch note

- **WHEN** the LP is redirected to the acceptance screen due to a version mismatch
- **THEN** a note is displayed: "The NDA has been updated since you last signed. Please review and accept the new version."

#### Scenario: Expiry note

- **WHEN** the LP is redirected to the acceptance screen due to fixed-period expiry
- **THEN** a note is displayed: "Your NDA acceptance has expired. Please review and re-accept."

#### Scenario: First-time acceptance has no note

- **WHEN** the LP is seeing the NDA acceptance screen for the first time (no prior acceptance)
- **THEN** no contextual note is displayed
