Feature: Import Exchange Rates
  Imports Exchange Rates and marks latest

@import
Scenario Outline: Import Exchange Rates
  Given Im logged in as a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund"
  Given the user has role "company_admin"
  Given there is a fund "name=SAAS Fund;currency=INR;unit_types=Series A,Series B,Series C1" for the entity
  And Given I upload the portfolio companies
  And Given I upload "portfolio_investments.xlsx" file for "Portfolio" of the fund
	And Given I upload an exchange_rates file "exchange_rates.xlsx"
  Then I should see the "Import in progress"
  Then There should be 2 exchange rates created