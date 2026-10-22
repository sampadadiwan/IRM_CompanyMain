# bulk-path-query-optimisation, phase 3 — KPI cumulation reads its target reports once per KPI name and
# cumulates each name once per job run (D3).
# Worked examples: openspec/changes/bulk-path-query-optimisation/business-rules.md (H3, E1, E3, E4, E11, X2)

@bulk_query @rack_test
Feature: KPI cumulation reads each KPI name's periods once
  Cumulating Quarter / YTD / Year values used to look up the period's report and its KPI for every
  KPI x period, and to cumulate a KPI name again for every report holding it. Values must not change.

  # Fiscal year starts in April (default): Q1 = Apr-Jun = 10+12+11 = 33, Q2 = Jul-Sep = 13+14+15 = 42,
  # YTD to Sep = 33 + 42 = 75
  Background:
    Given there is a user "" for an entity "entity_type=Investment Fund"
    And the user has role "company_admin"
    And there is an existing portfolio company "name=Acme;category=Portfolio Company"
    And the following Monthly KPI Reports exist with KPIs:
      | as_of      | name    | value |
      | 2026-04-30 | Revenue | 10    |
      | 2026-05-31 | Revenue | 12    |
      | 2026-06-30 | Revenue | 11    |
      | 2026-07-31 | Revenue | 13    |
      | 2026-08-31 | Revenue | 14    |
      | 2026-09-30 | Revenue | 15    |

  # H3 — Happy path: same values, and the target lookups no longer run per KPI x period
  Scenario: H3 Cumulated values are unchanged and periods are read once
    Given I count queries by call site
    When I run the KpiCumulateJob for the portfolio company
    Then I should see a "Quarter" KPI "Revenue" for "2026-06-30" with value "33.0"
    And I should see a "Quarter" KPI "Revenue" for "2026-09-30" with value "42.0"
    And I should see a "YTD" KPI "Revenue" for "2026-09-30" with value "75.0"
    # 200 queries from this method without the job's lookup: one report + one KPI find per KPI x period
    And at most 72 queries came from "KpiCumulative#process_cumulative_kpi"

  # E1 — Edge case: a Quarter report created mid-job is found again by the job's later steps, not duplicated
  Scenario: E1 Each missing period report is created once
    When I run the KpiCumulateJob for the portfolio company
    Then there should be 1 "Quarter" KPI report for "2026-06-30"
    And there should be 1 "YTD" KPI report for "2026-09-30"
    And the "Quarter" KPI "Revenue" for "2026-09-30" should have 1 record

  # E3 — Edge case: the six monthly reports all hold Revenue; it is cumulated once, not six times
  Scenario: E3 A KPI name held by several reports is cumulated once
    Given I count queries by call site
    When I run the KpiCumulateJob for the portfolio company
    # One lookup per autofill: 1 with the repeat skip, 16 without (once per report holding Revenue)
    Then at most 1 query came from "KpiCumulative#build_cumulation_lookup"
    And I should see a "YTD" KPI "Revenue" for "2026-09-30" with value "75.0"

  # E4 — Edge case: reports with a blank tag keep the original (tag-less) lookups and give the same values
  Scenario: E4 A blank report tag still cumulates
    Given there is a user "" for an entity "entity_type=Investment Fund"
    And there is an existing portfolio company "name=Blank Tag Co;category=Portfolio Company"
    And the following Monthly KPI Reports exist with KPIs:
      | as_of      | name   | value | tag_list |
      | 2026-04-30 | Orders | 5     |          |
      | 2026-05-31 | Orders | 6     |          |
      | 2026-06-30 | Orders | 7     |          |
    When I run the KpiCumulateJob for the portfolio company
    Then I should see a "Quarter" KPI "Orders" for "2026-06-30" with value "18.0"

  # E11 — Edge case: data changed between two runs is read fresh by the second run (nothing outlives a job)
  # April 10 -> 20, so Q1 = 20+12+11 = 43 and YTD to Sep = 43 + 42 = 85
  Scenario: E11 The second run uses a KPI edited after the first
    When I run the KpiCumulateJob for the portfolio company
    And the monthly "Revenue" KPI for "2026-04-30" is changed to 20
    And I run the KpiCumulateJob for the portfolio company
    Then I should see a "Quarter" KPI "Revenue" for "2026-06-30" with value "43.0"
    And I should see a "YTD" KPI "Revenue" for "2026-09-30" with value "85.0"

  # X2 — Error case: a cumulative that fails to save is reported, once per period (not once per report)
  Scenario: X2 A failed cumulative save is reported once
    Given cumulative KPI saves will fail
    When I run the KpiCumulateJob for the portfolio company
    Then a KPI cumulation error email should be sent
    And the KPI cumulation error email should mention "Could not save Quarter cumulative for &#39;Revenue&#39; as of 2026-06-30" once

  # X4 — Error case (found in review): saving Q1 runs the RAG cascade, which re-judges the STORED Q2 (42)
  # against the new Q1 (63) and marks it red; Q2 is then saved at 79, green against 63. A Q2 held in memory
  # from before the cascade could skip writing that green. This guards the outcome. It also passes on the
  # earlier code: saving YTD-Sep (same date as Q2) cascades to Q2 again and heals it - so the guard is the
  # outcome, not the window. KPIs are no longer held across the run (build_cumulation_lookup).
  # April 10 -> 40 makes Q1 = 40+12+11 = 63; July 13 -> 50 makes Q2 = 50+14+15 = 79
  Scenario: X4 A RAG status re-judged mid-run by the cascade still ends up right
    Given an Investor KPI Mapping for "Revenue" exists with RAG comparator "PriorPeriod", direction "higher_is_better", red threshold 0.95, green threshold 1.00
    When I run the KpiCumulateJob for the portfolio company
    Then the "Quarter" KPI "Revenue" for "2026-09-30" should have RAG status "green"
    When the monthly "Revenue" KPI for "2026-04-30" is changed to 40
    And the monthly "Revenue" KPI for "2026-07-31" is changed to 50
    And I run the KpiCumulateJob for the portfolio company
    Then I should see a "Quarter" KPI "Revenue" for "2026-09-30" with value "79.0"
    And the "Quarter" KPI "Revenue" for "2026-09-30" should have RAG status "green"
