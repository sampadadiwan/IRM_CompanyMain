Feature: Capital Distributions
  Capital Distributions fees

Scenario Outline: Create a capital distribution
  Given Im logged in as a user "" for an entity "entity_type=Investment Fund"
  Given the user has role "company_admin"
  Given there is a fund "name=SAAS Fund;currency=INR" for the entity
  Given there is an existing investor "name=Investor 1"
  Given there is a capital commitment of "orig_folio_committed_amount_cents=100000000;folio_currency=INR" for the last investor
  Given there is a capital commitment of "orig_folio_committed_amount_cents=100000000;folio_currency=INR;fund_close=Second Close" for the last investor
  Given there is a AccountEntry for distribution "<income_account_entry>"
  Given there is a AccountEntry for distribution "<tax_account_entry>"
  Given there is a AccountEntry for distribution "<fv_account_entry>"
  When I create a Capital Distribution "<capital_distribution>"  
  Then it should create Capital Distribution
  And the data should be correctly displayed for each Capital Distribution Payment

  Examples:
    | capital_distribution | income_account_entry | tax_account_entry | fv_account_entry |
    | title=Capital Distribution 1;income_cents=10000000;cost_of_investment_cents=5000000;reinvestment_cents=2000000;distribution_date=2024-12-15 | name=Portfolio Cashflows;reporting_date=2024-12-02;entry_type=Income;amount_cents=100000 | name=TDS;reporting_date=2024-12-02;entry_type=Tax;amount_cents=50000 | name=FV for Redemption;reporting_date=2024-12-02;entry_type=FV For Redemption;amount_cents=10000 |
