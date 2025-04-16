Feature: Portfolio
  Can create and view a fund pofrfolio investment

Scenario Outline: Create new portfolio investment
  Given Im logged in as a user "" for an entity "<entity>"
  Given the user has role "company_admin"
  Given there is an existing portfolio company "name=MyFavStartup;category=Portfolio Company"
  Given there is a fund "<fund>" for the entity
  Given there is an investment instrument for the portfolio company "<portfolio_instrument>"
  When I create a new portfolio investment "portfolio_company_name=MyFavStartup;base_amount_cents=1000000;quantity=200"
  Then a portfolio investment should be created
  Then I should see the portfolio investment details on the details page

  Examples:
    |entity                             |fund                           | portfolio_instrument |
    |entity_type=Investment Fund;       |name=Test fund;currency=INR    | name=XYZ;currency=INR |
    |entity_type=Investment Fund;       |name=Merger Fund;currency=INR  | name=XYZ;currency=USD |


Scenario Outline: Create new PI and aggregate PI
  Given Im logged in as a user "" for an entity "<entity>"
  Given the user has role "company_admin"
  Given there is an existing portfolio company "name=MyFavStartup;category=Portfolio Company"
  Given there is an investment instrument for the portfolio company "name=Stock;category=Unlisted;sub_category=Equity;sector=Tech"
  Given there is a fund "<fund>" for the entity
  Given there are "3" portfolio investments "quantity=200"
  Given there are "3" portfolio investments "quantity=-100"
  Given the fund snapshot is created
  Then the total number of portfolio investments with snapshots should be "12"
  Then an aggregate portfolio investment should be created
  And the aggregate portfolio investment should have a quantity of "300"
  Then I should see the aggregate portfolio investment details on the details page

  Examples:
    |entity                             |fund                |
    |entity_type=Investment Fund;       |name=Test fund      |
    |entity_type=Investment Fund;       |name=Merger Fund;unit_types=Series A,Series B    |


Scenario Outline: Create valuation and FMV
  Given there is a user "" for an entity "<entity>"
  # Given the user has role "company_admin"
  Given there is an existing portfolio company "name=MyFavStartup;category=Portfolio Company"
  Given there is an investment instrument for the portfolio company "name=XYZ;category=Unlisted;sub_category=Equity;sector=Tech"
  Given there is a fund "<fund>" for the entity
  Given there are "3" portfolio investments "quantity=200;category=Unlisted"
  Given there are "3" portfolio investments "quantity=-100;category=Unlisted;"
  Given there is a valuation "per_share_value_cents=12000" for the portfolio company
  Then the fmv must be calculated for the portfolio


  Examples:
    |entity                             |fund                |
    |entity_type=Investment Fund;       |name=Test fund      |
    |entity_type=Investment Fund;       |name=Merger Fund;unit_types=Series A,Series B    |

Scenario Outline: Generate Fund Reports
  Given Im logged in as a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund"
  Given the user has role "company_admin"
  Given there is a fund "name=SAAS Fund;currency=INR;unit_types=Series A,Series B,Series C1" for the entity
  And Given I upload an investors file for the fund
  And Given import file "capital_commitments_multi_currency.xlsx" for "CapitalCommitment"
  And Given I upload the portfolio companies
  And Given import file "portfolio_investments3.xlsx" for "PortfolioInvestment"
  Then There should be "8" portfolio investments created
  Given The user generates all fund reports for the fund
  Then There should be "3" reports created
  And Sebi report should be generated for the fund


@import
Scenario Outline: Import portfolio investments
  Given Im logged in as a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund"
  Given the user has role "company_admin"
  Given there is a fund "name=SAAS Fund;currency=INR;unit_types=Series A,Series B,Series C1" for the entity
  And Given I upload an investors file for the fund
  And Given I upload "capital_commitments_multi_currency.xlsx" file for "Commitments" of the fund
  Then I should see the "Import in progress"
  And Given I upload the portfolio companies
  And Given I upload "portfolio_investments.xlsx" file for "Portfolio" of the fund
  Then I should see the "Import in progress"
  Then There should be "8" portfolio investments created
  And the portfolio investments must have the data in the sheet
  And the aggregate portfolio investments must have cost of sold computed


@import
Scenario Outline: Import portfolio valuations
  Given Im logged in as a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund"
  Given the user has role "company_admin"
  Given there is a fund "name=SAAS Fund;currency=INR" for the entity
  And Given I upload the portfolio companies
  And the portfolio companies have investment instruments "name=Common Stock;category=Unlisted;sub_category=Equity;sector=Tech"
  And Given I upload "valuations.xlsx" file for portfolio companies of the fund
  Then I should see the "Import in progress"
  Then There should be "4" valuations created
  And the valuations must have the data in the sheet

Scenario Outline: FIFO
  Given there is a user "" for an entity "entity_type=Investment Fund;"
  Given there is an existing portfolio company "name=MyFavStartup;category=Portfolio Company"
  Given there is an investment instrument for the portfolio company "name=Common Stock;category=Unlisted;sub_category=Equity;sector=Tech"
  Given there is a fund "name=Test fund" for the entity
  Given there is a valuation "per_share_value_cents=10000;valuation_date=01/01/2022" for the portfolio company
  Given there are "3" portfolio investments "quantity=200"
  Given there are "1" portfolio investments "<sell>"
  Then there must be "<attribution_count>" portfolio attributions created

  Examples:
    |sell                |attribution_count                |
    |quantity=-200       |1       |
    |quantity=-300       |2       |
    |quantity=-400       |2       |
    |quantity=-500       |3       |
    |quantity=-600       |3       |



Scenario Outline: Stock Adjustment
  Given Im logged in as a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund"
  Given the user has role "company_admin"
  Given there is a fund "name=SAAS Fund;currency=INR" for the entity
  Given there is an existing portfolio company "name=Apple;primary_email=tc@apple.com;category=Portfolio Company"
  Given there is an investment instrument for the portfolio company "name=Stock;category=Unlisted;sub_category=Equity;sector=Tech;investment_domicile=Domestic;startup=true"
  Given there is a valuation "per_share_value_cents=10000" for the portfolio company
  And Given I upload "portfolio_investments2.xlsx" file for "Portfolio" of the fund
  Then I should see the "Import in progress"
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


Scenario Outline: Stock Conversion
  Given Im logged in as a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund"
  Given the user has role "company_admin"
  Given there is a fund "name=SAAS Fund;currency=INR" for the entity
  Given there is an existing portfolio company "name=Apple;primary_email=tc@apple.com;category=Portfolio Company"
  Given there is an investment instrument for the portfolio company "<from_instrument>"
  Given there is a valuation "per_share_value_cents=10000" for the portfolio company
  And Given I upload "portfolio_investments2.xlsx" file for "Portfolio" of the fund
  Then I should see the "Import in progress"
  Then There should be "2" portfolio investments created
  Given there is an investment instrument for the portfolio company "<to_instrument>"
  Given I create a new stock conversion "<conversion>"  from "<from_instrument>" to "<to_instrument>"
  Then the from portfolio investments must be adjusted
  And the to portfolio investments must be created
  And the APIs must have the right quantity post transfer
  And When I reverse the stock conversion
  Then the to portfolio investments must be deleted
  And the stock conversion must be deleted
  And the from portfolio investments must be adjusted
  Examples:
    |conversion                                     | from_instrument | to_instrument |
    |from_quantity=1000;to_quantity=2000;notes=Test  | name=Stock;investment_domicile=Domestic      | name=CCPS;investment_domicile=Domestic     |
    |from_quantity=2000;to_quantity=50000;notes=Test  | name=Stock;investment_domicile=Domestic;currency=INR| name=Debt;investment_domicile=Domestic ;currency=USD    |
