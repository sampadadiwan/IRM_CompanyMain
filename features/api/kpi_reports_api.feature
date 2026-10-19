Feature: KPI reports over the JSON API
  The client-onboarding agent creates KPI reports with the bearer-token API, sending the portfolio
  company's workbook as a multipart file. The workbook check runs on that file exactly as it does on the
  website's upload, and a blocked workbook answers a JSON 422 with the check's errors.
  Reference: .claude/skills/client-onboarding/api-gaps.md (G30)

  Background:
    Given there is a user "first_name=FundAdmin" for an entity "name=VentureFund;entity_type=Investment Fund"
    And the user has role "company_admin"
    And the fund entity has KPIs enabled
    And there is an existing portfolio company "name=TestStartup;category=Portfolio Company"
    And the target KPIs are "Revenue"
    And I have an API token for KPI reports

  # G30 — Happy path: a multipart workbook is checked and the report is created with it (was a 500: to_h on an UploadedFile)
  Scenario: G30 A KPI report created over the API with a multipart workbook
    When I create a KPI report for "TestStartup" as of "2026-08-31" over the API with the workbook:
      | KPI     | Jul 2026 | Aug 2026 |
      | Revenue | 100      | 200      |
    Then the API status is 201
    And the API answer is JSON
    And the KPI report for "TestStartup" as of "2026-08-31" has a KPIs document

  # G30 — Error case: a workbook with blocking errors is not saved; the answer is a JSON 422 naming the errors (was the HTML form)
  Scenario: G30 A KPI report whose workbook has blocking errors answers a JSON 422
    When I create a KPI report for "TestStartup" as of "2026-08-31" over the API with the workbook:
      | KPI     | Notes |
      | Revenue | 100   |
    Then the API status is 422
    And the API answer is JSON
    And the API answer at "validation.ok" is "false"
    And no KPI report exists for "TestStartup" as of "2026-08-31"

  # G31 — Happy path: extracted KPIs can be listed, and narrowed to one report (kpi_report_id is not ransackable — a q[] condition would be dropped)
  Scenario: G31 KPIs are listed over the API and filtered by report
    Given an approved KPI "Revenue" of 100.0 exists for "TestStartup" as of "2026-07-31" period "Month"
    And an approved KPI "Revenue" of 200.0 exists for "TestStartup" as of "2026-08-31" period "Month"
    And I remember the "Month" KPI report for "TestStartup" as of "2026-08-31" as "aug_report"
    When "me" sends GET "/kpis.json?all=true"
    Then the API status is 200
    And the API answer is a list of 2 rows
    When "me" sends GET "/kpis.json?kpi_report_id={aug_report}"
    Then the API answer is a list of 1 row
    And the API answer at "0.kpi_report_id" is "{aug_report}"
    And the API answer at "0.status" is "approved"

  # G32 — Happy path: two reports as of the same date are told apart by period; show carries the KPIs and the check
  Scenario: G32 KPI report JSON says which period, company and status a report is
    Given an approved KPI "Revenue" of 100.0 exists for "TestStartup" as of "2026-06-30" period "Month"
    And an approved KPI "Revenue" of 300.0 exists for "TestStartup" as of "2026-06-30" period "Quarter"
    And I remember the "Quarter" KPI report for "TestStartup" as of "2026-06-30" as "q1_report"
    When "me" sends GET "/kpi_reports.json"
    Then the API status is 200
    And the API list has a row where "period" is "Month"
    And the API list has a row where "period" is "Quarter"
    When "me" sends GET "/kpi_reports/{q1_report}.json"
    Then the API status is 200
    And the API answer at "period" is "Quarter"
    And the API answer at "portfolio_company_name" is "TestStartup"
    And the API answer at "kpis.0.value" is "300.0"

  # G34 — Error case: ?portfolio_company_id= narrows the KPI list (it was ignored and returned every company's KPIs)
  Scenario: G34 KPIs are filtered by portfolio company
    Given an approved KPI "Revenue" of 100.0 exists for "TestStartup" as of "2026-07-31" period "Month"
    And there is an existing portfolio company "name=OtherStartup;category=Portfolio Company"
    And the target KPIs are "Revenue"
    And an approved KPI "Revenue" of 900.0 exists for "OtherStartup" as of "2026-07-31" period "Month"
    And I remember the portfolio company "TestStartup" as "test_startup"
    When "me" sends GET "/kpis.json?portfolio_company_id={test_startup}"
    Then the API answer is a list of 1 row
    And the API answer at "0.portfolio_company_id" is "{test_startup}"

  # G36 — Error case: the JSON list returns Budget reports too unless tag_list is sent (the website's Actual-only default dropped them)
  Scenario: G36 The KPI report list returns every tag unless asked for one
    Given an approved KPI "Revenue" of 100.0 exists for "TestStartup" as of "2026-07-31" period "Month"
    And an approved "Budget" KPI "Revenue" of 120.0 exists for "TestStartup" as of "2026-07-31" period "Month"
    When "me" sends GET "/kpi_reports.json"
    Then the API list has a row where "tag_list" is "Actual"
    And the API list has a row where "tag_list" is "Budget"
    When "me" sends GET "/kpi_reports.json?tag_list=Actual"
    Then the API list has no row where "tag_list" is "Budget"
