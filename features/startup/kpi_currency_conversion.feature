@rack_test
Feature: KPI Currency Conversion
  Converts KPI values from a portfolio company's reporting currency to the fund's
  base currency during upload, using configurable FX methods per KPI mapping.

  Background:
    Given there is a user "" for an entity "entity_type=Investment Fund"
    Given the user has role "company_admin"
    And there is an existing portfolio company "name=FxStartup;category=Portfolio Company"

  # --- Phase 1: Core Conversion Pipeline ---

  Scenario: Spot rate (report_date) converts using rate on the report's as_of date
    Given the portfolio company has kpi_currency "USD"
    And the following exchange rates exist:
      | from | to  | rate | as_of      |
      | USD  | INR | 84.0 | 2024-01-31 |
      | USD  | INR | 85.0 | 2024-03-31 |
    And the following KPI mappings exist for currency conversion:
      | name            | category        | fx_conversion_method |
      | Working Capital | Balance Sheet   | report_date          |
    And the following Monthly KPI Reports exist with KPIs for currency conversion:
      | as_of      | name            | value |
      | 2024-01-31 | Working Capital | 1000  |
      | 2024-03-31 | Working Capital | 2000  |
    Then the KPI "Working Capital" for "2024-01-31" should have value "84000.0"
    And the KPI "Working Capital" for "2024-01-31" should have original_value "1000.0"
    And the KPI "Working Capital" for "2024-01-31" should have fx_rate_used "84.0"
    And the KPI "Working Capital" for "2024-03-31" should have value "170000.0"
    And the KPI "Working Capital" for "2024-03-31" should have fx_rate_used "85.0"

  Scenario: Average rate converts using mean of opening and closing rates
    Given the portfolio company has kpi_currency "USD"
    And the following exchange rates exist:
      | from | to  | rate | as_of      |
      | USD  | INR | 84.0 | 2024-01-01 |
      | USD  | INR | 86.0 | 2024-01-31 |
    And the following KPI mappings exist for currency conversion:
      | name    | category         | fx_conversion_method |
      | Revenue | Income Statement | average_rate         |
    And the following Monthly KPI Reports exist with KPIs for currency conversion:
      | as_of      | name    | value |
      | 2024-01-31 | Revenue | 1000  |
    Then the KPI "Revenue" for "2024-01-31" should have value "85000.0"
    And the KPI "Revenue" for "2024-01-31" should have original_value "1000.0"
    And the KPI "Revenue" for "2024-01-31" should have fx_rate_used "85.0"

  Scenario: Not applicable skips conversion entirely
    Given the portfolio company has kpi_currency "USD"
    And the following exchange rates exist:
      | from | to  | rate | as_of      |
      | USD  | INR | 84.0 | 2024-01-31 |
    And the following KPI mappings exist for currency conversion:
      | name      | category           | fx_conversion_method |
      | Headcount | Operating Metrics  | not_applicable       |
    And the following Monthly KPI Reports exist with KPIs for currency conversion:
      | as_of      | name      | value |
      | 2024-01-31 | Headcount | 150   |
    Then the KPI "Headcount" for "2024-01-31" should have value "150.0"
    And the KPI "Headcount" for "2024-01-31" should have no original_value

  Scenario: Same currency portco skips conversion
    # kpi_currency not set — defaults to entity currency, no conversion
    And the following KPI mappings exist for currency conversion:
      | name    | category         | fx_conversion_method |
      | Revenue | Income Statement | average_rate         |
    And the following Monthly KPI Reports exist with KPIs for currency conversion:
      | as_of      | name    | value |
      | 2024-01-31 | Revenue | 5000  |
    Then the KPI "Revenue" for "2024-01-31" should have value "5000.0"
    And the KPI "Revenue" for "2024-01-31" should have no original_value

  Scenario: Missing exchange rate stores value unconverted
    Given the portfolio company has kpi_currency "EUR"
    # No exchange rates exist for EUR→INR — common.rb only creates USD rates
    And the following KPI mappings exist for currency conversion:
      | name    | category         | fx_conversion_method |
      | Revenue | Income Statement | average_rate         |
    And the following Monthly KPI Reports exist with KPIs for currency conversion:
      | as_of      | name    | value |
      | 2024-06-30 | Revenue | 1000  |
    Then the KPI "Revenue" for "2024-06-30" should have value "1000.0"
    And the KPI "Revenue" for "2024-06-30" should have no original_value

  # --- Phase 2: Recompute ---

  Scenario: Recompute updates converted KPIs when exchange rate changes
    Given the portfolio company has kpi_currency "USD"
    And the following exchange rates exist:
      | from | to  | rate | as_of      |
      | USD  | INR | 80.0 | 2024-01-31 |
    And the following KPI mappings exist for currency conversion:
      | name            | category      | fx_conversion_method |
      | Working Capital | Balance Sheet | report_date          |
    And the following Monthly KPI Reports exist with KPIs for currency conversion:
      | as_of      | name            | value |
      | 2024-01-31 | Working Capital | 1000  |
    Then the KPI "Working Capital" for "2024-01-31" should have value "80000.0"
    # Now the FM corrects the exchange rate
    When the exchange rate for "USD" to "INR" on "2024-01-31" is updated to "85.0"
    And I run the KPI currency recompute job
    Then the KPI "Working Capital" for "2024-01-31" should have value "85000.0"
    And the KPI "Working Capital" for "2024-01-31" should have original_value "1000.0"
    And the KPI "Working Capital" for "2024-01-31" should have fx_rate_used "85.0"

  # --- Smart Defaults ---

  Scenario: Smart default sets fx_conversion_method based on category
    Given the following KPI mappings exist for currency conversion:
      | name            | category         | fx_conversion_method |
      | Revenue         | Income Statement |                      |
      | Working Capital | Balance Sheet    |                      |
      | Headcount       | Operating Metrics|                      |
      | Capex           | Cashflow Statement |                    |
    Then the mapping "Revenue" should have fx_conversion_method "average_rate"
    And the mapping "Working Capital" should have fx_conversion_method "report_date"
    And the mapping "Headcount" should have fx_conversion_method "not_applicable"
    And the mapping "Capex" should have fx_conversion_method "average_rate"

  # --- Bulk Import ---

  Scenario: Mapping import accepts FX conversion aliases
    Given the portfolio company has kpi_currency "USD"
    When I import KPI mappings with FX conversion values:
      | standard_kpi_name | reported_kpi_name | category         | fx_conversion |
      | Revenue           | Revenue           | Income Statement | avg           |
      | Cash              | Cash              | Balance Sheet    | spot          |
      | Headcount         | Headcount         | Operating Metrics| na            |
      | EBITDA            | EBITDA            | Income Statement | average_rate  |
    Then the mapping "Revenue" should have fx_conversion_method "average_rate"
    And the mapping "Cash" should have fx_conversion_method "report_date"
    And the mapping "Headcount" should have fx_conversion_method "not_applicable"
    And the mapping "EBITDA" should have fx_conversion_method "average_rate"

  Scenario: Mapping import defaults to not_applicable when FX conversion is blank
    When I import KPI mappings with FX conversion values:
      | standard_kpi_name | reported_kpi_name | category         | fx_conversion |
      | Revenue           | Revenue           | Income Statement |               |
    Then the mapping "Revenue" should have fx_conversion_method "not_applicable"
