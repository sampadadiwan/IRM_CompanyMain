Feature: Portfolio Report
  Can create and view a portfolio report

Scenario Outline: Create new PI and aggregate PI
  Given Im logged in as a user "" for an entity "<entity>"
  Given the user has role "company_admin"
  Given there is an existing portfolio company "name=MyFavStartup;category=Portfolio Company"
  Given there is an investment instrument for the portfolio company "name=Stock;category=Unlisted;sub_category=Equity;sector=Tech"
  Given there is a fund "<fund>" for the entity
  Given there are "3" portfolio investments "quantity=200"
  Given there are "3" portfolio investments "quantity=-100"
  Then an aggregate portfolio investment should be created
  Then I should see the aggregate portfolio investment details on the details page
  Given I add widgets for the aggregate portfolio investment
  And I add track record for the aggregate portfolio investment
  And I add preview documents for the aggregate portfolio investment
  When I go to aggregate portfolio investment preview
  Then I can see all the preview details

  Examples:
    |entity                             |fund                |
    |entity_type=Investment Fund;       |name=Test fund      |
    |entity_type=Investment Fund;       |name=Merger Fund;unit_types=Series A,Series B    |
