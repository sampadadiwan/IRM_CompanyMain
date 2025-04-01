Feature: Fund Ratio
  Manage fund ratios

Scenario Outline: Compute Fund Ratios
  Given Im logged in as a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund"
  Given the user has role "company_admin"
  Given there is a fund "name=Fund X;currency=INR" for the entity
  And Given I upload an exchange_rates file "fund_ratios/exchange_rates.xlsx"
  And Given I upload investors file "fund_ratios/investors" for the fund
  And Given I upload "fund_ratios/valuations.xlsx" file for portfolio companies of the fund
  And Given I upload "fund_ratios/capital_commitments.xlsx" file for "Commitments" of the fund
  And Given I upload "fund_ratios/capital_calls.xlsx" file for "Calls" of the fund
  And Given I upload "fund_ratios/capital_distributions.xlsx" file for "Distributions" of the fund
  And Given I upload "fund_ratios/portfolio_investments3.xlsx" file for "Portfolio" of the fund
  And given the fund_ratios are computed for the date "30-9-2024"
  Then the fund ratios computed must match the ratios in "fund_ratios/fund_ratios computed.xlsx"
  


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