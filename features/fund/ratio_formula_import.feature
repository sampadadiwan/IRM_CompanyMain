Feature: Import Ratio Formula
  Can bulk import ratio formulas for a fund

  Background:
    Given Im logged in as a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund"
    Given the user has role "company_admin"
    Given there is a fund "name=SAAS Fund;currency=INR" for the entity

@import
  Scenario: Import creates ratio formulas from xlsx
    Given Given import file "ratio_formulas.xlsx" for "RatioFormula"
    Then there should be "2" ratio formulas for the fund
    And the ratio formula "1" should have level "Fund" action "add_cashflow" period "as_on" ratio "XIRR" account_entry_names "Operating Income, Revenue"
    And the ratio formula "2" should have level "Folio" action "reduce_cashflow" period "all" ratio "MOIC" account_entry_names "Capital Expenditure"
    # Verify the model stores raw enum values regardless of humanized input
    And the ratio formula "1" should store raw enum value "add_cashflow" for action
    And the ratio formula "1" should store raw enum value "as_on" for period

@import
  Scenario: Re-importing the same file raises duplicate errors
    Given Given import file "ratio_formulas.xlsx" for "RatioFormula"
    Then there should be "2" ratio formulas for the fund
    And re-importing "ratio_formulas.xlsx" for "RatioFormula" should fail with duplicate errors
