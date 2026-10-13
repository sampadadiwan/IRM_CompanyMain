@financial_statements
Feature: Financial statement sets — view, lock, drift, comparatives and downloads
  A generated statement set is reviewed, locked with a frozen copy, compared with earlier locked
  sets, flagged when its data changes, and downloaded as Excel or PDF.
  Worked examples: openspec/changes/fund-financial-statements/design.md#worked-examples

  Background:
    Given Alpha Fund I is set up for financial statements
    And the fund has statement accounts:
      | name              | type    |
      | Professional fees | expense |
      | Cash              | asset   |
      | Contributions     | capital |
    And the mapping rules:
      | entry_type         | name         | account           |
      | Non Deal Expense   | Audit Fees   | Professional fees |
      | Non Deal Expense   | Legal Fees   | Professional fees |
      | Cash               | Bank Balance | Cash              |
      | Capital Remittance | Contribution | Contributions     |
    And fund-level entries:
      | entry_type         | name         | date       | amount  |
      | Capital Remittance | Contribution | 2025-01-15 | 500,000 |
      | Cash               | Bank Balance | 2025-01-15 | 500,000 |
      | Non Deal Expense   | Audit Fees   | 2025-05-15 | 60,000  |
      | Non Deal Expense   | Legal Fees   | 2025-08-15 | 28,400  |
      | Cash               | Bank Balance | 2025-08-15 | -88,400 |
      | Non Deal Expense   | Audit Fees   | 2026-05-15 | 30,000  |
      | Non Deal Expense   | Legal Fees   | 2026-05-20 | 15,200  |
      | Cash               | Bank Balance | 2026-05-20 | -45,200 |

  # H15 — Happy path: Ravi/Meera locks a ready set; figures are frozen and the statements run is locked —
  # also with the default validation rules on ("allocation_run_already_locked" must not block the lock)
  Scenario: Lock a statement set
    Given the default validation rules are seeded
    And a successful accounting run from "2026-04-01" to "2026-06-30"
    And statements are generated for "2026-04-01" to "2026-06-30"
    And I am logged in as Meera
    When I open the statement set
    And I lock the statement set
    Then the popup said "Checked before locking"
    And the popup said "✓ Balance"
    And the popup said "✓ Nothing unmapped"
    And the statement set shows "Locked on"
    And the statement set shows "by Meera Admin"
    And the statement set is locked with a frozen copy

  # X8 — Error case: entries nobody mapped keep Lock disabled, with the reason
  @rack_test
  Scenario: Lock disabled by unmapped entries
    Given fund-level entries:
      | entry_type       | name          | date       | amount |
      | Non Deal Expense | Director Fees | 2026-05-15 | 8,000  |
      | Tax              | TDS           | 2026-05-15 | 1,150  |
    And a successful accounting run from "2026-04-01" to "2026-06-30"
    And statements are generated for "2026-04-01" to "2026-06-30"
    And I am logged in as Meera
    When I open the statement set
    Then the statement set shows "2 account entries in this period aren't mapped"
    And Lock is disabled with "Map or exclude 2 entries before locking."

  # X9 — Error case: a failed check refuses a direct lock request; the set stays Draft
  @rack_test
  Scenario: Lock refused when a check fails
    Given the partners' capital entry is "Capital" "Closing Capital"
    And the fund has folios "F-101"
    And folio "F-101" has entries:
      | entry_type | name            | date       | amount | cumulative |
      | Capital    | Closing Capital | 2026-06-30 | 1,000  | yes        |
    And a successful accounting run from "2026-04-01" to "2026-06-30"
    And statements are generated for "2026-04-01" to "2026-06-30"
    Then locking directly is refused with "Partners' capital tie-out failed"

  # E9 — Edge case: nothing behind a locked set changed — no banner
  Scenario: No drift
    Given a successful accounting run from "2026-04-01" to "2026-06-30"
    And statements are generated for "2026-04-01" to "2026-06-30"
    And the statement set is locked by Meera
    And I am logged in as Meera
    When I open the statement set
    Then there is no drift banner

  # E10 — Edge case: an entry edited after locking shows the banner (locked → current); the PDF keeps the locked figure
  @rack_test
  Scenario: Edited entry behind a locked set
    Given a successful accounting run from "2026-04-01" to "2026-06-30"
    And statements are generated for "2026-04-01" to "2026-06-30"
    And the statement set is locked by Meera
    When the "Non Deal Expense" "Audit Fees" entry of "2026-05-15" is changed to "32,700"
    And I am logged in as Meera
    And I open the statement set on "Profit & Loss"
    Then the drift banner lists "Professional fees ($45,200) → ($47,900)"
    And the statement set's PDF shows "($45,200)"

  # H18 — Happy path: the prior-year column comes from the locked set's frozen copy, flagged when it has changed
  @rack_test
  Scenario: Prior year from the frozen copy
    Given a successful accounting run from "2025-07-01" to "2025-09-30"
    And statements are generated for "2025-07-01" to "2025-09-30"
    And the statement set is locked by Meera
    When the "Non Deal Expense" "Audit Fees" entry of "2025-05-15" is changed to "61,000"
    And a successful accounting run from "2026-07-01" to "2026-09-30"
    And statements are generated for "2026-07-01" to "2026-09-30"
    Then the "prior_ytd" column of "Profit & Loss" reads "-88,400" for "Professional fees"
    And the "prior_ytd" column of "Profit & Loss" is headed with "changed since locked"

  # E11 — Edge case: with no locked prior set, the prior column is computed and says so
  @rack_test
  Scenario: First year on CapHive
    Given a successful accounting run from "2026-04-01" to "2026-06-30"
    And statements are generated for "2026-04-01" to "2026-06-30"
    Then the "prior_ytd" column of "Profit & Loss" is headed with "Not locked — computed"
    And the "prior_ytd" column of "Profit & Loss" reads "-60,000" for "Professional fees"

  # E26 — Edge case: re-locking after an unlock and a regenerate overwrites the frozen copy
  @rack_test
  Scenario: Re-lock after unlock
    Given a successful accounting run from "2026-04-01" to "2026-06-30"
    And statements are generated for "2026-04-01" to "2026-06-30"
    And the statement set is locked by Meera
    When the allocation runs for the period are unlocked by Meera
    And the "Non Deal Expense" "Audit Fees" entry of "2026-05-15" is changed to "32,700"
    And the "Cash" "Bank Balance" entry of "2026-05-20" is changed to "-47,900"
    And statements are generated for "2026-04-01" to "2026-06-30"
    And the statement set is locked by Meera
    Then the frozen copy shows "Professional fees" of "47,900" for "period"

  # H19 — Happy path: Draft downloads — Excel has a sheet per statement, every PDF page is watermarked DRAFT
  @rack_test
  Scenario: Draft Excel and PDF
    Given "Professional fees" is also placed on "Schedule of Fund Expenses"
    And a successful accounting run from "2026-04-01" to "2026-06-30"
    And statements are generated for "2026-04-01" to "2026-06-30"
    Then the Excel download has the sheets "Balance Sheet | Profit & Loss | Statement of Changes in Partner | Schedule of Fund Expenses | Checks"
    And every page of the PDF download says "DRAFT"

  # H20 — Happy path: a read-only user views and downloads but sees no Generate, Lock or editors
  # X13 — Error case: a read-only user's lock request is not authorised
  Scenario: Read-only user
    Given a successful accounting run from "2026-04-01" to "2026-06-30"
    And statements are generated for "2026-04-01" to "2026-06-30"
    And Priya has read-only access to the fund
    And I am logged in as Priya
    When I open the statement set
    Then Priya sees no Generate, Lock or editing buttons
    And Priya cannot lock the statement set

  # X14 — Error case: another entity's user cannot reach the statement set
  Scenario: Other entity
    Given a successful accounting run from "2026-04-01" to "2026-06-30"
    And statements are generated for "2026-04-01" to "2026-06-30"
    And Omar works for another entity
    Then Omar cannot find the statement set
