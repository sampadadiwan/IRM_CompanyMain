Feature: Fund Ratio Access
  Can access fund ratios as a company

Scenario Outline: Access Fund Ratios as Other User
  Given there is a user "" for an entity "entity_type=Company;name=TestCompany303"
  And the user has role "<role>"
  Given there is a fund "name=Test fund" for the entity
  Given the fund has fund ratios
  Given there is another user "" for another entity "entity_type=Consulting"
  Then "first_name=Another User" has "false" "<crud>" access to the fund_ratios

  Examples:
  |role         |crud|
  |company_admin|"show,create,new,update,edit,destroy"|
