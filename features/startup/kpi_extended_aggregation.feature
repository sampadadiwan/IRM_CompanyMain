Feature: KPI Extended Aggregation Logic

  Background:
    Given there is a user "" for an entity "entity_type=Investment Fund"
    Given the user has role "company_admin"
    And there is an existing portfolio company "name=MyFavStartup;category=Portfolio Company"

  Scenario: Forward Fill monthly KPIs: a quarter with a missing month gets no Quarter, each month keeps its balance
    Given the following Monthly KPI Reports exist with KPIs:
      | as_of      | name           | value | tag_list | cumulate_mode |
      | 2023-01-31 | Num of Stores  | 10    | Actual   | forward_fill  |
      | 2023-02-28 | Num of Stores  | 12    | Actual   | forward_fill  |
    # March is missing
    When I run the KPI cumulate method for "Num of Stores"
    Then I should NOT see a "Quarter" KPI "Num of Stores" for "2023-03-31"
    And I should see a "YTD" KPI "Num of Stores" for "2023-02-28" with value "12.0"

  Scenario: Compute KPI using formula from other aggregated KPIs
    Given the following Monthly KPI Reports exist with KPIs:
      | as_of      | name           | value | tag_list | cumulate_mode |
      | 2023-01-31 | Revenue        | 100   | Actual   | cumulate      |
      | 2023-02-28 | Revenue        | 150   | Actual   | cumulate      |
      | 2023-03-31 | Revenue        | 200   | Actual   | cumulate      |
      | 2023-01-31 | Cost           | 80    | Actual   | cumulate      |
      | 2023-02-28 | Cost           | 90    | Actual   | cumulate      |
      | 2023-03-31 | Cost           | 100   | Actual   | cumulate      |
    And an Investor KPI Mapping for "Profit" with formula "Revenue - Cost" and mode "compute"
    When I run the KpiCumulateJob for the portfolio company
    Then I should see a "Quarter" KPI "Profit" for "2023-03-31" with value "180.0"

  Scenario: Compute KPI using division formula, from a complete quarter of each component
    Given the following Monthly KPI Reports exist with KPIs:
      | as_of      | name         | value | tag_list | cumulate_mode |
      | 2023-01-31 | Revenue      | 1000  | Actual   | cumulate      |
      | 2023-02-28 | Revenue      | 1000  | Actual   | cumulate      |
      | 2023-03-31 | Revenue      | 1000  | Actual   | cumulate      |
      | 2023-01-31 | Contribution | 200   | Actual   | cumulate      |
      | 2023-02-28 | Contribution | 200   | Actual   | cumulate      |
      | 2023-03-31 | Contribution | 200   | Actual   | cumulate      |
    And an Investor KPI Mapping for "Margin" with formula "Contribution / Revenue" and mode "compute"
    When I run the KpiCumulateJob for the portfolio company
    Then I should see a "Quarter" KPI "Margin" for "2023-03-31" with value "0.2"
