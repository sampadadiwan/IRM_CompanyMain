@rack_test
Feature: ReportBuilderFormulaService — derived columns via safe expression evaluation

  Scenario: Basic arithmetic formula produces correct result
    Given a formula "doubled" with expression "[amount] * 2"
    And a row with "amount" = 500.0
    When I evaluate the formula against that row
    Then the evaluated row should have "doubled" equal to 1000.0

  Scenario: Formula dividing two columns produces a ratio
    Given a formula "called_pct" with expression "[called] / [committed] * 100"
    And a row with "called" = 25.0
    And a row with "committed" = 100.0
    When I evaluate the formula against that row
    Then the evaluated row should have "called_pct" equal to 25.0

  Scenario: Formula referencing a dotted column key (joined column)
    Given a formula "double_commitment" with expression "[capital_commitments.folio_committed_amount] * 2"
    And a row with "capital_commitments.folio_committed_amount" = 50000.0
    When I evaluate the formula against that row
    Then the evaluated row should have "double_commitment" equal to 100000.0

  Scenario: Formula with division by zero returns nil without raising
    Given a formula "ratio" with expression "[numerator] / [denominator]"
    And a row with "numerator" = 100.0
    And a row with "denominator" = 0.0
    When I evaluate the formula against that row
    Then the evaluated row should have "ratio" equal to nil

  Scenario: A formula can reference the result of a preceding formula
    Given a formula "base" with expression "[amount] * 10"
    And a row with "amount" = 5.0
    When I evaluate the formula against that row
    Then the evaluated row should have "base" equal to 50.0

  Scenario: validate returns true for a syntactically valid expression
    Given a row with "amount" = 100.0
    When I validate the formula expression "[amount] + 10"
    Then the formula validation should pass

  Scenario: validate returns an error message for an invalid expression
    Given a row with "amount" = 100.0
    When I validate the formula expression "INVALID SYNTAX @@!!"
    Then the formula validation should fail with an error

  Scenario: validate returns an error for an unclosed bracket
    When I validate the formula expression "[unclosed"
    Then the formula validation should fail with an error

  # ── FORMULAS ON PLAIN NUMBERS (report-builder-trust) ────────────────────
  # Worked examples: openspec/changes/report-builder-trust/design.md#worked-examples

  # H8 — Happy path: a ratio of two root amounts is a plain number (2.50, not ₹2.50) and ROUND works
  @report_builder
  Scenario: A ratio of two amounts is a number
    Given the Acme report builder data
    And a "CapitalCommitment" report with columns "folio_id,committed_amount,call_amount"
    And the report has formula "Committed to called" = "ROUND([committed_amount] / [call_amount], 2)"
    When I run the report
    Then the row where "folio_id" is "F-1" shows "2.5" in formula "Committed to called"

  # H9 — Happy path: a root amount minus a related total (5,00,00,000 − 1,80,00,000 = 3,20,00,000)
  @report_builder
  Scenario: An own amount minus a related total
    Given the Acme report builder data
    And a "CapitalCommitment" report with columns "folio_id,committed_amount,capital_remittances.collected_amount"
    And the report has related data "capital_remittances"
    And the report has formula "Not yet collected" = "[committed_amount] - [capital_remittances.collected_amount]"
    When I run the report
    Then the row where "folio_id" is "F-1" shows "32000000" in formula "Not yet collected"

  # E6 — Edge case: dividing by zero gives a blank for that row only
  @report_builder
  Scenario: Division by zero is blank for that row only
    Given the Acme report builder data
    And a "CapitalCommitment" report with columns "folio_id,call_amount,collected_amount"
    And the report has formula "Called to collected" = "ROUND([call_amount] / [collected_amount], 2)"
    When I run the report
    Then the row where "folio_id" is "F-3" is blank in formula "Called to collected"
    And the row where "folio_id" is "F-1" shows "1.11" in formula "Called to collected"

  # X7 — Error case: a formula saved with broken syntax leaves its cells blank; the report still renders
  @report_builder
  Scenario: A broken formula leaves blank cells
    Given the Acme report builder data
    And a "CapitalCommitment" report with columns "folio_id,committed_amount"
    And the report has formula "Broken" = "[committed_amount] / "
    When I run the report
    Then the row where "folio_id" is "F-1" is blank in formula "Broken"
