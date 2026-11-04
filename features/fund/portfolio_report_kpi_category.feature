@rack_test
Feature: The portfolio report KPI rows carry their category
  Every KPI row the company report offers has a category next to its data type: the category of the KPI mapping behind it,
  as saved. A mapping with no category gives a blank. The row is the same in the all-KPIs list and in its category's list.
  Worked examples: openspec/changes/portfolio-report-category-gross-irr/design.md#worked-examples

  Background:
    Given there is a user "" for an entity "entity_type=Investment Fund"
    And the user has role "company_admin"
    And there is an existing portfolio company "name=MyFavStartup;category=Portfolio Company"
    And the following Monthly KPI Reports exist with KPIs:
      | as_of      | name    | value | period | tag_list |
      | 2026-06-30 | Revenue | 92    | YTD    | Actual   |
      | 2026-06-30 | Churn   | 0.04  | YTD    | Actual   |
      | 2026-06-30 | Headcount | 40  | YTD    | Actual   |
    And the "Revenue" KPI mapping is shown in the portfolio report
    And the "Churn" KPI mapping is shown in the portfolio report
    And the "Headcount" KPI mapping is shown in the portfolio report
    And the "Revenue" KPI mapping has category "Financial"
    And the "Churn" KPI mapping has category "Customer Metrics"
    And the "Churn" KPI mapping has data type "percentage"

  # H1 — Happy path: the Revenue row shows the category of its mapping, "Financial"
  Scenario: H1 Row carries its category
    When the portfolio report rows are built up to "2026-06-30"
    Then the report row "Revenue" should have category "Financial"

  # H2 — Happy path: the same row in the Financial list shows "Financial", and only that category's rows are in it
  Scenario: H2 Same category in the category's own list
    When the portfolio report rows are built up to "2026-06-30"
    Then the report row "Revenue" should have category "Financial"
    When the portfolio report rows for the "Financial" category are built up to "2026-06-30"
    Then the report row "Revenue" should have category "Financial"
    And the report has no row "Churn"

  # H3 — Happy path: data type and the period value are as before
  Scenario: H3 Existing row fields unchanged
    When the portfolio report rows are built up to "2026-06-30"
    Then the report row "Churn" should have data type "percentage"
    And the report row "Churn" should have "ytd_06_26_actual" equal to "0.04"

  # E1 — Edge case: "Customer Metrics" keeps its capitals and space
  Scenario: E1 Category keeps its case
    When the portfolio report rows are built up to "2026-06-30"
    Then the report row "Churn" should have category "Customer Metrics"

  # E2 — Edge case: Headcount has no category, the row shows a blank and the report builds
  Scenario: E2 Mapping without a category
    When the portfolio report rows are built up to "2026-06-30"
    Then the report row "Headcount" should have category ""
