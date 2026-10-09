# Spec Delta

## Purpose

Gates LP access to NDA-protected Data Room folders behind a click-through acceptance flow, recording every accept and decline as an append-only audit trail tied to the NDA configuration.

## ADDED Requirements

### Requirement: NDA gate intercepts folder access

The system SHALL redirect an LP to the NDA acceptance screen when the LP navigates to a Data Room folder that has an active effective NDA and the LP has not accepted that NDA.

#### Scenario: LP without acceptance hits NDA-protected folder

- **WHEN** an LP navigates to a folder whose effective NDA config is enabled
- **AND** the LP has no acceptance record with status "accepted" for that NDA config at the current version
- **THEN** the system redirects the LP to the NDA acceptance screen for that NDA config

#### Scenario: LP with accepted NDA accesses folder

- **WHEN** an LP navigates to a folder whose effective NDA config is enabled
- **AND** the LP's latest acceptance record for that NDA config has status "accepted" at the current version
- **THEN** the system shows the folder contents without interruption

#### Scenario: Folder has no active NDA

- **WHEN** an LP navigates to a folder that has no effective NDA config or whose effective NDA config is disabled
- **THEN** the system shows the folder contents without interruption

#### Scenario: GP employee bypasses NDA gate

- **WHEN** a GP employee navigates to an NDA-protected folder within their own entity
- **THEN** the system shows the folder contents without interruption (no NDA gate)

### Requirement: Acceptance screen displays NDA document

The system SHALL display the NDA acceptance screen with the NDA PDF document rendered inline, the entity name, the folder name, a confirmation checkbox, Accept and Decline buttons, and the contact email if configured.

#### Scenario: Acceptance screen renders with all elements

- **WHEN** the NDA acceptance screen is shown to an LP
- **THEN** the screen displays the NDA PDF inline via an embedded viewer
- **AND** shows the entity name and folder name as context
- **AND** shows a confirmation checkbox that is unchecked by default
- **AND** shows an Accept button that is disabled until the checkbox is checked
- **AND** shows a Decline button
- **AND** shows the contact email if the NDA config has one configured

#### Scenario: Acceptance screen without contact email

- **WHEN** the NDA acceptance screen is shown and the NDA config has no contact email
- **THEN** the contact email line is not displayed

### Requirement: LP can accept NDA via click-through

The system SHALL record an acceptance when the LP checks the confirmation checkbox and clicks Accept, then redirect the LP to the folder they originally wanted to access.

#### Scenario: LP accepts NDA

- **WHEN** an LP checks the confirmation checkbox and clicks Accept
- **THEN** the system creates an NDA acceptance record with status "accepted", the current NDA version, the LP's IP address, and browser user agent
- **AND** redirects the LP to the folder they originally navigated to

#### Scenario: Accept button disabled without checkbox

- **WHEN** an LP views the acceptance screen without checking the confirmation checkbox
- **THEN** the Accept button is disabled and cannot be clicked

### Requirement: LP can decline NDA

The system SHALL record a decline when the LP clicks Decline and show a confirmation page explaining the LP cannot access the folder.

#### Scenario: LP declines NDA

- **WHEN** an LP clicks Decline on the acceptance screen
- **THEN** the system creates an NDA acceptance record with status "declined", the current NDA version, the LP's IP address, and browser user agent
- **AND** shows the decline confirmation page with the folder name, an explanation that access requires NDA acceptance, a "Try Again" link, and a "Back to Data Rooms" link

#### Scenario: LP retries after decline

- **WHEN** an LP clicks "Try Again" on the decline confirmation page
- **THEN** the system shows the NDA acceptance screen again

### Requirement: Acceptance is tied to NdaConfig not folder

The system SHALL check acceptance against the effective NDA config, so that accepting once covers all folders sharing the same NDA config via inheritance.

#### Scenario: Inherited NDA already accepted on parent

- **WHEN** an LP has accepted NDA-A on a parent folder
- **AND** the LP navigates to a child folder that inherits NDA-A
- **THEN** the system shows the folder contents without interruption

#### Scenario: Child folder with own NDA requires separate acceptance

- **WHEN** an LP has accepted NDA-A on a parent folder
- **AND** the LP navigates to a child folder that has its own NDA-B (override)
- **AND** the LP has not accepted NDA-B
- **THEN** the system redirects the LP to the NDA acceptance screen for NDA-B

#### Scenario: Child folder opted out of NDA

- **WHEN** a child folder has opted out of NDA (nda_inheritance_mode = "opt_out")
- **AND** the parent folder has an active NDA
- **THEN** the LP accesses the child folder without any NDA screen

### Requirement: Acceptance records are append-only

The system SHALL create a new record for each accept or decline event, preserving the full history. The latest record for a given user and NDA config determines access.

#### Scenario: Multiple records preserved

- **WHEN** an LP accepts NDA-A, then later declines NDA-A (e.g. after revocation in a future module)
- **THEN** both records exist in the system
- **AND** the latest record (declined) determines the LP's access status

#### Scenario: Acceptance record contains audit fields

- **WHEN** an acceptance or decline record is created
- **THEN** it contains the NDA config reference, user reference, entity reference, status, NDA version at time of action, IP address, browser user agent, and timestamp

### Requirement: E-sign acceptance method falls back to click-through

The system SHALL fall back to click-through acceptance when the NDA config's acceptance method is set to "esign" and e-sign integration is not yet available.

#### Scenario: E-sign configured but not available

- **WHEN** an LP encounters an NDA with acceptance_method "esign"
- **THEN** the system shows the standard click-through acceptance screen

### Requirement: Return URL is sanitized

The system SHALL validate the return URL parameter to prevent open redirect attacks. Only relative paths on the same host are accepted.

#### Scenario: Valid return URL

- **WHEN** the return_to parameter is a valid relative path (e.g. "/documents/folder?folder_id=123&entity_id=456")
- **THEN** the LP is redirected to that path after acceptance

#### Scenario: Missing or invalid return URL

- **WHEN** the return_to parameter is missing, empty, or an absolute URL to an external host
- **THEN** the LP is redirected to the Data Rooms listing page after acceptance

### Requirement: Minimal layout for acceptance screens

The system SHALL render the NDA acceptance and decline screens using a minimal layout without application navigation, showing only the company logo and a "Back to Data Rooms" link.

#### Scenario: Acceptance screen uses minimal layout

- **WHEN** the NDA acceptance screen is rendered
- **THEN** it uses a minimal layout with no sidebar, no header navigation menus, only the company logo and a "Back to Data Rooms" link
