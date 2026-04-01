Feature: Currency Dropdown Visibility
  Verify currency dropdowns are displayed when multiple currencies are available

  Background:
    Given Im logged in as a user "first_name=Test" for an entity "name=Test Entity;entity_type=Investment Fund;currency=USD"
    Given the user has role "company_admin"
    Given there is a fund "name=Test Fund;currency=USD" for the entity

  Scenario: Currency dropdown shown in fund ratios when multiple currencies exist
    Given there is an existing portfolio company "name=TestCo;category=Portfolio Company"
    Given there is an investment instrument for the portfolio company "name=Stock;currency=USD"
    Given there is a fund ratio "name=IRR (USD);value=15.5;scenario=Default" for the fund
    Given there is a fund ratio "name=IRR (INR);value=12.3;scenario=Default" for the fund
    Given there is a fund ratio "name=TVPI;value=2.5;scenario=Default" for the fund
    When I visit the portfolio company dashboard
    Then I should see a select element for currency filtering
