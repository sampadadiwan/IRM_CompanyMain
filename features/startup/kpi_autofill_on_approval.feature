# frozen_string_literal: true
# Feature: KPI autofill recomputation triggered by approval

@kpi_autofill_on_approval @rack_test
Feature: KPI autofill on approval
  As a fund manager
  I want cumulative KPI values (Quarter, YTD, Year) to auto-populate when I approve KPIs
  So that I don't have to manually click Recompute Cumulative

  Background:
    Given there is a user "first_name=FundAdmin" for an entity "name=TestFund;entity_type=Investment Fund"
    And a portfolio company "TestCo" exists under the current entity
    And investor KPI mappings exist for "TestCo" with autofill types:
      | standard_kpi_name   | autofill     |
      | Revenue             | cumulate     |
      | Assets              | forward_fill |
      | Gross Profit Margin | compute      |

  @kpi_autofill_approve_all
  Scenario: Approve all quarterly KPIs triggers cumulation with scoped report IDs
    Given "TestCo" has pending quarterly KPIs:
      | name    | period  | as_of      | value     |
      | Revenue | Quarter | 2025-06-30 | 770000000 |
      | Revenue | Quarter | 2025-09-30 | 825000000 |
      | Revenue | Quarter | 2025-12-31 | 890000000 |
      | Revenue | Quarter | 2026-03-31 | 960000000 |
    When I approve all pending KPIs for "TestCo"
    Then a KpiCumulateJob should be enqueued with a scalar portfolio_company_id
    And the enqueued job should have force true and compute_percentage_change true
    And the enqueued job should have exactly 4 report IDs
    And after the job runs, YTD KPIs should exist for "Revenue"

  @kpi_autofill_approve_single
  Scenario: Approve single KPI triggers scoped cumulation with 1 report ID
    Given "TestCo" has pending quarterly KPIs:
      | name    | period  | as_of      | value     |
      | Revenue | Quarter | 2025-06-30 | 770000000 |
    When I approve the "Revenue" KPI for "2025-06-30" on "TestCo"
    Then a KpiCumulateJob should be enqueued with a scalar portfolio_company_id
    And the enqueued job should have force true and compute_percentage_change true
    And the enqueued job should have exactly 1 report ID

  @kpi_autofill_mapping_backfill
  Scenario: Mapping backfill assigns mapping to cumulated KPIs with nil mapping
    Given "TestCo" has an approved cumulated KPI with nil investor_kpi_mapping_id
    When KpiCumulateJob runs for "TestCo" with force
    Then the cumulated KPI should have an investor_kpi_mapping_id assigned

  @kpi_autofill_forward_fill_quarterly
  Scenario: Forward fill derives YTD from quarterly data when no monthly data exists
    Given "TestCo" has approved quarterly KPIs with forward_fill mapping:
      | name   | period  | as_of      | value      |
      | Assets | Quarter | 2025-06-30 | 1845000000 |
      | Assets | Quarter | 2025-09-30 | 1970000000 |
    And "TestCo" has no monthly KPI reports
    When KpiCumulateJob runs for "TestCo" with force
    Then YTD KPIs should exist for "Assets" on "TestCo"
