# Worked examples (H7, H10-H13, H19, H20, E8, E12-E15, E18, E19, X2): openspec/changes/fix-portfolio-dashboard-widgets/design.md#worked-examples
Feature: KPI widgets on the company page
  The Performance Table lists the months that have reports and opens on the latest; the Kpis widget is the KPI grid
  without a Budget View setting; Key KPIs shows the KPIs flagged for the report.

  Background:
    Given Im logged in as a user "" for an entity "entity_type=Investment Fund"
    And the user has role "company_admin"
    And the fund entity has KPIs enabled
    And there is an existing portfolio company "name=Flipkart Unlisted;category=Portfolio Company"

  # H7 — Happy path: Key KPIs shows the KPIs flagged "show in report"
  @rack_test
  Scenario: Key KPIs shows the company's flagged KPIs
    Given the following Monthly KPI Reports exist with KPIs:
      | as_of      | name    | value | tag_list |
      | 2026-03-31 | Revenue | 120   | Actual   |
      | 2026-03-31 | EBITDA  | 30    | Actual   |
    And the "Revenue" KPI mapping is shown in the portfolio report
    And the company dashboard has the widget "Key Kpis" with metadata ""
    When I open the company page
    Then the Key Kpis widget should show the card "Revenue"
    And the Key Kpis widget should not show the card "EBITDA"

  # H10 — Happy path: the dropdown lists the months that have reports, latest selected and shown
  @rack_test
  Scenario: Dropdown lists all months with reports
    Given the following Monthly KPI Reports exist with KPIs:
      | as_of      | name    | value | tag_list |
      | 2022-01-31 | Revenue | 100   | Actual   |
      | 2025-10-31 | Revenue | 110   | Actual   |
      | 2026-03-31 | Revenue | 120   | Actual   |
    When I open the performance table
    Then the month dropdown should list "Mar 2026, Oct 2025, Jan 2022"
    And "Mar 2026" should be the selected month
    And the performance table should be shown

  # H11 — Happy path: an old month is one choice away and the list stays complete
  @rack_test
  Scenario: Reaching an old month in one step
    Given the following Monthly KPI Reports exist with KPIs:
      | as_of      | name    | value | tag_list |
      | 2022-01-31 | Revenue | 100   | Actual   |
      | 2025-10-31 | Revenue | 110   | Actual   |
      | 2026-03-31 | Revenue | 120   | Actual   |
    When I open the performance table
    And I choose the month "Jan 2022" in the dropdown
    Then the performance table should be shown
    And "Jan 2022" should be the selected month
    And the month dropdown should list "Mar 2026, Oct 2025, Jan 2022"

  # H12 — Happy path: the Kpis widget has no Budget View setting
  @rack_test
  Scenario: Budget View is not offered
    Given the company dashboard has the widget "Kpis" with metadata ""
    When I go to the edit page for the "Kpis" widget
    Then there should be no field for "budget_view"
    And the field "compound" should have the label "Data-only view"
    And the field "show_action_buttons" should have the label "Show action buttons"

  # H13 — Happy path: the Kpis widget shows the KPI grid
  @rack_test
  Scenario: Kpis widget shows the KPI grid
    Given the following Monthly KPI Reports exist with KPIs:
      | as_of      | name    | value | tag_list |
      | 2026-03-31 | Revenue | 120   | Actual   |
    And the company dashboard has the widget "Kpis" with metadata ""
    When I open the company page
    Then the Kpis widget should show the KPI grid

  # H19 — Happy path: the Kpis widget hides the action buttons by default
  @rack_test
  Scenario: Action buttons are off by default
    Given the company dashboard has the widget "Kpis" with metadata ""
    When I open the company page
    Then the Kpis widget should hide the action buttons

  # H20 — Happy path: Show action buttons ON shows them
  @rack_test
  Scenario: Show action buttons shows them
    Given the company dashboard has the widget "Kpis" with metadata "{show_action_buttons: true}"
    When I open the company page
    Then the Kpis widget should show the action buttons

  # E8 — Edge case: a widget saved with Compound still applies and the form shows Data-only view ON
  @rack_test
  Scenario: Saved Data-only view still applies
    Given the company dashboard has the widget "Kpis" with metadata "{compound: true}"
    When I open the company page
    Then the Kpis widget should be in data-only view
    When I go to the edit page for the "Kpis" widget
    Then the field "compound" should be ON

  # E12 — Edge case: a company with no KPI report
  @rack_test
  Scenario: Company has no KPI report
    When I open the performance table
    Then the page should say "No KPI reports have been uploaded for this company yet."
    And the month dropdown should have no months

  # E13 — Edge case: a month with no report offers the nearest months that have one
  @rack_test
  Scenario: Requested month has no report
    Given the following Monthly KPI Reports exist with KPIs:
      | as_of      | name    | value | tag_list |
      | 2022-01-31 | Revenue | 100   | Actual   |
      | 2026-03-31 | Revenue | 120   | Actual   |
    When I open the performance table for "2026-02-28"
    Then the page should say "No KPI report found for the specified date. Try any of the dates below"
    And the page should offer the nearest months "2026-03-31, 2022-01-31"

  # E14 — Edge case: a portfolio-company user sees only the months of Actual reports
  @rack_test
  Scenario: Only reports the viewer may see
    Given the following Monthly KPI Reports exist with KPIs:
      | as_of      | name    | value | tag_list |
      | 2022-01-31 | Revenue | 100   | Actual   |
      | 2025-10-31 | Revenue | 110   | Budget   |
      | 2026-03-31 | Revenue | 120   | Actual   |
      | 2026-03-31 | Revenue | 115   | Budget   |
    And the KPI reports are open to the portfolio company
    And the portfolio company has an approved portco user "first_name=Priya"
    And I sign in as the portco user
    When I open the performance table
    Then the month dropdown should list "Mar 2026, Jan 2022"
    And the performance table should be shown

  # E15 — Edge case: a widget saved with Budget View still shows the grid
  @rack_test
  Scenario: Existing widget saved with Budget View
    Given the following Monthly KPI Reports exist with KPIs:
      | as_of      | name    | value | tag_list |
      | 2026-03-31 | Revenue | 120   | Actual   |
    And the company dashboard has the widget "Kpis" with metadata "{budget_view: true, compound: true}"
    When I open the company page
    Then the Kpis widget should show the KPI grid
    And the Kpis widget should be in data-only view

  # E18 — Edge case: Actual and Budget reports in one month list the month once
  @rack_test
  Scenario: A month with two reports is listed once
    Given the following Monthly KPI Reports exist with KPIs:
      | as_of      | name    | value | tag_list |
      | 2026-03-31 | Revenue | 120   | Actual   |
      | 2026-03-31 | Revenue | 115   | Budget   |
    When I open the performance table
    Then the month dropdown should list "Mar 2026"

  # E19 — Edge case: a mid-month report date is reachable from the dropdown
  @rack_test
  Scenario: Mid-month report date
    Given the following Monthly KPI Reports exist with KPIs:
      | as_of      | name    | value | tag_list |
      | 2026-02-28 | Revenue | 100   | Actual   |
      | 2026-03-15 | Revenue | 120   | Actual   |
    When I open the performance table
    And I choose the month "Mar 2026" in the dropdown
    Then the performance table should be shown

  # X2 — Error case: a direct request for a report the viewer may not see is refused
  @rack_test
  Scenario: Direct request for a report the viewer may not see
    Given the following Monthly KPI Reports exist with KPIs:
      | as_of      | name    | value | tag_list |
      | 2025-10-31 | Revenue | 110   | Budget   |
      | 2026-03-31 | Revenue | 120   | Actual   |
    And the KPI reports are open to the portfolio company
    And the portfolio company has an approved portco user "first_name=Priya"
    And I sign in as the portco user
    When I request the performance table for "2025-10-31" by URL
    Then no report content should be shown
    And the request should have been refused
