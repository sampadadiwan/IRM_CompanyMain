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
  # The per-holding preview page is retired (lp-folio-portfolio-dashboard E66, E80): no Preview or Show Portfolio
  # buttons; sharing with LPs is per company and laid out in LP layouts
  Then I should not see "Hide Portfolio"
  And I should see "Sharing with LPs has moved to the company"

  Examples:
    |entity                             |fund                |
    |entity_type=Investment Fund;       |name=Test fund      |
    |entity_type=Investment Fund;       |name=Merger Fund;unit_types=Series A,Series B    |
