@rack_test
Feature: KPI forward fill from monthly and quarterly balances
  A forward-fill KPI (cash, headcount) carries balances. Its YTD at a date is the balance at that date, so a missing
  month stops nothing. A Quarter needs all 3 months and a Year needs all 4 quarters.

  Background:
    Given there is a user "" for an entity "entity_type=Investment Fund"
    And the user has role "company_admin"
    And there is an existing portfolio company "name=MyFavStartup;category=Portfolio Company"

  # H6 — Happy path: an uploaded Q1 balance, then a month balance
  Scenario: H6 Quarter balance then month balance
    Given the following Monthly KPI Reports exist with KPIs:
      | as_of      | name | value | period  | source | cumulate_mode |
      | 2025-06-30 | Cash | 100   | Quarter | upload | forward_fill  |
      | 2025-07-31 | Cash | 120   | Month   |        | forward_fill  |
    When I run the KPI cumulate method for "Cash"
    Then I should see a "YTD" KPI "Cash" for "2025-06-30" with value "100.0"
    And I should see a "YTD" KPI "Cash" for "2025-07-31" with value "120.0"

  # E8 — Edge case: an incomplete quarter gets no Quarter, but each month's YTD is its own balance
  Scenario: E8 Incomplete quarter balance
    Given the following Monthly KPI Reports exist with KPIs:
      | as_of      | name | value | cumulate_mode |
      | 2025-07-31 | Cash | 120   | forward_fill  |
      | 2025-08-31 | Cash | 130   | forward_fill  |
    When I run the KPI cumulate method for "Cash"
    Then I should NOT see a "Quarter" KPI "Cash" for "2025-09-30"
    And I should see a "YTD" KPI "Cash" for "2025-07-31" with value "120.0"
    And I should see a "YTD" KPI "Cash" for "2025-08-31" with value "130.0"

  # E36 — Edge case: a missing July does not stop August and September
  Scenario: E36 A forward-fill gap does not stop YTD
    Given the following Monthly KPI Reports exist with KPIs:
      | as_of      | name | value | cumulate_mode |
      | 2025-04-30 | Cash | 10    | forward_fill  |
      | 2025-05-31 | Cash | 20    | forward_fill  |
      | 2025-06-30 | Cash | 30    | forward_fill  |
      | 2025-08-31 | Cash | 50    | forward_fill  |
      | 2025-09-30 | Cash | 60    | forward_fill  |
    When I run the KPI cumulate method for "Cash"
    Then I should see a "YTD" KPI "Cash" for "2025-04-30" with value "10.0"
    And I should see a "YTD" KPI "Cash" for "2025-05-31" with value "20.0"
    And I should see a "YTD" KPI "Cash" for "2025-06-30" with value "30.0"
    And I should see a "YTD" KPI "Cash" for "2025-08-31" with value "50.0"
    And I should see a "YTD" KPI "Cash" for "2025-09-30" with value "60.0"
    And I should see a "Quarter" KPI "Cash" for "2025-06-30" with value "30.0"
    And I should NOT see a "Quarter" KPI "Cash" for "2025-09-30"

  # E39 — Edge case: a later quarter balance is the balance at that date, not added to the earlier quarter
  Scenario: E39 A later quarter balance without a month
    Given the following Monthly KPI Reports exist with KPIs:
      | as_of      | name | value | period  | source | cumulate_mode |
      | 2025-06-30 | Cash | 40    | Quarter | upload | forward_fill  |
      | 2025-09-30 | Cash | 50    | Quarter | upload | forward_fill  |
    When I run the KPI cumulate method for "Cash"
    Then I should see a "YTD" KPI "Cash" for "2025-06-30" with value "40.0"
    And I should see a "YTD" KPI "Cash" for "2025-09-30" with value "50.0"
