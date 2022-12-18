Feature: Investment Opportunity
  Can create and view a investment_opportunity as a company

Scenario Outline: Create new investment_opportunity
  Given Im logged in as a user "" for an entity "<entity>"
  Given the user has role "company_admin"
  And I am at the investment_opportunities page
  When I create a new investment_opportunity "<investment_opportunity>"
  Then I should see the "<msg>"
  And an investment_opportunity should be created
  And I should see the investment_opportunity details on the details page
  And I should see the investment_opportunity in all investment_opportunities page

  Examples:
  	|entity                                 |investment_opportunity                  |msg	|
  	|entity_type=Investment Fund;enable_inv_opportunities=true  |company_name=Test IO|opportunity was successfully created|
    |entity_type=Investment Fund;enable_inv_opportunities=true  |company_name=IO 2   |opportunity was successfully created|

