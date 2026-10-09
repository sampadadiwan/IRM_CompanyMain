@financial_statements
Feature: Financial statement generation — the statements run
  Generate starts a separate allocation run, tagged "Financial Statements", that runs only the
  fund's statement formula and writes "Financial Statement" entries. Guards refuse with a message.
  Worked examples: openspec/changes/fund-financial-statements/design.md#worked-examples

  Background:
    Given Alpha Fund I is set up for financial statements
    And the fund has statement accounts:
      | name              | type    |
      | Professional fees | expense |
      | Transaction costs | expense |
      | Cash              | asset   |
      | Contributions     | capital |
    And the mapping rules:
      | entry_type         | name         | account           |
      | Non Deal Expense   | Audit Fees   | Professional fees |
      | Non Deal Expense   | Legal Fees   | Professional fees |
      | Deal Expense       |              | Transaction costs |
      | Cash               | Bank Balance | Cash              |
      | Capital Remittance | Contribution | Contributions     |
    And fund-level entries:
      | entry_type         | name         | date       | amount  |
      | Capital Remittance | Contribution | 2026-01-15 | 500,000 |
      | Cash               | Bank Balance | 2026-01-15 | 500,000 |
      | Non Deal Expense   | Audit Fees   | 2026-08-15 | 30,000  |
      | Non Deal Expense   | Legal Fees   | 2026-08-20 | 15,200  |
      | Deal Expense       | Acme Ltd     | 2026-09-01 | 62,400  |
      | Cash               | Bank Balance | 2026-09-30 | -107,600 |

  # H12 — Happy path: Generate writes fund-level "Financial Statement" lines dated the end date and records the source run
  Scenario: Generate statements
    Given a locked successful accounting run from "2026-07-01" to "2026-09-30"
    When statements are generated for "2026-07-01" to "2026-09-30"
    Then the statement set is "ready"
    And the statement set was built from the accounting run
    And the statements run covers only "2026-09-30"
    And the statement lines include "FS · Professional fees" of "45,200" dated "2026-09-30"
    And the statement lines include "FS · YTD Professional fees" of "45,200" dated "2026-09-30"
    And the statement lines include "FS · Cash" of "392,400" dated "2026-09-30"
    And the statement lines include "FS · Opening Cash" of "500,000" dated "2026-09-30"
    And no statement line is named like an account
    And the "Profit & Loss" statement shows "Professional fees" of "-45,200" for "period"
    And there are no folio statement lines
    And the check "Balance" is "passed"
    And the "Balance Sheet" statement shows "Total liabilities and partners' capital" of "392,400" for "balance"
    And the Balance Sheet line reads "392,400 = 0 + 392,400" and balances for "balance"

  # H14 — Happy path: from the Statements tab, Generate is allowed over a locked accounting run and opens the ready set
  Scenario: Generate from the Statements tab over a locked accounting run
    Given a locked successful accounting run from "2026-07-01" to "2026-09-30"
    And I am logged in as Meera
    When I generate statements on the Statements tab for "01/07/2026" to "30/09/2026"
    Then the popup said "Statements run starts"
    And the popup said "✓ No allocation run in progress"
    And the popup said "✓ Statement formula enabled"
    And the popup said "✓ Completed accounting run covering the period (latest: 01/07/2026 – 30/09/2026)"
    Then the statement set shows "01/07/2026 – 30/09/2026"
    And the statement set shows "Built from accounting run"
    And the statement set shows "Total partners' capital"
    And the statement set shows "Assets = Liabilities + Partners' capital"
    And the statement set shows "FS · Professional fees"
    And the statement set offers "View statement lines"
    And the Statements tab lists the set as "Draft"

  # H13 — Happy path: a statements run leaves every accounting entry exactly as it was
  Scenario: Accounting entries untouched by a statements run
    Given a locked successful accounting run from "2026-07-01" to "2026-09-30"
    And I remember the fund's accounting entries
    When statements are generated for "2026-07-01" to "2026-09-30"
    Then the fund's accounting entries are unchanged

  # E16 — Edge case: Regenerate deletes the old lines and writes new ones (3 per account)
  # E1 — Edge case: generating the same period again reuses the Draft; one record
  Scenario: Regenerate replaces the lines
    Given a successful accounting run from "2026-07-01" to "2026-09-30"
    When statements are generated for "2026-07-01" to "2026-09-30"
    And I remember the statement lines
    And statements are generated for "2026-07-01" to "2026-09-30"
    Then the statement lines were replaced
    And there are 12 statement lines
    And there is one statement set for "2026-07-01" to "2026-09-30"

  # E12 — Edge case: an ordinary (untagged) allocation run neither creates nor deletes statement lines
  Scenario: Ordinary run skips the statement formula
    Given a successful accounting run from "2026-07-01" to "2026-09-30"
    When statements are generated for "2026-07-01" to "2026-09-30"
    And I remember the statement lines
    And an ordinary allocation run is run for "2026-07-01" to "2026-09-30"
    Then the statement lines are unchanged

  # E31 — Edge case: an allocate-by-name formula named like a statement account never allocates the statement line
  Scenario: Statement lines are not allocated by an ordinary run
    Given the fund has folios "101,102"
    And the fund has an "AllocateAccountEntry-Name" formula "Professional fees" with formula:
      """
      fund_account_entry.amount_cents / 2
      """
    And a successful accounting run from "2026-07-01" to "2026-09-30"
    When statements are generated for "2026-07-01" to "2026-09-30"
    Then the statement lines include "FS · Professional fees" of "45,200" dated "2026-09-30"
    When an ordinary allocation run is run for "2026-07-01" to "2026-09-30"
    Then no folio entry "Professional fees" was allocated

  # H24 — Happy path: an account placed on two statements shows the same figure on both
  Scenario: Account on two statements
    Given "Professional fees" is also placed on "Schedule of Fund Expenses"
    And a successful accounting run from "2026-07-01" to "2026-09-30"
    When statements are generated for "2026-07-01" to "2026-09-30"
    Then the "Profit & Loss" statement shows "Professional fees" of "-45,200" for "period"
    And the "Schedule of Fund Expenses" statement shows "Professional fees" of "-45,200" for "period"

  # X1 — Error case: no successful accounting run covers the period
  Scenario: No accounting run
    When statements are generated for "2026-10-01" to "2026-12-31"
    Then generation is refused with "Run and complete the fund's allocations for this period first."

  # X2 — Error case: an allocation run is in progress on the fund
  Scenario: Run in progress
    Given a successful accounting run from "2026-07-01" to "2026-09-30"
    And an allocation run is in progress on the fund
    When statements are generated for "2026-07-01" to "2026-09-30"
    Then generation is refused with "An allocation run is in progress for this fund"

  # E25 — Edge case: a second click while the first statements run is still running is refused; one run
  Scenario: Double-click Generate
    Given a successful accounting run from "2026-07-01" to "2026-09-30"
    When statements are generated for "2026-07-01" to "2026-09-30"
    And an allocation run is in progress on the fund
    And statements are generated for "2026-07-01" to "2026-09-30"
    Then generation is refused with "An allocation run is in progress for this fund"
    And there is one statement set for "2026-07-01" to "2026-09-30"

  # E28 — Edge case: another set already ends on the same date
  Scenario: Same end date, different period
    Given a successful accounting run from "2026-01-01" to "2026-09-30"
    When statements are generated for "2026-07-01" to "2026-09-30"
    And statements are generated for "2026-01-01" to "2026-09-30"
    Then generation is refused with "already exist (01/07/2026 – 30/09/2026)"

  # X3 — Error case: locked statements can't be regenerated
  Scenario: Regenerate locked statements
    Given a successful accounting run from "2026-07-01" to "2026-09-30"
    When statements are generated for "2026-07-01" to "2026-09-30"
    And the statement set is locked by Meera
    And statements are generated for "2026-07-01" to "2026-09-30"
    Then generation is refused with "These statements are locked."

  # X15 — Error case: the statement formula is disabled
  Scenario: Formula disabled
    Given a successful accounting run from "2026-07-01" to "2026-09-30"
    And the statement formula is disabled
    When statements are generated for "2026-07-01" to "2026-09-30"
    Then generation is refused with "Enable the fund's financial statement formula first."

  # X16 — Error case: a locked statements run on the end date blocks regeneration of a Draft
  Scenario: Locked statements run overlaps
    Given a successful accounting run from "2026-07-01" to "2026-09-30"
    When statements are generated for "2026-07-01" to "2026-09-30"
    And the statements run is locked from the allocation runs list
    And statements are generated for "2026-07-01" to "2026-09-30"
    Then generation is refused with "Unlock the statements run for this period first."

  # X4 — Error case: the allocate screen's lock check is unchanged, so an ordinary run on a locked period is still blocked
  Scenario: Ordinary run still blocked
    Given a locked successful accounting run from "2026-07-01" to "2026-09-30"
    When statements are generated for "2026-07-01" to "2026-09-30"
    Then an ordinary run for "2026-07-01" to "2026-09-30" is still blocked by the locked accounting run

  # X11 — Error case: the statements run fails; the set shows Failed with the run's error
  Scenario: Run fails
    Given a successful accounting run from "2026-07-01" to "2026-09-30"
    When statements are generated for "2026-07-01" to "2026-09-30" and the run fails
    Then the statement set is "failed"
