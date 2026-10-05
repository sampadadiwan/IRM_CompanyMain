Feature: Allocation scratch database cleanup
  The run-id cleanup of the scratch SQLite copy runs when the copy is reused, or when the run is a
  re-run into an existing AllocationRun (rows with that run id are already in the primary DB).
  A fresh run skips it, because on a large fund the unindexed scan starved Sidekiq's watchdog.

  Background:
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

  Scenario: H1 H2 A fresh scratch copy skips the run id cleanup and results are unchanged
    Given SQL statements are being recorded
    And the Allocation Run "start_date=01/04/2023;end_date=30/06/2024" is created for the "Comprehensive Test Fund Aug 2025"
    Then no scratch cleanup by allocation run id was issued
    And the account entries generated match the account entries in "allocate_account_entries_2/generated_account_entries.xlsx"
    And the AllocationRun status is set to "Success"

  Scenario: E1 A reused scratch copy is still cleaned by allocation run id
    Given the scratch database is reused between runs like in development
    And the Allocation Run "start_date=01/04/2023;end_date=30/06/2024" is created for the "Comprehensive Test Fund Aug 2025"
    And SQL statements are being recorded
    And the Allocation Run "start_date=01/04/2023;end_date=30/06/2024" is created for the "Comprehensive Test Fund Aug 2025"
    Then a scratch cleanup by allocation run id was issued
    And the account entries generated match the account entries in "allocate_account_entries_2/generated_account_entries.xlsx"

  Scenario: X1 A failing load script is reported as before
    Given the load script fails
    And the Allocation Run "start_date=01/04/2023;end_date=30/06/2024" is created for the "Comprehensive Test Fund Aug 2025"
    Then the AllocationRun status starts with "Failed to load isolated SQLite DB"

  Scenario Outline: E2 Re-running an existing run after a formula was disabled does not duplicate entries
    Given the Allocation Run "start_date=01/04/2023;end_date=30/06/2024" is created for the "Comprehensive Test Fund Aug 2025"
    And the account entries of "Comprehensive Test Fund Aug 2025" are recorded
    And the <position> formula of "Comprehensive Test Fund Aug 2025" is disabled
    And SQL statements are being recorded
    When the last Allocation Run is re-run
    Then a scratch cleanup by allocation run id was issued
    And the account entries of "Comprehensive Test Fund Aug 2025" are unchanged

    Examples:
      | position |
      | last     |
      | first    |

  Scenario: E3 Re-running an existing run with nothing changed keeps the same entries
    Given the Allocation Run "start_date=01/04/2023;end_date=30/06/2024" is created for the "Comprehensive Test Fund Aug 2025"
    And the account entries of "Comprehensive Test Fund Aug 2025" are recorded
    When the last Allocation Run is re-run
    Then the account entries of "Comprehensive Test Fund Aug 2025" are unchanged
    And the AllocationRun status is set to "Success"

