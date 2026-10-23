@rack_test
Feature: Stale calculated KPI figures are removed and uploaded ones are kept
  When a recomputation shows that a calculated Quarter, YTD or Year no longer qualifies, it is removed. A figure a person
  uploaded or entered is never removed or overwritten. Only one cumulation runs per company at a time.

  Background:
    Given there is a user "" for an entity "entity_type=Investment Fund"
    And the user has role "company_admin"
    And there is an existing portfolio company "name=MyFavStartup;category=Portfolio Company"

  # H8 — Happy path: approving the August figure recalculates the YTD
  Scenario: H8 Approval triggers calculation
    Given the following Monthly KPI Reports exist with KPIs:
      | as_of      | name    | value | period  | source | status     |
      | 2025-06-30 | Revenue | 100   | Quarter | upload | approved   |
      | 2025-07-31 | Revenue | 10    | Month   |        | approved   |
      | 2025-08-31 | Revenue | 20    | Month   |        | unapproved |
    When I run the KpiCumulateJob for the portfolio company
    Then I should NOT see a "YTD" KPI "Revenue" for "2025-08-31"
    When the staged KPI "Revenue" as of "2025-08-31" is approved with cumulation
    Then I should see a "YTD" KPI "Revenue" for "2025-08-31" with value "130.0"

  # E12 — Edge case: un-approving a month removes the Quarter and the YTD that depended on it
  Scenario: E12 A month un-approved removes the calculated Quarter and dependent YTD
    Given the following Monthly KPI Reports exist with KPIs:
      | as_of      | name    | value | period  | source |
      | 2025-06-30 | Revenue | 100   | Quarter | upload |
      | 2025-07-31 | Revenue | 10    | Month   |        |
      | 2025-08-31 | Revenue | 20    | Month   |        |
      | 2025-09-30 | Revenue | 30    | Month   |        |
    When I run the KpiCumulateJob for the portfolio company
    Then I should see a "Quarter" KPI "Revenue" for "2025-09-30" with value "60.0"
    And I should see a "YTD" KPI "Revenue" for "2025-09-30" with value "160.0"
    When the "Month" KPI "Revenue" for "2025-08-31" tagged "Actual" is unapproved
    And I run the KpiCumulateJob for the portfolio company
    Then I should NOT see a "Quarter" KPI "Revenue" for "2025-09-30"
    And I should NOT see a "YTD" KPI "Revenue" for "2025-09-30"
    And I should NOT see a "YTD" KPI "Revenue" for "2025-08-31"
    And I should see a "YTD" KPI "Revenue" for "2025-07-31" with value "110.0"

  # E13 — Edge case: a partial Quarter built earlier from two months is removed
  Scenario: E13 A previously wrong partial quarter is removed
    Given the following Monthly KPI Reports exist with KPIs:
      | as_of      | name    | value | period  | notes                             |
      | 2025-07-31 | Revenue | 10    | Month   |                                   |
      | 2025-08-31 | Revenue | 20    | Month   |                                   |
      | 2025-09-30 | Revenue | 30    | Quarter | Auto-generated Quarter cumulative |
    When I run the KpiCumulateJob for the portfolio company
    Then I should NOT see a "Quarter" KPI "Revenue" for "2025-09-30"

  # E14 — Edge case: an uploaded Quarter where the rules would calculate none is kept
  Scenario: E14 An uploaded figure survives a recompute
    Given the following Monthly KPI Reports exist with KPIs:
      | as_of      | name    | value | period  | source |
      | 2025-07-31 | Revenue | 10    | Month   |        |
      | 2025-08-31 | Revenue | 20    | Month   |        |
      | 2025-09-30 | Revenue | 99    | Quarter | upload |
    When I run the KpiCumulateJob for the portfolio company
    Then I should see a "Quarter" KPI "Revenue" for "2025-09-30" with value "99.0"

  # E30 — Edge case: an uploaded figure approved over a calculated one stays uploaded through later recomputes
  Scenario: E30 An uploaded figure replaces a calculated one
    Given the following Monthly KPI Reports exist with KPIs:
      | as_of      | name    | value |
      | 2025-07-31 | Revenue | 10    |
      | 2025-08-31 | Revenue | 20    |
      | 2025-09-30 | Revenue | 30    |
    When I run the KpiCumulateJob for the portfolio company
    Then I should see a "Quarter" KPI "Revenue" for "2025-09-30" with value "60.0"
    And the "Quarter" KPI "Revenue" for "2025-09-30" should have source "auto_cumulation"
    Given a staged uploaded "Quarter" KPI "Revenue" of 77 as of "2025-09-30" exists
    When the staged KPI "Revenue" as of "2025-09-30" is approved with cumulation
    And I run the KpiCumulateJob for the portfolio company
    Then I should see a "Quarter" KPI "Revenue" for "2025-09-30" with value "77.0"
    And the "Quarter" KPI "Revenue" for "2025-09-30" should have source "upload"
    And the "Quarter" KPI "Revenue" for "2025-09-30" should have 1 record

  # E34 — Edge case: a run that finds the company busy changes nothing and runs later on the data as it then stands
  Scenario: E34 A busy company queues the run again
    Given the following Monthly KPI Reports exist with KPIs:
      | as_of      | name    | value |
      | 2025-07-31 | Revenue | 10    |
      | 2025-08-31 | Revenue | 20    |
      | 2025-09-30 | Revenue | 30    |
    And another cumulation run holds the company's lock
    When I run the KpiCumulateJob for the portfolio company
    Then I should NOT see a "Quarter" KPI "Revenue" for "2025-09-30"
    And the cumulation should be queued again as attempt 1
    When the company's lock is free and the queued cumulation runs
    Then I should see a "Quarter" KPI "Revenue" for "2025-09-30" with value "60.0"

  # E37 — Edge case: removing the Budget figure an Actual figure was judged against refreshes the Actual status
  Scenario: E37 A status judged against a removed figure refreshes
    Given an Investor KPI Mapping for "Revenue" exists with RAG comparator "Budget", direction "higher_is_better", red threshold 0.95, green threshold 1.00
    And the following Monthly KPI Reports exist with KPIs:
      | as_of      | name    | value | tag_list |
      | 2025-04-30 | Revenue | 10    | Actual   |
      | 2025-05-31 | Revenue | 10    | Actual   |
      | 2025-06-30 | Revenue | 10    | Actual   |
      | 2025-04-30 | Revenue | 10    | Budget   |
      | 2025-05-31 | Revenue | 10    | Budget   |
      | 2025-06-30 | Revenue | 10    | Budget   |
    When I run the KpiCumulateJob for the portfolio company
    Then the "YTD" KPI "Revenue" for "2025-06-30" tagged "Actual" should have RAG status "green"
    When the "Month" KPI "Revenue" for "2025-06-30" tagged "Budget" is unapproved
    And I run the KpiCumulateJob for the portfolio company
    Then there should be no "YTD" KPI "Revenue" for "2025-06-30" tagged "Budget"
    And the "YTD" KPI "Revenue" for "2025-06-30" tagged "Actual" should have no RAG status

  # X1 — Error case: a calculated row that fails to save is reported by period, other KPIs are still written
  Scenario: X1 A calculated row that fails to save is reported and the other KPIs are still written
    Given the following Monthly KPI Reports exist with KPIs:
      | as_of      | name    | value |
      | 2025-07-31 | Revenue | 10    |
      | 2025-08-31 | Revenue | 20    |
      | 2025-09-30 | Revenue | 30    |
      | 2025-07-31 | Cost    | 1     |
      | 2025-08-31 | Cost    | 2     |
      | 2025-09-30 | Cost    | 3     |
    And saving the calculated "Revenue" figures will fail
    When I run the KpiCumulateJob for the portfolio company
    Then a KPI cumulation error email should be sent
    And the KPI cumulation error email should mention "Could not save Quarter cumulative for &#39;Revenue&#39; as of 2025-09-30" once
    And I should NOT see a "Quarter" KPI "Revenue" for "2025-09-30"
    And I should see a "Quarter" KPI "Cost" for "2025-09-30" with value "6.0"
