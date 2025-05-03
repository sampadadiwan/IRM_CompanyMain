Feature: Fund Unit Setting
  Create and fetch fund unit settings


@import
Scenario Outline: Fetch Commitments fund unit setting
  Given Im logged in as a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund"
  Given the user has role "company_admin"
  Given there is a fund "name=SAAS Fund;currency=INR;unit_types=Series A,Series B,Series C, Series D" for the entity
  And Given I upload a fund unit settings "fund_unit_setting_test.xlsx" for the fund
  Then There should be "4" fund unit settings created with data in "fund_unit_setting_test.xlsx"
  And Given I upload an investors file for the fund
  And Given I upload "capital_commitments_multi_currency_fund_unit.xlsx" file for "Commitments" of the fund
  Then I should see the "Import in progress"
  Then There should be "8" capital commitments created
  And the imported data must have the form_type updated
  And the capital commitments must have the data in the sheet
  And the capital commitments must have the percentages updated
  And the fund must have the counter caches updated
  Then I can fetch the fund unit setting associated with the commitments
  And I can fetch the lp and gp commitments