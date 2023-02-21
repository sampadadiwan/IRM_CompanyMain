Feature: Portfolio
  Can create and view a fund pofrfolio investment

Scenario Outline: Create new portfolio investment
  Given Im logged in as a user "" for an entity "<entity>"
  Given the user has role "company_admin"
  Given there is an existing portfolio company "name=MyFavStartup;category=Portfolio Company" 
  Given there is a fund "<fund>" for the entity
  When I create a new portfolio investment "portfolio_company_name=MyFavStartup;amount_cents=1000000;quantity=200;investment_type=Equity"
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
  Given there are "3" portfolio investments "quantity=200;investment_type=Equity"
  Given there are "3" portfolio investments "quantity=-100;investment_type=Equity"
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
  Given there is a valuation "per_share_value_cents=10000;instrument_type=Equity" for the portfolio company 
  Given there are "3" portfolio investments "quantity=200;investment_type=Equity"
  Given there is a valuation "per_share_value_cents=12000;instrument_type=Equity" for the portfolio company 
  Given there are "3" portfolio investments "quantity=-100;investment_type=Equity"
  Then the fmv must be calculated for the portfolio
    

  Examples:
    |entity                             |fund                |
    |entity_type=Investment Fund;       |name=Test fund      |
    |entity_type=Investment Fund;       |name=Merger Fund;unit_types=Series A,Series B    |
