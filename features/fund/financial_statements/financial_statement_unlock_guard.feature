@financial_statements
Feature: Unlocking allocation runs over locked financial statements
  Unlocking allocation runs can change the data behind locked statements. A popup warns first;
  on confirmation the statements go back to Draft (their frozen copy kept) and the fund's Fund
  accounting users are told once. Without locked statements, Unlock works exactly as before.
  Worked examples: openspec/changes/fund-financial-statements/design.md#worked-examples

  Background:
    Given Alpha Fund I is set up for financial statements
    And Ravi is tagged FundAccounting
    And the fund has statement accounts:
      | name              | type    |
      | Professional fees | expense |
      | Cash              | asset   |
      | Contributions     | capital |
    And the mapping rules:
      | entry_type         | name         | account           |
      | Non Deal Expense   | Audit Fees   | Professional fees |
      | Cash               | Bank Balance | Cash              |
      | Capital Remittance | Contribution | Contributions     |
    And fund-level entries:
      | entry_type         | name         | date       | amount  |
      | Capital Remittance | Contribution | 2026-01-15 | 500,000 |
      | Cash               | Bank Balance | 2026-01-15 | 470,000 |
      | Non Deal Expense   | Audit Fees   | 2026-02-15 | 30,000  |

  # H16 — Happy path: Unlock on a run whose period has locked statements shows the action-summary popup
  # H17 — Happy path: confirming unlocks the runs, returns the statements to Draft and notifies Fund accounting once
  Scenario: Unlock warns, then demotes and notifies
    Given statements for "2026-04-01" to "2026-06-30" are generated and locked
    And I am logged in as Meera
    When I open the fund's allocation runs
    And I click Unlock on the accounting run
    Then the unlock popup says "Statements back to Draft"
    And the unlock popup says "Fund accounting notified"
    When I confirm the unlock
    Then the accounting run is "unlocked"
    And the locked statement sets are "draft"
    And the statement set keeps its frozen copy
    And Ravi gets 1 financial statement notification
    And Ravi gets an email "financial statements back to Draft"

  # E23 — Edge case: cancelling the popup leaves the runs and the statements locked; nobody is notified
  Scenario: Cancel the unlock
    Given statements for "2026-04-01" to "2026-06-30" are generated and locked
    And I am logged in as Meera
    When I open the fund's allocation runs
    And I click Unlock on the accounting run
    And I cancel the unlock
    Then the accounting run is "locked"
    And the locked statement sets are "locked"
    And Ravi gets 0 financial statement notifications

  # E8 — Edge case: with no locked statements, Unlock keeps its plain confirmation and sends nothing
  Scenario: Unlock with no locked statements
    Given a locked successful accounting run from "2026-04-01" to "2026-06-30"
    And I am logged in as Meera
    When I open the fund's allocation runs
    Then the plain unlock confirmation is used
    When I unlock the accounting run accepting the plain confirmation
    Then the accounting run is "unlocked"
    And Ravi gets 0 financial statement notifications

  # E15 — Edge case: Unlock all with two locked periods demotes both with one notification listing both
  Scenario: Unlock all with two locked periods
    Given statements for "2026-01-01" to "2026-03-31" are generated and locked
    And statements for "2026-04-01" to "2026-06-30" are generated and locked
    And Meera also has the support role
    And I am logged in as Meera
    When I open the fund's allocation runs
    And I click Unlock all
    And I confirm the unlock
    Then the locked statement sets are "draft"
    And Ravi gets 1 financial statement notification
    And Ravi's notification lists "01/01/2026 – 31/03/2026 and 01/04/2026 – 30/06/2026"
