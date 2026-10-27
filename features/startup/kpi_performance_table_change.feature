@rack_test
Feature: The performance table's growth follows the direction of the movement
  The growth of a figure on the performance table is the difference from the earlier figure over the size of the earlier
  figure, so a loss that shrinks is a rise and a loss that grows is a fall. A positive earlier figure gives the same growth
  as before.
  Worked examples: openspec/changes/portfolio-report-quarter-activity-and-change-sign/design.md#worked-examples

  Background:
    Given Im logged in as a user "" for an entity "entity_type=Investment Fund"
    And the user has role "company_admin"
    And there is an existing portfolio company "name=MyFavStartup;category=Portfolio Company"

  # H25 — Happy path: a loss of 100 grows to 125, the month's growth is -25
  Scenario: H25 Loss grows
    Given the following Monthly KPI Reports exist with KPIs:
      | as_of      | name   | value | period |
      | 2026-05-31 | EBITDA | -100  | month  |
      | 2026-06-30 | EBITDA | -125  | month  |
    And the "EBITDA" KPI mapping is shown in the portfolio report
    When the performance table is built as of "2026-06-30"
    Then the performance table row "EBITDA" should have a growth_monthly of -25.0

  # H26 — Happy path: a loss of 100 shrinks to 80, the month's growth is +20
  Scenario: H26 Loss shrinks
    Given the following Monthly KPI Reports exist with KPIs:
      | as_of      | name   | value | period |
      | 2026-05-31 | EBITDA | -100  | month  |
      | 2026-06-30 | EBITDA | -80   | month  |
    And the "EBITDA" KPI mapping is shown in the portfolio report
    When the performance table is built as of "2026-06-30"
    Then the performance table row "EBITDA" should have a growth_monthly of 20.0

  # E34 — Edge case: 100 to 120 is +20, as before
  Scenario: E34 Positive earlier figure
    Given the following Monthly KPI Reports exist with KPIs:
      | as_of      | name    | value | period |
      | 2026-05-31 | Revenue | 100   | month  |
      | 2026-06-30 | Revenue | 120   | month  |
    And the "Revenue" KPI mapping is shown in the portfolio report
    When the performance table is built as of "2026-06-30"
    Then the performance table row "Revenue" should have a growth_monthly of 20.0

  # E35 — Edge case: an earlier figure of zero has nothing to divide by
  Scenario: E35 Earlier figure zero
    Given the following Monthly KPI Reports exist with KPIs:
      | as_of      | name   | value | period |
      | 2026-05-31 | EBITDA | 0     | month  |
      | 2026-06-30 | EBITDA | -5    | month  |
    And the "EBITDA" KPI mapping is shown in the portfolio report
    When the performance table is built as of "2026-06-30"
    Then the performance table row "EBITDA" should have an empty growth_monthly

  # E36 — Edge case: the June 2026 YTD of -3.8 against -3.154 a year earlier is a fall of 20.48
  Scenario: E36 YTD against a negative year-earlier figure
    Given the following Monthly KPI Reports exist with KPIs:
      | as_of      | name   | value  | period |
      | 2025-06-30 | EBITDA | -3.154 | month  |
      | 2026-06-30 | EBITDA | -3.8   | month  |
    And the "EBITDA" KPI mapping is shown in the portfolio report
    When the performance table is built as of "2026-06-30"
    Then the performance table row "EBITDA" should have a growth_ytd_py of -20.48
