# The intermittent "No unique index found for id" in allocation runs (seen in runs since 2026-10-14).
# Cause: the scratch SQLite databases share one schema cache; once anything asks it about account_entries
# with no scratch database swapped in, it caches "no such table", and every later AccountEntrySqlite.insert_all
# in that process raised. AccountEntrySqlite.insert_all now re-reads that table's schema from the scratch
# database it is writing to.

@import @rack_test
Feature: Allocation runs survive a schema cache read outside a scratch database

  # X1 — Error case: the cache is poisoned first, exactly as an unrelated lookup in the same worker would;
  # the allocation still writes its entries and succeeds
  Scenario: X1 An allocation run succeeds after the scratch schema cache was read outside a scratch database
    Given there is a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund;currency=INR"
    And the user has role "company_admin"
    And there is a fund "name=Comprehensive Test Fund Aug 2025 - Master Fund;currency=USD;unit_types=A,B,C,D,A4" for the entity
    And there is a fund "name=Comprehensive Test Fund Aug 2025;currency=INR;unit_types=A,B,C,D,A4;master_fund_id=1" for the entity
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
    And the allocation engine's schema cache was read outside a scratch database
    And the Allocation Run "start_date=01/04/2023;end_date=30/06/2024," is created for the "Comprehensive Test Fund Aug 2025"
    Then the account entries generated match the account entries in "allocate_account_entries_2/generated_account_entries.xlsx"
    And the AllocationRun status is set to "Success"
