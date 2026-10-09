@financial_statements
Feature: Financial statement mapping — accounts, rules, layout and the Unmapped list
  A fund's statement accounts, the rules that feed account entries into them, the statements'
  layout and the Unmapped list, with a live preview for a chosen period.
  Worked examples: openspec/changes/fund-financial-statements/design.md#worked-examples

  # H21 — Happy path: a fund's first account creates the three core statements and the statement formula
  Scenario: First account sets the fund up
    Given Alpha Fund I is not set up for financial statements
    And I am logged in as Meera
    When I add the account "Professional fees" of type "Expense"
    Then I see "Account Professional fees added."
    And the fund has the core statements "Balance Sheet | Profit & Loss | Statement of Changes in Partners' Capital"

  # H1 — Happy path: an expense account defaults to Movement, is placed under Expenses on the P&L, and the formula exists
  Scenario: Create an expense account
    Given Alpha Fund I is set up for financial statements
    And I am logged in as Meera
    When I add the account "Professional fees" of type "Expense"
    Then the account "Professional fees" is a "expense" "movement" account
    And "Professional fees" is on the "Profit & Loss" under "Expenses"
    And the fund has its statement formula

  # X5 — Error case: a second account with the same name is refused
  Scenario: Duplicate account name rejected
    Given Alpha Fund I is set up for financial statements
    And the fund has statement accounts:
      | name              | type    |
      | Professional fees | expense |
    And I am logged in as Meera
    When I add the account "Professional fees" of type "Expense"
    Then I see "Name has already been taken"

  # H6 — Happy path: an entry with amounts and no rule is listed as Unmapped with its total
  # H7 — Happy path: Map pre-fills the rule; once saved the entry leaves Unmapped and the account preview includes it
  Scenario: Map an unmapped entry from the list
    Given Alpha Fund I is set up for financial statements
    And the fund has statement accounts:
      | name              | type    |
      | Professional fees | expense |
    And the mapping rules:
      | entry_type       | name       | account           |
      | Non Deal Expense | Audit Fees | Professional fees |
    And fund-level entries:
      | entry_type       | name          | date       | amount |
      | Non Deal Expense | Audit Fees    | 2026-08-15 | 30,000 |
      | Non Deal Expense | Director Fees | 2026-08-20 | 8,000  |
    And I am logged in as Meera
    When I open the Mapping tab for "2026-07-01" to "2026-09-30"
    Then the Unmapped list shows "Non Deal Expense" "Director Fees" with "8,000"
    When I open How checks work
    Then the checks explanation says "Do the statements add up"
    And the Mapping preview of "Professional fees" this period is "30,000"
    When I click Map on "Director Fees"
    And I send it to "Professional fees"
    Then the Unmapped list is empty
    And the Mapping preview of "Professional fees" this period is "38,000"

  # H8 — Happy path: changing a rule from Excluded to an account updates the preview without creating any entry
  Scenario: Preview updates on rule change
    Given Alpha Fund I is set up for financial statements
    And the fund has statement accounts:
      | name           | type    |
      | Other expenses | expense |
    And the mapping rules:
      | entry_type | name | account  |
      | Tax        | TDS  | Excluded |
    And fund-level entries:
      | entry_type | name | date       | amount |
      | Tax        | TDS  | 2026-08-15 | 1,150  |
    And I am logged in as Meera
    When I open the Mapping tab for "2026-07-01" to "2026-09-30"
    Then the Mapping preview of "Other expenses" this period is "0"
    When I change the rule for "Tax" "TDS" to "Other expenses"
    Then the Mapping preview of "Other expenses" this period is "1,150"

  # X6 — Error case: deleting an account a rule still uses is refused, naming the rule
  Scenario: Account in use cannot be deleted
    Given Alpha Fund I is set up for financial statements
    And the fund has statement accounts:
      | name              | type    |
      | Professional fees | expense |
    And the mapping rules:
      | entry_type       | name       | account           |
      | Non Deal Expense | Audit Fees | Professional fees |
    And I am logged in as Meera
    When I open the Mapping tab for "2026-07-01" to "2026-09-30"
    And I delete the account "Professional fees"
    Then I see "Professional fees is used by rule Non Deal Expense · Audit Fees"

  # X19 — Error case: an account name can't start with the "FS ·" prefix CapHive adds to stored statement lines
  Scenario: Account name with the statement prefix rejected
    Given Alpha Fund I is set up for financial statements
    And I am logged in as Meera
    When I add the account "FS · Professional fees" of type "Expense"
    Then I see "can't start with \"FS ·\""

  # H22 — Happy path: a core statement can be renamed
  Scenario: Core statement renamed
    Given Alpha Fund I is set up for financial statements
    And I am logged in as Meera
    When I open the Layout tab for "Profit & Loss"
    And I rename the statement to "Statement of Operations"
    Then I see "Statement of Operations saved."
    And the fund has the core statements "Balance Sheet | Statement of Operations | Statement of Changes in Partners' Capital"

  # X17 — Error case: a core statement cannot be deleted (and the Layout tab offers no Delete for it)
  Scenario: Core statement cannot be deleted
    Given Alpha Fund I is set up for financial statements
    And I am logged in as Meera
    When I open the Layout tab for "Balance Sheet"
    Then I do not see "Delete"
    And destroying the core statement "Balance Sheet" is refused with "Core statements can be renamed but not deleted"

  # H23 — Happy path: a schedule is added as a period statement over the same accounts
  Scenario: Add a schedule
    Given Alpha Fund I is set up for financial statements
    And I am logged in as Meera
    When I add a schedule "Schedule of Fund Expenses" for a period
    Then I see "Schedule of Fund Expenses added."

  # H3 — Happy path: moving a row up changes its order in the statement
  Scenario: Reorder rows
    Given Alpha Fund I is set up for financial statements
    And the fund has statement accounts:
      | name              | type    |
      | Management fees   | expense |
      | Professional fees | expense |
    And I am logged in as Meera
    When I open the Layout tab for "Profit & Loss"
    And I move "Professional fees" up
    Then the layout of "Profit & Loss" lists "Professional fees" before "Management fees"

  # H2 — Happy path: a subtotal adds the displayed values of its rows
  Scenario: Subtotal sums its rows
    Given Alpha Fund I is set up for financial statements
    And the fund has statement accounts:
      | name              | type    |
      | Management fees   | expense |
      | Professional fees | expense |
    And the mapping rules:
      | entry_type       | name           | account           |
      | Fees             | Management Fee | Management fees   |
      | Non Deal Expense | Audit Fees     | Professional fees |
    And fund-level entries:
      | entry_type       | name           | date       | amount  |
      | Fees             | Management Fee | 2026-08-15 | 250,000 |
      | Non Deal Expense | Audit Fees     | 2026-08-15 | 45,200  |
    When I preview from "2026-07-01" to "2026-09-30"
    Then the previewed "Profit & Loss" shows "Total expenses" of "-295,200" for "period"
    Given I am logged in as Meera
    When I open the statements preview for "2026-07-01" to "2026-09-30"
    And I open the "Profit & Loss" preview tab
    Then the preview tab shows "Total expenses" with "($295,200)"
    And the preview tab lists the account "Professional fees" fed by "Non Deal Expense · Audit Fees"
    And the preview tab does not list the account "Cash"

  # H4 — Happy path: an any-name rule catches a name uploaded later
  Scenario: Entry-type rule catches new names
    Given Alpha Fund I is set up for financial statements
    And the fund has statement accounts:
      | name              | type    |
      | Transaction costs | expense |
    And the mapping rules:
      | entry_type   | name | account           |
      | Deal Expense |      | Transaction costs |
    And fund-level entries:
      | entry_type   | name     | date       | amount |
      | Deal Expense | Acme Ltd | 2026-08-15 | 62,400 |
    When I preview from "2026-07-01" to "2026-09-30"
    Then the preview of "Transaction costs" for "period" is "62,400"
    And nothing is unmapped

  # H5 — Happy path: an exact-name rule wins over the entry type's any-name rule
  Scenario: Exact rule wins
    Given Alpha Fund I is set up for financial statements
    And the fund has statement accounts:
      | name              | type    |
      | Professional fees | expense |
      | Other expenses    | expense |
    And the mapping rules:
      | entry_type       | name       | account           |
      | Non Deal Expense |            | Other expenses    |
      | Non Deal Expense | Audit Fees | Professional fees |
    And fund-level entries:
      | entry_type       | name       | date       | amount |
      | Non Deal Expense | Audit Fees | 2026-08-15 | 30,000 |
      | Non Deal Expense | Bank Fees  | 2026-08-15 | 500    |
    When I preview from "2026-07-01" to "2026-09-30"
    Then the preview of "Professional fees" for "period" is "30,000"
    And the preview of "Other expenses" for "period" is "500"

  # E2 — Edge case: excluded entries are on no line and not Unmapped
  Scenario: Excluded entries
    Given Alpha Fund I is set up for financial statements
    And the fund has statement accounts:
      | name              | type    |
      | Professional fees | expense |
    And the mapping rules:
      | entry_type           | name | account  |
      | Portfolio Allocation |      | Excluded |
    And fund-level entries:
      | entry_type           | name     | date       | amount |
      | Portfolio Allocation | Acme Ltd | 2026-08-15 | 99,000 |
    When I preview from "2026-07-01" to "2026-09-30"
    Then "Portfolio Allocation" "Acme Ltd" is not unmapped
    And the preview of "Professional fees" for "period" is "0"

  # E3 — Edge case: folio-level entries never reach the statements
  Scenario: Folio-level entries ignored
    Given Alpha Fund I is set up for financial statements
    And the fund has folios "F-102"
    And the fund has statement accounts:
      | name              | type    |
      | Professional fees | expense |
    And the mapping rules:
      | entry_type       | name       | account           |
      | Non Deal Expense | Audit Fees | Professional fees |
    And fund-level entries:
      | entry_type       | name       | date       | amount |
      | Non Deal Expense | Audit Fees | 2026-08-15 | 30,000 |
    And folio "F-102" has entries:
      | entry_type       | name       | date       | amount |
      | Non Deal Expense | Audit Fees | 2026-08-15 | 500    |
    When I preview from "2026-07-01" to "2026-09-30"
    Then the preview of "Professional fees" for "period" is "30,000"

  # E17 — Edge case: the statements' own "Financial Statement" entries are never Unmapped
  Scenario: Statement lines are never mapped
    Given Alpha Fund I is set up for financial statements
    And the fund has statement accounts:
      | name              | type    |
      | Professional fees | expense |
    And a statements run wrote "Professional fees" lines for "2026-09-30"
    When I preview from "2026-07-01" to "2026-09-30"
    Then "Financial Statement" "FS · Professional fees" is not unmapped
    And the preview of "Professional fees" for "period" is "0"

  # E22 — Edge case: an unmapped pair that nets to zero is not listed
  Scenario: Zero total is not unmapped
    Given Alpha Fund I is set up for financial statements
    And fund-level entries:
      | entry_type       | name     | date       | amount |
      | Non Deal Expense | Misc Fee | 2026-08-15 | 700    |
      | Non Deal Expense | Misc Fee | 2026-09-15 | -700   |
    When I preview from "2026-07-01" to "2026-09-30"
    Then nothing is unmapped
