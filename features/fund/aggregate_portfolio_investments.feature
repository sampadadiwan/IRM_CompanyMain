Feature: AggregatePortfolioInvestment
  Can create and view a fund Aggregate Portfolio Investment

Scenario Outline: Create new Aggregate Portfolio Investment
  Given Im logged in as a user "" for an entity "<entity>"
  And the user has role "company_admin"
  And there is an existing portfolio company "name=MyFavStartup;category=Portfolio Company"
  And there is an investment instrument for the portfolio company "name=Stock;category=Unlisted;sub_category=Equity;sector=Tech"
  And there is a fund "<fund1>" for the entity
  Given there are "3" portfolio investments "quantity=200;category=Unlisted"
  And there is a fund "<fund2>" for the entity
  Given there are "3" portfolio investments "quantity=100;category=Unlisted"
  Then 2 aggregate portfolio investments should be created
  Then I search for Merger

Examples:
  | entity                             | fund1                | fund2                                    |
  | entity_type=Investment Fund;       | name=Test fund       | name=Merger Fund;unit_types=Series A,Series B |
