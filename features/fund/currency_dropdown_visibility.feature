Feature: Currency Dropdown Visibility
  Verify currency dropdowns are displayed based on show_currency_filter metadata setting

  Background:
    Given Im logged in as a user "first_name=Test" for an entity "name=Test Entity;entity_type=Investment Fund;currency=USD"
    Given the user has role "company_admin"
    Given there is a fund "name=Test Fund;currency=USD" for the entity

  Scenario: Fund Ratios - Currency dropdown shown when show_currency_filter is true
    Given there is an existing portfolio company "name=TestCo;category=Portfolio Company"
    Given there is an investment instrument for the portfolio company "name=Stock;currency=USD"
    Given there is a fund ratio "name=IRR (USD);value=15.5;scenario=Default" for the fund
    Given there is a fund ratio "name=IRR (INR);value=12.3;scenario=Default" for the fund
    Given there is a fund ratio "name=TVPI;value=2.5;scenario=Default" for the fund
    Given the Fund Ratios widget has metadata "{scenarios: true, condensed: true, chart: false, title: 'Ratios: Actual', hide_search: true, months: 6, show_currency_filter: true}"
    When I visit the portfolio company dashboard
    Then I should see a currency dropdown for fund ratios

  Scenario: Fund Ratios - Currency dropdown hidden when show_currency_filter is false
    Given there is an existing portfolio company "name=TestCo;category=Portfolio Company"
    Given there is an investment instrument for the portfolio company "name=Stock;currency=USD"
    Given there is a fund ratio "name=IRR (USD);value=15.5;scenario=Default" for the fund
    Given there is a fund ratio "name=IRR (INR);value=12.3;scenario=Default" for the fund
    Given there is a fund ratio "name=TVPI;value=2.5;scenario=Default" for the fund
    Given the Fund Ratios widget has metadata "{scenarios: true, condensed: true, chart: false, title: 'Ratios: Actual', hide_search: true, months: 6, show_currency_filter: false}"
    When I visit the portfolio company dashboard
    Then I should not see a currency dropdown for fund ratios

  @rack_test
  Scenario: Portfolio Stats - Currency dropdown shown when show_currency_filter is true
    Given there is an existing portfolio company "name=TestCo;category=Portfolio Company"
    Given there is an investment instrument for the portfolio company "name=Stock;currency=USD"
    Given there is a portfolio investment for the fund "base_amount_cents=10000000"
    Given the Portfolio Stats widget has metadata "{force_units: 'Millions', fields: 'Bought Amount,Sold Amount,FMV,Cost of Remaining', show_currency_filter: true}"
    When I visit the portfolio company dashboard
    Then I should see a currency dropdown for portfolio stats

  Scenario: Portfolio Stats - Currency dropdown hidden when show_currency_filter is false
    Given there is an existing portfolio company "name=TestCo;category=Portfolio Company"
    Given there is an investment instrument for the portfolio company "name=Stock;currency=USD"
    Given there is a portfolio investment for the fund "base_amount_cents=10000000"
    Given the Portfolio Stats widget has metadata "{force_units: 'Millions', fields: 'Bought Amount,Sold Amount,FMV,Cost of Remaining', show_currency_filter: false}"
    When I visit the portfolio company dashboard
    Then I should not see a currency dropdown for portfolio stats


  Scenario: Portfolio Company Report (Valuations) - Currency dropdown hidden when show_currency_filter is false
    Given there is an existing portfolio company "name=TestCo;category=Portfolio Company"
    Given there is an investment instrument for the portfolio company "name=Stock;currency=USD"
    Given there is a valuation with multiple currencies for the investment instrument
    Given the Portfolio Company Report widget has metadata with show_currency_filter false
    When I visit the portfolio company dashboard
    Then I should not see a currency dropdown for valuations
