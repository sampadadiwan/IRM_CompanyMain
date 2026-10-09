# Spec Delta

## Purpose

Keeps a fund's generated financial statements as records that can be reviewed, locked with a
frozen copy of their figures, compared against prior periods and downloaded, and warns when the
data behind a locked statement changes.

## ADDED Requirements

### Requirement: Statement records
The system SHALL keep one financial statement set per fund and period (start date, end date),
covering every statement of the fund (Balance Sheet, Profit & Loss, Changes in Partners' Capital
and schedules) generated together, with
status Draft or Locked, the accounting run and statements run it was built from, its check
results and its unmapped count. Generating a period that already has a Draft SHALL regenerate
that Draft.

#### Scenario: Generate creates a draft
- **WHEN** a user generates statements for 1 Jul–30 Sep 2026 on a fund with the three core statements and a Schedule of Fund Expenses
- **THEN** a Draft statement set for that period appears in the Statements list, containing the Balance Sheet, Profit & Loss, Statement of Changes in Partners' Capital and Schedule of Fund Expenses

#### Scenario: Duplicate period
- **WHEN** a Draft for 1 Jul–30 Sep 2026 exists and the user generates the same period
- **THEN** the same Draft is regenerated; no second record is created

### Requirement: Lock with frozen copy
The system SHALL allow locking only when every check has passed (or is skipped) and the unmapped
count is zero. Locking SHALL lock the statement's statements run and store a frozen copy of every
line figure, the mapping and layout used, and the check results, with who locked it and when.

#### Scenario: Lock disabled by unmapped entries
- **WHEN** a Draft has 2 unmapped entries
- **THEN** Lock is disabled with "Map or exclude 2 entries before locking"

#### Scenario: Lock succeeds
- **WHEN** a Draft with all checks passed and nothing unmapped is locked by R. Iyer
- **THEN** it shows "Locked on <date> by R. Iyer" and its figures are frozen

### Requirement: Unlock of allocation runs over locked statements
When a user unlocks allocation runs (Unlock or Unlock all) whose period overlaps a locked
statement, the system SHALL first show a confirmation popup naming the affected statements. On
confirmation, those statements SHALL return to Draft, their frozen copy SHALL be kept until they
are locked again, and the fund's Fund accounting users SHALL be notified (email + in-app) with
who unlocked, the fund and the periods. Cancelling SHALL leave everything locked.

#### Scenario: Warning shown
- **WHEN** a user clicks Unlock on accounting run #3331 and the Q3 2026 statement is locked
- **THEN** a popup says the Q3 2026 statements will go back to Draft and Fund accounting will be notified

#### Scenario: Confirmed unlock
- **WHEN** the user confirms
- **THEN** the runs are unlocked, the Q3 2026 statement is Draft, and Fund accounting users receive one notification

#### Scenario: No locked statements
- **WHEN** the period has no locked statement
- **THEN** Unlock behaves exactly as today, with no popup and no notification

### Requirement: Drift warning
When a locked statement is opened or downloaded, the system SHALL recompute its figures from
current data and, for any line that differs from the frozen copy by 1 unit or more, show a
"Changed since locked" warning listing each line with locked and current figures. Downloads of a
locked statement SHALL use the frozen figures.

#### Scenario: Edited entry behind a locked statement
- **WHEN** "Non Deal Expense / Audit Fees" for Q2 2026 is edited from 30,000 to 32,700 after Q2 2026 was locked
- **THEN** opening Q2 2026 shows "Changed since locked: Professional fees 45,200 → 47,900"

#### Scenario: No drift
- **WHEN** nothing behind a locked statement changed
- **THEN** no warning is shown

### Requirement: Comparatives from frozen copies
Statement columns SHALL be: At-a-date statements (Balance Sheet and date schedules) — at period
end and at the prior financial year-end; For-a-period statements (Profit & Loss, Changes in
Partners' Capital and period schedules) — current period, year to date, and the same year-to-date
period of the prior year. Prior-period columns SHALL use the frozen copy of the
locked statement for that period; when it has drifted they SHALL be marked "Changed since
locked"; when no locked statement exists they SHALL be computed from current data and headed
"Not locked — computed". The current-period and year-to-date columns SHALL be computed by the
statements run.

#### Scenario: Prior year from frozen copy
- **WHEN** the FY 2025 statement is locked with Professional fees 88,400 and FY 2025 entries were later edited
- **THEN** the Q3 2026 statement's prior-year column shows 88,400 marked "Changed since locked"

#### Scenario: First year on CapHive
- **WHEN** no statement for the prior year exists
- **THEN** the prior-year column is headed "Not locked — computed"

### Requirement: Excel and PDF output
The system SHALL let users download each statement set as Excel (one sheet per statement) and PDF
(one section per statement), with the comparatives and the checks. Drafts SHALL be watermarked "DRAFT". Dates SHALL
follow the user's locale on screen.

#### Scenario: Draft PDF
- **WHEN** a user downloads a Draft as PDF
- **THEN** each page carries a "DRAFT" watermark

### Requirement: Access
Viewing statements SHALL require read access to the fund; generating, editing mapping or layout,
and locking SHALL require update access to the fund.

#### Scenario: Read-only user
- **WHEN** a user with read-only access opens Financial Statements
- **THEN** they can view and download but Generate, Lock and the mapping editors are not shown
