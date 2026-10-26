@rack_test
Feature: The portfolio report shows how far each Actual KPI is from its Budget
  For every Actual column the report offers <label>_vs_budget_compute_percent: (Actual - Budget) / Budget times 100
  (-8 means 8% below Budget). The existing <label>_vs_budget_percent (Actual / Budget times 100) is unchanged.
  Worked examples: openspec/changes/portfolio-report-fund-metrics/design.md#worked-examples

  Background:
    Given there is a user "" for an entity "entity_type=Investment Fund"
    And the user has role "company_admin"
    And there is an existing portfolio company "name=MyFavStartup;category=Portfolio Company"

  # H16 — Happy path: YTD Actual 92 against Budget 100 is 8% below; the percent-of field still says 92
  Scenario: Actual below Budget
    Given the following Monthly KPI Reports exist with KPIs:
      | as_of      | name    | value | period | tag_list |
      | 2026-06-30 | Revenue | 92    | YTD    | Actual   |
      | 2026-06-30 | Revenue | 100   | YTD    | Budget   |
    And the "Revenue" KPI mapping is shown in the portfolio report
    When the portfolio report rows are built up to "2026-06-30"
    Then the report row "Revenue" should have "ytd_06_26_actual_vs_budget_compute_percent" equal to "-8"
    And the report row "Revenue" should have "ytd_06_26_actual_vs_budget_percent" equal to "92"

  # H17 — Happy path: Quarter Actual 75 against Budget 60 is 25% above
  Scenario: Actual above Budget
    Given the following Monthly KPI Reports exist with KPIs:
      | as_of      | name    | value | period  | tag_list |
      | 2026-06-30 | Revenue | 75    | Quarter | Actual   |
      | 2026-06-30 | Revenue | 60    | Quarter | Budget   |
    And the "Revenue" KPI mapping is shown in the portfolio report
    When the portfolio report rows are built up to "2026-06-30"
    Then the report row "Revenue" should have "quarter_06_26_actual_vs_budget_compute_percent" equal to "25"

  # E25 — Edge case: an Actual column with no Budget
  Scenario: No Budget
    Given the following Monthly KPI Reports exist with KPIs:
      | as_of      | name    | value | period | tag_list |
      | 2026-06-30 | Revenue | 92    | Month  | Actual   |
    And the "Revenue" KPI mapping is shown in the portfolio report
    When the portfolio report rows are built up to "2026-06-30"
    Then the report row "Revenue" should have "month_06_26_actual_vs_budget_compute_percent" equal to "N/A"

  # E26 — Edge case: a Budget of zero has nothing to divide by
  Scenario: Zero Budget
    Given the following Monthly KPI Reports exist with KPIs:
      | as_of      | name    | value | period | tag_list |
      | 2026-06-30 | Revenue | 92    | Month  | Actual   |
      | 2026-06-30 | Revenue | 0     | Month  | Budget   |
    And the "Revenue" KPI mapping is shown in the portfolio report
    When the portfolio report rows are built up to "2026-06-30"
    Then the report row "Revenue" should have "month_06_26_actual_vs_budget_compute_percent" equal to "N/A"
