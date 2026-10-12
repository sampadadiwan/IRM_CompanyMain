# funds/financial-statement-mapping Specification

## Purpose

Lets a fund define its own statement accounts and statement layout, and map its fund-level
account entries onto those accounts, so financial statements can be built from the entries the
fund already has without any entry silently falling out of the totals.

## Requirements

### Requirement: Statement accounts per fund
The system SHALL let a user with update rights on a fund create, rename, retype and delete
statement accounts for that fund. Each account SHALL have a name unique within the fund, a type
(Asset, Liability, Partners' capital, Income, Expense, Gain/Loss) and a behaviour (Balance or
Movement). Balance SHALL default for Asset, Liability and Partners' capital; Movement for the rest.

#### Scenario: Create an expense account
- **WHEN** a user adds account "Professional fees" of type Expense to Alpha Fund I
- **THEN** the account is saved with behaviour Movement and is visible only on Alpha Fund I

#### Scenario: Duplicate account name rejected
- **WHEN** a user adds a second account named "Professional fees" to the same fund
- **THEN** the save fails with "Name has already been taken"

#### Scenario: Account in use cannot be deleted
- **WHEN** a user deletes an account referenced by a mapping rule or the layout
- **THEN** the delete is refused with a message naming the rules/layout rows that use it

### Requirement: Statements per fund
Every fund using financial statements SHALL have three core statements — Balance Sheet (column
style At a date), Profit & Loss and Statement of Changes in Partners' Capital (column style For a
period) — which can be renamed but not deleted. A user with update rights SHALL be able to add,
rename and delete schedules, each with a name unique within the fund and a column style (At a
date or For a period).

#### Scenario: Core statements created
- **WHEN** a user saves the first statement account of Alpha Fund I
- **THEN** the fund has Balance Sheet, Profit & Loss and Statement of Changes in Partners' Capital

#### Scenario: Core statement renamed
- **WHEN** a user renames "Profit & Loss" to "Statement of Operations"
- **THEN** the new name is used on screen and in downloads

#### Scenario: Core statement cannot be deleted
- **WHEN** a user tries to delete the Balance Sheet
- **THEN** the delete is refused with "Core statements can be renamed but not deleted"

#### Scenario: Add a schedule
- **WHEN** a user adds "Schedule of Fund Expenses" with column style For a period
- **THEN** it appears in the Layout tab and in every statement set generated afterwards

### Requirement: Statement layout
The system SHALL let a user arrange, per statement, an ordered list of section headings, accounts
and subtotals. A subtotal SHALL sum the rows it names. One account MAY appear on more than one
statement.

#### Scenario: Subtotal sums its rows
- **WHEN** the Profit & Loss layout has "Total expenses" as a subtotal of "Management fees" (-250,000) and "Professional fees" (-45,200)
- **THEN** the statement shows "Total expenses" as -295,200

#### Scenario: Reorder rows
- **WHEN** a user drags "Professional fees" above "Management fees"
- **THEN** the new order is saved and used on the next preview and generation

#### Scenario: Account on two statements
- **WHEN** "Audit fees" is placed on the Profit & Loss and on the Schedule of Fund Expenses
- **THEN** both show the same figure for the period

### Requirement: Mapping rules
The system SHALL let a user create rules matching fund-level account entries by entry type and
optionally an exact name. A rule SHALL target either one statement account of the same fund or
Excluded. There SHALL be at most one rule per (entry type, name) per fund. When an entry matches
both an exact-name rule and an entry-type-only rule, the exact-name rule SHALL apply. Only
fund-level entries (no investor folio) SHALL be mapped.

#### Scenario: Entry-type rule catches new names
- **WHEN** a rule maps entry type "Deal Expense" (any name) to "Transaction costs" and a new entry "Deal Expense / Acme Ltd" is uploaded
- **THEN** that entry's amount is included in "Transaction costs" without any new rule

#### Scenario: Exact rule wins
- **WHEN** "Non Deal Expense" (any name) maps to "Other expenses" and "Non Deal Expense / Audit Fees" maps to "Professional fees"
- **THEN** Audit Fees amounts count only in "Professional fees"

#### Scenario: Excluded entries
- **WHEN** entry type "Portfolio Allocation" is mapped to Excluded
- **THEN** those entries appear in no statement line and not in the Unmapped list

#### Scenario: Folio-level entries ignored
- **WHEN** an investor-level entry "Non Deal Expense / Audit Fees" exists for folio F-102
- **THEN** it contributes nothing to any statement line

### Requirement: Unmapped list
The system SHALL list, for a chosen period, every fund-level (entry type, name) with a non-zero
total in that period that matches no rule, with its total and a Map action pre-filling a new
rule.

#### Scenario: New unmapped name appears
- **WHEN** "Non Deal Expense / Director Fees" of 8,000 is uploaded for Q3 2026 and no rule matches it
- **THEN** the Unmapped panel for Q3 2026 shows "Non Deal Expense · Director Fees · 8,000" with a Map button

#### Scenario: Map from the list
- **WHEN** the user clicks Map on that row and picks "Professional fees"
- **THEN** a rule is saved, the row leaves the Unmapped panel and the preview of "Professional fees" rises by 8,000

### Requirement: Live preview
The system SHALL show, for a chosen period, each statement account's figure computed from the
current mapping and current account entries, updating after each rule change without running
an allocation and without saving any statement.

#### Scenario: Preview updates on rule change
- **WHEN** the user changes "Tax / TDS" from Excluded to "Other expenses"
- **THEN** the "Other expenses" preview rises by the TDS total for the period, and no account entry is created

### Requirement: Balance and movement figures
The system SHALL compute a Balance account as its value at the period end and a Movement account
as its change over the period, from either cumulative or periodic entries:
a Movement SHALL be the sum of periodic entries dated in the period, or the latest cumulative
value at the end less the latest cumulative value before the start; a Balance SHALL be the
latest cumulative value at the end, or the sum of all periodic entries up to the end.

#### Scenario: Movement from cumulative entries
- **WHEN** "Interest income" comes from cumulative entries of 7,800 at 30 Jun 2026 and 11,900 at 30 Sep 2026
- **THEN** its Q3 2026 movement is 4,100

#### Scenario: Balance from periodic entries
- **WHEN** "Cash" comes from periodic entries of 100,000 (Q1), -20,000 (Q2) and 5,000 (Q3 2026)
- **THEN** its balance at 30 Sep 2026 is 85,000

### Requirement: AI-drafted mapping from existing statements
The system SHALL accept one PDF or Excel file of the fund's existing financial statements (≤ 20 MB)
— any period — and SHALL produce a draft of accounts, layout and rules: for each printed line, the
fund's account entries that will feed it. The draft SHALL propose the mapping only and SHALL NOT
compare printed amounts with CapHive figures. It SHALL list mapping gaps: lines no entry feeds and
entries not used by any line. A draft SHALL NOT change the fund's mapping until a user approves it;
Discard SHALL remove it.

#### Scenario: Draft maps printed lines to account entries
- **WHEN** the uploaded statement prints "Professional fees" and the fund has entries Non Deal Expense · Audit Fees and Legal Fees
- **THEN** the draft shows Professional fees fed by both entries, marked Mapped, with no amounts compared

#### Scenario: Mapping gaps listed
- **WHEN** the draft leaves Tax · TDS on no line
- **THEN** it is listed as an entry not used, and the user can place it on a line or Exclude it from the review

#### Scenario: Nothing saved before approval
- **WHEN** a user discards a draft
- **THEN** the fund's accounts, layout and rules are unchanged

#### Scenario: Unsupported file
- **WHEN** the user uploads a .docx file
- **THEN** the upload is refused with "Upload a PDF or Excel file"
