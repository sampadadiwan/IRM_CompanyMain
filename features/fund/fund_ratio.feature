Feature: Fund Ratio
  Can run allocation

@import
Scenario Outline: Import Fund Ratio
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given the user has role "company_admin"
  And there is a fund "<fund>" for the entity
  Given there is an existing investor "" with "1" users
  Given there is an existing investor "" with "1" users
  And there is an existing portfolio company "name=MyFavStartup;category=Portfolio Company"
  And there is an investment instrument for the portfolio company "name=Stock;category=Unlisted;sub_category=Equity;sector=Tech"
  Given there are "3" portfolio investments "quantity=200;category=Unlisted"
  Given my firm is an investor in the fund
  Given there are capital commitments of "committed_amount_cents=100000000" from each investor
  Given there is a CapitalCommitment with "folio_id=DF1"
  Given a Bulk Upload is performed for FundRatios with file "fund_ratios.xlsx"
  Then I should find Fund Ratios created with correct data for Fund
  Then I should find Fund Ratios created with correct data for API
  Then I should find Fund Ratios created with correct data for Capital Commitment

  Examples:
      |user     |entity                                 |fund                 |
      |           |entity_type=Investment Fund;enable_funds=true  |name=Demo Fund  |

@import
Scenario Outline: Bulk update Fund Ratio
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given the user has role "company_admin"
  And there is a fund "<fund>" for the entity
  Given there is an existing investor "" with "1" users
  Given there is an existing investor "" with "1" users
  And there is an existing portfolio company "name=MyFavStartup;category=Portfolio Company"
  And there is an investment instrument for the portfolio company "name=Stock;category=Unlisted;sub_category=Equity;sector=Tech"
  Given there are "3" portfolio investments "quantity=200;category=Unlisted"
  Given my firm is an investor in the fund
  Given there are capital commitments of "committed_amount_cents=100000000" from each investor
  Given there is a CapitalCommitment with "folio_id=DF1" 
  Given a Bulk Upload is performed for FundRatios with file "fund_ratios.xlsx"
  Given a Bulk Upload is performed for FundRatios with file "fund_ratios_update.xlsx"
  Then the Fund ratios must be updated

  Examples:
      |user     |entity                                 |fund                 |
      |           |entity_type=Investment Fund;enable_funds=true  |name=Demo Fund  |