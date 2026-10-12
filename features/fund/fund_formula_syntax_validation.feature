@rack_test
Feature: FundFormula syntax validation
  Before a formula is persisted it must parse as valid Ruby. Parser::CurrentRuby.parse
  builds an AST without executing the formula — no eval, no subprocess fork — so a
  typo or unbalanced expression is caught at save time instead of failing later when
  the allocation engine evals it against a live binding.

  This validation (formula_syntax_valid?) is independent of formula_kosher? (the
  CRUD/system-call denylist) — a formula can be syntactically valid Ruby and still be
  rejected by the denylist, or vice versa.


  Scenario: Well-formed single-expression formula is valid
    Given a fund formula with formula "@committed_capital * @fee_rate / 365 * @days_in_period"
    When I validate the fund formula
    Then the fund formula should be valid

  Scenario: Well-formed multi-statement formula is valid
    Given a fund formula with formula:
      """
      gross = @base_cents * @rate / 100;
      tax = gross * 0.18;
      gross + tax
      """
    When I validate the fund formula
    Then the fund formula should be valid

  Scenario: Unbalanced parenthesis is rejected
    Given a fund formula with formula "@committed_capital * ("
    When I validate the fund formula
    Then the fund formula should be invalid with a formula error containing "invalid Ruby syntax"

  Scenario: Dangling operator is rejected
    Given a fund formula with formula "@base_cents +"
    When I validate the fund formula
    Then the fund formula should be invalid with a formula error containing "invalid Ruby syntax"

  Scenario: Unterminated string literal is rejected
    Given a fund formula with formula '@fee_type.start_with?("Management'
    When I validate the fund formula
    Then the fund formula should be invalid with a formula error containing "invalid Ruby syntax"

  Scenario: Blank formula is not flagged by the syntax check
    # presence is already enforced separately by `validates :formula, presence: true`;
    # formula_syntax_valid? should not also raise a confusing syntax error on blank input.
    Given a fund formula with formula ""
    When I validate the fund formula
    Then the fund formula should be invalid
    And the fund formula should not have a syntax error
