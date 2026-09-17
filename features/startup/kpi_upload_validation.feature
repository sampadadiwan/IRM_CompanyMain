Feature: Server-side validation of portco KPI workbooks
  As a fund admin I want every uploaded KPI workbook checked on the server before it is saved
  As a portco user I want to see exactly how my file was read (raw → stored) before I submit
  So that formatting is interpreted, nothing becomes a silent 0, and the fund gets the period it asked for

  # Reference: docs/technical/kpi_portco_upload_validation_review.md (§2.1–§2.10 sign-offs, phase 1)

  Background:
    Given there is a user "first_name=FundAdmin" for an entity "name=VentureFund;entity_type=Investment Fund"
    And the fund entity has KPIs enabled
    And there is an existing portfolio company "name=TestStartup;category=Portfolio Company"
    And the portfolio company has an approved portco user "first_name=PortCoUser"
    And a KPI report shell exists for "TestStartup" as of "2026-06-30" with status "link_sent" and period "Month"

  # ─────────────────────────────────────────────────────────
  # §2.4 Number normalisation — interpret formatting, store the intended number
  # ─────────────────────────────────────────────────────────
  @kpi_validation
  Scenario: Formatted numbers are interpreted and stored as the intended values
    Given the target KPIs are "Revenue, EBITDA, Headcount, Cash"
    And a KPI workbook with sheet "MIS":
      | KPI       | May 2026   | Jun 2026     |
      | Revenue   | 1,200      | ₹ 12,50,000  |
      | EBITDA    | (500)      | $1.2M        |
      | Headcount | 45 L       | 2.5 Cr       |
      | Cash      | 1 200      | 500-         |
    When the workbook is validated for the KPI report
    Then the validation has no errors
    And the cell "MIS!B2" is stored as "1200"
    And the cell "MIS!C2" is stored as "1250000"
    And the cell "MIS!B3" is stored as "-500"
    And the cell "MIS!C3" is stored as "1200000"
    And the cell "MIS!B4" is stored as "4500000"
    And the cell "MIS!C4" is stored as "25000000"
    And the cell "MIS!B5" is stored as "1200"
    And the cell "MIS!C5" is stored as "-500"
    And the requested period is present with "4" KPIs filled

  @kpi_validation
  Scenario: Percent signs on a percentage KPI become fractions; an explicit unit overrides the mapping denomination
    Given the following KPI mappings with denominations exist for the portfolio company:
      | reported_kpi_name | denomination |
      | Revenue           | Crores       |
    And the KPI mapping "Gross Margin" exists with data type "percentage"
    And a KPI workbook with sheet "MIS":
      | KPI          | May 2026 | Jun 2026 |
      | Revenue      | 1.5      | 1.5 Cr   |
      | Gross Margin | 42%      | 0.41     |
    When the workbook is validated for the KPI report
    Then the validation has no errors
    And the cell "MIS!B2" is stored as "15000000"
    And the cell "MIS!C2" is stored as "15000000"
    And the validation has warning "unit_overrides_denomination"
    And the cell "MIS!B3" is stored as "0.42"
    And the cell "MIS!C3" is stored as "0.41"

  @kpi_validation
  Scenario: Excel error cells, ambiguous text and non-numbers are errors, placeholders are skipped with a warning
    Given the target KPIs are "Revenue, EBITDA, Headcount, Cash"
    And a KPI workbook with sheet "MIS":
      | KPI       | May 2026    | Jun 2026 |
      | Revenue   | #DIV/0!     | 100      |
      | EBITDA    | 10 (prev 8) | 100      |
      | Headcount | ten         | 100      |
      | Cash      | TBD         | 100      |
    When the workbook is validated for the KPI report
    Then the validation has error "excel_error_cell"
    And the validation has error "ambiguous_value"
    And the validation has error "non_numeric_value"
    And the validation has warning "placeholder_blank"
    And the cell "MIS!B2" has status "error"
    And the cell "MIS!B5" has status "skipped"
    And no KPI rows were written

  # ─────────────────────────────────────────────────────────
  # §2.5 The file must contain the period the fund asked for
  # ─────────────────────────────────────────────────────────
  @kpi_validation
  Scenario: Requested period missing from the file is a blocking error
    Given the target KPIs are "Revenue"
    And a KPI workbook with sheet "MIS":
      | KPI     | Apr 2026 | May 2026 |
      | Revenue | 100      | 110      |
    When the workbook is validated for the KPI report
    Then the validation has error "requested_period_missing"
    And the validation error "requested_period_missing" mentions "Jun 2026 (Month)"

  @kpi_validation
  Scenario: Requested period present but blank is a blocking error; partially blank is a warning
    Given the target KPIs are "Revenue, EBITDA"
    And a KPI workbook with sheet "MIS":
      | KPI     | May 2026 | Jun 2026 |
      | Revenue | 100      |          |
      | EBITDA  | 20       |          |
    When the workbook is validated for the KPI report
    Then the validation has error "requested_period_blank"
    Given a KPI workbook with sheet "MIS":
      | KPI     | May 2026 | Jun 2026 |
      | Revenue | 100      | 120      |
      | EBITDA  | 20       |          |
    When the workbook is validated for the KPI report
    Then the validation has no errors
    And the validation has warning "requested_period_partial"
    And the validation warning "requested_period_partial" mentions "EBITDA"

  @kpi_validation
  Scenario: A Quarter request answered with monthly columns is accepted with a warning about derivation
    Given the target KPIs are "Revenue"
    And a KPI report shell exists for "TestStartup" as of "2026-06-30" with status "link_sent" and period "Quarter"
    And a KPI workbook with sheet "MIS":
      | KPI     | Apr 2026 | May 2026 | Jun 2026 |
      | Revenue | 100      | 110      | 120      |
    When the workbook is validated for the KPI report
    Then the validation has no errors
    And the validation has warning "requested_period_derived"
    And the validation warning "requested_period_derived" mentions "Revenue"

  @kpi_validation
  Scenario: A file reference that names a storage other than the upload cache is refused
    Given the target KPIs are "Revenue"
    When a workbook reference with storage "store" is validated for the KPI report
    Then the validation has error "no_file"
    And the validation error "no_file" mentions "not valid"

  @kpi_validation
  Scenario: Other periods in the file are always imported and reported; changed approved values are flagged old → new
    Given the target KPIs are "Revenue"
    And an approved KPI "Revenue" of 100 exists for "TestStartup" as of "2026-05-31" period "Month"
    And a KPI workbook with sheet "MIS":
      | KPI     | Apr 2026 | May 2026 | Jun 2026 |
      | Revenue | 90       | 105      | 120      |
    When the workbook is validated for the KPI report
    Then the validation has no errors
    And the validation has warning "historic_periods_touched"
    And the validation has warning "historic_value_changed"
    And the cell "MIS!C2" is marked changed from "100" to "105"
    When the workbook is imported for the KPI report
    Then the approved KPI "Revenue" as of "2026-05-31" still has value 100
    And an unapproved KPI "Revenue" as of "2026-05-31" exists with value 105
    And an unapproved KPI "Revenue" as of "2026-04-30" exists with value 90

  @kpi_validation
  Scenario: Future Actual columns are ignored with a visible warning
    Given the target KPIs are "Revenue"
    And a KPI workbook with sheet "MIS":
      | KPI     | Jun 2026 | Dec 2027 |
      | Revenue | 100      | 999      |
    When the workbook is validated for the KPI report
    Then the validation has no errors
    And the validation has warning "future_period_skipped"
    And the cell "MIS!C2" has status "future"

  @kpi_validation
  Scenario: Fiscal-year labels follow the fund's month_offset_for_fy setting
    Given the target KPIs are "Revenue"
    And a KPI report shell exists for "TestStartup" as of "2025-12-31" with status "link_sent" and period "Year"
    And a KPI workbook with sheet "MIS":
      | KPI     | FY24 | FY25 |
      | Revenue | 100  | 120  |
    When the workbook is validated for the KPI report
    Then the validation has error "requested_period_missing"
    Given the fund's financial year starts in January
    When the workbook is validated for the KPI report
    Then the validation has no errors
    And the requested period is present with "1" KPIs filled

  @kpi_validation
  Scenario: Extra spacing around FY/CY tokens doesn't break period-type detection or import
    Given the target KPIs are "Revenue"
    And a KPI workbook with sheet "MIS":
      | KPI     | Q1 FY 25 | H1 FY 2023 | FY 20 - 21 |
      | Revenue | 140      | 200        | 300        |
    When the workbook is imported for the KPI report
    Then an unapproved KPI "Revenue" as of "2024-06-30" period "Quarter" exists with value 140
    And an unapproved KPI "Revenue" as of "2022-09-30" period "Half Year" exists with value 200
    And an unapproved KPI "Revenue" as of "2021-03-31" period "Year" exists with value 300

  @kpi_validation
  Scenario: With no explicit fiscal-year setting, the US deployment defaults to a January fiscal year
    Given the target KPIs are "Revenue"
    And a KPI report shell exists for "TestStartup" as of "2025-12-31" with status "link_sent" and period "Year"
    And the deployment is the "US" site with no fiscal-year override
    And a KPI workbook with sheet "MIS":
      | KPI     | FY24 | FY25 |
      | Revenue | 100  | 120  |
    When the workbook is validated for the KPI report
    Then the validation has no errors
    And the requested period is present with "1" KPIs filled

  @kpi_validation
  Scenario: With no explicit fiscal-year setting, the India deployment defaults to an April fiscal year
    Given the target KPIs are "Revenue"
    And a KPI report shell exists for "TestStartup" as of "2025-12-31" with status "link_sent" and period "Year"
    And the deployment is the "IN" site with no fiscal-year override
    And a KPI workbook with sheet "MIS":
      | KPI     | FY24 | FY25 |
      | Revenue | 100  | 120  |
    When the workbook is validated for the KPI report
    Then the validation has error "requested_period_missing"

  # ─────────────────────────────────────────────────────────
  # §2.6 Duplicates and hidden sheets
  # ─────────────────────────────────────────────────────────
  @kpi_validation
  Scenario: Same KPI on two rows with different values is an error; identical values are a warning
    Given the target KPIs are "Revenue"
    And a KPI workbook with sheet "MIS":
      | KPI     | May 2026 | Jun 2026 |
      | Revenue | 100      | 120      |
      | Notes   |          |          |
      | Revenue | 100      | 999      |
    When the workbook is validated for the KPI report
    Then the validation has error "duplicate_kpi_row"
    Given a KPI workbook with sheet "MIS":
      | KPI     | May 2026 | Jun 2026 |
      | Revenue | 100      | 120      |
      | Revenue | 100      | 120      |
    When the workbook is validated for the KPI report
    Then the validation has no errors
    And the validation has warning "duplicate_kpi_row_identical"

  @kpi_validation
  Scenario: Hidden sheets are skipped with a warning
    Given the target KPIs are "Revenue"
    And a KPI workbook with sheet "MIS":
      | KPI     | May 2026 | Jun 2026 |
      | Revenue | 100      | 120      |
    And the workbook also has a hidden sheet "Scratch":
      | KPI     | May 2026 | Jun 2026 |
      | Revenue | 1        | 2        |
    When the workbook is validated for the KPI report
    Then the validation has no errors
    And the validation has warning "hidden_sheet_skipped"
    And the cell "MIS!C2" is stored as "120"
    And there is no validated cell in sheet "Scratch"

  # ─────────────────────────────────────────────────────────
  # §2.7 No mappings, §2.3 header handling
  # ─────────────────────────────────────────────────────────
  @kpi_validation
  Scenario: A portco with no KPI mappings gets a blocking error, not a green tick
    Given a KPI workbook with sheet "MIS":
      | KPI     | May 2026 | Jun 2026 |
      | Revenue | 100      | 120      |
    When the workbook is validated for the KPI report
    Then the validation has error "no_mappings"

  @kpi_validation
  Scenario: Title rows above the header are fine; a file with no period header anywhere is an error
    Given the target KPIs are "Revenue"
    And a KPI workbook with sheet "MIS":
      | TestStartup MIS |          |          |
      | Prepared by CFO |          |          |
      | KPI             | May 2026 | Jun 2026 |
      | Revenue         | 100      | 120      |
    When the workbook is validated for the KPI report
    Then the validation has no errors
    And the cell "MIS!C4" is stored as "120"
    Given a KPI workbook with sheet "MIS":
      | KPI     | Notes | Comments |
      | Revenue | good  | stable   |
    When the workbook is validated for the KPI report
    Then the validation has error "no_header"

  @kpi_validation
  Scenario: A single-period sheet is accepted when the KPI names below the header match
    Given the target KPIs are "Revenue"
    And a KPI workbook with sheet "MIS":
      | KPI     | Jun 2026 |
      | Revenue | 120      |
    When the workbook is validated for the KPI report
    Then the validation has no errors
    And the validation has warning "single_period_header"
    And the cell "MIS!B2" is stored as "120"

  # ─────────────────────────────────────────────────────────
  # §2.9 Plausibility — warnings only
  # ─────────────────────────────────────────────────────────
  @kpi_validation
  Scenario: A value three orders of magnitude off the last approved figure warns about denomination but does not block
    Given the following KPI mappings with denominations exist for the portfolio company:
      | reported_kpi_name | denomination |
      | Revenue           | Crores       |
    And an approved KPI "Revenue" of 15000000 exists for "TestStartup" as of "2026-05-31" period "Month"
    And a KPI workbook with sheet "MIS":
      | KPI     | Jun 2026 |
      | Revenue | 16000000 |
    When the workbook is validated for the KPI report
    Then the validation has no errors
    And the validation has warning "denomination_suspect"

  # ─────────────────────────────────────────────────────────
  # §2.10 / §3.3 The verdict is stored and shown to the portco before saving
  # ─────────────────────────────────────────────────────────
  @kpi_validation @kpi_magic_link
  Scenario: The portco sees the server verdict and the raw → stored table before saving, and it is persisted on the report
    Given the target KPIs are "Revenue"
    When I open the KPI report edit page as the portco user via a valid signed link
    And I go to the "Upload & Validate KPIs" step of the KPI report wizard
    And I upload a KPI XLSX with a formatted revenue value for June 2026
    Then I should see "Workbook check"
    And I should see "How we read your file"
    And I should see "1,250,000"
    And I should see "You were asked for Jun 2026 (Month)"
    And I acknowledge all KPI warnings
    And I go to the "Additional Details" step of the KPI report wizard
    And the "Submit Report" button should be enabled
    And the KPI report has a stored validation result with "0" errors
