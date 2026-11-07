# Worked examples H13, E31, E32, X8: openspec/changes/archive/2026-11-07-dashboard-insight-widgets/business-rules.md#4
@rack_test
Feature: Peer KPI Comparison on the Aggregated Portfolio Dashboard
  One KPI's latest value and change, side by side for every company on the page.

  Background:
    Given Im logged in as a user "" for an entity "entity_type=Investment Fund"
    And the user has role "company_admin"
    And the fund entity has KPIs enabled
    And today is "2026-09-30"
    And the insight portfolio companies "Zeta Foods, Orbit Pay, Kite Robotics" exist

  # H13 — Happy path: the KPI's change for each company, biggest first
  Scenario: Peer KPI Comparison compares Revenue
    Given "Zeta Foods" has an "Actual" "Quarter" KPI report dated "2026-06-30" with:
      | name    | value | change |
      | Revenue | 120   | 12.50  |
    And "Orbit Pay" has an "Actual" "Quarter" KPI report dated "2026-06-30" with:
      | name    | value | change |
      | Revenue | 80    | -4.00  |
    And the "Peer KPI Comparison" widget on the "Aggregated Portfolio Dashboard" has settings "{kpi_name: 'Revenue'}"
    When I open the aggregated portfolio dashboard for the insight widgets
    Then the "Peer KPI Comparison" insight widget should list the rows "Zeta Foods, Orbit Pay"
    And the "Peer KPI Comparison" insight widget row "Zeta Foods" should show "12.5 %"
    And the "Peer KPI Comparison" insight widget row "Orbit Pay" should show "-4.0 %"
    And the "Peer KPI Comparison" insight widget row "Orbit Pay" should show "30/06/2026"

  # E31 — Edge case: a KPI reported under another name matches through its mapping's standard name
  Scenario: Peer KPI Comparison matches the standard name
    Given "Zeta Foods" has an "Actual" "Quarter" KPI report dated "2026-06-30" with:
      | name    | value | change |
      | Revenue | 120   | 12.50  |
    And "Orbit Pay" has an "Actual" "Quarter" KPI report dated "2026-06-30" with:
      | name        | value | change | standard |
      | Net Revenue | 80    | -4.00  | Revenue  |
    And the "Peer KPI Comparison" widget on the "Aggregated Portfolio Dashboard" has settings "{kpi_name: 'revenue'}"
    When I open the aggregated portfolio dashboard for the insight widgets
    Then the "Peer KPI Comparison" insight widget should list the rows "Zeta Foods, Orbit Pay"

  # E32 — Edge case: a company without the KPI is left out
  Scenario: Peer KPI Comparison leaves out a company without the KPI
    Given "Zeta Foods" has an "Actual" "Quarter" KPI report dated "2026-06-30" with:
      | name    | value | change |
      | Revenue | 120   | 12.50  |
    And "Orbit Pay" has an "Actual" "Quarter" KPI report dated "2026-06-30" with:
      | name    | value | change |
      | Revenue | 80    | -4.00  |
    And "Kite Robotics" has an "Actual" "Quarter" KPI report dated "2026-06-30" with:
      | name   | value | change |
      | EBITDA | 9     | 3.00   |
    And the "Peer KPI Comparison" widget on the "Aggregated Portfolio Dashboard" has settings "{kpi_name: 'Revenue'}"
    When I open the aggregated portfolio dashboard for the insight widgets
    Then the "Peer KPI Comparison" insight widget should list the rows "Zeta Foods, Orbit Pay"

  # X8 — Error case: no KPI name set gives a prompt to set it
  Scenario: Peer KPI Comparison without a KPI name
    Given the "Peer KPI Comparison" widget on the "Aggregated Portfolio Dashboard" has settings "{kpi_name: ''}"
    When I open the aggregated portfolio dashboard for the insight widgets
    Then the "Peer KPI Comparison" insight widget should show "Set the KPI name in this widget's settings."
