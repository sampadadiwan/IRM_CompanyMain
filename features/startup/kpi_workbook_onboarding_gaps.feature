Feature: KPI workbook layouts found while onboarding clients (gaps G25–G27)
  As a fund admin onboarding a portfolio company's own MIS
  I want quarter headings with notes, segment blocks and repeated labels read correctly
  So that a dry run never shows "ok" for a figure stored under the wrong period or KPI

  # Reference: .claude/skills/client-onboarding/api-gaps.md (G25, G26, G27)

  Background:
    Given there is a user "first_name=FundAdmin" for an entity "name=VentureFund;entity_type=Investment Fund"
    And the fund entity has KPIs enabled
    And there is an existing portfolio company "name=TestStartup;category=Portfolio Company"
    And the portfolio company has an approved portco user "first_name=PortCoUser"
    And a KPI report shell exists for "TestStartup" as of "2026-06-30" with status "link_sent" and period "Month"

  # ─────────────────────────────────────────────────────────
  # G25 — a quarter heading with a note is a quarter, not the month in the note
  # ─────────────────────────────────────────────────────────

  # G25 — Happy path: Ayati's "Q1 FY27" with "(Apr-Jun'26)" on a second line is the quarter ending 30 Jun 2026
  @kpi_validation @rack_test
  Scenario: A quarter heading with its months on a second line is read as the quarter
    Given the target KPIs are "Product Sales"
    And a KPI workbook with sheet "P&L":
      | KPI           | Q4 FY26\n(Jan-Mar'26) | Q1 FY27\n(Apr-Jun'26) |
      | Product Sales | 7500000               | 8588635.53            |
    When the workbook is validated for the KPI report
    Then the cell "P&L!C2" is stored as "8588635.53"
    And the cell "P&L!C2" is read as a "Quarter" ending "2026-06-30"
    And the cell "P&L!B2" is read as a "Quarter" ending "2026-03-31"

  # G25 — Edge case: the same note in brackets on the heading's own line
  @kpi_validation @rack_test
  Scenario: A quarter heading with its months in brackets is read as the quarter
    Given the target KPIs are "Product Sales"
    And a KPI workbook with sheet "P&L":
      | KPI           | Q4 FY26 (Jan-Mar'26) | Q1 FY27 (Apr-Jun'26) |
      | Product Sales | 7500000              | 8588635.53           |
    When the workbook is validated for the KPI report
    Then the cell "P&L!C2" is read as a "Quarter" ending "2026-06-30"

  # G25 — Edge case: a month heading with a note keeps its month
  @kpi_validation @rack_test
  Scenario: A month heading with a note in brackets stays a month
    Given the target KPIs are "Revenue"
    And a KPI workbook with sheet "MIS":
      | KPI     | May 2026 (Actual) | Jun 2026 (Actual) |
      | Revenue | 100               | 200               |
    When the workbook is validated for the KPI report
    Then the cell "MIS!C2" is read as a "Month" ending "2026-06-30"

  # G25 — Error case: a quarter heading no rule can read is refused, not stored as a month
  @kpi_validation @rack_test
  Scenario: A quarter-style heading that cannot be read is ignored with a warning
    Given the target KPIs are "Revenue"
    And a KPI workbook with sheet "MIS":
      | KPI     | May 2026 | Jun 2026 | Q5 FY27 |
      | Revenue | 100      | 200      | 900     |
    When the workbook is validated for the KPI report
    Then the validation has warning "unrecognized_period"
    And the validation warning "unrecognized_period" mentions "Q5 FY27"
    And there is no validated cell "MIS!D2"
    And the cell "MIS!C2" is stored as "200"

  # ─────────────────────────────────────────────────────────
  # G26 — a period spread over segment columns is read from its Total
  # ─────────────────────────────────────────────────────────

  # G26 — Happy path: Butterfly's Summary, each month over its segments and a Total
  @kpi_validation @rack_test
  Scenario: A month spread over segment columns is read from its Total column
    Given the target KPIs are "Revenue"
    And a KPI workbook with sheet "Summary":
      | KPI     | May'26  |         |          | Jun'26  |         |          |
      |         | Therapy | Testing | Total    | Therapy | Testing | Total    |
      | Revenue | 2081    | 607     | 2688     | 2100    | 650     | 2750     |
    When the workbook is validated for the KPI report
    Then the validation has no errors
    And the cell "Summary!D3" is stored as "2688"
    And the cell "Summary!G3" is stored as "2750"
    And the cell "Summary!G3" is read as a "Month" ending "2026-06-30"
    And there is no validated cell "Summary!B3"
    And there is no validated cell "Summary!E3"

  # G26 — Error case: a segment block with no Total is refused, not read from its first column
  @kpi_validation @rack_test
  Scenario: A month spread over segment columns without a Total is an error
    Given the target KPIs are "Revenue"
    And a KPI workbook with sheet "Summary":
      | KPI     | May'26  |         | Jun'26  |         |
      |         | Therapy | Testing | Therapy | Testing |
      | Revenue | 2081    | 607     | 2100    | 650     |
    When the workbook is validated for the KPI report
    Then the validation has error "segment_block_without_total"
    And the validation error "segment_block_without_total" mentions "Therapy, Testing"
    And there is no validated cell "Summary!B3"
    And there is no validated cell "Summary!D3"

  # G26 — Edge case: a sheet with one column per month is read as before
  @kpi_validation @rack_test
  Scenario: A sheet with one column per period has no segment row
    Given the target KPIs are "Revenue, EBITDA"
    And a KPI workbook with sheet "MIS":
      | KPI     | May 2026 | Jun 2026 |
      | Revenue | 100      | 200      |
      | EBITDA  | 10       | 20       |
    When the workbook is validated for the KPI report
    Then the validation has no errors
    And the cell "MIS!B2" is stored as "100"
    And the cell "MIS!C3" is stored as "20"

  # G26 — Edge case (backward compatibility): Actual / Budget / Variance under a merged month is not a segment block; the month is read from its first column as before
  @kpi_validation @rack_test
  Scenario: A merged month over Actual, Budget and Variance columns reads as before
    Given the target KPIs are "Revenue"
    And a KPI workbook with sheet "MIS":
      | KPI     | May 2026 |         |          |       | Jun 2026 |         |          |       |
      |         | Actual   | Budget  | Variance | Var % | Actual   | Budget  | Variance | Var % |
      | Revenue | 1250000  | 1400000 | -150000 | -0.11 | 2080000  | 2100000 | -20000  | -0.01 |
    When the workbook is validated for the KPI report
    Then the validation has no errors
    And the validation has no warning "segment_block_without_total"
    And the cell "MIS!F3" is stored as "2080000"

  # G26 — Edge case: a merged non-period heading ("Notes") with labels under it is not a segment block
  @kpi_validation @rack_test
  Scenario: A merged Notes heading with labels below it is not treated as a segment block
    Given the target KPIs are "Revenue"
    And a KPI workbook with sheet "MIS":
      | KPI     | May 2026 | Jun 2026 | Notes |         |
      |         |          |          | Owner | Comment |
      | Revenue | 100      | 200      | CFO   | ok      |
    When the workbook is validated for the KPI report
    Then the validation has no errors
    And the cell "MIS!C3" is stored as "200"

  # G28 — Edge case: "Grand Total" closes a segment block too (Butterfly's "Apr - Mar'25")
  @kpi_validation @rack_test
  Scenario: A segment block ending in Grand Total is read from that column
    Given the target KPIs are "Revenue"
    And a KPI workbook with sheet "Summary":
      | KPI     | May'26  |         |             | Jun'26  |         |             |
      |         | Therapy | Testing | Grand Total | Therapy | Testing | Grand Total |
      | Revenue | 2081    | 607     | 2688        | 2100    | 650     | 2750        |
    When the workbook is validated for the KPI report
    Then the validation has no errors
    And the cell "Summary!G3" is stored as "2750"

  # G28 — Edge case: a block without a Total is only a warning when no mapped KPI has values in it
  @kpi_validation @rack_test
  Scenario: An un-totalled segment block that no mapped KPI uses does not block the workbook
    Given the target KPIs are "Revenue"
    And a KPI workbook with sheet "Summary":
      | KPI       | May'26  |         | Jun 2026 |
      |           | Therapy | Testing |          |
      | Revenue   |         |         | 200      |
      | Headcount | 12      | 9       | 22       |
    When the workbook is validated for the KPI report
    Then the validation has no errors
    And the validation has warning "segment_block_without_total"
    And the cell "Summary!D3" is stored as "200"

  # G28 — Edge case: a side table under a non-period heading ("Prepaid Expenses") is not a segment block
  @kpi_validation @rack_test
  Scenario: A side table headed Prepaid Expenses is not taken as a period block
    Given the target KPIs are "Revenue"
    And a KPI workbook with sheet "Cash Flow":
      | KPI     | May 2026 | Jun 2026 | Prepaid Expenses |         |
      |         |          |          | Opening          | Closing |
      | Revenue | 100      | 200      | 5                | 7       |
    When the workbook is validated for the KPI report
    Then the validation has no errors
    And the validation has no warning "segment_block_without_total"
    And the cell "Cash Flow!C3" is stored as "200"

  # ─────────────────────────────────────────────────────────
  # G29 — cell refs name the real cell when column A is empty
  # ─────────────────────────────────────────────────────────

  # G29 — Happy path: Revspot's sheets start at column B; the ref names the value's cell, not the label's
  @kpi_validation @rack_test
  Scenario: A sheet whose table starts in column B gives refs in the right columns
    Given the target KPIs are "Revenue"
    And a KPI workbook with sheet "FY27 YTD P&L":
      |  | KPI     | May 2026 | Jun 2026 |
      |  | Revenue | 100      | 200      |
    When the workbook is validated for the KPI report
    Then the cell "FY27 YTD P&L!C2" is stored as "100"
    And the cell "FY27 YTD P&L!D2" is stored as "200"
    And there is no validated cell "FY27 YTD P&L!B2"

  # ─────────────────────────────────────────────────────────
  # G27 — a mapping can be limited to one sheet
  # ─────────────────────────────────────────────────────────

  # G27 — Happy path: P&L "Rent" is read from the P&L only; the cash-flow "Rent" row is left alone
  @kpi_validation @rack_test
  Scenario: A mapping limited to a sheet ignores the same label on other sheets
    Given the KPI mapping "Rent" reported as "Rent" reads only sheet "P&L"
    And a KPI workbook with sheet "P&L":
      | KPI  | May 2026 | Jun 2026 |
      | Rent | 100      | 110      |
    And the workbook also has a sheet "Cash Flow":
      | KPI  | May 2026 | Jun 2026 |
      | Rent | 300      | 0        |
    When the workbook is validated for the KPI report
    Then the cell "P&L!C2" is stored as "110" for KPI "Rent"
    And there is no validated cell in sheet "Cash Flow"

  # G27 — Edge case: one label, two mappings, each read from its own sheet
  @kpi_validation @rack_test
  Scenario: The same label maps to different KPIs on different sheets
    Given the KPI mapping "Rent" reported as "Rent" reads only sheet "P&L"
    And the KPI mapping "Rent Paid" reported as "Rent" reads only sheet "Cash Flow"
    And a KPI workbook with sheet "P&L":
      | KPI  | May 2026 | Jun 2026 |
      | Rent | 100      | 110      |
    And the workbook also has a sheet "Cash Flow":
      | KPI  | May 2026 | Jun 2026 |
      | Rent | 300      | 0        |
    When the workbook is validated for the KPI report
    Then the validation has no errors
    And the cell "P&L!C2" is stored as "110" for KPI "Rent"
    And the cell "Cash Flow!B2" is stored as "300" for KPI "Rent Paid"

  # G27 — Edge case: a sheet-specific mapping wins over an unscoped one on its sheet; the unscoped one reads the rest
  @kpi_validation @rack_test
  Scenario: A sheet-specific mapping takes precedence over an unscoped one with the same label
    Given the target KPIs are "Others"
    And the KPI mapping "Other Expenses" reported as "Others" reads only sheet "P&L"
    And a KPI workbook with sheet "P&L":
      | KPI    | May 2026 | Jun 2026 |
      | Others | 40       | 45       |
    And the workbook also has a sheet "Ops":
      | KPI    | May 2026 | Jun 2026 |
      | Others | 7        | 8        |
    When the workbook is validated for the KPI report
    Then the cell "P&L!C2" is stored as "45" for KPI "Other Expenses"
    And the cell "Ops!C2" is stored as "8" for KPI "Others"
    And the validation has no warning "parent_context_unknown"

  # G27 — Edge case: the sheet name matches ignoring case and extra spaces
  @kpi_validation @rack_test
  Scenario: A mapping's sheet name matches regardless of case and spacing
    Given the KPI mapping "Rent" reported as "Rent" reads only sheet "  p&l  "
    And a KPI workbook with sheet "P&L":
      | KPI  | May 2026 | Jun 2026 |
      | Rent | 100      | 110      |
    When the workbook is validated for the KPI report
    Then the cell "P&L!C2" is stored as "110" for KPI "Rent"

  # ─────────────────────────────────────────────────────────
  # G29b — the stored KPI note names the real cell too
  # ─────────────────────────────────────────────────────────

  # G29b — Happy path: an imported value from a sheet starting at column B notes column C (0-based 2) and cell C2
  @kpi_validation @rack_test
  Scenario: The note on an imported KPI names the value's cell when the sheet starts at column B
    Given the target KPIs are "Revenue"
    And a KPI workbook with sheet "MIS":
      |  | KPI     | May 2026 | Jun 2026 |
      |  | Revenue | 100      | 200      |
    When the workbook is imported for the KPI report
    Then the imported KPI "Revenue" as of "2026-05-31" has a note mentioning "Col: 2, Cell: C2"
    And the imported KPI "Revenue" as of "2026-06-30" has a note mentioning "Col: 3, Cell: D2"

  # ─────────────────────────────────────────────────────────
  # G33 — a computed KPI skips reports that hold none of its parts
  # ─────────────────────────────────────────────────────────

  # G33 — Happy path: computed where its parts are; a balance-sheet-only report (and the empty shell) are skipped without an error
  @rack_test
  Scenario: A computed KPI is skipped on reports that hold none of its components
    Given the target KPIs are "Revenue, Cost, Cash"
    And the computed KPI mapping "Gross Profit" has the formula "Revenue - Cost"
    And an approved KPI "Revenue" of 100.0 exists for "TestStartup" as of "2026-06-30" period "Quarter"
    And an approved KPI "Cost" of 40.0 exists for "TestStartup" as of "2026-06-30" period "Quarter"
    And an approved KPI "Cash" of 5.0 exists for "TestStartup" as of "2026-05-31" period "Month"
    When the computed KPI "Gross Profit" is computed
    Then the computation reports no errors
    And the KPI "Gross Profit" as of "2026-06-30" period "Quarter" has value 60.0

  # G33 — Error case: a report with only some of the parts is still an error, and names what is missing
  @rack_test
  Scenario: A computed KPI with only some of its components reports which are missing
    Given the target KPIs are "Revenue, Cost"
    And the computed KPI mapping "Gross Profit" has the formula "Revenue - Cost"
    And an approved KPI "Revenue" of 100.0 exists for "TestStartup" as of "2026-05-31" period "Month"
    When the computed KPI "Gross Profit" is computed
    Then the computation reports one error mentioning "missing Cost"

  # G33 — Edge case: a KPI name inside a longer one is not a component of its own ("Cash" in "Operating Cash Flow")
  @rack_test
  Scenario: A computed KPI is skipped on a report holding only a name that appears inside its formula's KPI
    Given the target KPIs are "Cash, Operating Cash Flow"
    And the computed KPI mapping "Burn" has the formula "Operating Cash Flow"
    And an approved KPI "Cash" of 5.0 exists for "TestStartup" as of "2026-05-31" period "Month"
    And an approved KPI "Operating Cash Flow" of -30.0 exists for "TestStartup" as of "2026-06-30" period "Quarter"
    When the computed KPI "Burn" is computed
    Then the computation reports no errors
    And the KPI "Burn" as of "2026-06-30" period "Quarter" has value -30.0

  # ─────────────────────────────────────────────────────────
  # G35 — a month range is the period it spans
  # ─────────────────────────────────────────────────────────

  # G35 — Happy path: Butterfly's "Apr - Mar'25" is the year FY24-25, not June 2025
  @kpi_validation @rack_test
  Scenario: A month range covering a year is read as the year
    Given the target KPIs are "Revenue"
    And a KPI workbook with sheet "P&L":
      | KPI     | Apr - Mar'25 | Apr - Mar'26 |
      | Revenue | 145274468.37 | 160000000    |
    When the workbook is validated for the KPI report
    Then the cell "P&L!B2" is read as a "Year" ending "2025-03-31"
    And the cell "P&L!B2" is stored as "145274468.37"

  # G35 — Edge case: a six-month range is a half year
  @kpi_validation @rack_test
  Scenario: A month range covering six months is read as a half year
    Given the target KPIs are "Revenue"
    And a KPI workbook with sheet "P&L":
      | KPI     | Oct-Mar 26 | Apr-Sep 26 |
      | Revenue | 100        | 200        |
    When the workbook is validated for the KPI report
    Then the cell "P&L!C2" is read as a "Half Year" ending "2026-09-30"

  # G35 — Error case: a range we do not store (two months) is ignored with a warning, not stored as a month
  @kpi_validation @rack_test
  Scenario: A two-month range is ignored with a warning
    Given the target KPIs are "Revenue"
    And a KPI workbook with sheet "P&L":
      | KPI     | May 2026 | Jun 2026 | Apr - May'26 |
      | Revenue | 100      | 200      | 300          |
    When the workbook is validated for the KPI report
    Then the validation has warning "unrecognized_period"
    And there is no validated cell "P&L!D2"
