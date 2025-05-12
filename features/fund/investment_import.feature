Feature: Investment Import
  Can bulk upload and update investments

Scenario Outline: Bulk upload and update investment
  Given Im logged in as a user "" for an entity "<entity>"
  Given the user has role "company_admin"
  Given there is an existing portfolio company "name=MyFavStartup;category=Portfolio Company"
  Given there is a fund "<fund>" for the entity
  Given there is an investment instrument for the portfolio company "<portfolio_instrument>"
  When I create a new portfolio investment "portfolio_company_name=MyFavStartup;base_amount_cents=1000000;quantity=200"
  Then a portfolio investment should be created
  Then I should see the portfolio investment details on the details page
  Given I go to the portfolio company page
  And I go to the captable of the portfolio company
  And I upload investments file "investments_test.xlsx"
  Then "2" Investments should be created for the portfolio company with expected details
  And I go to the portfolio company page
  And I go to the captable of the portfolio company
  Given I upload investments file "investments_update.xlsx"
  Then Investments should have the updated data from "investments_update.xlsx"



  Examples:
    |entity                             |fund                           | portfolio_instrument |
    |entity_type=Investment Fund;       |name=Test fund;currency=INR    | name=XYZ;currency=INR |
