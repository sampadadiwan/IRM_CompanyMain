# KPI report journey — which reports get one, and what each check says.
# Worked examples — openspec/changes/kpi-report-journey/design.md#worked-examples
Feature: KPI report journey
  As a fund KPI user
  I want a step bar on each KPI report I request
  So that I know what is needed next — without journeys on the reports an import creates

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

  # H3 — Upload creates many reports, one journey
  Scenario: Only the requested report gets a journey when an import creates reports for other periods
    Given the fund requests KPIs from "Acme Pvt Ltd" for "2026-06-30" period "Month"
    When the portco submits the workbook for the KPI report
    Then the KPI report for "Acme Pvt Ltd" as of "2026-06-30" has the "KPI Report Review" journey
    And the KPI report for "Acme Pvt Ltd" as of "2026-05-31" has no journey

  # H4 — Pending across periods
  Scenario: Approve or reject KPIs counts the portfolio company's pending KPIs on every period
    Given the fund requests KPIs from "Acme Pvt Ltd" for "2026-06-30" period "Month"
    When the portco submits the workbook for the KPI report
    Then the KPI report's journey should show:
      | task                   | status  | message                                   |
      | Set up KPI mappings    | passed  | 2 KPI mappings                            |
      | Send upload request    | passed  | Upload link sent                          |
      | Submit KPIs            | passed  | Submitted                                 |
      | Import workbook        | passed  | Workbook imported                         |
      | Approve or reject KPIs | current | 4 KPIs across 2 periods await a decision  |
    And the KPI report's journey action for "Approve or reject KPIs" links to the pending KPIs of "Acme Pvt Ltd"

  # H14 — Fund upload skips the portco steps
  Scenario: A report the fund creates itself shows the portco steps as not applicable
    When the fund creates a KPI report for "Acme Pvt Ltd" as of "2026-06-30" period "Month"
    Then the KPI report's journey should show:
      | task                | status | message              |
      | Send upload request | na     | Uploaded by the fund |
      | Submit KPIs         | na     | Uploaded by the fund |
      | Import workbook     | current| No KPI workbook uploaded yet |

  # H15 — No KPI mappings yet
  Scenario: A portfolio company without KPI mappings is stuck on the first task
    Given there is an existing portfolio company "name=Beta Foods;category=Portfolio Company"
    When the fund requests KPIs from "Beta Foods" for "2026-06-30" period "Month"
    Then the KPI report's journey current task should be "Set up KPI mappings"
    And the KPI report's journey should show:
      | task                | status  | message                                     |
      | Set up KPI mappings | current | No KPI mappings — imports will find nothing |

  # E2 — Editing a by-product report later
  Scenario: Editing a report the import created still gives it no journey
    Given the fund requests KPIs from "Acme Pvt Ltd" for "2026-06-30" period "Month"
    And the portco submits the workbook for the KPI report
    When the notes of the KPI report for "Acme Pvt Ltd" as of "2026-05-31" are edited
    Then the KPI report for "Acme Pvt Ltd" as of "2026-05-31" has no journey

  # E3 — Company's own report
  Scenario: A report without a portfolio company gets no journey
    When the fund creates its own KPI report as of "2026-06-30"
    Then that KPI report has no journey

  # E5 — Everything rejected
  Scenario: Rejecting every KPI on the report sends the journey back to the import
    Given the fund requests KPIs from "Acme Pvt Ltd" for "2026-06-30" period "Month"
    And the portco submits the workbook for the KPI report
    When every KPI on the KPI report is rejected
    Then the KPI report's journey current task should be "Import workbook"
    And the KPI report's journey should show:
      | task            | status  | message                                                                               |
      | Import workbook | current | No KPIs on this report — they were rejected, or the workbook had no column for this period |

  # E14 — Import with an Investor template assigned
  Scenario: Importing KPIs no longer launches a workflow on the portfolio company
    Given "Acme Pvt Ltd" has an Investor workflow template assigned
    And the fund requests KPIs from "Acme Pvt Ltd" for "2026-06-30" period "Month"
    When the portco submits the workbook for the KPI report
    Then "Acme Pvt Ltd" has no workflow instance

  # E18 — Asking the portco for an existing report
  Scenario: Requesting a period an import already created gives that report a journey
    Given a KPI report exists for "Acme Pvt Ltd" as of "2026-05-31" period "Month" without a journey
    When the fund requests KPIs from "Acme Pvt Ltd" for "2026-05-31" period "Month"
    Then the KPI report for "Acme Pvt Ltd" as of "2026-05-31" has the "KPI Report Review" journey

  # H10 — Approval on the grid
  Scenario: Approve all on the grid moves every journey of the portfolio company on
    Given the fund admin can manage stakeholders
    And the fund requests KPIs from "Acme Pvt Ltd" for "2026-06-30" period "Month"
    And the portco submits the workbook for the KPI report
    And the fund starts a journey on the KPI report for "Acme Pvt Ltd" as of "2026-05-31"
    And I am logged in as the fund admin
    When I approve all pending KPIs of "Acme Pvt Ltd" on the KPI grid
    Then the journeys of "Acme Pvt Ltd" as of "2026-06-30" and "2026-05-31" are on "Close report"

  # H15 (found in the local pre-QA run) — a company with no portal users still gets the journey
  Scenario: Requesting KPIs from a company with no portal users still starts its journey
    Given there is an existing portfolio company "name=Beta Foods;category=Portfolio Company"
    When the fund sends a KPI request to "Beta Foods" for "2026-06-30" period "Month" from the grid
    Then the KPI report for "Beta Foods" as of "2026-06-30" has the "KPI Report Review" journey
    And the KPI report's journey current task should be "Set up KPI mappings"
