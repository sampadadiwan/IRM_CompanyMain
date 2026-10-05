# Spec Delta

## Purpose

GP-facing NDA status dashboard providing visibility into investor NDA acceptance status, stakeholder-level exemption display, and compliance export for NDA-protected Data Room folders.

## ADDED Requirements

### Requirement: Status summary displayed in NDA Settings modal

The system SHALL display a Status tab in the NDA Settings modal showing NDA acceptance counters and an investor status table when the folder has an active NDA config.

#### Scenario: GP views status summary for NDA-protected folder

- **WHEN** a GP opens the NDA Settings modal for a folder with an enabled NDA config
- **THEN** the Status tab is enabled and clickable
- **AND** clicking the Status tab shows counters for Accepted, Pending, Declined, and Exempt investor statuses
- **AND** a simple table lists all investors with access to the folder, showing: Investor Name, Status, Signed By, Date
- **AND** a "View Full Dashboard" link is visible

#### Scenario: Status tab hidden when no active NDA

- **WHEN** a GP opens the NDA Settings modal for a folder without an enabled NDA config
- **THEN** the Status tab is not visible (only the Settings tab is shown)

#### Scenario: Status tab for inherited NDA

- **WHEN** a GP opens the NDA Settings modal for a folder that inherits its parent's NDA
- **THEN** the Status tab shows investor statuses for the effective (parent's) NDA config
- **AND** the investor universe comes from the current folder's access rights

### Requirement: Dedicated NDA status dashboard page

The system SHALL provide a full-page dashboard showing all investors with folder access, their NDA status, and user-level detail in an AG Grid with filtering, searching, and row grouping.

#### Scenario: GP opens dedicated dashboard from modal

- **WHEN** a GP clicks "View Full Dashboard" in the modal Status tab
- **THEN** the system navigates to a dedicated page showing an AG Grid table
- **AND** rows are grouped by investor, expandable to show individual users
- **AND** columns include: Investor Name, User Name, Status, NDA Version, Signed By, Signed Date, Valid Until

#### Scenario: Investor-level status derivation

- **WHEN** the dashboard renders an investor row
- **THEN** the status is "Accepted" if the latest NdaAcceptance for that investor has status "accepted"
- **AND** the status is "Declined" if the latest NdaAcceptance has status "declined"
- **AND** the status is "Pending" if no NdaAcceptance record exists for that investor and NDA config
- **AND** the status is "Exempt" if any InvestorAccess for that investor has exempt_from_nda=true

#### Scenario: User-level detail in expanded row

- **WHEN** a GP expands an investor row
- **THEN** each user under that investor with folder access is shown
- **AND** the user who physically signed the NDA is marked as "Signer"
- **AND** users designated as NDA signatories on their InvestorAccess show a "Signatory" badge
- **AND** other users show "—" for status

#### Scenario: Dashboard filtered by status

- **WHEN** a GP selects a status filter (e.g., "Pending")
- **THEN** only investors matching that status are shown in the grid

#### Scenario: Dashboard searched by name

- **WHEN** a GP types a search term
- **THEN** only investors or users whose name matches the search term are shown

### Requirement: Investor universe from folder access rights

The system SHALL derive the list of investors shown on the dashboard from the folder's current access rights, including both direct investor assignments and category-based access rights.

#### Scenario: Direct investor access right

- **WHEN** an AccessRight exists for the folder with a specific access_to_investor_id
- **THEN** that investor appears on the dashboard

#### Scenario: Category-based access right

- **WHEN** an AccessRight exists for the folder with an access_to_category (e.g., "LP")
- **THEN** all investors of that category within the entity appear on the dashboard

#### Scenario: Investor removed from access rights

- **WHEN** an investor's access right to the folder is deleted
- **THEN** that investor no longer appears on the dashboard (status is computed dynamically)

### Requirement: Stakeholder-level NDA exemption via InvestorAccess

The system SHALL allow a GP to mark an investor as exempt from NDA by checking `exempt_from_nda` on InvestorAccess when granting or editing access.

#### Scenario: GP creates InvestorAccess with exemption

- **WHEN** a GP creates or edits an InvestorAccess record and checks the `exempt_from_nda` checkbox
- **THEN** the InvestorAccess is saved with `exempt_from_nda = true`
- **AND** the investor's status on the NDA dashboard shows "Exempt"

#### Scenario: GP removes exemption by re-adding InvestorAccess

- **WHEN** a GP deletes an InvestorAccess that had `exempt_from_nda = true` and re-adds it without the exempt flag
- **THEN** the investor's status on the dashboard reverts to their NDA acceptance status (Accepted, Pending, or Declined)

#### Scenario: Exemption is a simple boolean

- **WHEN** `exempt_from_nda` is set on InvestorAccess
- **THEN** there is no reason field; it is a boolean flag only

#### Scenario: Dashboard displays exemption read-only

- **WHEN** a GP views the NDA status dashboard
- **THEN** exempt investors are shown with status "Exempt"
- **AND** there are no exempt/revoke action buttons on the dashboard itself
- **AND** exemption is managed solely through the InvestorAccess form

### Requirement: Exempt investor's users bypass NDA gate

The system SHALL check for stakeholder-level exemption via InvestorAccess before checking stakeholder-level acceptance in the NDA gate, so that an exempt investor's users always access the folder without an NDA screen.

#### Scenario: Exempt investor's user accesses folder before stakeholder signs

- **WHEN** a user belonging to an exempt investor navigates to an NDA-protected folder
- **AND** no one from their stakeholder has accepted the NDA
- **THEN** the system shows the folder contents immediately (no NDA screen)

#### Scenario: Exempt investor's user accesses folder after stakeholder signs

- **WHEN** a user belonging to an exempt investor navigates to an NDA-protected folder
- **AND** their stakeholder has already accepted the NDA
- **THEN** the system shows the folder contents immediately (exemption takes precedence in display)

#### Scenario: Exemption removed, stakeholder not accepted

- **WHEN** a GP removes exemption (deletes InvestorAccess and re-adds without exempt flag)
- **AND** the investor's stakeholder has not accepted the NDA
- **AND** a user of that investor navigates to the NDA-protected folder
- **THEN** the system redirects the user to the NDA acceptance screen

#### Scenario: Gate check order

- **WHEN** a non-GP user navigates to an NDA-protected folder
- **THEN** the gate checks `InvestorAccess.exists?(user_id:, entity_id:, approved: true, exempt_from_nda: true)`
- **AND** the system checks in order: (1) GP bypass, (2) stakeholder exemption (InvestorAccess.exempt_from_nda), (3) stakeholder acceptance, (4) redirect to NDA screen
- **AND** an exempt investor's user passes at step 2 without reaching step 3

### Requirement: GP can export NDA status records

The system SHALL allow a GP to download NDA status records as an XLSX file from the dedicated dashboard.

#### Scenario: GP exports NDA status

- **WHEN** a GP clicks "Export" on the dedicated dashboard
- **THEN** the system generates an XLSX file containing all investors and users with columns: Investor Name, User Name, Email, Status, NDA Version, Signed Date, Valid Until
- **AND** the file downloads to the GP's browser

### Requirement: NDA Settings hidden on Data Room root

The system SHALL hide the NDA Settings option on the Data Room root folder, since NDA is configured on sub-folders inside Data Room, not the root.

#### Scenario: NDA Settings not available on root folder

- **WHEN** a GP navigates to the Data Room root folder
- **THEN** the Actions dropdown does not include an "NDA Settings" option

#### Scenario: NDA Settings available on sub-folders

- **WHEN** a GP navigates to a sub-folder inside Data Room
- **THEN** the Actions dropdown includes an "NDA Settings" option
