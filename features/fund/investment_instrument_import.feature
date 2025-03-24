Feature: Investment Instruent Import
  Import investment instrument

Scenario Outline: Import Portfolio Insstrument
  Given Im logged in as a user "" for an entity "<entity>"
  Given the user has role "company_admin"
  Given there is an existing portfolio company "name=Delta Ventures;category=Portfolio Company"
  Given there is an existing portfolio company "name=Awesome Ventures;category=Portfolio Company"
  Given there is a fund "<fund>" for the entity
  When I upload investment instruments file "<upload_file>"
  Then "2" investment instruments should be created
  Then I should see the investment instrument details on the import page

  Examples:
    |entity                             |fund                           | upload_file |
    |entity_type=Investment Fund;       |name=Test fund;currency=INR    | investment_instruments.xlsx |
