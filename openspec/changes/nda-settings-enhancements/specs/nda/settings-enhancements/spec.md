# Spec Delta

## Purpose

NDA settings form improvements that protect LP access during inherited NDA overrides, prevent retroactive validity changes after acceptance, surface expiry visibility, fix expired NDA editing, and resolve dashboard dropdown clipping.

## ADDED Requirements

### Requirement: Actions dropdown visible on single-row NDA Status table

The NDA Status dashboard's kebab Actions dropdown SHALL render fully visible when only one investor row exists in the table, without being clipped by the table container's overflow boundary.

#### Scenario: Single investor row shows dropdown
- **WHEN** the NDA Status dashboard renders with exactly one investor row
- **AND** the GP clicks the kebab (three-dot) Actions button
- **THEN** the dropdown menu SHALL render fully visible, overlapping the table boundary if needed

#### Scenario: Multiple investor rows still show dropdown
- **WHEN** the NDA Status dashboard renders with multiple investor rows
- **AND** the GP clicks any kebab Actions button
- **THEN** the dropdown menu SHALL render fully visible (no regression)

### Requirement: Resign checkbox when overriding inherited NDA

When a GP clicks "Set Own NDA" on a folder that inherits its parent's NDA and LPs have already accepted that inherited NDA for this folder, the NDA settings form SHALL display a resign checkbox showing the count of accepted investors and offering the choice to require re-signing.

#### Scenario: Override with inherited acceptances shows resign checkbox
- **WHEN** a child folder inherits an enabled NDA from its parent
- **AND** 3 LPs have accepted the inherited NDA with folder-level access rights on the child
- **AND** the GP clicks "Set Own NDA" on the child folder
- **THEN** the form SHALL display: "3 investors have already signed the inherited NDA for this folder"
- **AND** the form SHALL display an unchecked checkbox: "Require them to re-sign the new NDA"

#### Scenario: Override without inherited acceptances hides resign checkbox
- **WHEN** a child folder inherits an enabled NDA from its parent
- **AND** no LPs have accepted the inherited NDA for this folder
- **AND** the GP clicks "Set Own NDA"
- **THEN** the form SHALL NOT display the resign checkbox section

#### Scenario: Resign unchecked migrates acceptances
- **WHEN** the GP saves the new NDA with the resign checkbox unchecked (default)
- **THEN** the system SHALL copy accepted NdaAcceptance records from the inherited NDA to the new NDA, scoped to investors with folder-level access rights on this folder
- **AND** the copied acceptances SHALL preserve the original accepted_at timestamp
- **AND** the original acceptance records on the parent NDA SHALL remain untouched
- **AND** the child folder's NDA Status SHALL show those LPs as "Accepted"

#### Scenario: Resign checked starts fresh
- **WHEN** the GP saves the new NDA with the resign checkbox checked
- **THEN** the system SHALL NOT copy any acceptance records
- **AND** the child folder's NDA Status SHALL show all LPs as "Pending"

#### Scenario: Version record stores actual resign choice
- **WHEN** the GP saves the new NDA (either resign option)
- **THEN** the NdaConfigVersion record SHALL store the actual resign_required value from the checkbox

### Requirement: Validity type locked after acceptances

When any LP has accepted an NDA, the validity type radio buttons (Until Revoked, Fixed Period, Specific Date) SHALL be disabled to prevent retroactive type changes that could break existing LP access calculations.

#### Scenario: Validity radios disabled when acceptances exist
- **WHEN** the GP opens edit NDA settings
- **AND** at least 1 LP has accepted the NDA
- **THEN** all three validity type radio buttons SHALL be disabled
- **AND** a lock icon with explanation SHALL display: "Validity type is locked because investors have already accepted. To change type, upload a new NDA version with re-sign required."

#### Scenario: Validity radios enabled when no acceptances
- **WHEN** the GP opens edit NDA settings
- **AND** no LPs have accepted the NDA
- **THEN** all three validity type radio buttons SHALL be enabled
- **AND** no lock message SHALL display

#### Scenario: Fixed period can only extend when locked
- **WHEN** validity type is locked at "Fixed Period" with current period of 90 days
- **THEN** the period dropdown SHALL only show options >= 90 days (90, 180, 365)
- **AND** the dropdown SHALL NOT show 30 days

#### Scenario: Specific date can only extend when locked
- **WHEN** validity type is locked at "Specific Date" with current date of 2027-03-15
- **AND** the date has not expired
- **THEN** the date picker min attribute SHALL be set to 2027-03-15
- **AND** the GP SHALL NOT be able to select an earlier date

### Requirement: Expiry summary on NDA edit

When editing an NDA with time-based validity (Fixed Period or Specific Date), the form SHALL display when existing acceptances expire so the GP can decide whether to revise the NDA.

#### Scenario: Fixed period shows expiry range
- **WHEN** the GP edits an NDA with "Fixed Period" validity of 90 days
- **AND** the earliest LP accepted on Jan 15, 2027 and latest on Mar 22, 2027
- **THEN** the form SHALL display: "Earliest expiry: Apr 15, 2027 · Latest expiry: Jun 20, 2027"

#### Scenario: Specific date shows single expiry
- **WHEN** the GP edits an NDA with "Specific Date" validity set to Dec 31, 2027
- **THEN** the form SHALL display: "All NDAs expire on: Dec 31, 2027"

#### Scenario: Until revoked shows no expiry summary
- **WHEN** the GP edits an NDA with "Until Revoked" validity
- **THEN** the form SHALL NOT display any expiry summary

#### Scenario: No accepted investors shows no expiry summary
- **WHEN** the GP edits an NDA with "Fixed Period" validity
- **AND** no LPs have accepted
- **THEN** the form SHALL NOT display any expiry summary

### Requirement: Expired NDA can be edited and saved

When an NDA has a specific_date validity that has expired (date in the past), the GP SHALL be able to save changes to the NDA settings without the form silently blocking submission.

#### Scenario: Save expired NDA with new future date
- **WHEN** the GP opens edit settings for an NDA with expired validity_date (e.g., 2026-10-08, today is 2026-10-13)
- **AND** the GP selects a new future date (e.g., 2027-01-01)
- **AND** the GP clicks Save
- **THEN** the form SHALL submit successfully
- **AND** the NDA SHALL be updated with the new date

#### Scenario: Save expired NDA without changing date
- **WHEN** the GP opens edit settings for an expired NDA
- **AND** the GP changes only the contact email without touching the date
- **AND** the GP clicks Save
- **THEN** the form SHALL submit successfully
- **AND** the contact email SHALL be updated
- **AND** the expired validity_date SHALL remain unchanged

#### Scenario: Date picker min is tomorrow for expired NDA
- **WHEN** the GP opens edit settings for an NDA with expired validity_date
- **THEN** the date picker min attribute SHALL be set to tomorrow's date
- **AND** the GP SHALL be able to select any future date for renewal
