# KPI report journey — undoing actions move the journey back.
# Worked examples — openspec/changes/kpi-report-journey/design.md#worked-examples
Feature: KPI report journey moves back
  As a fund KPI user
  I want the journey to move back when work is undone
  So that a reopened report never looks finished

  Background:
    Given there is a user "first_name=FundAdmin" for an entity "name=Kaveri Ventures;entity_type=Investment Fund"
    And the fund entity has KPIs enabled
    And the fund admin can manage stakeholders
    And there is an existing portfolio company "name=Acme Pvt Ltd;category=Portfolio Company"
    And the target KPIs are "Revenue, EBITDA"
    And KPI report journeys are set up for the entity
    And a KPI workbook with sheet "MIS":
      | KPI     | May 2026 | Jun 2026 |
      | Revenue | 100      | 120      |
      | EBITDA  | 10       | 12       |
    And the fund requests KPIs from "Acme Pvt Ltd" for "2026-06-30" period "Month"

  # E12 — Reopen after close
  Scenario: Reopening a closed, emailed report moves the journey back and lets the email be sent again
    Given there is a second fund employee "first_name=Priya;last_name=Sharma"
    And "Acme Pvt Ltd" is managed by "Priya"
    And the KPI journey has a "Send completion email" task with actor "Priya"
    And the portco submits the workbook for the KPI report
    And the KPI report is closed
    And the completion email is sent twice
    And I am logged in as the fund admin
    When I open the KPI report
    And I click "Reopen & ask to re-upload" and confirm the dialog
    Then the KPI report's journey current task should be "Submit KPIs"
    And the KPI report's completion email can be sent again
    And the KPI report's journey history records a move back to "Submit KPIs"

  # E13 — Unapprove a KPI
  Scenario: Unapproving a KPI moves a complete journey back to Approve or reject KPIs
    Given the portco submits the workbook for the KPI report
    And the KPI report is closed
    And I am logged in as the fund admin
    When I unapprove the KPI "Revenue" of the KPI report
    Then the KPI report's journey current task should be "Approve or reject KPIs"
    And the KPI report's journey should show:
      | task                   | status  | message                                |
      | Approve or reject KPIs | current | 1 KPI across 1 period awaits a decision |

  # X4 — Import fails
  @rack_test
  Scenario: A failed import sends the journey back to Submit KPIs
    Given the portco has submitted the workbook but the import has not run
    When the import fails
    Then the KPI report's journey current task should be "Submit KPIs"
    And the KPI report's journey should show:
      | task        | status  | message                                |
      | Submit KPIs | current | Import failed — reopened for the portco |
