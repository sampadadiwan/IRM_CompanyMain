@rack_test
Feature: Call fee formula errors name the fee and the folio
  CallFee#calculate_formula evals the fee formula held in notes once per remittance. When
  the formula raises (e.g. capital_commitment.fund_unit_setting.setup_fee for a commitment
  with no unit type, so fund_unit_setting is nil), the error is re-raised as
  CallFee::FormulaError naming the fee and the commitment, instead of a bare NoMethodError
  from inside eval. Successful formulas return exactly what they did before, and a formula
  blocked by safe_eval! still raises ApplicationRecord::UnsafeEvalError.

  Background:
    Given a commitment "id=511;investor_name=Investor A;folio_id=F-511;unit_type=" with no fund unit settings

  Scenario: A formula that evaluates returns its value unchanged
    Given a call fee "Setup Fees" with formula "capital_remittance.call_amount_cents * 2 / 100.0"
    When the call fee formula is calculated for a remittance with call amount 1000000 cents
    Then the call fee formula result should be 20000.0

  Scenario: A nil-safe unit setting lookup returns zero for a commitment with no unit type
    Given a call fee "Setup Fees" with formula "capital_remittance.call_amount_cents * ((capital_commitment.fund_unit_setting&.setup_fee || 0) / 100.0)"
    When the call fee formula is calculated for a remittance with call amount 1000000 cents
    Then the call fee formula result should be 0.0

  Scenario: A formula that hits a missing unit setting names the fee and the commitment
    Given a call fee "Setup Fees" with formula "capital_remittance.call_amount_cents * (capital_commitment.fund_unit_setting.setup_fee / 100.0)"
    When the call fee formula is calculated for a remittance with call amount 1000000 cents
    Then the call fee formula should fail with a FormulaError containing "Fee formula 'Setup Fees'"
    And the call fee formula error should contain "commitment 511 (Investor A, folio F-511)"
    And the call fee formula error should contain "NoMethodError: undefined method 'setup_fee' for nil"
    And the call fee formula error cause should be a "NoMethodError"

  Scenario: A mistyped formula is wrapped too
    Given a call fee "Setup Fees" with formula "capital_remittance.call_amount_cents * ("
    When the call fee formula is calculated for a remittance with call amount 1000000 cents
    Then the call fee formula should fail with a FormulaError containing "SyntaxError"

  Scenario: A formula blocked by safe_eval is not wrapped
    Given a call fee "Setup Fees" saved without validation with formula "system('ls')"
    When the call fee formula is calculated for a remittance with call amount 1000000 cents
    Then the call fee formula should fail with an UnsafeEvalError
