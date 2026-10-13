@rack_test
Feature: Tracking Currency Job
  As a fund manager
  I want to calculate tracking currency amounts for my fund
  So that I can see the fund performance in a different currency

  # Entity currency scenarios: verify entity_currency_amount_cents / entity_currency_fmv_cents
  # are populated on portfolio investments so cross-fund aggregations work on a single column.

  @import
  Scenario: Entity currency populated for a fund whose currency differs from the entity currency
    Given there is a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund;currency=INR"
    Given the user has role "company_admin"
    And the entity has "enable_tracking_currency" permission
    Given there is a fund "name=Comprehensive Test Fund Aug 2025 - Master Fund;currency=USD;unit_types=A,B,C,D,A4" for the entity
    Given there is a fund "name=Comprehensive Test Fund Aug 2025;currency=INR;unit_types=A,B,C,D,A4;master_fund_id=1;tracking_currency=USD" for the entity
    And Given import file "allocate_account_entries_2/exchange_rates.xlsx" for "ExchangeRate"
    And Given import file "allocate_account_entries_2/investors.xlsx" for "Investor"
    And Given import file "allocate_account_entries_2/valuations.xlsx" for "Valuation"
    And Given import file "allocate_account_entries_2/fund_unit_settings.xlsx" for "FundUnitSetting"
    And Given import file "allocate_account_entries_2/capital_commitments.xlsx" for "CapitalCommitment"
    And Given import file "allocate_account_entries_2/capital_calls.xlsx" for "CapitalCall"
    And Given import file "allocate_account_entries_2/capital_remittance_payments.xlsx" for "CapitalRemittancePayment"
    And Given import file "allocate_account_entries_2/capital_distributions.xlsx" for "CapitalDistribution"
    And Given import file "allocate_account_entries_2/portfolio_investments.xlsx" for "PortfolioInvestment"
    And Given import file "allocate_account_entries_2/account_entries.xlsx" for "AccountEntry"
    And Given import file "allocate_account_entries_2/fund_formulas.xlsx" for "FundFormula"
    When I run the TrackingCurrencyJob for all funds in the entity
    Then the entity currency amounts should be calculated for the USD fund
    And the entity currency FMV should be calculated for the USD fund

  @import
  Scenario: Entity currency equals fund currency — entity currency columns are a direct copy
    Given there is a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund;currency=INR"
    Given the user has role "company_admin"
    And the entity has "enable_tracking_currency" permission
    Given there is a fund "name=Comprehensive Test Fund Aug 2025 - Master Fund;currency=USD;unit_types=A,B,C,D,A4" for the entity
    Given there is a fund "name=Comprehensive Test Fund Aug 2025;currency=INR;unit_types=A,B,C,D,A4;master_fund_id=1;tracking_currency=USD" for the entity
    And Given import file "allocate_account_entries_2/exchange_rates.xlsx" for "ExchangeRate"
    And Given import file "allocate_account_entries_2/investors.xlsx" for "Investor"
    And Given import file "allocate_account_entries_2/valuations.xlsx" for "Valuation"
    And Given import file "allocate_account_entries_2/fund_unit_settings.xlsx" for "FundUnitSetting"
    And Given import file "allocate_account_entries_2/capital_commitments.xlsx" for "CapitalCommitment"
    And Given import file "allocate_account_entries_2/capital_calls.xlsx" for "CapitalCall"
    And Given import file "allocate_account_entries_2/capital_remittance_payments.xlsx" for "CapitalRemittancePayment"
    And Given import file "allocate_account_entries_2/capital_distributions.xlsx" for "CapitalDistribution"
    And Given import file "allocate_account_entries_2/portfolio_investments.xlsx" for "PortfolioInvestment"
    And Given import file "allocate_account_entries_2/account_entries.xlsx" for "AccountEntry"
    And Given import file "allocate_account_entries_2/fund_formulas.xlsx" for "FundFormula"
    When I run the TrackingCurrencyJob for the fund
    Then the entity currency amounts should equal the fund currency amounts for the INR fund

  @import
  Scenario: Entity currency FMV is refreshed when exchange rates are updated and force is used
    Given there is a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund;currency=INR"
    Given the user has role "company_admin"
    And the entity has "enable_tracking_currency" permission
    Given there is a fund "name=Comprehensive Test Fund Aug 2025 - Master Fund;currency=USD;unit_types=A,B,C,D,A4" for the entity
    Given there is a fund "name=Comprehensive Test Fund Aug 2025;currency=INR;unit_types=A,B,C,D,A4;master_fund_id=1;tracking_currency=USD" for the entity
    And Given import file "allocate_account_entries_2/exchange_rates.xlsx" for "ExchangeRate"
    And Given import file "allocate_account_entries_2/investors.xlsx" for "Investor"
    And Given import file "allocate_account_entries_2/valuations.xlsx" for "Valuation"
    And Given import file "allocate_account_entries_2/fund_unit_settings.xlsx" for "FundUnitSetting"
    And Given import file "allocate_account_entries_2/capital_commitments.xlsx" for "CapitalCommitment"
    And Given import file "allocate_account_entries_2/capital_calls.xlsx" for "CapitalCall"
    And Given import file "allocate_account_entries_2/capital_remittance_payments.xlsx" for "CapitalRemittancePayment"
    And Given import file "allocate_account_entries_2/capital_distributions.xlsx" for "CapitalDistribution"
    And Given import file "allocate_account_entries_2/portfolio_investments.xlsx" for "PortfolioInvestment"
    And Given import file "allocate_account_entries_2/account_entries.xlsx" for "AccountEntry"
    And Given import file "allocate_account_entries_2/fund_formulas.xlsx" for "FundFormula"
    When I run the TrackingCurrencyJob for all funds in the entity
    Given I go to the fund show page for "Comprehensive Test Fund Aug 2025 - Master Fund"
    Given I know the entity currency amounts for the fund
    Given I update all the exchange rates
    When I run the TrackingCurrencyJob for all funds in the entity
    Then the entity currency amounts should not be recalculated for the fund
    When I run the TrackingCurrencyJob with force for the fund
    Then the entity currency amounts should be recalculated for the fund

  @import
  Scenario: Cross-fund entity currency aggregation — both funds have non-zero entity currency columns
    Given there is a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund;currency=INR"
    Given the user has role "company_admin"
    And the entity has "enable_tracking_currency" permission
    Given there is a fund "name=Comprehensive Test Fund Aug 2025 - Master Fund;currency=USD;unit_types=A,B,C,D,A4" for the entity
    Given there is a fund "name=Comprehensive Test Fund Aug 2025;currency=INR;unit_types=A,B,C,D,A4;master_fund_id=1;tracking_currency=USD" for the entity
    And Given import file "allocate_account_entries_2/exchange_rates.xlsx" for "ExchangeRate"
    And Given import file "allocate_account_entries_2/investors.xlsx" for "Investor"
    And Given import file "allocate_account_entries_2/valuations.xlsx" for "Valuation"
    And Given import file "allocate_account_entries_2/fund_unit_settings.xlsx" for "FundUnitSetting"
    And Given import file "allocate_account_entries_2/capital_commitments.xlsx" for "CapitalCommitment"
    And Given import file "allocate_account_entries_2/capital_calls.xlsx" for "CapitalCall"
    And Given import file "allocate_account_entries_2/capital_remittance_payments.xlsx" for "CapitalRemittancePayment"
    And Given import file "allocate_account_entries_2/capital_distributions.xlsx" for "CapitalDistribution"
    And Given import file "allocate_account_entries_2/portfolio_investments.xlsx" for "PortfolioInvestment"
    And Given import file "allocate_account_entries_2/account_entries.xlsx" for "AccountEntry"
    And Given import file "allocate_account_entries_2/fund_formulas.xlsx" for "FundFormula"
    When I run the TrackingCurrencyJob for all funds in the entity
    Then every portfolio investment in the entity should have a non-zero entity currency amount

  @import
  Scenario: Recalculate tracking currency for a fund
    Given there is a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund;currency=INR"
    Given the user has role "company_admin"
    Given there is a fund "name=Comprehensive Test Fund Aug 2025 - Master Fund;currency=USD;unit_types=A,B,C,D,A4" for the entity
    Given there is a fund "name=Comprehensive Test Fund Aug 2025;currency=INR;unit_types=A,B,C,D,A4;master_fund_id=1;tracking_currency=USD" for the entity
    And Given import file "allocate_account_entries_2/exchange_rates.xlsx" for "ExchangeRate"
    And Given import file "allocate_account_entries_2/investors.xlsx" for "Investor"
    And Given import file "allocate_account_entries_2/valuations.xlsx" for "Valuation"
    And Given import file "allocate_account_entries_2/fund_unit_settings.xlsx" for "FundUnitSetting"
    And Given import file "allocate_account_entries_2/capital_commitments.xlsx" for "CapitalCommitment"
    And Given import file "allocate_account_entries_2/capital_calls.xlsx" for "CapitalCall"
    And Given import file "allocate_account_entries_2/capital_remittance_payments.xlsx" for "CapitalRemittancePayment"
    And Given import file "allocate_account_entries_2/capital_distributions.xlsx" for "CapitalDistribution"
    And Given import file "allocate_account_entries_2/portfolio_investments.xlsx" for "PortfolioInvestment"
    And Given import file "allocate_account_entries_2/account_entries.xlsx" for "AccountEntry"
    And Given import file "allocate_account_entries_2/fund_formulas.xlsx" for "FundFormula"
    When I run the TrackingCurrencyJob for the fund
    Then the tracking amounts should be calculated for the fund

  @import
  Scenario: Recalculate tracking currency for a fund with force
    Given Im logged in as a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund;currency=INR"
    Given the user has role "company_admin"
    Given there is a fund "name=Comprehensive Test Fund Aug 2025 - Master Fund;currency=USD;unit_types=A,B,C,D,A4" for the entity
    Given there is a fund "name=Comprehensive Test Fund Aug 2025;currency=INR;unit_types=A,B,C,D,A4;master_fund_id=1;tracking_currency=USD" for the entity
    And Given import file "allocate_account_entries_2/exchange_rates.xlsx" for "ExchangeRate"
    And Given import file "allocate_account_entries_2/investors.xlsx" for "Investor"
    And Given import file "allocate_account_entries_2/valuations.xlsx" for "Valuation"
    And Given import file "allocate_account_entries_2/fund_unit_settings.xlsx" for "FundUnitSetting"
    And Given import file "allocate_account_entries_2/capital_commitments.xlsx" for "CapitalCommitment"
    And Given import file "allocate_account_entries_2/capital_calls.xlsx" for "CapitalCall"
    And Given import file "allocate_account_entries_2/capital_remittance_payments.xlsx" for "CapitalRemittancePayment"
    And Given import file "allocate_account_entries_2/capital_distributions.xlsx" for "CapitalDistribution"
    And Given import file "allocate_account_entries_2/portfolio_investments.xlsx" for "PortfolioInvestment"
    And Given import file "allocate_account_entries_2/account_entries.xlsx" for "AccountEntry"
    And Given import file "allocate_account_entries_2/fund_formulas.xlsx" for "FundFormula"
    When I run the TrackingCurrencyJob for the fund
    Then the tracking amounts should be calculated for the fund
    Given I know the amounts calculated for the fund
    Given I update all the exchange rates
    When I run the TrackingCurrencyJob for the fund
    Then the tracking amounts should not be recalculated
    When I run the TrackingCurrencyJob with force for the fund
    Then the tracking amounts should be recalculated
