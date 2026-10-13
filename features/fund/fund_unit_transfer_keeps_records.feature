@rack_test
Feature: A fund unit transfer never deletes the source commitment's records
  FundUnitTransferService copies a share of the source commitment's remittances, payments and
  distribution payments to the destination and reduces the originals; it never deletes them.
  The existing "adjusted upon fund unit transfer" steps only check the records that still exist,
  so they would pass even if a transfer deleted them — this feature guards that.

@import
Scenario Outline: Transfer keeps every source record and adds one "out" unit
  Given Im logged in as a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund;currency=INR"
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
  Given the capital calls are approved
  And Given import file "fund_ratios/capital_remittance_payments.xlsx" for "CapitalRemittancePayment"
  Given the units are generated
  Given I note the records of the transfer's from and to commitments
  When fund units are transferred "<transfer>"
  Then no record of the from commitment is deleted by the transfer
  And the from commitment gains exactly one fund unit
  And the to commitment gains a copy of every from commitment remittance, payment and distribution payment

Examples:
  | transfer                                                                                      |
  | price=100,premium=10,transfer_ratio=1,transfer_account_entries=true,account_entries_excluded=nil    |
  | price=1000,premium=100,transfer_ratio=.5,transfer_account_entries=false,account_entries_excluded=nil |
