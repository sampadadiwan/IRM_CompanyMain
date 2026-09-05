@import @account_entry_report_perf
Feature: Account Entries Period Report stays bounded on large ledgers
  The fund-level and folio-level Account Entries Period Reports read account_entries,
  which is the largest table in the system. The page must therefore hold to a fixed,
  small number of queries against that table no matter how many entries a fund has,
  refuse a date range wide enough to scan the whole ledger, and never 500 on a bad page
  number. See docs/technical/account_entry_report_performance.md.

  These scenarios assert the query budget as well as the numbers, because a correct
  report built from eight scans of the ledger is exactly the regression being prevented.

  Background:
    Given there is a user "first_name=Test" for an entity "name=Urban;entity_type=Investment Fund;currency=INR"
    Given the user has role "company_admin"
    Given there is a fund "name=Report Fund;currency=INR;unit_types=A1" for the entity
    And the report fund has folios "101,102,103"

  Scenario: The report totals match the ledger
    Given the ledger holds "Setup Fee" of "100" for folio "101" on "2024-01-31"
    And the ledger holds "Setup Fee" of "300" for folio "102" on "2024-01-31"
    And the ledger holds "Carry" of "50" for folio "103" on "2024-02-29"
    When I view the fund report from "2024-01-01" to "2024-03-31"
    Then the report should show an entry count of "3"
    And the report should show "3" folios touched
    And the report should show "2" distinct entry names
    And the report total in cents should be "450"

  Scenario: Cumulative checkpoint entries are excluded from the report
    Given the ledger holds "Setup Fee" of "100" for folio "101" on "2024-01-31"
    And the ledger holds a cumulative "Setup Fee" of "999" for folio "101" on "2024-01-31"
    When I view the fund report from "2024-01-01" to "2024-03-31"
    Then the report should show an entry count of "1"
    And the report total in cents should be "100"

  # Regression: the folio KPI was briefly derived by counting rows of a query grouped by
  # (commitment_name, capital_commitment_id), which double-counts a folio whose
  # denormalized commitment_name changed mid-period.
  Scenario: A folio recorded under two names still counts as one folio
    Given the ledger holds "Setup Fee" of "100" for folio "101" on "2024-01-31" recorded as "Acme Capital"
    And the ledger holds "Setup Fee" of "200" for folio "101" on "2024-02-29" recorded as "Acme Capital Partners"
    When I view the fund report from "2024-01-01" to "2024-03-31"
    Then the report should show "1" folios touched
    And the report should show an entry count of "2"

  Scenario: One page load makes a fixed small number of queries against account_entries
    Given the ledger holds "Setup Fee" of "100" for folio "101" on "2024-01-31"
    And the ledger holds "Setup Fee" of "300" for folio "102" on "2024-01-31"
    And the ledger holds "Carry" of "50" for folio "103" on "2024-02-29"
    When I view the fund report from "2024-01-01" to "2024-03-31" counting account entry queries
    Then at most "6" queries should have been made against account entries

  Scenario: Adding more entries does not add more queries
    Given the ledger holds "40" entries spread across the folios in "2024"
    When I view the fund report from "2024-01-01" to "2024-12-31" counting account entry queries
    Then at most "6" queries should have been made against account entries

  Scenario: Paging the detail pivot does not rebuild the whole page
    Given the ledger holds "40" entries spread across the folios in "2024"
    When I request page "1" of the detail pivot as a Turbo Frame, counting account entry queries
    Then at most "3" queries should have been made against account entries
    And the response should contain the detail pivot frame

  Scenario: An over-wide date range is clamped and the user is told
    Given the ledger holds "Setup Fee" of "100" for folio "101" on "2024-01-31"
    When I view the fund report from "2000-01-01" to "2024-03-31"
    Then the report should say the range was shortened
    And the report start date should be no earlier than "2022-03-31"

  Scenario: A date range within the limit is left alone
    Given the ledger holds "Setup Fee" of "100" for folio "101" on "2024-01-31"
    When I view the fund report from "2024-01-01" to "2024-03-31"
    Then the report should not say the range was shortened
    And the report start date should be "2024-01-01"

  Scenario: A page number past the end of the pivot shows the last page instead of failing
    Given the ledger holds "Setup Fee" of "100" for folio "101" on "2024-01-31"
    When I view page "999" of the fund report from "2024-01-01" to "2024-03-31"
    Then the report page should load successfully

  # Regression: trailing_trend used to ignore the folio filter on a fund-level report,
  # so the trend chart showed fund-wide numbers beside folio-filtered KPIs. Two folios
  # are selected rather than one because selecting exactly one folio is the app's signal
  # to switch to that investor's own folio-level report instead.
  Scenario: The trend chart honours the selected folios
    Given the ledger holds "Setup Fee" of "100" for folio "101" on "2024-01-31"
    And the ledger holds "Setup Fee" of "300" for folio "102" on "2024-01-31"
    And the ledger holds "Setup Fee" of "50" for folio "103" on "2024-01-31"
    Then the trend total for the whole fund should be "450"
    And the trend total filtered to folios "101,102" should be "400"
