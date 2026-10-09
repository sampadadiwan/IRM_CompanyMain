# KPI report journey, end to end in the browser: every task of the journey, as the fund and the
# portfolio company actually do it, checking the step bar on the report page after each one.
#   H16 — the portfolio company uploads (magic link): all seven tasks, completion email included
#   H17 — the fund uploads the workbook itself: the portco tasks are n/a
# Worked examples H16, H17 — openspec/changes/kpi-report-journey/design.md#worked-examples
Feature: KPI report journey end to end
  As a fund KPI team
  I want to follow one KPI report from request to completion in the browser
  So that I know the step bar tracks every task the way we really work

  Background:
    Given there is a user "first_name=FundAdmin" for an entity "name=Kaveri Ventures;entity_type=Investment Fund"
    And the fund entity has KPIs enabled
    And the fund admin can manage stakeholders
    And there is an existing portfolio company "name=TestStartup;category=Portfolio Company"
    And KPI report journeys are set up for the entity

  # H16 — portco upload, the whole journey
  @kpi_magic_link
  Scenario: A portfolio company's upload goes through every task to the completion email
    Given the portfolio company has an approved portco user "first_name=PortCoUser"
    And there is a second fund employee "first_name=Priya;last_name=Sharma"
    And "TestStartup" is managed by "Priya"
    And the KPI journey has a "Send completion email" task with actor "Priya"
    And I am logged in as the fund admin
    # Task 1 — Set up KPI mappings
    And the fund requests KPIs from "TestStartup" for "2026-06-30" period "Month"
    When I open the KPI report
    Then the step bar should show:
      | mark | task                |
      | ●    | Set up KPI mappings |
    And the panel should say "No KPI mappings — imports will find nothing"
    When I add the KPI mappings "Revenue, EBITDA, No. of orders, Total shareholders equity" for "TestStartup" on the mapping form
    And I open the KPI report
    # Tasks 2–3 — the request went out; waiting for the portfolio company
    Then the step bar should show:
      | mark | task                |
      | ✓    | Set up KPI mappings |
      | ✓    | Send upload request |
      | ●    | Submit KPIs         |
    # The portfolio company uploads and submits on its magic link
    When I open the KPI report edit page as the portco user via a valid signed link
    And I pick the sample KPI workbook "01_success_realistic_mis.xlsx" in the file picker
    And the workbook check panel shows "No blocking errors"
    And I acknowledge all KPI warnings
    And I go to the "Additional Details" step of the KPI report wizard
    And I click "Submit Report" and confirm the dialog
    And I switch back to the fund admin's browser
    And I open the KPI report
    # Tasks 4–5 — imported; the staged values wait for a decision
    Then the step bar should show:
      | mark | task                   |
      | ✓    | Submit KPIs            |
      | ✓    | Import workbook        |
      | ●    | Approve or reject KPIs |
    And the panel should say "await a decision"
    And the other periods the upload created have no journey
    # Task 6 — Close report
    When I click Close report and confirm
    Then the step bar should show:
      | mark | task                   |
      | ✓    | Approve or reject KPIs |
      | ✓    | Close report           |
      | ●    | Send completion email  |
    # Task 7 — Send completion email
    When I click Send completion email and confirm
    Then "Priya" receives the email "KPIs for TestStartup — Jun 30, 2026 are complete"
    And the journey panel shows "Journey complete"

  # H17 — fund upload, the whole journey
  Scenario: A workbook the fund uploads itself skips the portco tasks and completes at Close report
    Given the target KPIs are "Revenue, EBITDA, No. of orders, Total shareholders equity"
    And I am logged in as the fund admin
    When I create a KPI report for "TestStartup" as of "2026-06-30" period "Month" with the workbook "02_success_template_shape.xlsx" on the New KPI Report screen
    And I open the KPI report
    Then the step bar should show:
      | mark | task                   |
      | ✓    | Set up KPI mappings    |
      | n/a  | Send upload request    |
      | n/a  | Submit KPIs            |
      | ✓    | Import workbook        |
      | ●    | Approve or reject KPIs |
    When I click Close report and confirm
    Then the step bar should show:
      | mark | task                   |
      | ✓    | Approve or reject KPIs |
      | ✓    | Close report           |
    And the journey panel shows "Journey complete"
    And all KPIs of "TestStartup" are approved
