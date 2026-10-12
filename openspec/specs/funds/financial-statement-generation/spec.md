# funds/financial-statement-generation Specification

## Purpose

Produces a fund's financial-statement lines as account entries through a dedicated statements
allocation run, kept separate from the fund's accounting runs, and checks the result for
internal consistency.

## Requirements

### Requirement: Statement formula
The system SHALL provide a fund formula type that, when run, computes every statement account
of the fund for the run's period from the fund's mapping and writes one fund-level account entry
per account and figure, with entry type "Financial Statement". It SHALL be evaluated once per
fund, not once per investor.

#### Scenario: Lines written as account entries
- **WHEN** a statements run for Q3 2026 completes on a fund with 40 statement accounts
- **THEN** fund-level entries with entry type "Financial Statement", reporting date 30 Sep 2026, exist for those accounts, and no investor-level entries are created

### Requirement: Separate statements run
The system SHALL start statements runs from the Financial Statements screen as allocation runs
containing only the fund's statement formulas, with investor statements and fund ratios
switched off. A statements run SHALL delete and replace only entries created by statement
formulas for its period. An allocation run started any other way SHALL NOT run statement
formulas, even when no tags are selected.

#### Scenario: Accounting entries untouched by a statements run
- **WHEN** a statements run for Q3 2026 completes
- **THEN** every non-"Financial Statement" account entry for Q3 2026 is unchanged

#### Scenario: Ordinary run skips statement formulas
- **WHEN** a user runs allocations for Q3 2026 from the allocate screen with no tags
- **THEN** no "Financial Statement" entries are created or deleted

### Requirement: Statements run preconditions
The system SHALL refuse to start a statements run when (a) no allocation run of the fund with
status Success covers the whole period, (b) any allocation run of the fund is in progress, or
(c) the fund has no enabled statement formula. It SHALL record the covering accounting run on the
statement.

#### Scenario: No accounting run
- **WHEN** a user generates Q3 2026 statements and the fund has no successful run covering 1 Jul–30 Sep 2026
- **THEN** generation is refused with "Run and complete the fund's allocations for this period first."

#### Scenario: Run in progress
- **WHEN** an allocation run on the fund has status Pending
- **THEN** generation is refused with "An allocation run is in progress for this fund. Try again when it finishes."

#### Scenario: Source run recorded
- **WHEN** generation succeeds with accounting run #3331 covering the period
- **THEN** the statement shows "Built from accounting run #3331"

### Requirement: One statement set per end date
The system SHALL refuse to generate statements for a period whose end date equals the end date of
another statement set of the same fund with a different start date, naming that set; the existing
set's year-to-date column covers the longer period.

#### Scenario: Same end date, different period
- **WHEN** Q3 2026 statements (1 Jul–30 Sep 2026) exist and the user generates 1 Jan–30 Sep 2026
- **THEN** generation is refused with a message naming the 1 Jul–30 Sep 2026 statements and nothing is created

### Requirement: Statements run allowed over locked accounting runs
A locked allocation run SHALL NOT block a new run whose formulas are all statement formulas. It
SHALL continue to block every other overlapping run as today. A locked statements run SHALL block
another statements run over an overlapping period.

#### Scenario: Locked accounting run
- **WHEN** accounting run #3331 for Q3 2026 is locked and a user generates Q3 2026 statements
- **THEN** the statements run starts

#### Scenario: Locked statements run
- **WHEN** the Q3 2026 statements run is locked and a user clicks Regenerate
- **THEN** regeneration is refused with "These statements are locked."

#### Scenario: Ordinary run still blocked
- **WHEN** accounting run #3331 is locked and a user starts an ordinary allocation run for Q3 2026
- **THEN** it is refused as today

### Requirement: Completeness warnings
The system SHALL warn, without blocking Lock, when a cumulative entry feeding an account has no
row dated within the period (stale balance), when an account placed on a statement is fed by no
entries, and when an entry is stored both as a running total and as movements. Locking a set with
warnings SHALL ask the user to confirm them.

#### Scenario: Stale balance
- **WHEN** Cash is uploaded as a running total whose latest row is 30 Jun 2026 and Q3 2026 statements are generated
- **THEN** Cash shows its 30 Jun 2026 value and a warning names the date of that value

#### Scenario: Account with no entries
- **WHEN** "Accrued expenses" is on the Balance Sheet and no rule feeds it
- **THEN** the line shows 0 and a warning says no entries feed it

### Requirement: Integrity checks
Each generated statement SHALL carry four checks with pass/fail and the difference:
(1) Balance — total assets − total liabilities = total partners' capital;
(2) NAV tie-out — total partners' capital = the fund's NAV entry at the period end (skipped with
"No NAV entry" when none exists);
(3) Partners' capital tie-out — total partners' capital = the sum of investor capital-account
balances at the period end (skipped with "Not configured" when the fund has no capital entry set);
(4) Roll-forward — opening partners' capital + the rows of the Statement of Changes in Partners'
Capital = closing partners' capital.
Differences under 1 unit of fund currency SHALL pass.

#### Scenario: Balance check fails
- **WHEN** assets are 10,000,000, liabilities 200,000 and partners' capital 9,798,800
- **THEN** the Balance check fails with difference 1,200

#### Scenario: Rounding tolerated
- **WHEN** the difference is 0.40
- **THEN** the check passes

#### Scenario: No NAV entry
- **WHEN** the fund has no NAV entry at the period end
- **THEN** the NAV tie-out shows "Skipped — no NAV entry" and does not block locking

#### Scenario: Capital tie-out not configured
- **WHEN** the fund has no capital entry set in its financial statement settings
- **THEN** the Partners' capital tie-out shows "Skipped — not configured" and does not block locking
