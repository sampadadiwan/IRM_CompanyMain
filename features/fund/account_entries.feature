Feature: Account Entries
  Can run allocation


@import
Scenario Outline: Allocate account entries
  Given there is a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund;currency=INR"
  Given the user has role "company_admin"
  Given there is a fund "name=Comprehensive Test Fund Aug 2025 - Master Fund;currency=USD;unit_types=A,B,C,D,A4" for the entity
  Given there is a fund "name=Comprehensive Test Fund Aug 2025;currency=INR;unit_types=A,B,C,D,A4;master_fund_id=1" for the entity
  And Given import file "allocate_account_entries_2/exchange_rates.xlsx" for "ExchangeRate"
  And Given import file "allocate_account_entries_2/investors.xlsx" for "Investor"
  And Given import file "allocate_account_entries_2/valuations.xlsx" for "Valuation"
  And Given import file "allocate_account_entries_2/fund_unit_settings.xlsx" for "FundUnitSetting"
  And Given import file "allocate_account_entries_2/capital_commitments.xlsx" for "CapitalCommitment"
  And Given import file "allocate_account_entries_2/capital_calls.xlsx" for "CapitalCall"
  And Given import file "allocate_account_entries_2/capital_remittance_payments.xlsx" for "CapitalRemittancePayment"
  And Given import file "allocate_account_entries_2/capital_distributions.xlsx" for "CapitalDistribution"
  And Given import file "allocate_account_entries_2/portfolio_investments.xlsx" for "PortfolioInvestment"
  And Given import file "allocate_account_entries_2/account_entries.xlsx" for "AccountEntry"
  And Given import file "allocate_account_entries_2/fund_formulas.xlsx" for "FundFormula"
  And the Allocation Run "<allocation_run>" is created for the "Comprehensive Test Fund Aug 2025"
  Then the account entries generated match the account entries in "allocate_account_entries_2/generated_account_entries.xlsx"
  And the AllocationRun status is set to "Success"

  Examples:
    | allocation_run |
    | start_date=01/04/2023;end_date=30/06/2024, |

Scenario Outline: Allocate Account Entries
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given the user has role "company_admin"
  Given there is an existing investor "" with "1" users
  Given there is an existing investor "" with "1" users
  Given there is a fund "<fund>" for the entity
  Given the investors are added to the fund
  Given there are capital commitments of "committed_amount_cents=100000000" from each investor
  Given there are Fund Formulas are added to the fund
  When I am at the fund details page
  Given that Account Entries are allocated
  Then I see AllocationRun created

  Examples:
      |user     |entity                                 |fund                 |
      |           |entity_type=Investment Fund;enable_funds=true  |name=Test  |

Scenario Outline: When AllocationRun is locked
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given the user has role "company_admin"
  Given there is an existing investor "" with "1" users
  Given there is an existing investor "" with "1" users
  Given there is a fund "<fund>" for the entity
  Given the investors are added to the fund
  Given there are capital commitments of "committed_amount_cents=100000000" from each investor
  Given there are Fund Formulas are added to the fund
  When I am at the fund details page
  Given that Account Entries are allocated
  Then I see AllocationRun created
  Given I lock the AllocationRun
  Given that Account Entries are allocated
  Then I get the error on AllocationRun creation

  Examples:
      |user     |entity                                 |fund                 |
      |           |entity_type=Investment Fund;enable_funds=true  |name=Test  |

Scenario Outline: Create New Account Entry for commitment
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given the user has role "company_admin"
  Given there is an existing investor "" with "1" users
  Given there is an existing investor "" with "1" users
  Given there is a fund "<fund>" for the entity
  Given the investors are added to the fund
  Given there are capital commitments of "committed_amount_cents=100000000" from each investor
  Given I am at the capital commitment page
  Given I add a new account entry
  Then an account entry is created for the commitment

  Examples:
      |user     |entity                                 |fund                 |
      |           |entity_type=Investment Fund;enable_funds=true  |name=Test  |

Scenario Outline: Edit Account Entry parent
  Given Im logged in as a user "<user>" for an entity "<entity>"
  Given the user has role "company_admin"
  Given there is an existing investor "" with "1" users
  Given there is an existing investor "" with "1" users
  Given there is a fund "<fund>" for the entity
  Given the investors are added to the fund
  Given there are capital commitments of "committed_amount_cents=100000000" from each investor
  Given I am at the capital commitment page
  Given I add a new account entry
  Then an account entry is created for the commitment
  Then I edit the account entry with debug "true"
  Then the account entry parent is updated


  Examples:
      |user     |entity                                 |fund                 |
      |           |entity_type=Investment Fund;enable_funds=true  |name=Test  |


@notification @import
Scenario Outline: AE download in a job
  Given Im logged in as a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund"
  Given the user has role "company_admin"
  Given the user can receive emails
  Given there is a fund "name=SAAS Fund;currency=INR;unit_types=Series A,Series B,Series C1" for the entity
  And Given I upload an investors file for the fund
  And Given I upload "capital_commitments_multi_currency.xlsx" file for "Commitments" of the fund
  Then I should see the "Import in progress"
  Then There should be "8" capital commitments created
  And Given I upload "account_entries.xlsx" file for Account Entries
  Given I filter the AEs
  And I download all the AEs
  Then a new file is generated for the download
  And I get an email with the file attached
  Given I filter and pivot the AEs
  And I download all the pivoted AEs
  Then a new file is generated for the download
  And I get an email with the file attached

  Examples:
      |user     |entity                                 |fund                 |
      |           |entity_type=Investment Fund;enable_funds=true  |name=Test  |
