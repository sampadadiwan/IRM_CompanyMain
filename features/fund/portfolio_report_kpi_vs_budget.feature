@rack_test
Feature: The portfolio report shows each Actual KPI as a percentage of its Budget
  For every Actual column the report offers <label>_vs_budget_percent: Actual divided by Budget of the same KPI, period
  and date, times 100 (92 means 92% of Budget). It is worked out when the report is built, so a Budget approved later
  shows on the next report. The report uses approved KPIs only.

  Background:
    Given there is a user "" for an entity "entity_type=Investment Fund"
    And the user has role "company_admin"
    And there is an existing portfolio company "name=MyFavStartup;category=Portfolio Company"

  # H10 — Happy path: June 2026 YTD Actual 92 against YTD Budget 100
  Scenario: H10 YTD Actual against YTD Budget
    Given the following Monthly KPI Reports exist with KPIs:
      | as_of      | name    | value | period | tag_list |
      | 2026-06-30 | Revenue | 92    | YTD    | Actual   |
      | 2026-06-30 | Revenue | 100   | YTD    | Budget   |
    And the "Revenue" KPI mapping is shown in the portfolio report
    When the portfolio report rows are built up to "2026-06-30"
    Then the report row "Revenue" should have "ytd_06_26_actual_vs_budget_percent" equal to "92"

  # H11 — Happy path: June 2026 Quarter Actual 45 against Quarter Budget 60
  Scenario: H11 Quarter Actual against Quarter Budget
    Given the following Monthly KPI Reports exist with KPIs:
      | as_of      | name    | value | period  | tag_list |
      | 2026-06-30 | Revenue | 45    | Quarter | Actual   |
      | 2026-06-30 | Revenue | 60    | Quarter | Budget   |
    And the "Revenue" KPI mapping is shown in the portfolio report
    When the portfolio report rows are built up to "2026-06-30"
    Then the report row "Revenue" should have "quarter_06_26_actual_vs_budget_percent" equal to "75"

  # H12 — Happy path: a template that only uses <label> and <label>_percent sees the same values
  Scenario: H12 Existing fields unchanged for approved figures
    Given the following Monthly KPI Reports exist with KPIs:
      | as_of      | name    | value | period | tag_list |
      | 2026-06-30 | Revenue | 92    | YTD    | Actual   |
      | 2026-06-30 | Revenue | 100   | YTD    | Budget   |
    And the "YTD" KPI "Revenue" for "2026-06-30" has a stored percentage change of 12.5
    And the "Revenue" KPI mapping is shown in the portfolio report
    When the portfolio report rows are built up to "2026-06-30"
    Then the report row "Revenue" should have "ytd_06_26_actual" equal to "92"
    And the report row "Revenue" should have "ytd_06_26_actual_percent" equal to "12.5"
    And the report row "Revenue" should have "ytd_06_26_budget" equal to "100"

  # H15 — Happy path: each row carries its KPI's data type so a template can format percentages
  Scenario: H15 Row data type
    Given the following Monthly KPI Reports exist with KPIs:
      | as_of      | name    | value | period | tag_list |
      | 2026-06-30 | Revenue | 92    | Month  | Actual   |
    And the "Revenue" KPI mapping has data type "percentage"
    And the "Revenue" KPI mapping is shown in the portfolio report
    When the portfolio report rows are built up to "2026-06-30"
    Then the report row "Revenue" should have data type "percentage"

  # E21 — Edge case: an Actual column with no Budget column
  Scenario: E21 Budget missing
    Given the following Monthly KPI Reports exist with KPIs:
      | as_of      | name    | value | period | tag_list |
      | 2026-06-30 | Revenue | 92    | Month  | Actual   |
    And the "Revenue" KPI mapping is shown in the portfolio report
    When the portfolio report rows are built up to "2026-06-30"
    Then the report row "Revenue" should have "month_06_26_actual_vs_budget_percent" equal to "N/A"

  # E22 — Edge case: a Budget approved after the Actual shows when the report is built again
  Scenario: E22 Budget approved later
    Given the following Monthly KPI Reports exist with KPIs:
      | as_of      | name    | value | period | tag_list | status     |
      | 2026-06-30 | Revenue | 92    | Month  | Actual   | approved   |
      | 2026-06-30 | Revenue | 100   | Month  | Budget   | unapproved |
    And the "Revenue" KPI mapping is shown in the portfolio report
    When the portfolio report rows are built up to "2026-06-30"
    Then the report row "Revenue" should have "month_06_26_actual_vs_budget_percent" equal to "N/A"
    When the KPI "Revenue" tagged "Budget" is approved
    And the portfolio report rows are built up to "2026-06-30"
    Then the report row "Revenue" should have "month_06_26_actual_vs_budget_percent" equal to "92"

  # E23 — Edge case: a Budget of zero has nothing to divide by
  Scenario: E23 Budget zero
    Given the following Monthly KPI Reports exist with KPIs:
      | as_of      | name    | value | period | tag_list |
      | 2026-06-30 | Revenue | 92    | Month  | Actual   |
      | 2026-06-30 | Revenue | 0     | Month  | Budget   |
    And the "Revenue" KPI mapping is shown in the portfolio report
    When the portfolio report rows are built up to "2026-06-30"
    Then the report row "Revenue" should have "month_06_26_actual_vs_budget_percent" equal to "N/A"

  # E24 — Edge case: a Month Actual is not compared with a Quarter Budget of the same date
  Scenario: E24 Different period not compared
    Given the following Monthly KPI Reports exist with KPIs:
      | as_of      | name    | value | period  | tag_list |
      | 2026-06-30 | Revenue | 92    | Month   | Actual   |
      | 2026-06-30 | Revenue | 100   | Quarter | Budget   |
    And the "Revenue" KPI mapping is shown in the portfolio report
    When the portfolio report rows are built up to "2026-06-30"
    Then the report row "Revenue" should have "month_06_26_actual_vs_budget_percent" equal to "N/A"

  # E25 — Edge case: only Actual columns carry the field
  Scenario: E25 Only Actual columns
    Given the following Monthly KPI Reports exist with KPIs:
      | as_of      | name    | value | period | tag_list |
      | 2026-06-30 | Revenue | 92    | Month  | Actual   |
      | 2026-06-30 | Revenue | 100   | Month  | Budget   |
      | 2026-06-30 | Revenue | 90    | Month  | IC       |
    And the "Revenue" KPI mapping is shown in the portfolio report
    When the portfolio report rows are built up to "2026-06-30"
    Then the report row "Revenue" should have "month_06_26_actual_vs_budget_percent" equal to "92"
    And the report row "Revenue" should have no "month_06_26_budget_vs_budget_percent" field
    And the report row "Revenue" should have no "month_06_26_ic_vs_budget_percent" field

  # E28 — Edge case: an unapproved figure on either side is not compared
  Scenario Outline: E28 Unapproved figure
    Given the following Monthly KPI Reports exist with KPIs:
      | as_of      | name    | value | period | tag_list | status          |
      | 2026-06-30 | Revenue | 92    | Month  | Actual   | <actual_status> |
      | 2026-06-30 | Revenue | 100   | Month  | Budget   | <budget_status> |
    And the "Revenue" KPI mapping is shown in the portfolio report
    When the portfolio report rows are built up to "2026-06-30"
    Then the report row "Revenue" should have "month_06_26_actual_vs_budget_percent" equal to "N/A"

    Examples:
      | actual_status | budget_status |
      | approved      | unapproved    |
      | unapproved    | approved      |

  # E40 — Edge case: the tag is free text, so "budget" is the Budget column
  Scenario: E40 Tag case ignored
    Given the following Monthly KPI Reports exist with KPIs:
      | as_of      | name    | value | period | tag_list |
      | 2026-06-30 | Revenue | 92    | Month  | Actual   |
      | 2026-06-30 | Revenue | 100   | Month  | budget   |
    And the "Revenue" KPI mapping is shown in the portfolio report
    When the portfolio report rows are built up to "2026-06-30"
    Then the report row "Revenue" should have "month_06_26_actual_vs_budget_percent" equal to "92"

  # E29 — Edge case: the report shows approved KPIs only, in the main report and in the AI-drafted report's export
  Scenario: E29 Report shows approved KPIs only
    Given the following Monthly KPI Reports exist with KPIs:
      | as_of      | name    | value | period | tag_list | status     |
      | 2026-05-31 | Revenue | 50    | Month  | Actual   | approved   |
      | 2026-06-30 | Revenue | 92    | Month  | Actual   | unapproved |
    And the "Revenue" KPI mapping is shown in the portfolio report
    When the portfolio report rows are built up to "2026-06-30"
    Then the report row "Revenue" should have "month_05_26_actual" equal to "50"
    And the report row "Revenue" should have "month_06_26_actual" equal to "N/A"
    And the report row "Revenue" should have "month_06_26_actual_percent" equal to "N/A"
    When the AI-drafted report rows are built up to "2026-06-30"
    Then the report row "Revenue" should have "Month-05-26-Actual" equal to "50"
    And the report row "Revenue" should have "Month-06-26-Actual" equal to "N/A"

  # Not a H/E scenario: the rows are built from one index per report, so the queries do not grow with the number of
  # mappings. 4 mappings x 3 reports used to take 12 queries to find the KPIs, on top of the 4 that load the rows.
  Scenario: Report rows are built without a query per mapping
    Given the following Monthly KPI Reports exist with KPIs:
      | as_of      | name    | value | period | tag_list |
      | 2026-05-31 | Revenue | 10    | Month  | Actual   |
      | 2026-05-31 | Profit  | 11    | Month  | Actual   |
      | 2026-05-31 | Cost    | 12    | Month  | Actual   |
      | 2026-05-31 | Margin  | 13    | Month  | Actual   |
      | 2026-06-30 | Revenue | 92    | YTD    | Actual   |
      | 2026-06-30 | Profit  | 92    | YTD    | Actual   |
      | 2026-06-30 | Cost    | 92    | YTD    | Actual   |
      | 2026-06-30 | Margin  | 92    | YTD    | Actual   |
      | 2026-06-30 | Revenue | 100   | YTD    | Budget   |
      | 2026-06-30 | Profit  | 100   | YTD    | Budget   |
      | 2026-06-30 | Cost    | 100   | YTD    | Budget   |
      | 2026-06-30 | Margin  | 100   | YTD    | Budget   |
    And the "Revenue" KPI mapping is shown in the portfolio report
    And the "Profit" KPI mapping is shown in the portfolio report
    And the "Cost" KPI mapping is shown in the portfolio report
    And the "Margin" KPI mapping is shown in the portfolio report
    And I count queries by call site
    When the portfolio report rows are built up to "2026-06-30"
    Then at most 6 queries came from "PortfolioReportDocGenerator#grid_view_array"
    And the report row "Margin" should have "ytd_06_26_actual_vs_budget_percent" equal to "92"
