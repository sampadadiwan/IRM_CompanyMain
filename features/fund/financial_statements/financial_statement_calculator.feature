@financial_statements
Feature: Financial statement calculator — figures, checks and completeness warnings
  The calculator turns a fund's fund-level account entries and its statement mapping into account
  figures (period, year to date, balance), the four integrity checks and the completeness warnings.
  Worked examples: openspec/changes/fund-financial-statements/design.md#worked-examples

  Background:
    Given Alpha Fund I is set up for financial statements

  # H9 — Happy path: a cumulative entry's movement is its latest value minus its value before the period
  @rack_test
  Scenario: Movement from cumulative entries
    Given the fund has statement accounts:
      | name            | type   |
      | Interest income | income |
    And the mapping rules:
      | entry_type | name     | account         |
      | Income     | Interest | Interest income |
    And fund-level entries:
      | entry_type | name     | date       | amount | cumulative |
      | Income     | Interest | 2026-06-30 | 7,800  | yes        |
      | Income     | Interest | 2026-09-30 | 11,900 | yes        |
    When I preview from "2026-07-01" to "2026-09-30"
    Then the preview of "Interest income" for "period" is "4,100"
    And the preview of "Interest income" for "balance" is "11,900"

  # H10 — Happy path: a periodic entry's balance is its sum since inception
  @rack_test
  Scenario: Balance from periodic entries
    Given the fund has statement accounts:
      | name | type  |
      | Cash | asset |
    And the mapping rules:
      | entry_type | name         | account |
      | Cash       | Bank Balance | Cash    |
    And fund-level entries:
      | entry_type | name         | date       | amount  |
      | Cash       | Bank Balance | 2026-03-31 | 100,000 |
      | Cash       | Bank Balance | 2026-06-30 | -20,000 |
      | Cash       | Bank Balance | 2026-09-30 | 5,000   |
    When I preview from "2026-07-01" to "2026-09-30"
    Then the preview of "Cash" for "balance" is "85,000"
    And the preview of "Cash" for "period" is "5,000"
    And the preview of "Cash" for "opening" is "80,000"

  # E14 — Edge case: the first and last day of the period are inside it, the day before is not
  @rack_test
  Scenario: Dates on the period boundaries
    Given the fund has statement accounts:
      | name              | type    |
      | Professional fees | expense |
    And the mapping rules:
      | entry_type       | name       | account           |
      | Non Deal Expense | Audit Fees | Professional fees |
    And fund-level entries:
      | entry_type       | name       | date       | amount |
      | Non Deal Expense | Audit Fees | 2026-06-30 | 1,000  |
      | Non Deal Expense | Audit Fees | 2026-07-01 | 200    |
      | Non Deal Expense | Audit Fees | 2026-09-30 | 30     |
    When I preview from "2026-07-01" to "2026-09-30"
    Then the preview of "Professional fees" for "period" is "230"
    And the preview of "Professional fees" for "balance" is "1,230"

  # E13 — Edge case: a pair stored both as a running total and as movements uses the running total and warns
  @rack_test
  Scenario: Mixed cumulative and periodic entries
    Given the fund has statement accounts:
      | name            | type   |
      | Interest income | income |
    And the mapping rules:
      | entry_type | name     | account         |
      | Income     | Interest | Interest income |
    And fund-level entries:
      | entry_type | name     | date       | amount | cumulative |
      | Income     | Interest | 2026-06-30 | 7,800  | yes        |
      | Income     | Interest | 2026-09-30 | 11,900 | yes        |
      | Income     | Interest | 2026-08-15 | 999    | no         |
    When I preview from "2026-07-01" to "2026-09-30"
    Then the preview of "Interest income" for "period" is "4,100"
    And there is a "Mixed running total / movements" warning mentioning "Income · Interest"

  # E21 — Edge case: with an April financial year, year to date starts on 1 April
  @rack_test
  Scenario: April financial year
    Given the financial year starts in month 4
    And the fund has statement accounts:
      | name            | type   |
      | Interest income | income |
    And the mapping rules:
      | entry_type | name     | account         |
      | Income     | Interest | Interest income |
    And fund-level entries:
      | entry_type | name     | date       | amount |
      | Income     | Interest | 2026-03-01 | 100    |
      | Income     | Interest | 2026-05-15 | 200    |
      | Income     | Interest | 2026-08-15 | 300    |
    When I preview from "2026-07-01" to "2026-09-30"
    Then the preview of "Interest income" for "period" is "300"
    And the preview of "Interest income" for "ytd" is "500"

  # E4 — Edge case: a Balance difference under 1.00 passes
  @rack_test
  Scenario: Rounding difference passes
    Given the fund has statement accounts:
      | name          | type    |
      | Cash          | asset   |
      | Contributions | capital |
    And the mapping rules:
      | entry_type         | name         | account       |
      | Cash               | Bank Balance | Cash          |
      | Capital Remittance | Contribution | Contributions |
    And fund-level entries:
      | entry_type         | name         | date       | amount   |
      | Cash               | Bank Balance | 2026-07-15 | 1,000.40 |
      | Capital Remittance | Contribution | 2026-07-15 | 1,000    |
    When I preview from "2026-07-01" to "2026-09-30"
    Then the check "Balance" is "passed"

  # E5 — Edge case: a Balance difference of exactly 1.00 fails
  @rack_test
  Scenario: Difference of exactly one unit fails
    Given the fund has statement accounts:
      | name          | type    |
      | Cash          | asset   |
      | Contributions | capital |
    And the mapping rules:
      | entry_type         | name         | account       |
      | Cash               | Bank Balance | Cash          |
      | Capital Remittance | Contribution | Contributions |
    And fund-level entries:
      | entry_type         | name         | date       | amount   |
      | Cash               | Bank Balance | 2026-07-15 | 1,001.00 |
      | Capital Remittance | Contribution | 2026-07-15 | 1,000    |
    When I preview from "2026-07-01" to "2026-09-30"
    Then the check "Balance" fails by "1.00"

  # X10 — Error case: assets 10,000,000, liabilities 200,000 and capital 9,798,800 fail Balance by 1,200
  @rack_test
  Scenario: Balance check fails
    Given the fund has statement accounts:
      | name          | type      |
      | Investments   | asset     |
      | Payables      | liability |
      | Contributions | capital   |
    And the mapping rules:
      | entry_type         | name           | account       |
      | Portfolio FMV      | Investments    | Investments   |
      | Payable            | Audit Fee      | Payables      |
      | Capital Remittance | Contribution   | Contributions |
    And fund-level entries:
      | entry_type         | name         | date       | amount     | cumulative |
      | Portfolio FMV      | Investments  | 2026-09-30 | 10,000,000 | yes        |
      | Payable            | Audit Fee    | 2026-09-30 | 200,000    | yes        |
      | Capital Remittance | Contribution | 2026-07-15 | 9,798,800  | no         |
    When I preview from "2026-07-01" to "2026-09-30"
    Then the check "Balance" fails by "1,200"

  # E6 — Edge case: the NAV tie-out (set on the Settings tab) is skipped, not failed, when there is no NAV entry yet
  @rack_test
  Scenario: No NAV entry on or before the end date
    Given I am logged in as Meera
    When I set the NAV entry to "NAV" "NAV Post Carry" on the Settings tab
    Then the Settings tab says "No fund-level entry NAV · NAV Post Carry found"
    When I preview from "2026-07-01" to "2026-09-30"
    Then the check "NAV tie-out" is skipped with "no NAV entry"

  # E7 — Edge case: the partners' capital tie-out is skipped when no capital entry is configured
  Scenario: Capital tie-out not configured
    When I preview from "2026-07-01" to "2026-09-30"
    Then the check "Partners' capital tie-out" is skipped with "not configured"
    And the check "NAV tie-out" is skipped with "not configured"

  # E24 — Edge case: distributions stored positive with flip sign become negative capital; roll-forward passes
  @rack_test
  Scenario: Flip sign on distributions
    Given the fund has statement accounts:
      | name          | type    | flip |
      | Cash          | asset   | no   |
      | Contributions | capital | no   |
      | Distributions | capital | yes  |
    And the mapping rules:
      | entry_type           | name         | account       |
      | Cash                 | Bank Balance | Cash          |
      | Capital Remittance   | Contribution | Contributions |
      | Capital Distribution | Distribution | Distributions |
    And fund-level entries:
      | entry_type           | name         | date       | amount |
      | Cash                 | Bank Balance | 2026-01-15 | 1,000  |
      | Capital Remittance   | Contribution | 2026-01-15 | 1,000  |
      | Cash                 | Bank Balance | 2026-08-15 | -400   |
      | Capital Distribution | Distribution | 2026-08-15 | 400    |
    When I preview from "2026-07-01" to "2026-09-30"
    Then the preview of "Distributions" for "period" is "-400"
    And the check "Balance" is "passed"
    And the check "Roll-forward" is "passed"
    And the previewed "Statement of Changes in Partners' Capital" shows "Distributions" of "-400" for "period"

  # E29 — Edge case: a running total with nothing dated in the period uses its last value and warns
  @rack_test
  Scenario: Stale balance
    Given the fund has statement accounts:
      | name | type  |
      | Cash | asset |
    And the mapping rules:
      | entry_type | name         | account |
      | Cash       | Bank Balance | Cash    |
    And fund-level entries:
      | entry_type | name         | date       | amount  | cumulative |
      | Cash       | Bank Balance | 2026-06-30 | 520,000 | yes        |
    When I preview from "2026-07-01" to "2026-09-30"
    Then the preview of "Cash" for "balance" is "520,000"
    And there is a "Stale balance" warning mentioning "Cash · Bank Balance last value"

  # E30 — Edge case: an account on a statement that nothing feeds shows 0 and warns
  @rack_test
  Scenario: Account with no entries
    Given the fund has statement accounts:
      | name             | type      |
      | Accrued expenses | liability |
    When I preview from "2026-07-01" to "2026-09-30"
    Then the preview of "Accrued expenses" for "balance" is "0"
    And there is a "No entries" warning mentioning "Accrued expenses: no entries feed this line"
