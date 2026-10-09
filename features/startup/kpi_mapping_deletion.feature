# Deleting a KPI mapping: refused for parents, warned and cascaded when KPIs use it.
# Worked examples — openspec/changes/kpi-report-journey/design.md#worked-examples
Feature: Deleting a KPI mapping
  As a fund admin
  I want to delete a wrong KPI mapping with a clear warning
  So that I never hit an error page and I know what will be lost

  Background:
    Given there is a user "first_name=FundAdmin" for an entity "name=Kaveri Ventures;entity_type=Investment Fund"
    And the fund entity has KPIs enabled
    And the fund admin can manage stakeholders
    And there is an existing portfolio company "name=Acme Pvt Ltd;category=Portfolio Company"
    And the target KPIs are "Revenue, EBITDA, Headcount"
    And the computed KPI mapping "ARPC" has the formula "Revenue/EBITDA"
    And KPI report journeys are set up for the entity
    And a KPI workbook with sheet "MIS":
      | KPI     | May 2026 | Jun 2026 |
      | Revenue | 100      | 120      |
      | EBITDA  | 10       | 12       |
    And the fund requests KPIs from "Acme Pvt Ltd" for "2026-06-30" period "Month"
    And the portco submits the workbook for the KPI report
    And I am logged in as the fund admin

  # H11 — Unused mapping
  Scenario: A mapping no KPI uses is deleted without a warning
    When I open the KPI mapping "Headcount" of "Acme Pvt Ltd"
    And I click the mapping's Delete button and confirm
    Then the KPI mapping "Headcount" of "Acme Pvt Ltd" is deleted
    And I should see "Investor kpi mapping was successfully destroyed."

  # H12 — Popup shows counts
  Scenario: Deleting a mapping KPIs use warns what will be deleted
    When I open the KPI mapping "Revenue" of "Acme Pvt Ltd"
    And I click the mapping's Delete button
    Then the confirmation says "2 KPIs across 2 periods (0 approved)"
    And the confirmation says "ARPC uses Revenue"
    And the confirmation says "Cannot be undone"

  # E15 — Cancel
  Scenario: Cancelling the warning deletes nothing
    When I open the KPI mapping "Revenue" of "Acme Pvt Ltd"
    And I click the mapping's Delete button
    And I cancel the confirmation
    Then the KPI mapping "Revenue" of "Acme Pvt Ltd" still exists with 2 KPIs

  # H13 — Confirmed delete
  Scenario: Confirming deletes the mapping and its KPIs and moves the journey on
    When I open the KPI mapping "Revenue" of "Acme Pvt Ltd"
    And I click the mapping's Delete button and confirm
    Then the KPI mapping "Revenue" of "Acme Pvt Ltd" is deleted
    And "Acme Pvt Ltd" has no KPIs named "Revenue"
    And I should see "Revenue and 2 KPIs deleted."
    And the KPI report's journey should show:
      | task                   | status  | message                                  |
      | Approve or reject KPIs | current | 2 KPIs across 2 periods await a decision |

  # E16 — Last mapping deleted
  Scenario: Deleting the portfolio company's last mapping sends its journeys back to the first task
    Given "Acme Pvt Ltd" only has the KPI mapping "Revenue"
    When the KPI mapping "Revenue" of "Acme Pvt Ltd" is deleted by the fund admin
    Then the KPI report's journey current task should be "Set up KPI mappings"

  # X2 — Delete fails
  Scenario: A failed delete changes nothing and shows a message
    Given deleting KPI mappings fails with a database error
    When I open the KPI mapping "Revenue" of "Acme Pvt Ltd"
    And I click the mapping's Delete button and confirm
    Then I should see "Could not delete Revenue — nothing was changed"
    And the KPI mapping "Revenue" of "Acme Pvt Ltd" still exists with 2 KPIs

  # X5 — Parent mapping
  Scenario: A parent mapping cannot be deleted
    Given the KPI mapping "Headcount" of "Acme Pvt Ltd" is a child of "EBITDA"
    When I open the KPI mapping "EBITDA" of "Acme Pvt Ltd"
    Then the mapping's Delete button is disabled saying "Move or delete Headcount first"
    When the KPI mapping "EBITDA" of "Acme Pvt Ltd" is deleted by the fund admin
    Then the delete is refused with "Move or delete Headcount first"
    And the KPI mapping "EBITDA" of "Acme Pvt Ltd" still exists with 2 KPIs
