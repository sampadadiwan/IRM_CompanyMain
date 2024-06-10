Feature: Import Fund Unit Setting
  Can bulk import fund unit settings

@import
Scenario Outline: Import fund unit settings
  Given Im logged in as a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund"
  Given the user has role "company_admin"
  Given there is a fund "name=SAAS Fund;currency=INR" for the entity
  And Given I upload a fund unit settings "fund_unit_setting.xlsx" for the fund
  Then There should be "2" fund unit settings created with data in "fund_unit_setting.xlsx"
  And Given I upload a fund unit settings "fund_unit_setting_update.xlsx" for the fund
  Then There should be "2" fund unit settings created with data in "fund_unit_setting_update.xlsx"


