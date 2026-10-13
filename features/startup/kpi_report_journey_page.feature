# KPI report journey — the report page: panel, Close report, Send completion email, live updates.
# Worked examples — openspec/changes/kpi-report-journey/design.md#worked-examples
Feature: KPI report journey on the report page
  As a fund KPI user
  I want to close a period and announce it from the KPI report page
  So that the step bar shows the period is done and the right people are told

  Background:
    Given there is a user "first_name=FundAdmin" for an entity "name=Kaveri Ventures;entity_type=Investment Fund"
    And the fund entity has KPIs enabled
    And there is an existing portfolio company "name=Acme Pvt Ltd;category=Portfolio Company"
    And the target KPIs are "Revenue, EBITDA"
    And KPI report journeys are set up for the entity
    And a KPI workbook with sheet "MIS":
      | KPI     | May 2026 | Jun 2026 |
      | Revenue | 100      | 120      |
      | EBITDA  | 10       | 12       |
    And the fund requests KPIs from "Acme Pvt Ltd" for "2026-06-30" period "Month"

  # H5 — Close approves everything pending
  Scenario: Close report approves every pending KPI of the portfolio company and closes the report
    Given the portco submits the workbook for the KPI report
    And I am logged in as the fund admin
    When I open the KPI report
    And I click Close report and confirm
    Then all KPIs of "Acme Pvt Ltd" are approved
    And the KPI report is reviewed
    And the step bar should show:
      | mark | task                   |
      | ✓    | Approve or reject KPIs |
      | ✓    | Close report           |

  # H8 — Send the email
  Scenario: Send completion email emails the portfolio company's manager and completes the journey
    Given there is a second fund employee "first_name=Priya;last_name=Sharma"
    And "Acme Pvt Ltd" is managed by "Priya"
    And there is a second fund employee "first_name=Rahul;last_name=Mehta"
    And the KPI journey has a "Send completion email" task with actor "Rahul"
    And the portco submits the workbook for the KPI report
    And the KPI report is closed
    And the email queue is empty
    And I am logged in as the fund admin
    When I open the KPI report
    And I click Send completion email and confirm
    Then "Priya" receives the email "KPIs for Acme Pvt Ltd — Jun 30, 2026 are complete"
    And "Rahul" receives no completion email
    And the KPI report's journey should be complete

  # H9 — Import finishes while the page is open
  Scenario: The step bar moves on by itself when the import finishes
    Given the portco has submitted the workbook but the import has not run
    And I am logged in as the fund admin
    When I open the KPI report
    Then the step bar should show:
      | mark | task            |
      | ●    | Import workbook |
    When the import job runs while the page is open
    Then without reloading, the step bar should show:
      | mark | task                   |
      | ✓    | Import workbook        |
      | ●    | Approve or reject KPIs |

  # E6 — Not shown before import
  Scenario: No Close report button before the report has KPIs
    Given I am logged in as the fund admin
    When I open the KPI report
    Then I should not see the Close report button

  # E10 — Double click
  @rack_test
  Scenario: Sending the completion email twice sends it once
    Given there is a second fund employee "first_name=Priya;last_name=Sharma"
    And "Acme Pvt Ltd" is managed by "Priya"
    And the KPI journey has a "Send completion email" task with actor "Priya"
    And the portco submits the workbook for the KPI report
    And the KPI report is closed
    And the email queue is empty
    When the completion email is sent twice
    Then "Priya" receives 1 completion email

  # E11 — Not added
  @rack_test
  Scenario: Without a completion task the journey completes at Close report
    Given the portco submits the workbook for the KPI report
    And the KPI report is closed
    And I am logged in as the fund admin
    When I open the KPI report
    Then the KPI report's journey should be complete
    And I should not see the Send completion email button

  # H18 — Send the request from the report page
  Scenario: The panel's Send upload request sends the link for this report without creating another
    Given the portfolio company has an approved portco user "first_name=PortCoUser"
    And the fund creates a KPI report for "Acme Pvt Ltd" as of "2026-09-30" period "Quarter" for the portco to upload
    And the email queue is empty
    And I am logged in as the fund admin
    When I open the KPI report
    Then the panel action "Send upload request" should click "kpi_report_send_request_btn"
    When I click the panel action Send upload request and confirm
    Then "PortCoUser" is emailed the upload link
    And the KPI report's upload link is recorded as sent
    And "Acme Pvt Ltd" has 2 KPI reports
    When the report page's upload request is sent again for the KPI report
    Then "PortCoUser" is emailed the upload link once
    And the step bar should show:
      | mark | task                |
      | ✓    | Send upload request |
      | ●    | Submit KPIs         |

  # E19 — No portal user
  @rack_test
  Scenario: Send upload request is disabled when the company has no approved portal user
    Given the fund creates a KPI report for "Acme Pvt Ltd" as of "2026-09-30" period "Quarter" for the portco to upload
    And I am logged in as the fund admin
    When I open the KPI report
    Then the Send upload request button is disabled saying "Acme Pvt Ltd has no approved portal user"
    And the step bar should show:
      | mark | task                |
      | ●    | Send upload request |

  # H19 — Approvals in a new tab, with a way back
  Scenario: Review pending KPIs opens the grid in a new tab with a banner back to the report
    Given the fund admin can manage stakeholders
    And the portco submits the workbook for the KPI report
    And I am logged in as the fund admin
    When I open the KPI report
    And I click Review pending KPIs in the journey panel
    Then a new tab shows the review banner "4 KPIs pending"
    When I approve all staged KPIs in the new tab
    Then the new tab's banner says "All KPIs decided" and links back to the KPI report
    And in the original tab, without reloading, the step bar should show:
      | mark | task                   |
      | ✓    | Approve or reject KPIs |
      | ●    | Close report           |
