@rack_test
Feature: The report's difference from Budget and the fair market value change follow the direction of the movement
  The difference of an Actual from its Budget is a percentage of the size of the Budget, so a loss smaller than budgeted is
  above it, for a percentage KPI as for any other. The ratio "Actual as a percentage of Budget" is unchanged. The
  fair market value change is divided by the size of the value at the start.
  Worked examples: openspec/changes/portfolio-report-quarter-activity-and-change-sign/design.md#worked-examples

  Background:
    Given there is a user "" for an entity "entity_type=Investment Fund"
    And the user has role "company_admin"
    And there is an existing portfolio company "name=MyFavStartup;category=Portfolio Company"

  # H15 — Happy path: a loss of 80 against a budgeted loss of 100 is 20% better
  Scenario: H15 Loss smaller than budgeted
    Given the following Monthly KPI Reports exist with KPIs:
      | as_of      | name   | value | period | tag_list |
      | 2026-06-30 | EBITDA | -80   | YTD    | Actual   |
      | 2026-06-30 | EBITDA | -100  | YTD    | Budget   |
    And the "EBITDA" KPI mapping is shown in the portfolio report
    When the portfolio report rows are built up to "2026-06-30"
    Then the report row "EBITDA" should have "ytd_06_26_actual_vs_budget_compute_percent" equal to "20"

  # H16 — Happy path: a loss of 125 against a budgeted loss of 100 is 25% worse
  Scenario: H16 Loss larger than budgeted
    Given the following Monthly KPI Reports exist with KPIs:
      | as_of      | name   | value | period | tag_list |
      | 2026-06-30 | EBITDA | -125  | YTD    | Actual   |
      | 2026-06-30 | EBITDA | -100  | YTD    | Budget   |
    And the "EBITDA" KPI mapping is shown in the portfolio report
    When the portfolio report rows are built up to "2026-06-30"
    Then the report row "EBITDA" should have "ytd_06_26_actual_vs_budget_compute_percent" equal to "-25"

  # H17 — Happy path: a value of -100 at the start and -60 at the end is a change of 40
  Scenario: H17 Fair market value change, negative base
    When the fair market value change is worked out from -100.0 to -60.0
    Then the fair market value change is 40.0

  # H18 — Happy path: a percentage KPI of 15% against a budget of 20% is 25% below
  Scenario: H18 Percentage KPI against budget
    Given the following Monthly KPI Reports exist with KPIs:
      | as_of      | name     | value | period | tag_list |
      | 2026-06-30 | EBITDA % | 0.15  | YTD    | Actual   |
      | 2026-06-30 | EBITDA % | 0.20  | YTD    | Budget   |
    And the "EBITDA %" KPI mapping is shown in the portfolio report
    And the "EBITDA %" KPI mapping has data type "percentage"
    When the portfolio report rows are built up to "2026-06-30"
    Then the report row "EBITDA %" should have "ytd_06_26_actual_vs_budget_compute_percent" equal to "-25"

  # E17 — Edge case: the ratio of -80 to -100 is 80% and is not changed
  Scenario: E17 Ratio unchanged
    Given the following Monthly KPI Reports exist with KPIs:
      | as_of      | name   | value | period | tag_list |
      | 2026-06-30 | EBITDA | -80   | YTD    | Actual   |
      | 2026-06-30 | EBITDA | -100  | YTD    | Budget   |
    And the "EBITDA" KPI mapping is shown in the portfolio report
    When the portfolio report rows are built up to "2026-06-30"
    Then the report row "EBITDA" should have "ytd_06_26_actual_vs_budget_percent" equal to "80"

  # E18 — Edge case: 92 against a positive budget of 100 is -8, as before
  Scenario: E18 Positive budget
    Given the following Monthly KPI Reports exist with KPIs:
      | as_of      | name    | value | period | tag_list |
      | 2026-06-30 | Revenue | 92    | YTD    | Actual   |
      | 2026-06-30 | Revenue | 100   | YTD    | Budget   |
    And the "Revenue" KPI mapping is shown in the portfolio report
    When the portfolio report rows are built up to "2026-06-30"
    Then the report row "Revenue" should have "ytd_06_26_actual_vs_budget_compute_percent" equal to "-8"

  # E19 — Edge case: a budget of zero has nothing to divide by for a money or numeric KPI
  Scenario: E19 Comparator zero
    Given the following Monthly KPI Reports exist with KPIs:
      | as_of      | name   | value | period | tag_list |
      | 2026-06-30 | EBITDA | -80   | YTD    | Actual   |
      | 2026-06-30 | EBITDA | 0     | YTD    | Budget   |
    And the "EBITDA" KPI mapping is shown in the portfolio report
    When the portfolio report rows are built up to "2026-06-30"
    Then the report row "EBITDA" should have "ytd_06_26_actual_vs_budget_compute_percent" equal to "N/A"

  # E20 — Edge case: a value of 100 at the start and 120 at the end is a change of 20, as before
  Scenario: E20 Fair market value change, positive base
    When the fair market value change is worked out from 100.0 to 120.0
    Then the fair market value change is 20.0

  # E21 — Edge case: nothing at the start, nothing to compare with
  Scenario: E21 Fair market value change, base zero
    When the fair market value change is worked out from 0.0 to 50.0
    Then the fair market value change is "N/A"
