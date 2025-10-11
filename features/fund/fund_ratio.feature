Feature: Fund Ratio
  Manage fund ratios

Scenario Outline: Compute Fund Ratios
  Given there is a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund;currency=INR"
  Given the user has role "company_admin"
  Given there is a fund "name=Demo Fund 2;currency=INR;unit_types=A1,A2" for the entity
  And Given import file "fund_ratios/exchange_rates.xlsx" for "ExchangeRate"
  And Given import file "fund_ratios/investors.xlsx" for "Investor"
  And Given import file "fund_ratios/valuations.xlsx" for "Valuation"
  And Given import file "fund_ratios/investor_kycs.xlsx" for "InvestorKyc"
  And Given import file "fund_ratios/capital_commitments.xlsx" for "CapitalCommitment"
  And Given import file "fund_ratios/capital_distributions.xlsx" for "CapitalDistribution"
  And Given import file "fund_ratios/portfolio_investments.xlsx" for "PortfolioInvestment"
  And Given import file "fund_ratios/account_entries.xlsx" for "AccountEntry"
  And Given import file "fund_ratios/capital_calls.xlsx" for "CapitalCall"
  And Given import file "fund_ratios/capital_remittance_payments.xlsx" for "CapitalRemittancePayment"
  And given the fund_ratios are computed for the date "31-03-2024"
  Then the fund ratios computed must match the ratios in "fund_ratios/fund_ratios.xlsx"

Scenario Outline: Compute Fund Ratios in tracking currency
  Given there is a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund;currency=INR"
  Given the user has role "company_admin"
  Given there is a fund "name=Demo Fund 2;currency=INR;unit_types=A1,A2;tracking_currency=USD" for the entity
  And Given import file "fund_ratios/exchange_rates.xlsx" for "ExchangeRate"
  And Given import file "fund_ratios/investors.xlsx" for "Investor"
  And Given import file "fund_ratios/valuations.xlsx" for "Valuation"
  And Given import file "fund_ratios/investor_kycs.xlsx" for "InvestorKyc"
  And Given import file "fund_ratios/capital_commitments.xlsx" for "CapitalCommitment"
  And Given import file "fund_ratios/capital_distributions.xlsx" for "CapitalDistribution"
  And Given import file "fund_ratios/portfolio_investments.xlsx" for "PortfolioInvestment"
  And Given import file "fund_ratios/account_entries.xlsx" for "AccountEntry"
  And Given import file "fund_ratios/capital_calls.xlsx" for "CapitalCall"
  And Given import file "fund_ratios/capital_remittance_payments.xlsx" for "CapitalRemittancePayment"
  And given the fund_ratios are computed for the date "31-03-2024"
  Then the fund ratios must be computed in tracking currency also
  Given I log in as user "Test"
  And The Portfolio company MOIC ratio can be viewed properly

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


Scenario: Calculate XIRR from XLS sheets
  Given I have an Excel file "public/sample_uploads/xirr/xirr_scenarios.xlsx"
  When I read all sheets and compute XIRR
  Then each computed XIRR should match the expected output
