@rack_test
Feature: A KPI's percentage change follows the direction of the movement
  A change from a negative figure reads the way the figure moved: a loss that shrinks is a rise and a loss that grows is a
  fall. A percentage KPI (such as EBITDA %) changes in percentage points. A positive comparison figure gives the same change
  as before.
  Worked examples: openspec/changes/portfolio-report-quarter-activity-and-change-sign/design.md#worked-examples

  Background:
    Given Im logged in as a user "" for an entity "entity_type=Investment Fund"
    And the user has role "company_admin"
    And there is an existing portfolio company "name=MyFavStartup;category=Portfolio Company"
    And the portfolio company's financial year starts in January

  # H7 — Happy path: 100 to 120 is +20, as before
  Scenario: H7 Positive comparison figure
    Given the following Monthly KPI Reports exist with KPIs:
      | as_of      | name    | value | period |
      | 2026-05-31 | Revenue | 100   | Month  |
      | 2026-06-30 | Revenue | 120   | Month  |
    When the KPI percentage change job runs
    Then the "Month" KPI "Revenue" for "2026-06-30" should have a percentage change of 20.0

  # H8 — Happy path: a loss of 100 shrinks to 80, the change is +20
  Scenario: H8 Loss shrinks
    Given the following Monthly KPI Reports exist with KPIs:
      | as_of      | name   | value | period |
      | 2026-05-31 | EBITDA | -100  | Month  |
      | 2026-06-30 | EBITDA | -80   | Month  |
    When the KPI percentage change job runs
    Then the "Month" KPI "EBITDA" for "2026-06-30" should have a percentage change of 20.0

  # H9 — Happy path: a loss of 100 grows to 125, the change is -25
  Scenario: H9 Loss grows
    Given the following Monthly KPI Reports exist with KPIs:
      | as_of      | name   | value | period |
      | 2026-05-31 | EBITDA | -100  | Month  |
      | 2026-06-30 | EBITDA | -125  | Month  |
    When the KPI percentage change job runs
    Then the "Month" KPI "EBITDA" for "2026-06-30" should have a percentage change of -25.0

  # H10 — Happy path: -50 to 25 is a rise of 150
  Scenario: H10 Negative to positive
    Given the following Monthly KPI Reports exist with KPIs:
      | as_of      | name   | value | period |
      | 2026-05-31 | EBITDA | -50   | Month  |
      | 2026-06-30 | EBITDA | 25    | Month  |
    When the KPI percentage change job runs
    Then the "Month" KPI "EBITDA" for "2026-06-30" should have a percentage change of 150.0

  # H11 — Happy path: 50 to -25 is a fall of 150
  Scenario: H11 Positive to negative
    Given the following Monthly KPI Reports exist with KPIs:
      | as_of      | name   | value | period |
      | 2026-05-31 | EBITDA | 50    | Month  |
      | 2026-06-30 | EBITDA | -25   | Month  |
    When the KPI percentage change job runs
    Then the "Month" KPI "EBITDA" for "2026-06-30" should have a percentage change of -150.0

  # H12 — Happy path: the June 2026 YTD of -3.8 against -3.154 a year earlier is a fall of 20.48
  Scenario: H12 YTD against a negative year-earlier figure
    Given the following Monthly KPI Reports exist with KPIs:
      | as_of      | name   | value  | period |
      | 2025-06-30 | EBITDA | -3.154 | YTD    |
      | 2026-06-30 | EBITDA | -3.8   | YTD    |
    When the KPI percentage change job runs
    Then the "YTD" KPI "EBITDA" for "2026-06-30" should have a percentage change of -20.48

  # H13 — Happy path: EBITDA % goes from -63.2% to -55.7%, a rise of 7.5 points
  Scenario: H13 Percentage KPI margin improves
    Given the following Monthly KPI Reports exist with KPIs:
      | as_of      | name     | value  | period |
      | 2026-05-31 | EBITDA % | -0.632 | Month  |
      | 2026-06-30 | EBITDA % | -0.557 | Month  |
    And the "EBITDA %" KPI mapping has data type "percentage"
    When the KPI percentage change job runs
    Then the "Month" KPI "EBITDA %" for "2026-06-30" should have a percentage change of 7.5

  # H14 — Happy path: a change stored under the old rule (+25 for a loss that grew) is corrected by the recompute
  Scenario: H14 Recompute corrects a stored change
    Given the following Monthly KPI Reports exist with KPIs:
      | as_of      | name   | value | period |
      | 2026-05-31 | EBITDA | -100  | Month  |
      | 2026-06-30 | EBITDA | -125  | Month  |
    And the "Month" KPI "EBITDA" for "2026-06-30" has a stored percentage change of 25.0
    When the KPI percentage change job runs
    Then the "Month" KPI "EBITDA" for "2026-06-30" should have a percentage change of -25.0

  # E11 — Edge case: -100 and -100, no movement
  Scenario: E11 Equal negative figures
    Given the following Monthly KPI Reports exist with KPIs:
      | as_of      | name   | value | period |
      | 2026-05-31 | EBITDA | -100  | Month  |
      | 2026-06-30 | EBITDA | -100  | Month  |
    When the KPI percentage change job runs
    Then the "Month" KPI "EBITDA" for "2026-06-30" should have a percentage change of 0.0

  # E12 — Edge case: a comparison figure of zero gives no change for a money or numeric KPI
  Scenario: E12 Prior zero
    Given the following Monthly KPI Reports exist with KPIs:
      | as_of      | name   | value | period |
      | 2026-05-31 | EBITDA | 0     | Month  |
      | 2026-06-30 | EBITDA | -5    | Month  |
    When the KPI percentage change job runs
    Then the "Month" KPI "EBITDA" for "2026-06-30" should have an empty percentage change

  # E13 — Edge case: Quarter figures follow the same rule, -100 then -80 is +20
  Scenario: E13 Negative prior on a Quarter series
    Given the following Monthly KPI Reports exist with KPIs:
      | as_of      | name   | value | period  |
      | 2026-03-31 | EBITDA | -100  | Quarter |
      | 2026-06-30 | EBITDA | -80   | Quarter |
    When the KPI percentage change job runs
    Then the "Quarter" KPI "EBITDA" for "2026-06-30" should have a percentage change of 20.0

  # E14 — Edge case: -0.01 to 100 is a change too large to store, so it is empty
  Scenario: E14 Too large to store
    Given the following Monthly KPI Reports exist with KPIs:
      | as_of      | name   | value | period |
      | 2025-06-30 | EBITDA | -0.01 | YTD    |
      | 2026-06-30 | EBITDA | 100   | YTD    |
    When the KPI percentage change job runs
    Then the "YTD" KPI "EBITDA" for "2026-06-30" should have an empty percentage change

  # E15 — Edge case: a loss that grows from -100 to -125 has a change of -25, below the lower threshold of 10, so it shows red
  Scenario: E15 Growing loss is red
    Given the following Monthly KPI Reports exist with KPIs:
      | as_of      | name   | value | period |
      | 2026-05-31 | EBITDA | -100  | Month  |
      | 2026-06-30 | EBITDA | -125  | Month  |
    And the "EBITDA" KPI mapping has a lower threshold of 10
    When the KPI percentage change job runs
    And when I view the KPI report for the portfolio company in grid view as owner
    Then the "Month" KPI "EBITDA" for "2026-06-30" should show in red in the grid

  # E16 — Edge case: a stored change is left as it is until the recompute runs
  Scenario: E16 Not recomputed yet
    Given the following Monthly KPI Reports exist with KPIs:
      | as_of      | name   | value | period |
      | 2026-05-31 | EBITDA | -100  | Month  |
      | 2026-06-30 | EBITDA | -80   | Month  |
    And the "Month" KPI "EBITDA" for "2026-06-30" has a stored percentage change of -20.0
    Then the "Month" KPI "EBITDA" for "2026-06-30" should have a percentage change of -20.0

  # E22 — Edge case: a percentage KPI against a prior figure of zero still has a change, 5 points
  Scenario: E22 Percentage KPI against zero
    Given the following Monthly KPI Reports exist with KPIs:
      | as_of      | name     | value | period |
      | 2026-05-31 | EBITDA % | 0     | Month  |
      | 2026-06-30 | EBITDA % | 0.05  | Month  |
    And the "EBITDA %" KPI mapping has data type "percentage"
    When the KPI percentage change job runs
    Then the "Month" KPI "EBITDA %" for "2026-06-30" should have a percentage change of 5.0

  # E23 — Edge case: a percentage KPI from 20% to 15% is -5 points
  Scenario: E23 Percentage KPI falls
    Given the following Monthly KPI Reports exist with KPIs:
      | as_of      | name     | value | period |
      | 2026-05-31 | EBITDA % | 0.20  | Month  |
      | 2026-06-30 | EBITDA % | 0.15  | Month  |
    And the "EBITDA %" KPI mapping has data type "percentage"
    When the KPI percentage change job runs
    Then the "Month" KPI "EBITDA %" for "2026-06-30" should have a percentage change of -5.0

  # E24 — Edge case: the same figures on a numeric KPI are a relative change, 11.87
  Scenario: E24 Same figures on a numeric KPI
    Given the following Monthly KPI Reports exist with KPIs:
      | as_of      | name   | value  | period |
      | 2026-05-31 | Ratio  | -0.632 | Month  |
      | 2026-06-30 | Ratio  | -0.557 | Month  |
    And the "Ratio" KPI mapping has data type "numeric"
    When the KPI percentage change job runs
    Then the "Month" KPI "Ratio" for "2026-06-30" should have a percentage change of 11.87

  # E33 — Edge case: a percentage KPI's YTD against the YTD a year earlier is also in points, 7.5
  Scenario: E33 Percentage KPI year over year
    Given the following Monthly KPI Reports exist with KPIs:
      | as_of      | name     | value  | period |
      | 2025-06-30 | EBITDA % | -0.632 | YTD    |
      | 2026-06-30 | EBITDA % | -0.557 | YTD    |
    And the "EBITDA %" KPI mapping has data type "percentage"
    When the KPI percentage change job runs
    Then the "YTD" KPI "EBITDA %" for "2026-06-30" should have a percentage change of 7.5
