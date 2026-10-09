@financial_statements
Feature: AI-drafted mapping from a fund's existing statements
  The AI reads an uploaded statement (any period) and the fund's entry list and proposes lines and rules.
  CapHive validates the answer and shows the mapping only — amounts are never compared.
  Nothing is saved until the draft is approved. The AI is stubbed in these scenarios.
  Worked examples: openspec/changes/fund-financial-statements/design.md#worked-examples

  Background:
    Given Alpha Fund I is not set up for financial statements
    And fund-level entries:
      | entry_type       | name       | date       | amount |
      | Non Deal Expense | Audit Fees | 2026-05-15 | 30,000 |
      | Non Deal Expense | Legal Fees | 2026-08-20 | 15,200 |
      | Non Deal Expense | Bank Fees  | 2026-08-20 | 11,650 |
      | Tax              | TDS        | 2026-08-20 | 1,150  |
    And a statements PDF "fs_2026.pdf" printing:
      """
      Alpha Fund I — Statement of Operations for the period ended 30 September 2026
      Expenses
        Professional fees                45,200
        Other expenses                   12,800
      Total expenses                     58,000
      """
    And the AI answers:
      """
      {"as_at": "2026-09-30", "period_start": "2026-01-01",
       "statements": [{"kind": "profit_and_loss", "title": "Statement of Operations", "column_style": "for_period"},
                      {"kind": "balance_sheet", "title": "Statement of Net Assets", "column_style": "at_date"}],
       "lines": [
         {"key": "l1", "statement_title": "Statement of Operations", "section": "Expenses", "label": "Professional fees", "role": "account",
          "account_type": "expense", "behaviour": "movement", "flip_sign": true, "printed": 45200, "subtotal_of": []},
         {"key": "l2", "statement_title": "Statement of Operations", "section": "Expenses", "label": "Other expenses", "role": "account",
          "account_type": "expense", "behaviour": "movement", "flip_sign": false, "printed": 12800, "subtotal_of": []},
         {"key": "l3", "statement_title": "Statement of Operations", "section": "Expenses", "label": "Total expenses", "role": "subtotal",
          "printed": "(58,000)", "subtotal_of": ["l1", "l2"]},
         {"key": "l4", "statement_title": "Statement of Net Assets", "section": "Partners' capital", "label": "Accumulated net result", "role": "account",
          "account_type": "capital", "behaviour": "balance", "flip_sign": false, "printed": "(58,000)", "subtotal_of": []}],
       "rules": [
         {"entry_type": "Non Deal Expense", "name": "Audit Fees", "line": "l1"},
         {"entry_type": "Non Deal Expense", "name": "Legal Fees", "line": "l1"},
         {"entry_type": "Non Deal Expense", "name": "Bank Fees", "line": "l2"},
         {"entry_type": "Non Deal Expense", "name": "Audit Fee", "line": "l1"}],
       "excluded": []}
      """

  # H11 — Happy path: the draft maps each printed line to the fund's entries (no amounts compared); approved through the screens
  Scenario: Draft maps printed lines to account entries
    Given I am logged in as Meera
    When I upload it on the Suggest page
    Then the draft is "ready"
    And the draft line "Professional fees" is fed by "Non Deal Expense · Audit Fees" and "Non Deal Expense · Legal Fees"
    And the draft page shows the line "Professional fees" as "Mapped"
    And the draft page compares no amounts
    When I approve the draft on screen
    Then the fund has 2 statement accounts
    And the fund has a rule "Non Deal Expense" "Audit Fees" to "Professional fees"
    And the "profit_and_loss" statement is named "Statement of Operations"

  # E18 — Edge case: an entry the AI left unused is listed as a mapping gap; placing it from the review fixes the gap
  Scenario: Unused entry placed from the review
    When Meera asks for a draft from it as at "2026-09-30" with the P&L from "2026-01-01"
    Then the draft lists "Tax" "TDS" as not used
    When Meera moves "Tax" "TDS" to the draft line "Other expenses"
    Then the draft line "Other expenses" is fed by "Non Deal Expense · Bank Fees" and "Tax · TDS"
    And the draft lists no unused entries

  # E27 — Edge case: a rule naming an entry the fund doesn't have is dropped and listed
  Scenario: AI names an entry the fund lacks
    When Meera asks for a draft from it as at "2026-09-30" with the P&L from "2026-01-01"
    Then the draft dropped "Non Deal Expense" "Audit Fee" because "not an entry of this fund"

  # E19 — Edge case: discarding a ready draft leaves the mapping untouched
  Scenario: Discard draft
    When Meera asks for a draft from it as at "2026-09-30" with the P&L from "2026-01-01"
    And Meera discards the draft
    Then the draft is "discarded"
    And the fund has 0 statement accounts

  # E20 — Edge case: against an existing mapping, lines are tagged Same / New and approval updates by name
  Scenario: Draft against an existing mapping
    Given FinancialStatementSetup has run for the fund
    And the fund has statement accounts:
      | name              | type    |
      | Professional fees | expense |
    When Meera asks for a draft from it as at "2026-09-30" with the P&L from "2026-01-01"
    Then the draft line "Professional fees" is "same" against the existing mapping
    And the draft line "Other expenses" is "new" against the existing mapping
    When Meera approves the draft
    Then the fund has 2 statement accounts

  # X7 — Error case: a Word file is refused
  Scenario: Unsupported file
    Given a Word file "statements.docx"
    When Meera asks for a draft from it as at "2026-09-30" with the P&L from "2026-01-01"
    Then the upload is refused with "Upload a PDF or Excel file"

  # X12 — Error case: the AI call fails; the draft says why and offers Retry
  Scenario: AI failure
    Given the AI is unavailable
    When Meera asks for a draft from it as at "2026-09-30" with the P&L from "2026-01-01"
    Then the draft fails with "LLM unavailable"

  # X18 — Error case: a scanned PDF with no text fails with a clear message
  Scenario: Scanned PDF
    Given a scanned PDF "scan.pdf" with no text
    When Meera asks for a draft from it as at "2026-09-30" with the P&L from "2026-01-01"
    Then the draft fails with "couldn't read any text from this file"

  # E32 — Edge case: a statement from another period still maps every entry it names (the entry list covers everything up to today)
  Scenario: Statement from another period
    When Meera asks for a draft from it as at "2026-09-30" with the P&L from "2026-01-01"
    Then the draft line "Professional fees" is fed by "Non Deal Expense · Audit Fees" and "Non Deal Expense · Legal Fees"
    And the draft did not drop "Non Deal Expense" "Legal Fees"

  # E33 — Edge case: an "Accumulated net result" line nothing feeds becomes the calculated net result row
  Scenario: Accumulated net result becomes the net result row
    When Meera asks for a draft from it as at "2026-09-30" with the P&L from "2026-01-01"
    Then the draft line "Accumulated net result" is a "net_result" row

  # E34 — Edge case: CapHive sets each line's sign from the entries; the AI's wrong flip_sign is not used
  Scenario: Sign worked out by CapHive
    When Meera asks for a draft from it as at "2026-09-30" with the P&L from "2026-01-01"
    Then the draft line "Professional fees" is not sign-flipped
