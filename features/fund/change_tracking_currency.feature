@import
Feature: Support changes a fund's tracking currency
  Every tracking amount is stored in the tracking currency while its currency label is read live
  from funds.tracking_currency, so changing the currency means rebuilding every amount at the rate
  for its own date. ChangeTrackingCurrencyJob does that: it checks exchange rates first and changes
  nothing if any is missing, then saves the currency, rebuilds (or, when removing it, zeroes) the
  tracking amounts and their rollups, and regenerates fund ratios. While it runs - or after it has
  failed, until a retry - the fund is marked, the nightly tracking job and allocation runs leave it
  alone, and the fund page shows a banner. See docs/engineering/change_tracking_currency_plan.md.

  Background:
    Given Im logged in as a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund;currency=INR"
    Given the user has role "company_admin"
    And the entity has "enable_tracking_currency" permission
    Given there is a fund "name=Comprehensive Test Fund Aug 2025 - Master Fund;currency=USD;unit_types=A,B,C,D,A4" for the entity
    Given there is a fund "name=Comprehensive Test Fund Aug 2025;currency=INR;unit_types=A,B,C,D,A4;master_fund_id=1;tracking_currency=USD" for the entity
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
    When I run the TrackingCurrencyJob with force for the fund
    And fund ratios have been generated for the fund as of "2024-03-31"

  Scenario: Support changes the tracking currency and every tracking figure is rebuilt in it
    Given the user has role "support"
    And there is an exchange rate from "INR" to "EUR" of "0.0107" as of "2000-01-01"
    When I open Change Tracking Currency from the fund's actions menu
    And I submit a tracking currency change to "EUR" confirming with the fund name
    Then I should see the tracking currency change notice
    And the fund's tracking currency should be "EUR"
    And every tracking amount of the fund should be its fund amount at a rate of "0.0107"
    And the fund's tracking rollups should match the rows they sum
    And the fund ratios should be labelled "(EUR)" and none "(USD)"
    And no tracking currency change should be pending on the fund
    And the tracking currency change should be audited against the user

  @rack_test
  Scenario: A missing exchange rate aborts the change before anything is written
    Given the user has role "support"
    And there is an exchange rate from "INR" to "GBP" of "0.0095" as of "2099-01-01"
    And I know every tracking amount of the fund
    When a tracking currency change to "GBP" is run for the fund
    Then the fund's tracking currency should be "USD"
    And no tracking amount of the fund should have changed
    And no tracking currency change should be pending on the fund

  @rack_test
  Scenario: Removing the tracking currency zeroes every tracking figure
    Given the user has role "support"
    When I visit the change tracking currency page for the fund
    And I submit a tracking currency change to "" confirming with the fund name
    Then I should see the tracking currency change notice
    And the fund's tracking currency should still be blank
    And every tracking amount of the fund should be zero
    And the fund ratios should not be labelled "(USD)"

  @rack_test
  Scenario: A change is refused without the typed confirmation
    Given the user has role "support"
    And there is an exchange rate from "INR" to "EUR" of "0.0107" as of "2000-01-01"
    When I visit the change tracking currency page for the fund
    And I submit a tracking currency change to "EUR" confirming with "Wrong Fund"
    Then I should see "Type the fund name exactly to confirm."
    And the fund's tracking currency should be "USD"
    And no tracking currency change should be pending on the fund

  @rack_test
  Scenario: While a change is pending the nightly job and allocation runs leave the fund alone
    Given the user has role "support"
    And I know every tracking amount of the fund
    And a tracking currency change to "EUR" is pending on the fund
    When I run the TrackingCurrencyJob with force for all funds in the entity
    Then no tracking amount of the fund should have changed
    And an allocation run cannot be created for the fund
    When I visit the fund details page
    Then I should see "Tracking currency change to EUR in progress."

  @rack_test
  Scenario: A change that fails partway can be retried from the fund page
    Given the user has role "support"
    And there is an exchange rate from "INR" to "EUR" of "0.0107" as of "2000-01-01"
    And the tracking amount rebuild will fail once
    When a tracking currency change to "EUR" is run for the fund
    Then the tracking currency change should be marked failed
    When I visit the fund details page
    Then I should see "Tracking currency change to EUR failed."
    When I click "Retry"
    Then I should see "Tracking currency change restarted."
    And every tracking amount of the fund should be its fund amount at a rate of "0.0107"
    And no tracking currency change should be pending on the fund

  @rack_test
  Scenario: A retry that finds a rate missing after the currency was saved stays failed
    Given the user has role "support"
    And there is an exchange rate from "INR" to "EUR" of "0.0107" as of "2000-01-01"
    And the tracking amount rebuild will fail once
    When a tracking currency change to "EUR" is run for the fund
    Then the tracking currency change should be marked failed
    And the fund's tracking currency should be "EUR"
    Given the exchange rates from "INR" to "EUR" are deleted
    When I visit the fund details page
    And I retry the tracking currency change from the fund page
    Then the tracking currency change should be marked failed
    And the fund's tracking currency should be "EUR"
    When I visit the fund details page
    Then I should see "Tracking currency change to EUR failed."

  @rack_test
  Scenario: A change whose job died can be retried once it is stale
    Given the user has role "support"
    And there is an exchange rate from "INR" to "EUR" of "0.0107" as of "2000-01-01"
    And a tracking currency change to "EUR" is pending on the fund
    When I visit the fund details page
    Then I should see "Tracking currency change to EUR in progress."
    And I should not see "did not finish."
    Given the pending tracking currency change started "13" hours ago
    When I visit the fund details page
    Then I should see "Tracking currency change to EUR did not finish."
    When I retry the tracking currency change from the fund page
    And every tracking amount of the fund should be its fund amount at a rate of "0.0107"
    And no tracking currency change should be pending on the fund
