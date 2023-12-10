Feature: Portfolio
  Can create and view a fund pofrfolio investment

Scenario Outline: Create new portfolio investment
  Given Im logged in as a user "" for an entity "<entity>"
  Given the user has role "company_admin"
  Given there is an existing portfolio company "name=MyFavStartup;category=Portfolio Company" 
  Given there is a fund "<fund>" for the entity
  When I create a new portfolio investment "portfolio_company_name=MyFavStartup;amount_cents=1000000;quantity=200;category=Unlisted"
  Then a portfolio investment should be created
  Then I should see the portfolio investment details on the details page  

  Examples:
    |entity                             |fund                |
    |entity_type=Investment Fund;       |name=Test fund      |
    |entity_type=Investment Fund;       |name=Merger Fund;unit_types=Series A,Series B    |


Scenario Outline: Create new PI and aggregate PI
  Given Im logged in as a user "" for an entity "<entity>"
  Given the user has role "company_admin"
  Given there is an existing portfolio company "name=MyFavStartup;category=Portfolio Company" 
  Given there is a fund "<fund>" for the entity
  Given there are "3" portfolio investments "quantity=200;category=Unlisted"
  Given there are "3" portfolio investments "quantity=-100;category=Unlisted"
  Then an aggregate portfolio investment should be created
  Then I should see the aggregate portfolio investment details on the details page  

  Examples:
    |entity                             |fund                |
    |entity_type=Investment Fund;       |name=Test fund      |
    |entity_type=Investment Fund;       |name=Merger Fund;unit_types=Series A,Series B    |


Scenario Outline: Create valuation and FMV
  Given there is a user "" for an entity "<entity>"
  # Given the user has role "company_admin"
  Given there is an existing portfolio company "name=MyFavStartup;category=Portfolio Company" 
  Given there is a fund "<fund>" for the entity
  Given there is a valuation "per_share_value_cents=10000;category=Unlisted;sub_category=Equity;valuation_date=01/01/2022" for the portfolio company 
  Given there are "3" portfolio investments "quantity=200;category=Unlisted"
  Given there is a valuation "per_share_value_cents=12000;category=Unlisted;sub_category=Equity;valuation_date=01/01/2023" for the portfolio company 
  Given there are "3" portfolio investments "quantity=-100;category=Unlisted"
  Then the fmv must be calculated for the portfolio
    

  Examples:
    |entity                             |fund                |
    |entity_type=Investment Fund;       |name=Test fund      |
    |entity_type=Investment Fund;       |name=Merger Fund;unit_types=Series A,Series B    |

Scenario Outline: Import portfolio investments
  Given Im logged in as a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund"
  Given the user has role "company_admin"
  Given there is a fund "name=SAAS Fund;currency=INR" for the entity
  And Given I upload an investors file for the fund
  And Given I upload "capital_commitments_multi_currency.xlsx" file for "Commitments" of the fund
  Then I should see the "Import upload was successfully created"
  And Given I upload "portfolio_investments.xlsx" file for "Portfolio" of the fund
  Then I should see the "Import upload was successfully created"
  Then There should be "8" portfolio investments created
  And the portfolio investments must have the data in the sheet
  And the aggregate portfolio investments must have cost of sold computed

Scenario Outline: Import portfolio investments failed
  Given Im logged in as a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund"
  Given the user has role "company_admin"
  Given there is a fund "name=SAAS Fund;currency=INR" for the entity
  And Given I upload an investors file for the fund
  And Given I upload "capital_commitments_multi_currency.xlsx" file for "Commitments" of the fund
  Then I should see the "Import upload was successfully created"
  And Given I upload "co_invest_portfolio_investments_failed.xlsx" file for "Portfolio" of the fund
  Then I should see the "Import upload was successfully created"
  Then There should be "1" portfolio investments created


Scenario Outline: Import portfolio valuations
  Given Im logged in as a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund"
  Given the user has role "company_admin"
  Given there is a fund "name=SAAS Fund;currency=INR" for the entity
  And Given I upload "valuations.xlsx" file for portfolio companies of the fund
  Then I should see the "Import upload was successfully created"
  Then There should be "4" valuations created
  And the valuations must have the data in the sheet

Scenario Outline: FIFO
  Given there is a user "" for an entity "entity_type=Investment Fund;"
  Given there is an existing portfolio company "name=MyFavStartup;category=Portfolio Company" 
  Given there is a fund "name=Test fund" for the entity
  Given there is a valuation "per_share_value_cents=10000;category=Unlisted;sub_category=Equity;valuation_date=01/01/2022" for the portfolio company 
  Given there are "3" portfolio investments "quantity=200;category=Unlisted"
  Given there are "1" portfolio investments "<sell>"
  Then there must be "<attribution_count>" portfolio attributions created

  Examples:
    |sell                                        |attribution_count                |
    |quantity=-200;category=Unlisted;       |1       |
    |quantity=-300;category=Unlisted;       |2       |
    |quantity=-400;category=Unlisted;       |2       |
    |quantity=-500;category=Unlisted;       |3       |
    |quantity=-600;category=Unlisted;       |3       |



Scenario Outline: Stock Adjustment
  Given Im logged in as a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund"
  Given the user has role "company_admin"
  Given there is a fund "name=SAAS Fund;currency=INR" for the entity
  Given there is an existing portfolio company "name=Apple;pan=BUHNXDFEA7;category=Portfolio Company" 
  Given there is a valuation "per_share_value_cents=10000;category=Unlisted;sub_category=Equity" for the portfolio company
  And Given I upload "portfolio_investments2.xlsx" file for "Portfolio" of the fund
  Then I should see the "Import upload was successfully created"
  Then There should be "2" portfolio investments created
  Given I create a new stock adjustment "<adjustment>"
  Then the valuations must be adjusted
  And the Portfolio investments must be adjusted
  And the Portfolio attributions must be adjusted
  Examples:
    |adjustment |
    |adjustment=2.0;category=Unlisted;sub_category=Equity          |
    |adjustment=0.5;category=Unlisted;sub_category=Equity          |
    |adjustment=3.0;category=Unlisted;sub_category=Equity          |
