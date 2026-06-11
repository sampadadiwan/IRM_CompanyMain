Feature: Ratio Formula Management
  As a fund manager
  I want to define custom rules for financial ratios
  So that I can include specific account entries in my performance metrics

  Background:
    Given there is a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund;currency=INR"
    Given the user has role "company_admin"
    Given there is a fund "name=Demo Fund 2;currency=INR;unit_types=A1,A2" for the entity

  Scenario: Custom rule affects XIRR calculation
    Given Im logged in as user "Test"
    # Re-use working setup from existing tests
    And Given import file "fund_ratios/exchange_rates.xlsx" for "ExchangeRate"
    And Given import file "fund_ratios/investors.xlsx" for "Investor"
    And Given import file "fund_ratios/valuations.xlsx" for "Valuation"
    And Given import file "fund_ratios/investor_kycs.xlsx" for "InvestorKyc"
    And Given import file "fund_ratios/capital_commitments.xlsx" for "CapitalCommitment"
    And Given import file "fund_ratios/capital_distributions.xlsx" for "CapitalDistribution"
    And Given import file "fund_ratios/portfolio_investments.xlsx" for "PortfolioInvestment"
    And Given import file "fund_ratios/account_entries.xlsx" for "AccountEntry"
    And Given import file "fund_ratios/capital_calls.xlsx" for "CapitalCall"
    And Given import file "fund_ratios/capital_remittance_payments.xlsx" for "CapitalRemittancePayment"

    # Create the rule via factory/model
    Given there is a RatioFormula for the fund "Demo Fund 2" with "level=Fund;action=add_cashflow;ratio=XIRR;account_entry_names=Custom Inflow;period=all"
    
    # Add the custom entry that should be picked up by the formula
    And there is an AccountEntry "name=Custom Inflow;amount_cents=100000000;reporting_date=2024-01-01;entry_type=Income" for the fund
    
    When given the fund_ratios are computed for the date "31-03-2024"
    Then the FundRatio "XIRR" should be different from a computation without the formula

  Scenario: Access Ratio Formulas page
    Given Im logged in as user "Test"
    And I go to the fund show page for "Demo Fund 2"
    And I click link "Actions"
    And I click link "Account Entries"
    And I click link "Ratio Formulas"
    Then I should see "Ratio Formulas for Demo Fund 2"
    And I should see "New Ratio Formula"
