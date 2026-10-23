@rack_test
Feature: KPI cumulation from monthly and quarterly figures
  Quarter, YTD and Year figures of a cumulate KPI are worked out one fiscal year at a time, from approved month
  figures and uploaded Quarter figures. The fiscal year comes from the portfolio company, then the fund, then the region.

  Background:
    Given there is a user "" for an entity "entity_type=Investment Fund"
    And the user has role "company_admin"
    And there is an existing portfolio company "name=MyFavStartup;category=Portfolio Company"

  # E11 — Edge case: with no settings the fiscal year runs April to March
  Scenario: E11 India default fiscal year starts in April
    Given the deployment is the "IN" site with no fiscal-year override
    And the following Monthly KPI Reports exist with KPIs:
      | as_of      | name    | value |
      | 2026-01-31 | Revenue | 10    |
      | 2026-02-28 | Revenue | 10    |
      | 2026-03-31 | Revenue | 10    |
      | 2026-04-30 | Revenue | 10    |
      | 2026-05-31 | Revenue | 10    |
      | 2026-06-30 | Revenue | 10    |
    When I run the KPI cumulate method for "Revenue"
    Then I should see a "Quarter" KPI "Revenue" for "2026-06-30" with value "30.0"
    And I should see a "YTD" KPI "Revenue" for "2026-04-30" with value "10.0"
    And I should see a "YTD" KPI "Revenue" for "2026-06-30" with value "30.0"

  # E10 — Edge case: the portfolio company's own setting wins over the fund's April
  Scenario: E10 Portfolio company override starts the fiscal year in January
    Given the portfolio company's financial year starts in January
    And the following Monthly KPI Reports exist with KPIs:
      | as_of      | name    | value |
      | 2026-01-31 | Revenue | 10    |
      | 2026-02-28 | Revenue | 10    |
      | 2026-03-31 | Revenue | 10    |
      | 2026-04-30 | Revenue | 10    |
      | 2026-05-31 | Revenue | 10    |
      | 2026-06-30 | Revenue | 10    |
    When I run the KPI cumulate method for "Revenue"
    Then I should see a "Quarter" KPI "Revenue" for "2026-03-31" with value "30.0"
    And I should see a "YTD" KPI "Revenue" for "2026-03-31" with value "30.0"
    And I should see a "YTD" KPI "Revenue" for "2026-04-30" with value "40.0"

  # E35 — Edge case: the fund's setting is used when the company sets nothing
  Scenario: E35 Entity setting starts the fiscal year in January
    Given the fund's financial year starts in January
    And the following Monthly KPI Reports exist with KPIs:
      | as_of      | name    | value |
      | 2026-01-31 | Revenue | 10    |
      | 2026-02-28 | Revenue | 10    |
      | 2026-03-31 | Revenue | 10    |
      | 2026-04-30 | Revenue | 10    |
      | 2026-05-31 | Revenue | 10    |
      | 2026-06-30 | Revenue | 10    |
    When I run the KPI cumulate method for "Revenue"
    Then I should see a "Quarter" KPI "Revenue" for "2026-03-31" with value "30.0"
    And I should see a "YTD" KPI "Revenue" for "2026-03-31" with value "30.0"
    And I should see a "YTD" KPI "Revenue" for "2026-04-30" with value "40.0"

  # H2 — Happy path: all 3 months approved give a calculated Quarter
  Scenario: H2 A complete quarter gets a calculated Quarter
    Given the following Monthly KPI Reports exist with KPIs:
      | as_of      | name    | value | period  | source |
      | 2025-06-30 | Revenue | 100   | Quarter | upload |
      | 2025-07-31 | Revenue | 10    | Month   |        |
      | 2025-08-31 | Revenue | 20    | Month   |        |
      | 2025-09-30 | Revenue | 30    | Month   |        |
    When I run the KPI cumulate method for "Revenue"
    Then I should see a "Quarter" KPI "Revenue" for "2025-09-30" with value "60.0"
    And I should see a "YTD" KPI "Revenue" for "2025-09-30" with value "160.0"

  # E1 — Edge case: a quarter with a missing month gets no Quarter, and a missing month is never zero
  Scenario: E1 An incomplete quarter gets no Quarter
    Given the following Monthly KPI Reports exist with KPIs:
      | as_of      | name    | value |
      | 2025-07-31 | Revenue | 10    |
      | 2025-08-31 | Revenue | 20    |
    When I run the KPI cumulate method for "Revenue"
    Then I should NOT see a "Quarter" KPI "Revenue" for "2025-09-30"

  # E5 — Edge case: an uploaded Quarter keeps its value even when all 3 months are approved with a different total
  Scenario: E5 An uploaded Quarter is authoritative over its months
    Given the following Monthly KPI Reports exist with KPIs:
      | as_of      | name    | value | period  | source |
      | 2025-09-30 | Revenue | 40    | Quarter | upload |
      | 2025-07-31 | Revenue | 15    | Month   |        |
      | 2025-08-31 | Revenue | 15    | Month   |        |
      | 2025-09-30 | Revenue | 15    | Month   |        |
    When I run the KPI cumulate method for "Revenue"
    Then I should see a "Quarter" KPI "Revenue" for "2025-09-30" with value "40.0"
    And the "Quarter" KPI "Revenue" for "2025-09-30" should have 1 record

  # E7 — Edge case: three quarters make no Year
  Scenario: E7 Three quarters make no Year
    Given the following Monthly KPI Reports exist with KPIs:
      | as_of      | name    | value |
      | 2025-04-30 | Revenue | 10    |
      | 2025-05-31 | Revenue | 10    |
      | 2025-06-30 | Revenue | 10    |
      | 2025-07-31 | Revenue | 10    |
      | 2025-08-31 | Revenue | 10    |
      | 2025-09-30 | Revenue | 10    |
      | 2025-10-31 | Revenue | 10    |
      | 2025-11-30 | Revenue | 10    |
      | 2025-12-31 | Revenue | 10    |
    When I run the KPI cumulate method for "Revenue"
    Then I should see a "Quarter" KPI "Revenue" for "2025-12-31" with value "30.0"
    And I should NOT see a "Year" KPI "Revenue" for "2026-03-31"

  # H1 — Happy path: an uploaded Q1 then months walk the year without double counting
  Scenario: H1 Quarter then months
    Given the following Monthly KPI Reports exist with KPIs:
      | as_of      | name    | value      | period  | source |
      | 2025-06-30 | Revenue | 8588635.53 | Quarter | upload |
      | 2025-07-31 | Revenue | 4682642.64 | Month   |        |
      | 2025-08-31 | Revenue | 3021951.86 | Month   |        |
    When I run the KPI cumulate method for "Revenue"
    Then I should see a "YTD" KPI "Revenue" for "2025-06-30" with value "8588635.53"
    And I should see a "YTD" KPI "Revenue" for "2025-07-31" with value "13271278.17"
    And I should see a "YTD" KPI "Revenue" for "2025-08-31" with value "16293230.03"
    And I should NOT see a "YTD" KPI "Revenue" for "2025-09-30"

  # H3 — Happy path: uploaded quarters bridge a fiscal year with no months at all
  Scenario: H3 Quarters only
    Given the following Monthly KPI Reports exist with KPIs:
      | as_of      | name    | value | period  | source |
      | 2025-06-30 | Revenue | 100   | Quarter | upload |
      | 2025-09-30 | Revenue | 40    | Quarter | upload |
    When I run the KPI cumulate method for "Revenue"
    Then I should see a "YTD" KPI "Revenue" for "2025-06-30" with value "100.0"
    And I should see a "YTD" KPI "Revenue" for "2025-09-30" with value "140.0"

  # H4 — Happy path: 12 approved months make a Year
  Scenario: H4 Year from months
    Given the following Monthly KPI Reports exist with KPIs:
      | as_of      | name    | value |
      | 2025-04-30 | Revenue | 10    |
      | 2025-05-31 | Revenue | 10    |
      | 2025-06-30 | Revenue | 10    |
      | 2025-07-31 | Revenue | 10    |
      | 2025-08-31 | Revenue | 10    |
      | 2025-09-30 | Revenue | 10    |
      | 2025-10-31 | Revenue | 10    |
      | 2025-11-30 | Revenue | 10    |
      | 2025-12-31 | Revenue | 10    |
      | 2026-01-31 | Revenue | 10    |
      | 2026-02-28 | Revenue | 10    |
      | 2026-03-31 | Revenue | 10    |
    When I run the KPI cumulate method for "Revenue"
    Then I should see a "Year" KPI "Revenue" for "2026-03-31" with value "120.0"

  # H5 — Happy path: the Year is the total of four quarters however each was supplied
  Scenario: H5 Year from mixed data
    Given the following Monthly KPI Reports exist with KPIs:
      | as_of      | name    | value | period  | source |
      | 2025-06-30 | Revenue | 100   | Quarter | upload |
      | 2025-09-30 | Revenue | 40    | Quarter | upload |
      | 2025-10-31 | Revenue | 10    | Month   |        |
      | 2025-11-30 | Revenue | 10    | Month   |        |
      | 2025-12-31 | Revenue | 10    | Month   |        |
      | 2026-01-31 | Revenue | 10    | Month   |        |
      | 2026-02-28 | Revenue | 10    | Month   |        |
      | 2026-03-31 | Revenue | 10    | Month   |        |
    When I run the KPI cumulate method for "Revenue"
    Then I should see a "Year" KPI "Revenue" for "2026-03-31" with value "200.0"

  # H7 — Happy path: Budget may be future-dated, so its future quarter is calculated
  Scenario: H7 A Budget quarter in the future is calculated
    Given the following Monthly KPI Reports exist with KPIs:
      | as_of      | name    | value | tag_list |
      | 2030-01-31 | Revenue | 10    | Budget   |
      | 2030-02-28 | Revenue | 10    | Budget   |
      | 2030-03-31 | Revenue | 10    | Budget   |
    When I run the KPI cumulate method for "Revenue"
    Then I should see a "Quarter" KPI "Revenue" for "2030-03-31" with value "30.0"

  # E9 — Edge case: Actual figures dated after today are not calculated
  Scenario: E9 An Actual quarter in the future is not calculated
    Given the following Monthly KPI Reports exist with KPIs:
      | as_of      | name    | value | tag_list |
      | 2030-01-31 | Revenue | 10    | Actual   |
      | 2030-02-28 | Revenue | 10    | Actual   |
      | 2030-03-31 | Revenue | 10    | Actual   |
    When I run the KPI cumulate method for "Revenue"
    Then I should NOT see a "Quarter" KPI "Revenue" for "2030-03-31"

  # E2 — Edge case: a missing month stops YTD, nothing after it is calculated
  Scenario: E2 A gap stops YTD
    Given the following Monthly KPI Reports exist with KPIs:
      | as_of      | name    | value | period  | source |
      | 2025-06-30 | Revenue | 100   | Quarter | upload |
      | 2025-07-31 | Revenue | 10    | Month   |        |
      | 2025-09-30 | Revenue | 30    | Month   |        |
    When I run the KPI cumulate method for "Revenue"
    Then I should see a "YTD" KPI "Revenue" for "2025-06-30" with value "100.0"
    And I should see a "YTD" KPI "Revenue" for "2025-07-31" with value "110.0"
    And I should NOT see a "YTD" KPI "Revenue" for "2025-08-31"
    And I should NOT see a "YTD" KPI "Revenue" for "2025-09-30"

  # E3 — Edge case: partial months of a quarter bridged by an uploaded Quarter are not counted twice
  Scenario: E3 Partial months with an uploaded quarter are not double counted
    Given the following Monthly KPI Reports exist with KPIs:
      | as_of      | name    | value | period  | source |
      | 2025-06-30 | Revenue | 100   | Quarter | upload |
      | 2025-07-31 | Revenue | 10    | Month   |        |
      | 2025-09-30 | Revenue | 40    | Quarter | upload |
    When I run the KPI cumulate method for "Revenue"
    Then I should see a "YTD" KPI "Revenue" for "2025-07-31" with value "110.0"
    And I should see a "YTD" KPI "Revenue" for "2025-09-30" with value "140.0"

  # E4 — Edge case: three months win over a disagreeing uploaded quarter for YTD, and the uploaded Quarter stays
  Scenario: E4 Months take priority over a disagreeing uploaded quarter
    Given the following Monthly KPI Reports exist with KPIs:
      | as_of      | name    | value | period  | source |
      | 2025-06-30 | Revenue | 100   | Quarter | upload |
      | 2025-07-31 | Revenue | 10    | Month   |        |
      | 2025-08-31 | Revenue | 15    | Month   |        |
      | 2025-09-30 | Revenue | 20    | Month   |        |
      | 2025-09-30 | Revenue | 40    | Quarter | upload |
    When I run the KPI cumulate method for "Revenue"
    Then I should see a "YTD" KPI "Revenue" for "2025-09-30" with value "145.0"
    And I should see a "Quarter" KPI "Revenue" for "2025-09-30" with value "40.0"

  # E6 — Edge case: a gap in one fiscal year does not stop the next fiscal year
  Scenario: E6 A gap does not leak into the next fiscal year
    Given the following Monthly KPI Reports exist with KPIs:
      | as_of      | name    | value |
      | 2025-04-30 | Revenue | 10    |
      | 2025-05-31 | Revenue | 10    |
      | 2025-06-30 | Revenue | 10    |
      | 2025-07-31 | Revenue | 10    |
      | 2025-09-30 | Revenue | 10    |
      | 2026-04-30 | Revenue | 20    |
      | 2026-05-31 | Revenue | 20    |
      | 2026-06-30 | Revenue | 20    |
    When I run the KPI cumulate method for "Revenue"
    Then I should see a "YTD" KPI "Revenue" for "2025-07-31" with value "40.0"
    And I should NOT see a "YTD" KPI "Revenue" for "2025-09-30"
    And I should see a "YTD" KPI "Revenue" for "2026-06-30" with value "60.0"

  # E38 — Edge case: a Quarter figure covers its quarter end even though November is missing and December has a month
  Scenario: E38 A Quarter figure bridges a missing month
    Given the following Monthly KPI Reports exist with KPIs:
      | as_of      | name    | value | period  | source |
      | 2025-06-30 | Revenue | 100   | Quarter | upload |
      | 2025-09-30 | Revenue | 40    | Quarter | upload |
      | 2025-10-31 | Revenue | 10    | Month   |        |
      | 2025-12-31 | Revenue | 20    | Month   |        |
      | 2025-12-31 | Revenue | 50    | Quarter | upload |
    When I run the KPI cumulate method for "Revenue"
    Then I should see a "YTD" KPI "Revenue" for "2025-10-31" with value "150.0"
    And I should NOT see a "YTD" KPI "Revenue" for "2025-11-30"
    And I should see a "YTD" KPI "Revenue" for "2025-12-31" with value "190.0"
