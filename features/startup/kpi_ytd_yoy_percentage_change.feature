@rack_test
Feature: A YTD figure's percentage change is measured against the same YTD a year earlier
  A YTD figure is a running total, so against the previous month's YTD it would show only that month's contribution. It is
  compared with the YTD one year earlier instead. Month, Quarter and Year figures are still compared with their previous
  figure. When there is nothing a year earlier the change is empty, never measured against an older figure.

  Background:
    Given Im logged in as a user "" for an entity "entity_type=Investment Fund"
    And the user has role "company_admin"
    And there is an existing portfolio company "name=MyFavStartup;category=Portfolio Company"
    And the portfolio company's financial year starts in January

  # H9 — Happy path: June 2026 YTD against June 2025 YTD, not against the March 2026 YTD before it
  Scenario: H9 YTD compared with a year earlier
    Given the following Monthly KPI Reports exist with KPIs:
      | as_of      | name    | value   | period |
      | 2025-06-30 | Revenue | 7000000 | YTD    |
      | 2026-03-31 | Revenue | 8000000 | YTD    |
      | 2026-06-30 | Revenue | 8588636 | YTD    |
    When the KPI percentage change job runs
    Then the "YTD" KPI "Revenue" for "2026-06-30" should have a percentage change of 22.69
    And the "YTD" KPI "Revenue" for "2025-06-30" should have an empty percentage change
    And the "YTD" KPI "Revenue" for "2026-03-31" should have an empty percentage change

  # E15 — Edge case: no YTD a year earlier, so the change is empty and not measured against the previous month
  Scenario: E15 No YTD a year earlier
    Given the following Monthly KPI Reports exist with KPIs:
      | as_of      | name    | value | period |
      | 2025-06-30 | Revenue | 100   | YTD    |
      | 2026-06-30 | Revenue | 150   | YTD    |
      | 2026-07-31 | Revenue | 170   | YTD    |
    When the KPI percentage change job runs
    Then the "YTD" KPI "Revenue" for "2026-06-30" should have a percentage change of 50.0
    And the "YTD" KPI "Revenue" for "2026-07-31" should have an empty percentage change

  # E16 — Edge case: the year-earlier figure is removed by the cleanup, so the change becomes empty
  Scenario: E16 Year-earlier figure removed
    Given the following Monthly KPI Reports exist with KPIs:
      | as_of      | name    | value | period |
      | 2025-01-31 | Revenue | 10    | Month  |
      | 2025-02-28 | Revenue | 10    | Month  |
      | 2025-03-31 | Revenue | 10    | Month  |
      | 2025-04-30 | Revenue | 10    | Month  |
      | 2025-05-31 | Revenue | 10    | Month  |
      | 2025-06-30 | Revenue | 10    | Month  |
      | 2025-07-31 | Revenue | 10    | Month  |
      | 2026-01-31 | Revenue | 20    | Month  |
      | 2026-02-28 | Revenue | 20    | Month  |
      | 2026-03-31 | Revenue | 20    | Month  |
      | 2026-04-30 | Revenue | 20    | Month  |
      | 2026-05-31 | Revenue | 20    | Month  |
      | 2026-06-30 | Revenue | 20    | Month  |
      | 2026-07-31 | Revenue | 20    | Month  |
    When I run the KpiCumulateJob with percentage change computation
    Then the "YTD" KPI "Revenue" for "2026-07-31" should have a percentage change of 100.0
    When the "Month" KPI "Revenue" for "2025-04-30" tagged "Actual" is unapproved
    And I run the KpiCumulateJob with percentage change computation
    Then I should NOT see a "YTD" KPI "Revenue" for "2025-07-31"
    And the "YTD" KPI "Revenue" for "2026-07-31" should have an empty percentage change
    And the "YTD" KPI "Revenue" for "2026-03-31" should have a percentage change of 100.0

  # E17 — Edge case: the year-earlier YTD is zero, so there is nothing to divide by
  Scenario: E17 Year-earlier YTD zero
    Given the following Monthly KPI Reports exist with KPIs:
      | as_of      | name    | value | period |
      | 2025-06-30 | Revenue | 0     | YTD    |
      | 2026-06-30 | Revenue | 150   | YTD    |
    When the KPI percentage change job runs
    Then the "YTD" KPI "Revenue" for "2026-06-30" should have an empty percentage change

  # E18 — Edge case: the year-earlier month end differs (29 Feb 2024 and 28 Feb 2025), both directions
  Scenario: E18 Leap-day month end
    Given the following Monthly KPI Reports exist with KPIs:
      | as_of      | name    | value | period |
      | 2023-02-28 | Revenue | 50    | YTD    |
      | 2023-08-31 | Revenue | 80    | YTD    |
      | 2024-02-29 | Revenue | 100   | YTD    |
      | 2024-08-31 | Revenue | 110   | YTD    |
      | 2025-02-28 | Revenue | 120   | YTD    |
    When the KPI percentage change job runs
    Then the "YTD" KPI "Revenue" for "2025-02-28" should have a percentage change of 20.0
    And the "YTD" KPI "Revenue" for "2024-02-29" should have a percentage change of 100.0

  # E19 — Edge case: Actual and Budget are compared separately, each against its own tag a year earlier
  Scenario: E19 Tags separate
    Given the following Monthly KPI Reports exist with KPIs:
      | as_of      | name    | value | period | tag_list |
      | 2025-06-30 | Revenue | 100   | YTD    | Actual   |
      | 2025-12-31 | Revenue | 130   | YTD    | Actual   |
      | 2026-06-30 | Revenue | 120   | YTD    | Actual   |
      | 2025-06-30 | Revenue | 200   | YTD    | Budget   |
      | 2025-12-31 | Revenue | 230   | YTD    | Budget   |
      | 2026-06-30 | Revenue | 210   | YTD    | Budget   |
    When the KPI percentage change job runs
    Then the "Actual" "YTD" KPI "Revenue" for "2026-06-30" should have a percentage change of 20.0
    And the "Budget" "YTD" KPI "Revenue" for "2026-06-30" should have a percentage change of 5.0

  # E20 — Edge case: Month, Quarter and Year keep comparing with the previous figure
  Scenario: E20 Other periods unchanged
    Given the following Monthly KPI Reports exist with KPIs:
      | as_of      | name    | value | period  |
      | 2026-01-31 | Revenue | 100   | Month   |
      | 2026-02-28 | Revenue | 110   | Month   |
      | 2025-03-31 | Revenue | 300   | Quarter |
      | 2025-06-30 | Revenue | 330   | Quarter |
      | 2024-12-31 | Revenue | 1000  | Year    |
      | 2025-12-31 | Revenue | 1200  | Year    |
    When the KPI percentage change job runs
    Then the "Month" KPI "Revenue" for "2026-02-28" should have a percentage change of 10.0
    And the "Quarter" KPI "Revenue" for "2025-06-30" should have a percentage change of 10.0
    And the "Year" KPI "Revenue" for "2025-12-31" should have a percentage change of 20.0

  # E26 — Edge case: a change stored the old way (against the previous month) is corrected by the recompute
  Scenario: E26 Recompute corrects old values
    Given the following Monthly KPI Reports exist with KPIs:
      | as_of      | name    | value | period |
      | 2025-06-30 | Revenue | 100   | YTD    |
      | 2025-12-31 | Revenue | 120   | YTD    |
      | 2026-06-30 | Revenue | 150   | YTD    |
    And the "YTD" KPI "Revenue" for "2026-06-30" has a stored percentage change of 7.0
    When the KPI percentage change job runs
    Then the "YTD" KPI "Revenue" for "2026-06-30" should have a percentage change of 50.0

  # E27 — Edge case: a change the column cannot hold is stored empty and the rest of the series is still updated.
  # The last example rounds to 10,000.00, which must not slip through a check made before rounding.
  Scenario Outline: E27 YTD change too large to store
    Given the following Monthly KPI Reports exist with KPIs:
      | as_of      | name    | value     | period |
      | 2025-06-30 | Revenue | <earlier> | YTD    |
      | 2026-06-30 | Revenue | <later>   | YTD    |
      | 2025-07-31 | Revenue | 100       | YTD    |
      | 2026-07-31 | Revenue | 150       | YTD    |
    When the KPI percentage change job runs
    Then the "YTD" KPI "Revenue" for "2026-06-30" should have the stored percentage change "<stored>"
    And the "YTD" KPI "Revenue" for "2026-07-31" should have a percentage change of 50.0

    Examples:
      | earlier  | later      | stored  |
      | 1        | 1000000    | empty   |
      | 20000000 | 2019999000 | empty   |
      | 1000000  | 100999900  | 9999.99 |

  # E31 — Edge case: an empty change on a KPI with thresholds shows "-" with no colour and no error
  Scenario: E31 Empty change with thresholds set
    Given the following Monthly KPI Reports exist with KPIs:
      | as_of      | name    | value | period |
      | 2026-06-30 | Revenue | 150   | YTD    |
    And the "Revenue" KPI mapping has a lower threshold of 5
    When the KPI percentage change job runs
    And when I view the KPI report for the portfolio company in grid view as owner
    Then the "YTD" KPI "Revenue" for "2026-06-30" should show "-" with no colour in the grid
    And the KPI page of the "YTD" KPI "Revenue" for "2026-06-30" should show "-" as its percentage change
    And the KPI list should show "-" as the percentage change of the "YTD" KPI "Revenue" for "2026-06-30"

  # E32 — Edge case: the Recompute Auto-Fill action also recomputes the changes of the YTD figures it creates
  Scenario: E32 Recompute Auto-Fill recomputes changes
    Given the following Monthly KPI Reports exist with KPIs:
      | as_of      | name    | value | period |
      | 2025-01-31 | Revenue | 10    | Month  |
      | 2025-02-28 | Revenue | 10    | Month  |
      | 2026-01-31 | Revenue | 20    | Month  |
      | 2026-02-28 | Revenue | 20    | Month  |
    When I recompute the auto-fill for the portfolio company from the KPI grid
    Then I should see a "YTD" KPI "Revenue" for "2026-02-28" with value "40.0"
    And the "YTD" KPI "Revenue" for "2026-02-28" should have a percentage change of 100.0

  # E33 — Edge case: two owners' figures for the same KPI, tag and dates are compared separately, even when handed over
  # as one list. Normally one report holds one figure per KPI name, so this scenario skips that save check to set it up.
  Scenario: E33 Owners separate
    Given the following Monthly KPI Reports exist with KPIs:
      | as_of      | name    | value | period |
      | 2025-06-30 | Revenue | 100   | YTD    |
      | 2026-06-30 | Revenue | 150   | YTD    |
    And the following YTD KPIs of another owner exist:
      | as_of      | name    | value |
      | 2025-06-30 | Revenue | 200   |
      | 2026-06-30 | Revenue | 210   |
    And saving a KPI skips the check that its name is unique in the report
    When the percentage change is computed for all the approved KPIs in one list
    Then the "YTD" KPI "Revenue" for "2026-06-30" should have a percentage change of 50.0
    And the "YTD" KPI "Revenue" for "2026-06-30" owned by the other owner should have a percentage change of 5.0
