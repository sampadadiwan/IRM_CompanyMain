# Spec Delta

## MODIFIED Requirements

### Requirement: Investor-level status derivation

The system SHALL derive investor NDA status at read time including a new "Expired" status for acceptances that are stale due to version mismatch or time expiry.

#### Scenario: Investor-level status derivation

- **WHEN** the dashboard renders an investor row
- **THEN** the status is "Exempt" if any InvestorAccess for that investor has exempt_from_nda=true
- **AND** the status is "Pending" if no NdaAcceptance record exists for that investor and NDA config
- **AND** the status is "Declined" if the latest NdaAcceptance has status "declined"
- **AND** the status is "Expired" if the latest NdaAcceptance has status "accepted" but the acceptance's `nda_version` does not match the NDA config's current `version`, or the acceptance has exceeded the validity period
- **AND** the status is "Accepted" if the latest NdaAcceptance has status "accepted" at the current version and has not expired

### Requirement: Status summary displayed in NDA Settings modal

The system SHALL display a Status tab in the NDA Settings modal showing NDA acceptance counters and an investor status table when the folder has an active NDA config.

#### Scenario: GP views status summary for NDA-protected folder

- **WHEN** a GP opens the NDA Settings modal for a folder with an enabled NDA config
- **THEN** the Status tab is enabled and clickable
- **AND** clicking the Status tab shows counters for Accepted, Pending, Declined, Expired, and Exempt investor statuses
- **AND** a simple table lists all investors with access to the folder, showing: Investor Name, Status, Signed By, Date
- **AND** a "View Full Dashboard" link is visible

#### Scenario: Status tab hidden when no active NDA

- **WHEN** a GP opens the NDA Settings modal for a folder without an enabled NDA config
- **THEN** the Status tab is not visible (only the Settings tab is shown)

## ADDED Requirements

### Requirement: Expired status on dedicated dashboard

The system SHALL display "Expired" as a filterable status on the dedicated NDA status dashboard, with a reason indicator distinguishing version mismatch from time expiry.

#### Scenario: Expired investor shown on dashboard

- **WHEN** a GP views the NDA status dashboard
- **AND** an investor's latest acceptance is at an old NDA version or has exceeded the validity period
- **THEN** the investor's status shows as "Expired"
- **AND** a reason indicator shows "Version" (for version mismatch) or "Period" (for time expiry)

#### Scenario: Dashboard counters include Expired

- **WHEN** a GP views the NDA status dashboard
- **THEN** the counter row shows five statuses: Accepted, Pending, Declined, Expired, Exempt

#### Scenario: Dashboard filtered by Expired status

- **WHEN** a GP selects "Expired" from the status filter
- **THEN** only investors with Expired status are shown

#### Scenario: XLSX export includes Expired status

- **WHEN** a GP exports the NDA status dashboard to XLSX
- **THEN** the export includes investors with "Expired" status and the reason column
