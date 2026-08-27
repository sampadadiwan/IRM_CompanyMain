Feature: Sample portco KPI workbooks — what the portco sees on the magic link
  The files in public/sample_uploads/kpi_portco_uploads/ (see its README.md) are the demo set for the
  server-side workbook check. Every scenario here goes through the browser exactly as a portco would:
  open the signed link, pick the file, read the Workbook check panel, see whether Submit is allowed.
  (S Pvt Ltd in the README → "TestStartup" here; Jun 2026, Month; mapped KPIs Revenue, EBITDA,
  No. of orders, Total shareholders equity.)

  Background:
    Given there is a user "first_name=FundAdmin" for an entity "name=VentureFund;entity_type=Investment Fund"
    And the fund entity has KPIs enabled
    And there is an existing portfolio company "name=TestStartup;category=Portfolio Company"
    And the portfolio company has an approved portco user "first_name=PortCoUser"
    And the target KPIs are "Revenue, EBITDA, No. of orders, Total shareholders equity"
    And a KPI report shell exists for "TestStartup" as of "2026-06-30" with status "link_sent" and period "Month"
    And I open the KPI report edit page as the portco user via a valid signed link
    And I go to the "Additional Details" step of the KPI report wizard
    And the "Submit Report" button should be disabled

  # ─────────────────────────────────────────────────────────
  # Files that pass — the portco sees a green check and Submit is enabled
  # ─────────────────────────────────────────────────────────
  @kpi_sample_files @kpi_magic_link
  Scenario: 01 — a realistic MIS with formatting, a comments column and a hidden sheet passes
    When I pick the sample KPI workbook "01_success_realistic_mis.xlsx" in the file picker
    Then the workbook check panel shows "No blocking errors"
    And the workbook check panel shows "You were asked for Jun 2026 (Month)"
    And the workbook check panel shows "column present"
    And the workbook check panel shows "KPIs filled: 4 of 4"
    And the workbook check panel shows "header 'Comments' is not a period we recognise"
    And the workbook check panel shows "Hidden sheets ignored: Scratch"
    And the workbook check panel shows "This file also updates 2 other periods"
    And the workbook check panel shows "How we read your file"
    And the workbook check panel shows "2,450"
    And the workbook check panel shows "-310"
    And the workbook check panel does not show "Scratch!"
    And I go to the "Additional Details" step of the KPI report wizard
    And the "Submit Report" button should be enabled
    And I go to the "Additional Details" step of the KPI report wizard
    And the "Save Draft" button should be enabled

  @kpi_sample_files @kpi_magic_link
  Scenario: 02 — the template layout with only the requested column filled passes cleanly
    When I pick the sample KPI workbook "02_success_template_shape.xlsx" in the file picker
    Then the workbook check panel shows "No blocking errors"
    And the workbook check panel shows "KPIs filled: 4 of 4"
    And the workbook check panel shows "4 of 4 expected KPIs found"
    And I go to the "Additional Details" step of the KPI report wizard
    And the "Submit Report" button should be enabled

  @kpi_sample_files @kpi_magic_link
  Scenario: 07 — the warnings showcase passes with every warning explained
    When I pick the sample KPI workbook "07_warnings_showcase.xlsx" in the file picker
    Then the workbook check panel shows "No blocking errors"
    And the workbook check panel shows "Please review and acknowledge — these do not block submission"
    And the workbook check panel shows "its label in the Actual/Budget row is not one we recognise — column ignored"
    And the workbook check panel shows "'Dec 2027' was read as 31-Dec-2027, which is in the future"
    And the workbook check panel shows "appears more than once"
    And the workbook check panel shows "with the same value — imported once"
    And the workbook check panel shows "Total shareholders equity"
    And the workbook check panel shows "25,000,000"
    And the workbook check panel shows "future — ignored"
    And I go to the "Additional Details" step of the KPI report wizard
    And the "Submit Report" button should be enabled

  @kpi_sample_files @kpi_magic_link
  Scenario: 10 — European number formatting is read correctly
    When I pick the sample KPI workbook "10_success_european_numbers.xlsx" in the file picker
    Then the workbook check panel shows "No blocking errors"
    And the workbook check panel shows "2,450.75"
    And the workbook check panel shows "-295.25"
    And I go to the "Additional Details" step of the KPI report wizard
    And the "Submit Report" button should be enabled

  # ─────────────────────────────────────────────────────────
  # Files that are blocked — the portco sees the reason in red and cannot submit
  # ─────────────────────────────────────────────────────────

  @kpi_sample_files @kpi_magic_link
  Scenario: 03 — no period header
    When I pick the sample KPI workbook "03_error_no_header.xlsx" in the file picker
    Then the workbook check panel shows "Please fix these errors before submitting"
    And the workbook check panel shows "No sheet in the file has a header row with at least two period columns"
    And the workbook check panel shows "column not found in the file"
    And I go to the "Additional Details" step of the KPI report wizard
    And the "Submit Report" button should be disabled
    And I go to the "Additional Details" step of the KPI report wizard
    And the "Save Draft" button should be disabled

  @kpi_sample_files @kpi_magic_link
  Scenario: 04 — the requested period is missing
    When I pick the sample KPI workbook "04_error_requested_period_missing.xlsx" in the file picker
    Then the workbook check panel shows "Please fix these errors before submitting"
    And the workbook check panel shows "You were asked for Jun 2026 (Month), but no column in the file is that period"
    And the workbook check panel shows "Periods found: Jan 2026, Feb 2026, Mar 2026"
    And the workbook check panel shows "No. of orders"
    And I go to the "Additional Details" step of the KPI report wizard
    And the "Submit Report" button should be disabled

  @kpi_sample_files @kpi_magic_link
  Scenario: 05 — bad values are named cell by cell
    When I pick the sample KPI workbook "05_error_bad_values.xlsx" in the file picker
    Then the workbook check panel shows "Please fix these errors before submitting"
    And the workbook check panel shows "MIS!B2 (Revenue, May 2026): Excel error '#DIV/0!'"
    And the workbook check panel shows "MIS!B3 (EBITDA, May 2026): '10 (prev 8)' contains more than one number"
    And the workbook check panel shows "MIS!B4 (No. of orders, May 2026): 'ten' is not a number"
    And the workbook check panel shows "'TBD' treated as blank"
    And the workbook check panel shows "Excel error cell"
    And I go to the "Additional Details" step of the KPI report wizard
    And the "Submit Report" button should be disabled

  @kpi_sample_files @kpi_magic_link
  Scenario: 06 — duplicate period header and conflicting duplicate rows
    When I pick the sample KPI workbook "06_error_duplicates.xlsx" in the file picker
    Then the workbook check panel shows "Please fix these errors before submitting"
    And the workbook check panel shows "period 'Jun 2026' appears more than once in the header (columns C and D)"
    And the workbook check panel shows "'Revenue' for Jun 2026 appears at MIS!C2 (2,450) and MIS!C4 (2,999) with different values — keep one"
    And the workbook check panel shows "with the same value — imported once"
    And I go to the "Additional Details" step of the KPI report wizard
    And the "Submit Report" button should be disabled

  @kpi_sample_files @kpi_magic_link
  Scenario: 08 — a file that is not a spreadsheet
    When I pick the sample KPI workbook "08_error_not_a_spreadsheet.xlsx" in the file picker
    Then the workbook check panel shows "Please fix these errors before submitting"
    And the workbook check panel shows "could not be opened as a spreadsheet"
    And I go to the "Additional Details" step of the KPI report wizard
    And the "Submit Report" button should be disabled

  # ─────────────────────────────────────────────────────────
  # Fix-and-retry, submit, and the quarterly variant
  # ─────────────────────────────────────────────────────────

  @kpi_sample_files @kpi_magic_link
  Scenario: A blocked upload followed by a good one re-enables Submit, and Submit goes through
    When I pick the sample KPI workbook "05_error_bad_values.xlsx" in the file picker
    And I go to the "Additional Details" step of the KPI report wizard
    Then the "Submit Report" button should be disabled
    When I pick the sample KPI workbook "02_success_template_shape.xlsx" in the file picker
    Then the workbook check panel shows "No blocking errors"
    And I go to the "Additional Details" step of the KPI report wizard
    And the "Submit Report" button should be enabled
    And I go to the "Additional Details" step of the KPI report wizard
    When I click "Submit Report" and confirm the dialog
    Then I should see "KPI report submitted"
    And the KPI report for "TestStartup" should have status "submitted"
    And the KPI report import status is "imported"
    And the fund admin receives a submission notification email
    And the KPI report has an unapproved KPI "Revenue" as of "2026-06-30" with value 2450

  @kpi_sample_files @kpi_magic_link
  Scenario: A blocked file cannot be forced through, and is kept as a draft with the errors shown
    When I pick the sample KPI workbook "04_error_requested_period_missing.xlsx" in the file picker
    And I go to the "Additional Details" step of the KPI report wizard
    Then the "Submit Report" button should be disabled
    When I force a final submit of the KPI report form
    Then I should see "Not submitted"
    And I go to the "Upload & Validate KPIs" step of the KPI report wizard
    And the workbook check panel shows "You were asked for Jun 2026 (Month), but no column in the file is that period"
    And the KPI report for "TestStartup" should have status "draft_saved"
    And the fund admin receives no submission email

  @kpi_sample_files @kpi_magic_link
  Scenario: 09 — monthly columns for a quarterly request are accepted with a derivation warning
    Given a KPI report shell exists for "TestStartup" as of "2026-06-30" with status "link_sent" and period "Quarter"
    And I open the KPI report edit page as the portco user via a valid signed link
    When I pick the sample KPI workbook "09_quarter_request_answered_monthly.xlsx" in the file picker
    Then the workbook check panel shows "No blocking errors"
    And the workbook check panel shows "You were asked for Jun 2026 (Quarter) but the file has monthly columns instead"
    And I go to the "Additional Details" step of the KPI report wizard
    And the "Submit Report" button should be enabled

  @kpi_sample_files @kpi_magic_link
  Scenario: A portco whose fund has not configured KPI mappings is told so instead of getting a green tick
    Given the portfolio company has no KPI mappings
    And I open the KPI report edit page as the portco user via a valid signed link
    When I pick the sample KPI workbook "02_success_template_shape.xlsx" in the file picker
    Then the workbook check panel shows "Please fix these errors before submitting"
    And the workbook check panel shows "Your fund has not configured which KPIs to collect from TestStartup yet"
    And I go to the "Additional Details" step of the KPI report wizard
    And the "Submit Report" button should be disabled

  # ─────────────────────────────────────────────────────────
  # The fund side sees the same check; a workbook with blocking errors cannot be saved from the New page
  # ─────────────────────────────────────────────────────────
  @kpi_sample_files
  Scenario: Fund admin uploading a bad workbook on the New report page sees the errors and cannot save
    Given I am logged in as the fund admin
    When I open the New KPI report page for "TestStartup"
    And I pick the sample KPI workbook "05_error_bad_values.xlsx" in the file picker
    Then the workbook check panel shows "Please fix these errors before submitting"
    And the workbook check panel shows "MIS!B2 (Revenue, May 2026): Excel error '#DIV/0!'"
    And the workbook check panel shows "This report is for"
    And I go to the "Additional Details" step of the KPI report wizard
    And the "Save" button should be disabled
    When I force a save of the KPI report form
    Then I should see "Not saved — the KPI workbook has 3 blocking errors"
    And no KPI report exists for "TestStartup" other than the shell

  @kpi_sample_files
  Scenario: Fund admin uploading a good workbook on the New report page can save it
    Given I am logged in as the fund admin
    When I open the New KPI report page for "TestStartup"
    And I pick the sample KPI workbook "02_success_template_shape.xlsx" in the file picker
    Then the workbook check panel shows "No blocking errors"
    And I go to the "Additional Details" step of the KPI report wizard
    And the "Save" button should be enabled
