Feature: Server-side KPI workbook validation — extended coverage
  Covers the rules and flows not exercised by kpi_upload_validation.feature / portco_kpi_workflow.feature:
  plausibility warnings, header quirks, number locales, fund-side severity, endpoint authorisation,
  stale-verdict handling, upload types, import-job emails, the fund's show page and template variants.

  # Reference: docs/modules/portfolio/kpis/kpi_portco_upload_validation_review.md

  Background:
    Given there is a user "first_name=FundAdmin" for an entity "name=VentureFund;entity_type=Investment Fund"
    And the fund entity has KPIs enabled
    And there is an existing portfolio company "name=TestStartup;category=Portfolio Company"
    And the portfolio company has an approved portco user "first_name=PortCoUser"
    And a KPI report shell exists for "TestStartup" as of "2026-06-30" with status "link_sent" and period "Month"

  # ─────────────────────────────────────────────────────────
  # §2.9 Plausibility warnings (never blocking)
  # ─────────────────────────────────────────────────────────
  @kpi_validation_ext
  Scenario: A bare number on a percentage KPI whose scale disagrees with history warns
    Given the KPI mapping "Gross Margin" exists with data type "percentage"
    And an approved KPI "Gross Margin" of 0.40 exists for "TestStartup" as of "2026-05-31" period "Month"
    And a KPI workbook with sheet "MIS":
      | KPI          | Jun 2026 |
      | Gross Margin | 42       |
    When the workbook is validated for the KPI report
    Then the validation has no errors
    And the validation has warning "percentage_scale_suspect"
    And the cell "MIS!B2" is stored as "42"

  @kpi_validation_ext
  Scenario: A change beyond the mapping's thresholds warns; within them it does not
    Given the KPI mapping "Revenue" exists with lower threshold 20 and upper threshold 30
    And an approved KPI "Revenue" of 100 exists for "TestStartup" as of "2026-05-31" period "Month"
    And a KPI workbook with sheet "MIS":
      | KPI     | Jun 2026 |
      | Revenue | 50       |
    When the workbook is validated for the KPI report
    Then the validation has no errors
    And the validation has warning "threshold_breach"
    Given a KPI workbook with sheet "MIS":
      | KPI     | Jun 2026 |
      | Revenue | 110      |
    When the workbook is validated for the KPI report
    Then the validation has no warning "threshold_breach"

  @kpi_validation_ext
  Scenario: Without thresholds a swing beyond 200 percent is an outlier warning, and a sign flip is flagged
    Given the target KPIs are "Revenue, EBITDA"
    And an approved KPI "Revenue" of 100 exists for "TestStartup" as of "2026-05-31" period "Month"
    And an approved KPI "EBITDA" of 10 exists for "TestStartup" as of "2026-04-30" period "Month"
    And an approved KPI "EBITDA" of 12 exists for "TestStartup" as of "2026-05-31" period "Month"
    And a KPI workbook with sheet "MIS":
      | KPI     | Jun 2026 |
      | Revenue | 400      |
      | EBITDA  | -5       |
    When the workbook is validated for the KPI report
    Then the validation has no errors
    And the validation has warning "outlier"
    And the validation has warning "sign_flip"

  @kpi_validation_ext
  Scenario: A value in the red RAG band against the approved budget warns
    Given the KPI mapping "Churn" exists with RAG comparator "Budget", direction "lower_is_better", red threshold 1.5, green threshold 1.0
    And an approved "Budget" KPI "Churn" of 10 exists for "TestStartup" as of "2026-06-30" period "Month"
    And a KPI workbook with sheet "MIS":
      | KPI   | Jun 2026 |
      | Churn | 20       |
    When the workbook is validated for the KPI report
    Then the validation has no errors
    And the validation has warning "rag_red"

  @kpi_validation_ext
  Scenario: A value in the amber RAG band against the approved budget warns
    Given the KPI mapping "Retention" exists with RAG comparator "Budget", direction "higher_is_better", red threshold 0.7, green threshold 0.9
    And an approved "Budget" KPI "Retention" of 10 exists for "TestStartup" as of "2026-06-30" period "Month"
    And a KPI workbook with sheet "MIS":
      | KPI       | Jun 2026 |
      | Retention | 8        |
    When the workbook is validated for the KPI report
    Then the validation has no errors
    And the validation has warning "rag_amber"

  @kpi_validation_ext
  Scenario: Net Burn overspending against budget in the red RAG band warns
    Given the KPI mapping "Net Burn" exists with RAG comparator "Budget", direction "lower_is_better", red threshold 1.2, green threshold 1.0
    And an approved "Budget" KPI "Net Burn" of 100 exists for "TestStartup" as of "2026-06-30" period "Month"
    And a KPI workbook with sheet "MIS":
      | KPI      | Jun 2026 |
      | Net Burn | 130      |
    When the workbook is validated for the KPI report
    Then the validation has no errors
    And the validation has warning "rag_red"

  @kpi_validation_ext
  Scenario: Headcount overshooting budget in the red RAG band warns
    Given the KPI mapping "Headcount" exists with RAG comparator "Budget", direction "lower_is_better", red threshold 1.1, green threshold 1.0
    And an approved "Budget" KPI "Headcount" of 100 exists for "TestStartup" as of "2026-06-30" period "Month"
    And a KPI workbook with sheet "MIS":
      | KPI       | Jun 2026 |
      | Headcount | 120      |
    When the workbook is validated for the KPI report
    Then the validation has no errors
    And the validation has warning "rag_red"

  @kpi_validation_ext
  Scenario: A value in the green RAG band against the approved budget warns of nothing
    Given the KPI mapping "Churn" exists with RAG comparator "Budget", direction "lower_is_better", red threshold 1.5, green threshold 1.0
    And an approved "Budget" KPI "Churn" of 10 exists for "TestStartup" as of "2026-06-30" period "Month"
    And a KPI workbook with sheet "MIS":
      | KPI   | Jun 2026 |
      | Churn | 5        |
    When the workbook is validated for the KPI report
    Then the validation has no errors
    And the validation has no warning "rag_red"
    And the validation has no warning "rag_amber"

  @kpi_validation_ext
  Scenario: RAG rules produce no warning when there is no approved Budget to compare against
    Given the KPI mapping "Churn" exists with RAG comparator "Budget", direction "lower_is_better", red threshold 1.5, green threshold 1.0
    And a KPI workbook with sheet "MIS":
      | KPI   | Jun 2026 |
      | Churn | 20       |
    When the workbook is validated for the KPI report
    Then the validation has no errors
    And the validation has no warning "rag_red"
    And the validation has no warning "rag_amber"

  @kpi_validation_ext
  Scenario: A flat-threshold RAG rule (no comparator) warns without needing an approved Budget
    Given the KPI mapping "Gross Margin" exists with RAG comparator "none", direction "higher_is_better", red threshold 0.40, green threshold 0.55
    And a KPI workbook with sheet "MIS":
      | KPI          | Jun 2026 |
      | Gross Margin | 0.35     |
    When the workbook is validated for the KPI report
    Then the validation has no errors
    And the validation has warning "rag_red"

  @kpi_validation_ext
  Scenario: A brand-new KPI with no approved history raises no plausibility warnings
    Given the target KPIs are "Revenue"
    And a KPI workbook with sheet "MIS":
      | KPI     | Jun 2026 |
      | Revenue | 99999999 |
    When the workbook is validated for the KPI report
    Then the validation has no errors
    And the validation has no warning "denomination_suspect"
    And the validation has no warning "outlier"

  # ─────────────────────────────────────────────────────────
  # §2.3 / §2.6 Header quirks and number locales
  # ─────────────────────────────────────────────────────────
  @kpi_validation_ext
  Scenario: A non-period header column is ignored with a warning; a duplicated period header is an error
    Given the target KPIs are "Revenue"
    And a KPI workbook with sheet "MIS":
      | KPI     | May 2026 | Jun 2026 | Comments |
      | Revenue | 100      | 120      | good     |
    When the workbook is validated for the KPI report
    Then the validation has no errors
    And the validation has warning "unrecognized_period"
    And the validation warning "unrecognized_period" mentions "Comments"
    Given a KPI workbook with sheet "MIS":
      | KPI     | May 2026 | Jun 2026 | Jun 2026 |
      | Revenue | 100      | 120      | 121      |
    When the workbook is validated for the KPI report
    Then the validation has error "duplicate_period"

  @kpi_validation_ext
  Scenario: A mapped KPI missing from the file is a warning, and a wholly empty sheet is skipped with a warning
    Given the target KPIs are "Revenue, EBITDA"
    And a KPI workbook with sheet "MIS":
      | KPI     | May 2026 | Jun 2026 |
      | Revenue | 100      | 120      |
    And the workbook also has a sheet "Notes":
      |  |
    When the workbook is validated for the KPI report
    Then the validation has no errors
    And the validation has warning "kpi_missing"
    And the validation warning "kpi_missing" mentions "EBITDA"
    And the validation has warning "empty_sheet"

  @kpi_validation_ext
  Scenario: A consistently European-formatted sheet is read correctly; a sheet mixing formats is ambiguous
    Given the target KPIs are "Revenue, EBITDA"
    And a KPI workbook with sheet "MIS":
      | KPI     | May 2026 | Jun 2026   |
      | Revenue | 1.234,50 | 12.345.678 |
      | EBITDA  | 500,25   | '1.000     |
    When the workbook is validated for the KPI report
    Then the validation has no errors
    And the cell "MIS!B2" is stored as "1234.5"
    And the cell "MIS!C2" is stored as "12345678"
    And the cell "MIS!B3" is stored as "500.25"
    And the cell "MIS!C3" is stored as "1000"
    Given a KPI workbook with sheet "MIS":
      | KPI     | May 2026 | Jun 2026 |
      | Revenue | 1.234,50 | 1,234.50 |
      | EBITDA  | 500      | 600      |
    When the workbook is validated for the KPI report
    Then the validation has error "ambiguous_value"

  @kpi_validation_ext
  Scenario: Tag rows (ACT / BUDGET side by side) still satisfy an Actual request
    Given the target KPIs are "Revenue"
    And a KPI workbook with sheet "MIS":
      | KPI     | Jun 2026 | Jun 2026 |
      |         | ACT      | BUDGET   |
      | Revenue | 100      | 90       |
    When the workbook is validated for the KPI report
    Then the validation has no errors
    And the requested period is present with "1" KPIs filled

  # ─────────────────────────────────────────────────────────
  # §2.5 Fund-side (non-portco) reports get requested-period findings as warnings
  # ─────────────────────────────────────────────────────────
  @kpi_validation_ext
  Scenario: On a fund-created report the requested-period check does not block
    Given the target KPIs are "Revenue"
    And a fund-created KPI report exists for "TestStartup" as of "2026-05-31" period "Month"
    And a KPI workbook with sheet "MIS":
      | KPI     | Mar 2026 | Apr 2026 |
      | Revenue | 100      | 110      |
    When the workbook is validated for the KPI report
    Then the validation has no errors
    And the validation has warning "requested_period_missing"

  # ─────────────────────────────────────────────────────────
  # §3.1 C Endpoint authorisation
  # ─────────────────────────────────────────────────────────
  @kpi_validation_ext @kpi_magic_link
  Scenario: The validate_upload endpoint refuses an expired magic link
    Given the target KPIs are "Revenue"
    When I open the KPI report edit page as the portco user via a valid signed link
    And I call validate_upload with an expired signed link
    Then the validate_upload response status is 410

  @kpi_validation_ext
  Scenario: The New-page validate_upload refuses a portfolio company of another fund
    Given a portfolio company "ForeignStartup" of another fund exists
    And I am logged in as the fund admin
    When I call the New-page validate_upload for "ForeignStartup"
    Then the validate_upload response status is not 200

  # ─────────────────────────────────────────────────────────
  # §2.10 Stale verdicts, re-check, upload types
  # ─────────────────────────────────────────────────────────
  @kpi_validation_ext @kpi_magic_link
  Scenario: A verdict for a checked-but-never-saved upload is not shown after reload; Save Draft persists the attached document's verdict
    Given the target KPIs are "Revenue"
    When I open the KPI report edit page as the portco user via a valid signed link
    And I pick a KPI workbook file with a formatted revenue value for June 2026 in the file picker
    Then I should see "Workbook check"
    And I should see "1,250,000"
    When I reload the page
    And I go to the "Upload & Validate KPIs" step of the KPI report wizard
    Then I should see "Upload your KPI workbook"
    And I go to the "Additional Details" step of the KPI report wizard
    And the "Submit Report" button should be disabled
    When I pick a KPI workbook file with a formatted revenue value for June 2026 in the file picker
    And I should see "Workbook check"
    And I go to the "Additional Details" step of the KPI report wizard
    And I click "Save Draft" and wait for the page to reload
    And I go to the "Upload & Validate KPIs" step of the KPI report wizard
    Then I should see "Workbook check"
    And I should see "Re-check file"
    And the KPI report has a stored validation result for its attached document

  @kpi_validation_ext @kpi_magic_link
  Scenario: The KPI file picker only accepts spreadsheets and offers the template
    Given the target KPIs are "Revenue"
    When I open the KPI report edit page as the portco user via a valid signed link
    Then the KPIs upload field accepts only ".xlsx, .xls, .csv"
    And I should see "Download KPI template"

  # ─────────────────────────────────────────────────────────
  # §2.2 Import job emails: warnings alone are quiet, blocking errors are not
  # ─────────────────────────────────────────────────────────
  @kpi_validation_ext
  Scenario: An import with only informational warnings sends no error email; one with blocking errors does
    Given the target KPIs are "Revenue"
    And an approved KPI "Revenue" of 100 exists for "TestStartup" as of "2026-05-31" period "Month"
    And the email queue is cleared
    And a KPI workbook with sheet "MIS":
      | KPI     | May 2026 | Jun 2026 |
      | Revenue | 105      | 120      |
    When the workbook is imported for the KPI report
    Then the fund admin receives no email with subject containing "Errors in extracting KPIs"
    And the KPI report has a stored validation result with "0" errors
    Given a KPI workbook with sheet "MIS":
      | KPI     | May 2026 | Jun 2026 |
      | Revenue | #REF!    | 120      |
    When the workbook is imported for the KPI report
    Then the fund admin receives an email with subject containing "Errors in extracting KPIs"

  # ─────────────────────────────────────────────────────────
  # Fund show page and submitted email content
  # ─────────────────────────────────────────────────────────
  @kpi_validation_ext
  Scenario: The fund's show page summarises the import and the submitted email states what was staged
    Given the target KPIs are "Revenue"
    And a KPI workbook with sheet "MIS":
      | KPI     | May 2026 | Jun 2026 |
      | Revenue | 105      | 120      |
    And the KPI report has that workbook attached
    And the KPI report is marked submitted with a pending import
    When the KPI import job runs for the report
    Then the KPI report import status is "imported"
    And the submitted email to the fund admin mentions "Staged for your review"
    Given I am logged in as the fund admin
    When I view the KPI report for "TestStartup" as of "2026-06-30"
    Then I should see "Workbook import"
    And I should see "Imported"
    And I should see "values staged"
    And I should see "Workbook check details"
    And I should see a "Reopen & ask to re-upload" button

  @kpi_validation_ext
  Scenario: The reopen button is not offered on a report that has not been submitted
    Given I am logged in as the fund admin
    When I view the KPI report for "TestStartup" as of "2026-06-30"
    Then I should not see a "Reopen & ask to re-upload" button

  # ─────────────────────────────────────────────────────────
  # §3.4 P Template variants
  # ─────────────────────────────────────────────────────────
  @kpi_validation_ext
  Scenario: The template shows units, uses the requested period label and follows the fund's fiscal year
    Given the following KPI mappings with denominations exist for the portfolio company:
      | reported_kpi_name | denomination |
      | Revenue           | Crores       |
    And the KPI mapping "Gross Margin" exists with data type "percentage"
    Then the generated KPI template for the report has header "Jun 2026" and rows "Revenue, Gross Margin"
    And the generated KPI template lists unit "Crores" for "Revenue"
    And the generated KPI template lists unit "% (e.g. 42% or 0.42)" for "Gross Margin"
    Given a KPI report shell exists for "TestStartup" as of "2026-03-31" with status "link_sent" and period "Year"
    Then the generated KPI template for the report has header "FY26" and rows "Revenue"
    Given the fund's financial year starts in January
    And a KPI report shell exists for "TestStartup" as of "2026-12-31" with status "link_sent" and period "Year"
    Then the generated KPI template for the report has header "CY2026" and rows "Revenue"

  # ─────────────────────────────────────────────────────────
  # Review-gate fixes: shell dates, unrecognised tag columns, odd quarters, stuck imports
  # ─────────────────────────────────────────────────────────
  @kpi_validation_ext
  Scenario: A shell created for a mid-month date lives on the month end so uploads can match it
    When a KPI report shell is created through the service for "TestStartup" as of "2026-07-18" period "Month"
    Then the created shell has as_of "2026-07-31"

  @kpi_validation_ext
  Scenario: A Variance column next to Actual and Budget is ignored instead of colliding with Actual
    Given the target KPIs are "Revenue"
    And a KPI workbook with sheet "MIS":
      | KPI     | Jun 2026 | Jun 2026 | Jun 2026 |
      |         | Actual   | Budget   | Variance |
      | Revenue | 100      | 90       | 10       |
    When the workbook is validated for the KPI report
    Then the validation has no errors
    And the validation has warning "unrecognized_tag_column"
    And the requested period is present with "1" KPIs filled

  @kpi_validation_ext
  Scenario: A quarter that does not start in Jan/Apr/Jul/Oct still round-trips through the template
    Given the target KPIs are "Revenue"
    And a KPI report shell exists for "TestStartup" as of "2026-05-31" with status "link_sent" and period "Quarter"
    Then the generated KPI template for the report has header "Mar-May 2026" and rows "Revenue"
    And validating the generated template reports the requested period as present but blank

  @kpi_validation_ext
  Scenario: An import job that crashes after a submission reopens the report instead of leaving it pending
    Given the target KPIs are "Revenue"
    And a KPI workbook with sheet "MIS":
      | KPI     | May 2026 | Jun 2026 |
      | Revenue | 105      | 120      |
    And the KPI report has that workbook attached
    And the KPI report is marked submitted with a pending import
    And the KPI report is detached from its portfolio company
    When the KPI import job runs for the report and raises
    Then the KPI report for "TestStartup" should have status "draft_saved"
    And the KPI report import status is "failed"

  # ─────────────────────────────────────────────────────────
  # Parent–child KPI mappings (Revenue → North/South/East/West style) keep working through the
  # new check: the same child name under two parents is two mappings, never a "duplicate row".
  # ─────────────────────────────────────────────────────────
  @kpi_validation_ext
  Scenario: Parent-child mappings validate and import through the new checks without false duplicates
    Given the following parent-child KPI mappings exist for the portfolio company:
      | parent_name    | reported_kpi_name |
      |                | Net Sales         |
      | Net Sales      | Enterprise        |
      | Net Sales      | Mid-Market        |
      | Net Sales      | SMB               |
      |                | Operating Cost    |
      | Operating Cost | Enterprise        |
      | Operating Cost | Mid-Market        |
    And a KPI report shell exists for "TestStartup" as of "2025-06-30" with status "link_sent" and period "Month"
    When the sample KPI workbook "../kpi_extraction/indent_children.xlsx" is validated for the KPI report
    Then the validation has no errors
    And the validation has no warning "duplicate_kpi_row_identical"
    And the requested period is present with "7" KPIs filled
    And the validated cell for KPI "Net Sales - Enterprise" in "Jun 25" is stored as "600"
    And the validated cell for KPI "Operating Cost - Enterprise" in "Jun 25" is stored as "440"
    And the validated cell for KPI "Net Sales - Mid-Market" in "Apr 25" is stored as "300"
    And the validated cell for KPI "Operating Cost - Mid-Market" in "Apr 25" is stored as "400"

  @kpi_validation_ext @kpi_magic_link
  Scenario: A portco with parent-child mappings uploads the indented MIS via the magic link and can submit
    Given the following parent-child KPI mappings exist for the portfolio company:
      | parent_name | reported_kpi_name |
      |             | Revenue           |
      | Revenue     | North             |
      | Revenue     | South             |
      | Revenue     | East              |
      | Revenue     | West              |
    And a KPI workbook with sheet "MIS":
      | KPI     | May 2026 | Jun 2026 |
      | Revenue | 1,000    | 1,200    |
      | North   | 400      | 500      |
      | South   | 300      | 350      |
      | East    | 200      | 200      |
      | West    | 100      | 150      |
    And the KPI report has that workbook attached
    When I open the KPI report edit page as the portco user via a valid signed link
    And I go to the "Upload & Validate KPIs" step of the KPI report wizard
    Then the workbook check panel shows "No blocking errors"
    And the workbook check panel shows "KPIs filled: 5 of 5"
    And the workbook check panel shows "Revenue - North"
    And I acknowledge all KPI warnings
    And I go to the "Additional Details" step of the KPI report wizard
    And the "Submit Report" button should be enabled
    When I click "Submit Report" and confirm the dialog
    Then the KPI report for "TestStartup" should have status "submitted"
    And the KPI report has an unapproved KPI "Revenue - North" as of "2026-06-30" with value 500
    And the KPI report has an unapproved KPI "Revenue - West" as of "2026-06-30" with value 150
    And the KPI report has an unapproved KPI "Revenue" as of "2026-06-30" with value 1200

  @kpi_validation_ext
  Scenario: Filled-down parent labels (parent repeated on every child row) are read as child rows
    Given the following parent-child KPI mappings exist for the portfolio company:
      | parent_name    | reported_kpi_name |
      |                | Net Sales         |
      | Net Sales      | Enterprise        |
      | Net Sales      | SMB               |
      |                | Operating Cost    |
      | Operating Cost | Enterprise        |
    And a KPI workbook with sheet "MIS":
      | KPI            | Segment    | May 2026 | Jun 2026 |
      | Net Sales      |            | 900      | 1000     |
      | Net Sales      | Enterprise | 500      | 600      |
      | Net Sales      | SMB        | 400      | 400      |
      | Operating Cost |            | 700      | 800      |
      | Operating Cost | Enterprise | 400      | 440      |
    When the workbook is validated for the KPI report
    Then the validation has no errors
    And the validated cell for KPI "Net Sales" in "Jun 2026" is stored as "1000"
    And the validated cell for KPI "Net Sales - Enterprise" in "Jun 2026" is stored as "600"
    And the validated cell for KPI "Net Sales - SMB" in "Jun 2026" is stored as "400"
    And the validated cell for KPI "Operating Cost - Enterprise" in "Jun 2026" is stored as "440"

  @kpi_validation_ext
  Scenario: A child name mapped under two parents is not guessed when the sheet gives no parent context
    Given the following parent-child KPI mappings exist for the portfolio company:
      | parent_name    | reported_kpi_name |
      |                | Net Sales         |
      | Net Sales      | Enterprise        |
      |                | Operating Cost    |
      | Operating Cost | Enterprise        |
    And a KPI workbook with sheet "MIS":
      | KPI        | May 2026 | Jun 2026 |
      | Enterprise | 500      | 600      |
      | Net Sales  | 900      | 1000     |
    When the workbook is validated for the KPI report
    Then the validation has no errors
    And the validation has warning "parent_context_unknown"
    And the validated cell for KPI "Net Sales" in "Jun 2026" is stored as "1000"
    And there is no validated cell for KPI "Net Sales - Enterprise"

  @kpi_validation_ext
  Scenario: A parent that does not equal the sum of all its children gets a hint
    Given the following parent-child KPI mappings exist for the portfolio company:
      | parent_name | reported_kpi_name |
      |             | Revenue           |
      | Revenue     | North             |
      | Revenue     | South             |
    And a KPI workbook with sheet "MIS":
      | KPI     | May 2026 | Jun 2026 |
      | Revenue | 900      | 1000     |
      | North   | 500      | 600      |
      | South   | 400      | 300      |
    When the workbook is validated for the KPI report
    Then the validation has no errors
    And the validation has warning "children_sum_mismatch"
    And the validation warning "children_sum_mismatch" mentions "Jun 2026"
