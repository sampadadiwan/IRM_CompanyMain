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
