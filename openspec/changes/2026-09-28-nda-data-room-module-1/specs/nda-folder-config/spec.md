# nda-folder-config

## Purpose

Lets a fund manager (GP) configure an NDA requirement on any Data Room folder from the Documents
page — upload the NDA document, set validity and acceptance method, specify contact and
notification emails — and see at a glance which folders are NDA-protected via a lock icon in the
folder tree.

## ADDED Requirements

### Requirement: NDA Settings entry point in the Actions dropdown
The Documents page Actions dropdown SHALL show an "NDA Settings" item when the currently selected
folder is inside the Data Room (entity-level or model-level). The item SHALL NOT appear for
folders outside the Data Room. The item SHALL be visible only to GP/admin users and SHALL require
the `enable_data_rooms` feature flag.

#### Scenario: GP sees NDA Settings for a Data Room folder
- **WHEN** a GP user selects a folder inside the Data Room on the Documents page
- **THEN** the Actions dropdown includes "NDA Settings"

#### Scenario: NDA Settings hidden for non-Data Room folders
- **WHEN** a GP user selects a Fund folder or Portfolio Company folder on the Documents page
- **THEN** the Actions dropdown does not include "NDA Settings"

#### Scenario: LP user never sees NDA Settings
- **WHEN** an LP user views the Documents page for a Data Room folder they have access to
- **THEN** the Actions dropdown does not include "NDA Settings"

#### Scenario: NDA Settings requires enable_data_rooms flag
- **WHEN** the entity does not have `enable_data_rooms` enabled
- **THEN** "NDA Settings" does not appear in the Actions dropdown for any folder

### Requirement: NDA Settings modal opens on the same page
Clicking "NDA Settings" SHALL open a modal on the Documents page without navigating away. The
modal SHALL load via Turbo Frame. If the folder already has NDA configured, the modal SHALL load
with existing values pre-filled.

#### Scenario: Modal opens for a folder without existing NDA
- **WHEN** a GP clicks "NDA Settings" for a folder that has no NDA configured
- **THEN** a modal opens on the same page with "Require NDA" defaulting to "No" and the rest of
  the form hidden

#### Scenario: Modal opens for a folder with existing NDA
- **WHEN** a GP clicks "NDA Settings" for a folder that already has NDA configured
- **THEN** the modal opens with all existing values pre-filled (toggle, document, validity,
  acceptance method, contact email, notification recipients)

### Requirement: Enable NDA requirement on a folder
The NDA Settings modal SHALL have a "Require NDA before access" toggle (Yes/No). When set to
"No", only the toggle is shown. When set to "Yes", the full configuration form expands.

#### Scenario: Toggle from No to Yes shows the form
- **WHEN** a GP changes "Require NDA" from "No" to "Yes"
- **THEN** the form fields appear (NDA document, validity, acceptance method, contact email,
  notification recipients) without a server round-trip

#### Scenario: Toggle from Yes to No hides the form
- **WHEN** a GP changes "Require NDA" from "Yes" to "No"
- **THEN** the form fields are hidden, and only the toggle is visible

### Requirement: Upload NDA document
The NDA Settings modal SHALL have a file upload field for the NDA document. Only PDF files SHALL
be accepted. The uploaded file SHALL be stored via the existing FileUploader (Shrine/S3). After
selecting a file, the filename and size SHALL be displayed. Save SHALL be disabled when "Require
NDA" is "Yes" and no NDA document has been uploaded.

#### Scenario: Upload a PDF
- **WHEN** a GP selects a PDF file in the NDA document upload field
- **THEN** the filename and file size are displayed below the field

#### Scenario: Non-PDF rejected
- **WHEN** a GP attempts to save an NDA config with a non-PDF file
- **THEN** a validation error is shown stating the NDA document must be a PDF

#### Scenario: Save blocked without document
- **WHEN** "Require NDA" is "Yes" and no NDA document has been uploaded or previously saved
- **THEN** saving the form fails with a validation error that the NDA document is required

### Requirement: Configure NDA validity
The NDA Settings modal SHALL offer three validity options: "Until revoked" (default), "Fixed
period" (30 days, 90 days, 6 months, 12 months), and "Specific expiry date" (calendar date
picker). Validity is required when NDA is enabled.

#### Scenario: Default validity is "Until revoked"
- **WHEN** a GP enables NDA on a folder for the first time
- **THEN** the validity field defaults to "Until revoked"

#### Scenario: Fixed period shows duration options
- **WHEN** a GP selects "Fixed period" as the validity type
- **THEN** a dropdown appears with options: 30 days, 90 days, 6 months, 12 months
- **AND** the GP must select one before saving

#### Scenario: Specific date requires a future date
- **WHEN** a GP selects "Specific expiry date" and enters a date in the past
- **THEN** a validation error is shown stating the date must be in the future

#### Scenario: Validity days required for fixed period
- **WHEN** a GP selects "Fixed period" but does not choose a duration
- **THEN** saving the form fails with a validation error

### Requirement: Choose acceptance method
The NDA Settings modal SHALL offer two acceptance methods: "Click-through" (default) and
"Electronic signature". The e-sign option SHALL be visible but disabled with a message if the
entity has no e-sign provider configured.

#### Scenario: Default acceptance method is click-through
- **WHEN** a GP enables NDA on a folder for the first time
- **THEN** the acceptance method defaults to "Click-through"

#### Scenario: E-sign available when entity has provider
- **WHEN** the entity has Zoho Sign configured in Entity Settings
- **THEN** the "Electronic signature" radio button is enabled and selectable

#### Scenario: E-sign disabled without provider
- **WHEN** the entity has no e-sign provider configured
- **THEN** the "Electronic signature" radio button is disabled with the message "Configure an
  e-sign provider in Entity Settings to enable this option"

### Requirement: Set contact email
The NDA Settings modal SHALL have a "Contact email" field. The field is optional. If provided,
it SHALL be validated as a valid email address.

#### Scenario: Valid contact email saved
- **WHEN** a GP enters a valid email address in the contact email field and saves
- **THEN** the config is saved with that email

#### Scenario: Invalid contact email rejected
- **WHEN** a GP enters an invalid email format in the contact email field and saves
- **THEN** a validation error is shown

#### Scenario: Blank contact email allowed
- **WHEN** a GP leaves the contact email field blank and saves
- **THEN** the config is saved without a contact email

### Requirement: Configure notification recipients
The NDA Settings modal SHALL have a "Notification recipients" field accepting one or more email
addresses. Each entry SHALL be validated as a valid email address. The field is optional.

#### Scenario: Multiple notification recipients saved
- **WHEN** a GP enters multiple valid email addresses as notification recipients
- **THEN** all emails are stored as a JSON array on the config record

#### Scenario: Invalid notification email rejected
- **WHEN** a GP enters a list containing an invalid email address
- **THEN** a validation error is shown stating all entries must be valid email addresses

#### Scenario: No notification recipients is valid
- **WHEN** a GP leaves the notification recipients field blank
- **THEN** the config is saved without notification recipients

### Requirement: Save NDA configuration
Saving the NDA configuration SHALL create or update a single `NdaConfig` record for the folder
(polymorphic owner). The response SHALL update both the modal content and the folder tree (for
the lock icon) via Turbo Stream without a full page reload. The modal SHALL stay open after
saving. The `created_by` and `updated_by` fields SHALL be set to the current user.

#### Scenario: Create new NDA configuration
- **WHEN** a GP fills in all required fields and saves on a folder with no existing NDA config
- **THEN** an `NdaConfig` record is created with `owner = folder`, `created_by` and
  `updated_by` set to the current user, and the folder tree shows a lock icon next to the folder

#### Scenario: Update existing NDA configuration
- **WHEN** a GP changes the validity type on an existing NDA config and saves
- **THEN** the `NdaConfig` record is updated with the new validity type and `updated_by`
  set to the current user

#### Scenario: Validation errors re-render the modal
- **WHEN** a GP submits the form with validation errors (e.g., NDA enabled but no document)
- **THEN** the modal re-renders with error messages and no record is created or updated

### Requirement: Disable NDA preserves configuration
When a GP toggles "Require NDA" to "No" and saves, the `NdaConfig` record SHALL be retained
with `enabled: false`. All settings (document, validity, etc.) SHALL be preserved so the GP can
re-enable later. The lock icon SHALL disappear from the folder tree.

#### Scenario: Disable NDA keeps the record
- **WHEN** a GP toggles "Require NDA" to "No" and saves on a folder with an existing NDA config
- **THEN** the config record remains with `enabled = false` and all other fields unchanged
- **AND** the lock icon disappears from the folder tree

#### Scenario: Re-enable NDA shows preserved settings
- **WHEN** a GP reopens NDA Settings on a folder whose NDA was previously disabled
- **THEN** the modal shows "Require NDA = No" with the option to toggle back to "Yes"
- **AND** toggling to "Yes" reveals the previously saved settings (document, validity, etc.)

### Requirement: Lock icon in folder tree
A lock icon SHALL appear next to NDA-protected folders in the folder tree. The icon SHALL be
visible only to GP/admin users. The icon SHALL appear immediately after saving NDA settings
(via Turbo Stream, no page refresh). Hovering over the icon SHALL show a tooltip: "NDA required".

#### Scenario: Lock icon appears after enabling NDA
- **WHEN** a GP saves NDA settings with "Require NDA = Yes" on a folder
- **THEN** a lock icon appears next to that folder's name in the folder tree

#### Scenario: Lock icon disappears after disabling NDA
- **WHEN** a GP saves NDA settings with "Require NDA = No" on a folder
- **THEN** the lock icon is removed from that folder's name in the folder tree

#### Scenario: LP does not see lock icons
- **WHEN** an LP user views the folder tree
- **THEN** no lock icons are shown, even for NDA-protected folders

#### Scenario: Lock icon has tooltip
- **WHEN** a GP hovers over the lock icon next to an NDA-protected folder
- **THEN** a tooltip shows "NDA required"

### Requirement: Authorization
Only company admin users (GP role) who can manage the parent folder SHALL be able to access NDA
configuration endpoints. LP users and users without folder management rights SHALL be denied.
The folder MUST be inside a Data Room.

#### Scenario: GP with folder management rights can configure NDA
- **WHEN** a GP user with update rights on a Data Room folder accesses NDA settings
- **THEN** the modal renders and they can create or update the NDA config

#### Scenario: GP cannot configure NDA on a non-Data Room folder
- **WHEN** a GP user attempts to access NDA settings for a folder outside the Data Room
- **THEN** the request is denied by policy

#### Scenario: LP user denied NDA configuration access
- **WHEN** an LP user attempts to access NDA configuration endpoints directly
- **THEN** the request is denied by policy and no record is created

### Requirement: Entity scoping
The `NdaConfig` record SHALL store `entity_id` directly (set from the owner's entity). The
controller SHALL verify that the owner belongs to the current user's entity.

#### Scenario: Entity ID set automatically from folder
- **WHEN** a GP creates an NDA config on a folder
- **THEN** the config's `entity_id` is set to the folder's `entity_id`

#### Scenario: Cross-tenant access denied
- **WHEN** a user attempts to access NDA settings for a folder belonging to a different entity
- **THEN** the request is denied

### Requirement: Data Room detection
The system SHALL determine whether a folder is inside the Data Room by checking if the folder
itself or any of its ancestors is named "Data Room" and is a direct child of the entity's root
(system) folder. This check SHALL work for entity-level Data Rooms and model-level Data Rooms
(Fund, Deal, IO).

#### Scenario: Data Room root folder detected
- **WHEN** checking a folder named "Data Room" whose parent is the entity root folder
- **THEN** `in_data_room?` returns true

#### Scenario: Sub-folder inside Data Room detected
- **WHEN** checking a folder nested two levels inside the Data Room
- **THEN** `in_data_room?` returns true

#### Scenario: Fund folder not in Data Room
- **WHEN** checking a Fund folder that is not inside any Data Room hierarchy
- **THEN** `in_data_room?` returns false

#### Scenario: Entity root folder not in Data Room
- **WHEN** checking the entity root folder itself
- **THEN** `in_data_room?` returns false

### Requirement: One NDA config per owner
At most one `NdaConfig` record SHALL exist per owner, enforced by a unique composite index on
`[owner_type, owner_id]`. Creating a second config for the same owner SHALL fail.

#### Scenario: Duplicate config prevented
- **WHEN** an NDA config already exists for a folder and a second creation is attempted
- **THEN** the creation fails due to the unique constraint
