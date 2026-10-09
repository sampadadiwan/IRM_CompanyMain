# KPI report journey — seeding the template and rule.
# Worked examples — openspec/changes/kpi-report-journey/design.md#worked-examples
Feature: KPI report journey setup
  As a fund admin
  I want CapHive to seed the KPI report journey for my company
  So that every KPI report I request is tracked

  Background:
    Given there is a user "first_name=FundAdmin" for an entity "name=Kaveri Ventures;entity_type=Investment Fund"
    And the fund entity has KPIs enabled
    And there is an existing portfolio company "name=Acme Pvt Ltd;category=Portfolio Company"

  # H1 — Setup seeds the template and rule
  Scenario: Setup seeds the KPI Report Review template and its rule
    When the KPI report journey rollout runs for the entity
    Then the entity has the "KPI Report Review" template with the tasks:
      | Set up KPI mappings    |
      | Send upload request    |
      | Submit KPIs            |
      | Import workbook        |
      | Approve or reject KPIs |
      | Close report           |
    And the entity has 1 KPI report auto-assignment rule with no conditions
    And the entity has workflow templates enabled

  # E1 — Setup is idempotent and keeps edits
  Scenario: Running setup again keeps an admin's edits and adds nothing
    Given the KPI report journey rollout runs for the entity
    And the admin renames the KPI journey task "Close report" to "Close the period"
    And the admin adds a "Send completion email" task to the KPI journey
    When the KPI report journey rollout runs for the entity
    Then the "KPI Report Review" template has 7 tasks and no "CFO sign-off" task
    And the "KPI Report Review" template has a task "Close the period"
    And the entity has 1 KPI report auto-assignment rule with no conditions

  # E4 — Setup leaves existing reports alone
  Scenario: Existing reports get no journey when journeys are set up
    Given a KPI report shell exists for "Acme Pvt Ltd" as of "2026-09-30" with status "link_sent" and period "Quarter"
    And the email queue is empty
    When the KPI report journey rollout runs for the entity
    Then the KPI report for "Acme Pvt Ltd" as of "2026-09-30" has no journey
    And no emails are sent
