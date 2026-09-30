# Spec Delta

## Purpose

Turns a connected fund's Xero profit-and-loss and balance-sheet figures into fund-level account
entries, once per account per period, keeping them in step with Xero corrections without ever
silently changing a period an allocation run has already used.

## ADDED Requirements

### Requirement: Account mapping
The system SHALL keep, per connected fund, a list of the organisation's Xero accounts, each
Unmapped, Mapped (with entry type, entry name and a sign-flip choice) or Ignored. Accounts
first seen in a sync SHALL be added as Unmapped and the fund admins SHALL be notified once
per sync that adds any.

#### Scenario: First connection
- **WHEN** a fund is connected
- **THEN** every account in the organisation is listed as Unmapped and no account entries are created

#### Scenario: New account in Xero
- **WHEN** a sync finds an account not yet on the list
- **THEN** it is added as Unmapped and one notification lists the new accounts

#### Scenario: Map an account
- **WHEN** a fund admin maps "6150 Legal Fees" to entry type "Expense" with name "Legal Fees"
- **THEN** the next sync imports that account's figures under that type and name

#### Scenario: Mapping validation
- **WHEN** a fund admin saves a mapped account without an entry type
- **THEN** the mapping is not saved and the missing field is reported

### Requirement: Period pull
The system SHALL, each night, pull the two most recently finished periods (by the fund's
Monthly or Quarterly setting) for every connected fund, and SHALL pull a single chosen
period on request. For each Mapped account with a non-zero figure it SHALL produce one
fund-level account entry dated the period end: period movement for profit-and-loss accounts
(not cumulative), closing balance for balance-sheet accounts (cumulative). Unmapped and
Ignored accounts SHALL NOT produce entries.

#### Scenario: Nightly quarterly pull
- **WHEN** the nightly sync runs on 15/10/2026 for a quarterly fund
- **THEN** the quarters ending 30/09/2026 and 30/06/2026 are pulled

#### Scenario: Profit-and-loss account
- **WHEN** mapped account "6100 Audit Fees" shows 12,000.00 for the quarter ending 30/09/2026
- **THEN** a fund-level entry "Audit Fees" of 12,000.00, not cumulative, dated 30/09/2026, with no folio, exists

#### Scenario: Balance-sheet account
- **WHEN** mapped balance-sheet account "2100 Accrued Expenses" shows 3,400.00 at 30/09/2026
- **THEN** a cumulative fund-level entry of 3,400.00 dated 30/09/2026 exists

#### Scenario: Sign flip
- **WHEN** an account mapped with sign flip shows 500.00
- **THEN** the entry amount is -500.00

#### Scenario: Zero and unmapped accounts
- **WHEN** a pull contains an Unmapped account, an Ignored account and a Mapped account with 0.00
- **THEN** none of them produces an entry

#### Scenario: Sync now for an older period
- **WHEN** a fund admin chooses Sync now for 31/03/2026
- **THEN** only that period is pulled and the Xero tab shows the sync as queued

### Requirement: One entry per account per period
The system SHALL identify an entry it imported by the fund, the period end date and the Xero
account's identifier, and SHALL update that entry rather than create another when the figure
changes. When a previously imported account's figure becomes zero or disappears from the
period, the entry SHALL be removed. Entries not created by the sync SHALL never be changed.

#### Scenario: Correction in Xero
- **WHEN** "Audit Fees" for 30/09/2026 changes in Xero from 12,000.00 to 14,500.00 and the period has no allocation run
- **THEN** the existing entry's amount becomes 14,500.00 and there is still exactly one such entry

#### Scenario: Repeat pull unchanged
- **WHEN** the same period is pulled twice with no change in Xero
- **THEN** no entry is added, changed or removed

#### Scenario: Figure removed in Xero
- **WHEN** the only "Legal Fees" posting for the period is deleted in Xero and the period has no allocation run
- **THEN** the imported "Legal Fees" entry for that period is removed

#### Scenario: Hand-entered entry untouched
- **WHEN** a hand-uploaded fund-level entry "Audit Fees" exists for 30/09/2026 and Xero also has Audit Fees
- **THEN** the uploaded entry is unchanged and the synced entry exists alongside it

### Requirement: Allocated periods are held for review
The system SHALL NOT create, change or remove a synced entry whose date is covered by any
allocation run for the fund (locked or not). Instead it SHALL record a change awaiting review
showing the account, period, current CapHive amount and new Xero amount, and notify the fund
admins once per sync that adds items. Applying a held change SHALL perform it; dismissing it
SHALL leave CapHive unchanged until the Xero figure changes again.

#### Scenario: Change in an allocated period
- **WHEN** "Audit Fees" for 30/06/2026 changes in Xero from 12,000.00 to 14,500.00 and an allocation run covers 30/06/2026
- **THEN** the entry stays 12,000.00 and a review item "12,000.00 → 14,500.00" appears

#### Scenario: New account figure in an allocated period
- **WHEN** a newly mapped account has a figure for a period covered by an allocation run
- **THEN** no entry is created and a review item "none → amount" appears

#### Scenario: Apply
- **WHEN** a fund admin applies the review item
- **THEN** the entry becomes 14,500.00, the item leaves the list, and the admin is told to re-run the allocation for that date

#### Scenario: Dismiss and later change
- **WHEN** a fund admin dismisses the item and a later sync sees the same 14,500.00
- **THEN** no new item appears; if Xero later shows 15,000.00 a new item appears

#### Scenario: Unchanged figure while held
- **WHEN** a pending review item exists and the next sync sees the same Xero figure
- **THEN** no duplicate review item is created
