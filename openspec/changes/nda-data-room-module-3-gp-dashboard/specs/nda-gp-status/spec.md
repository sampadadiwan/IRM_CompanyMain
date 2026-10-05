# Spec Delta

## Purpose

GP-facing NDA status dashboard providing visibility into investor NDA acceptance status, user-level exemption management, bulk reminder sending, and compliance export for NDA-protected Data Room folders.

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
- **AND** the status is "Exempt" only if every user of that investor with folder access is individually exempted

#### Scenario: User-level detail in expanded row

- **WHEN** a GP expands an investor row
- **THEN** each user under that investor with folder access is shown
- **AND** the user who physically signed the NDA is marked as "Signer"
- **AND** exempt users show status "Exempt"
- **AND** users with the NDA tag on their InvestorAccess show "(NDA)" next to their name
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

### Requirement: GP can exempt individual users from NDA

The system SHALL allow a GP to mark individual users as exempt from a specific NDA, and exempt users SHALL bypass the NDA gate entirely.

#### Scenario: GP creates exemption for a user

- **WHEN** a GP marks a user as exempt from the NDA on the dedicated dashboard
- **THEN** an exemption record is created for that user and NDA config
- **AND** the user's status on the dashboard changes to "Exempt"
- **AND** the exemption records which GP created it

#### Scenario: GP provides exemption reason

- **WHEN** a GP creates an exemption and provides a reason (e.g., "NDA signed offline")
- **THEN** the reason is stored with the exemption record

#### Scenario: GP revokes exemption

- **WHEN** a GP revokes a user's exemption on the dedicated dashboard
- **THEN** the exemption record is removed
- **AND** the user's status reverts to their stakeholder's status (Accepted, Pending, or Declined)

#### Scenario: Exemption uniqueness

- **WHEN** a GP attempts to create a second exemption for the same user and NDA config
- **THEN** the system does not create a duplicate (one exemption per user per NDA config)

### Requirement: Exempt user bypasses NDA gate

The system SHALL check for user-level exemptions before checking stakeholder-level acceptance in the NDA gate, so that exempt users always access the folder without an NDA screen.

#### Scenario: Exempt user accesses NDA-protected folder before stakeholder signs

- **WHEN** an exempt user navigates to an NDA-protected folder
- **AND** no one from their stakeholder has accepted the NDA
- **THEN** the system shows the folder contents immediately (no NDA screen)

#### Scenario: Exempt user accesses folder after stakeholder signs

- **WHEN** an exempt user navigates to an NDA-protected folder
- **AND** their stakeholder has already accepted the NDA
- **THEN** the system shows the folder contents immediately (exemption takes precedence in display)

#### Scenario: Exemption revoked, stakeholder not accepted

- **WHEN** a GP revokes a user's exemption
- **AND** the user's stakeholder has not accepted the NDA
- **AND** the user navigates to the NDA-protected folder
- **THEN** the system redirects the user to the NDA acceptance screen

#### Scenario: Gate check order

- **WHEN** a non-GP user navigates to an NDA-protected folder
- **THEN** the system checks in order: (1) user exemption, (2) stakeholder acceptance
- **AND** an exempted user passes at step 1 without reaching step 2

### Requirement: GP can export NDA status records

The system SHALL allow a GP to download NDA status records as an XLSX file from the dedicated dashboard.

#### Scenario: GP exports NDA status

- **WHEN** a GP clicks "Export" on the dedicated dashboard
- **THEN** the system generates an XLSX file containing all investors and users with columns: Investor Name, User Name, Email, Status, NDA Version, Signed Date, Valid Until, Exemption Reason
- **AND** the file downloads to the GP's browser

### Requirement: GP can send bulk NDA reminders to pending investors

The system SHALL allow a GP to send reminder notifications to NDA-tagged users of investors who have not yet accepted the NDA.

#### Scenario: GP sends reminders to pending investors

- **WHEN** a GP clicks "Send Reminders" on the dedicated dashboard
- **AND** confirms the action in the confirmation dialog
- **THEN** the system sends reminder notifications to all NDA-tagged users of investors with "Pending" status
- **AND** shows a success message with the count of users reminded

#### Scenario: Reminder targets only NDA-tagged users

- **WHEN** a pending investor has three users: User A (NDA-tagged), User B (NDA-tagged), User C (not tagged)
- **THEN** only User A and User B receive the reminder notification
- **AND** User C does not receive a reminder

#### Scenario: Reminder content directs user to Data Room

- **WHEN** a user receives an NDA reminder notification
- **THEN** the notification includes a link that takes the user to the Data Room where they can review and accept the NDA

#### Scenario: No pending investors

- **WHEN** a GP clicks "Send Reminders" and no investors have "Pending" status
- **THEN** the button is disabled or a message indicates "No pending investors to remind"

#### Scenario: Reminder not sent to exempt users

- **WHEN** a user is exempt from the NDA
- **THEN** the user does not receive a reminder notification, even if their InvestorAccess has the NDA tag
