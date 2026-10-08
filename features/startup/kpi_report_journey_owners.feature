# KPI report journey — who is reminded and emailed (Managed by, template owner, Kpi team).
# Worked examples — openspec/changes/kpi-report-journey/design.md#worked-examples
Feature: KPI report journey owners
  As a fund that assigns each portfolio company to an employee
  I want to set who manages a portfolio company
  So that its KPI reminders and completion emails go to that person

  Background:
    Given there is a user "first_name=FundAdmin" for an entity "name=Kaveri Ventures;entity_type=Investment Fund"
    And the fund entity has KPIs enabled
    And there is an existing portfolio company "name=Acme Pvt Ltd;category=Portfolio Company"
    And there is a second fund employee "first_name=Priya;last_name=Sharma"

  # H6 — Pick a manager
  Scenario: A fund admin sets Managed by on a portfolio company
    Given the fund admin can manage stakeholders
    And I am logged in as the fund admin
    When I set Managed by on "Acme Pvt Ltd" to "Priya Sharma"
    Then "Acme Pvt Ltd" shows Managed by "Priya Sharma"

  # X1 — Outsider refused
  Scenario: A user of another entity cannot be the manager
    Given there is a user "Outsider" in another entity
    When Managed by on "Acme Pvt Ltd" is set to the user "Outsider"
    Then the portfolio company is not saved with "Managed by must be an employee of this organisation"

  # H7 — Manager wins over template (also: Record override wins)
  Scenario: The portfolio company's manager is reminded, not the template's owner
    Given "Acme Pvt Ltd" is managed by "Priya"
    And there is a second fund employee "first_name=Rahul;last_name=Mehta"
    And KPI report journeys are set up for the entity
    And the KPI journey task "Approve or reject KPIs" is owned by "Rahul"
    And Acme's requested KPI report is stalled on "Approve or reject KPIs" for 3 days
    When the journey reminder job runs
    Then only "Priya" is reminded about "Approve or reject KPIs"

  # E7 — Template owner when no manager
  Scenario: Without a manager the template's owner is reminded
    Given there is a second fund employee "first_name=Rahul;last_name=Mehta"
    And KPI report journeys are set up for the entity
    And the KPI journey task "Approve or reject KPIs" is owned by "Rahul"
    And Acme's requested KPI report is stalled on "Approve or reject KPIs" for 3 days
    When the journey reminder job runs
    Then only "Rahul" is reminded about "Approve or reject KPIs"

  # E8 — Kpi-tagged fallback (also: Several default owners)
  Scenario: Without a manager or owner every employee tagged Kpi is reminded once
    Given there is a second fund employee "first_name=Anita;last_name=Rao"
    And there is a second fund employee "first_name=Vikram;last_name=Kumar"
    And the fund employee "Anita" has the tag "Kpi"
    And the fund employee "Vikram" has the tag "Kpi"
    And KPI report journeys are set up for the entity
    And Acme's requested KPI report is stalled on "Approve or reject KPIs" for 3 days
    When the journey reminder job runs
    Then "Anita" and "Vikram" are each reminded once about "Approve or reject KPIs"

  # E9 — Nobody resolves
  Scenario: Nobody to remind shows Owner unavailable
    Given the fund admin can manage stakeholders
    And KPI report journeys are set up for the entity
    And Acme's requested KPI report is stalled on "Approve or reject KPIs" for 3 days
    When the journey reminder job runs
    Then nobody is reminded about "Approve or reject KPIs"
    And I am logged in as the fund admin
    And I open the KPI report
    And the journey panel shows "Owner unavailable"

  # X3 — Manager left (also: Owner left the company)
  Scenario: An inactive manager falls through to the template's owner
    Given "Acme Pvt Ltd" is managed by "Priya"
    And the user "Priya" is deactivated
    And there is a second fund employee "first_name=Rahul;last_name=Mehta"
    And KPI report journeys are set up for the entity
    And the KPI journey task "Approve or reject KPIs" is owned by "Rahul"
    And Acme's requested KPI report is stalled on "Approve or reject KPIs" for 3 days
    When the journey reminder job runs
    Then only "Rahul" is reminded about "Approve or reject KPIs"
