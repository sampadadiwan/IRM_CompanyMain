Feature: KPI Workbook Reading
  As a user
  I want to read KPI data from Excel workbooks
  So that I can analyze startup performance metrics accurately

  @rack_test
  Scenario Outline: Extracting specific KPIs from various workbooks
    Given there is a user "" for an entity "entity_type=Investment Fund"
    Given there is an existing portfolio company "name=MyFavStartup;category=Portfolio Company"
    Given the KPI workbook file "<workbook_file>" for a kpi report
    And the target KPIs are "<target_kpis>"
    When the KpiWorkbookReader processes the file
    Then the extracted KPI data should be valid for the given workbook and targets with "<count>"

    # Note: The 'Then' step requires specific implementation in the step definition.
    # This implementation should:
    # 1. Instantiate KpiWorkbookReader with the file and target KPIs.
    # 2. Call extract_kpis.
    # 3. Load expected data corresponding to the "<workbook_file>" (e.g., from fixtures or helper methods).
    # 4. Assert that the extracted data matches the expected data structure and values.

    Examples:
      | workbook_file                   | target_kpis                                                                          | count |
      | kpi_extraction/MIS sample.xlsx  | Revenue, Number of Distributors, Net Current Assets, Orders MoMGrowth, Returns%      | 17 |
      | kpi_extraction/MIS Sample2.xlsx | Revenue from operations, Gross Profit, EBITDA  | 8 |
      | kpi_extraction/MIS Sample3.xlsx | Number of customers, Opex, Gross NPA           | 8 |
      | kpi_extraction/Fintech MIS.xlsx | Loans Disbursed, Net Income, Numberof customers| 8 |
      # Add more example rows with different files or target KPI combinations as needed

  Scenario Outline: Generating a server-side KPI validation report from an uploaded workbook
    Given Im logged in as a user "" for an entity "entity_type=Investment Fund"
    Given the user has role "company_admin"
    And there is an existing portfolio company "name=MyFavStartup;category=Portfolio Company"
    And the following KPI mappings exist for the portfolio company:
      | reported_kpi_name       |
      | Revenue                 |
      | Number of Distributors  |
      | Net Current Assets      |
      | Orders MoMGrowth        |
      | Returns%                |
    And I am on the KPI upload page for the portfolio company
    When I upload the kpi workbook "<workbook_file>" for validation
    Then I should see a validation report with the message "<message>"
    And the report should list "<found_kpis>" found KPIs
    And the report should list "<missing_kpis>" missing KPIs

    Examples:
      | workbook_file                               | message                 | found_kpis | missing_kpis |
      | kpi_extraction/validation/all_found.xlsx    | 5 of 5 expected KPIs found | 5          | 0            |
      | kpi_extraction/validation/missing_kpis.xlsx | Returns%          | 4          | 1            |

  # invalid_header.xlsx has a blank row above the header: the old browser check (row 1 only) rejected
  # it, the server reads the header on row 2 — a valid file, and the panel must say so.
  Scenario Outline: Handling workbooks with structural quirks during server-side validation
    Given Im logged in as a user "" for an entity "entity_type=Investment Fund"
    Given the user has role "company_admin"
    And there is an existing portfolio company "name=MyFavStartup;category=Portfolio Company"
    And the following KPI mappings exist for the portfolio company:
      | reported_kpi_name       |
      | Revenue                 |
    And I am on the KPI upload page for the portfolio company
    When I upload the kpi workbook "<workbook_file>" for validation
    Then I should see a validation error with the message "<error_message>"

    Examples:
      | workbook_file                                  | error_message                                                                                                     |
      | kpi_extraction/validation/invalid_header.xlsx  | 1 of 1 expected KPIs found |
      | kpi_extraction/validation/empty_sheet.xlsx     | Sheet 'Sheet1' is empty  |

  Scenario: Future 'Actual' KPIs should not be imported
    Given there is a user "" for an entity "entity_type=Investment Fund"
    Given there is an existing portfolio company "name=MyFavStartup;category=Portfolio Company"
    Given the KPI workbook file "kpi_extraction/MIS sample.xlsx" for a "Actual" kpi report
    And the target KPIs are "Revenue"
    When the KpiWorkbookReader processes the file
    Then no KPI should be imported for future dates

  @rack_test
  Scenario: Future 'Budget' KPIs should be imported
    Given there is a user "" for an entity "entity_type=Investment Fund"
    Given there is an existing portfolio company "name=MyFavStartup;category=Portfolio Company"
    Given the KPI workbook file "kpi_extraction/MIS sample.xlsx" for a "Budget" kpi report
    And the target KPIs are "Revenue"
    When the KpiWorkbookReader processes the file
    Then KPIs should be imported for future dates

  @rack_test
  Scenario: KPI import with denominations
    Given there is a user "" for an entity "entity_type=Investment Fund"
    And there is an existing portfolio company "name=MyFavStartup;category=Portfolio Company"
    And the following KPI mappings with denominations exist for the portfolio company:
      | reported_kpi_name | denomination |
      | Revenue           | Millions     |
      | Net Profit        | Crores       |
      | Expenses          | Lakhs        |
      | Customers         | Thousands    |
    And the KPI workbook file "kpi_extraction/denomination_test.xlsx" for a kpi report
    When the KpiWorkbookReader processes the file
    Then the KPI "Revenue" should have a value of 10000000.0
    And the KPI "Net Profit" should have a value of 50000000.0
    And the KPI "Expenses" should have a value of 200000.0
    And the KPI "Customers" should have a value of 5000.0

  Scenario: Refresh should re-run kpi workbook job and update KPIs
    Given Im logged in as a user "" for an entity "entity_type=Investment Fund"
    Given the user has role "company_admin"
    Given there is an existing portfolio company "name=MyFavStartup;category=Portfolio Company"
    Given the KPI workbook file "<workbook_file>" for a kpi report
    And the target KPIs are "<target_kpis>"
    When the KpiWorkbookReader processes the file
    Then the extracted KPI data should be valid for the given workbook and targets with "<count>"

    Given I note the kpi values for the target KPIs
    And I add new target KPIs "EBITDA, COD %"
    Given I update the KPI workbook file to "<workbook_file2>"
    Then I go to the kpi report page
    And I click "Refresh"
    And I click "Proceed"
    Then the KPI data should be updated with the new values

    Examples:
      | workbook_file                   | workbook_file2                   | target_kpis                                                                          | count |
      | kpi_extraction/MIS sample.xlsx  | kpi_extraction/MIS sample1_refresh.xlsx | Revenue, Number of Distributors, Net Current Assets, Orders MoM Growth, Returns%      | 17 |

  # --- Scenarios for KPI parser fixes ---
  # Changed in feature/kpi-multi-column-detection: the parser no longer auto-creates
  # child InvestorKpiMapping records from indent/column layout (supersedes PR #1560).
  # All parent-child mappings must be pre-configured via bulk import. Scenarios below
  # reflect this: they set up mappings explicitly and assert value import, not mapping creation.

  # Scenario: ACT/BUDGET/IC tag row
  # The fixture tag_columns.xlsx has raw tag labels "ACT", "BUDGET", "IC" in the tag row.
  # Before Fix 12 (PR #1574), TAG_SYNONYMS mapped these to canonical values ("Actual", "Budget", "IC").
  # After Fix 12, the parser preserves original Excel text — so "ACT" stays "ACT", not "Actual".
  # The "Actual" tag in the expected list comes from the report-level fallback tag (set in test setup).
  # Expected tags updated from "Actual, Budget, IC" to "ACT, Actual, BUDGET, IC" to match new behavior.
  @rack_test
  Scenario: ACT/BUDGET/IC tag row creates separate KpiReports per tag
    Given there is a user "" for an entity "entity_type=Investment Fund"
    And there is an existing portfolio company "name=MyFavStartup;category=Portfolio Company"
    And the KPI workbook file "kpi_extraction/tag_columns.xlsx" for a "Actual" kpi report
    And the target KPIs are "Revenue, EBITDA"
    When the KpiWorkbookReader processes the file
    Then KPI reports should exist with tags "ACT, Actual, BUDGET, IC"
    And each tag should have KPI reports for the same periods

  @rack_test
  Scenario: Pre-configured parent-child mappings import values from indented Excel
    Given there is a user "" for an entity "entity_type=Investment Fund"
    And there is an existing portfolio company "name=MyFavStartup;category=Portfolio Company"
    And the following parent-child KPI mappings exist for the portfolio company:
      | parent_name    | reported_kpi_name |
      |                | Net Sales         |
      | Net Sales      | Enterprise        |
      | Net Sales      | Mid-Market        |
      | Net Sales      | SMB               |
      |                | Operating Cost    |
      | Operating Cost | Enterprise        |
      | Operating Cost | Mid-Market        |
    And the KPI workbook file "kpi_extraction/indent_children.xlsx" for a kpi report
    When the KpiWorkbookReader processes the file
    Then KPI values should be imported for mapping "Net Sales - Enterprise"
    And KPI values should be imported for mapping "Net Sales - Mid-Market"
    And KPI values should be imported for mapping "Net Sales - SMB"
    And KPI values should be imported for mapping "Operating Cost - Enterprise"
    And KPI values should be imported for mapping "Operating Cost - Mid-Market"
    And the KPI for mapping "Net Sales - Enterprise" should have value 500.0
    And the KPI for mapping "Operating Cost - Enterprise" should have value 400.0

  @rack_test
  Scenario: Pre-configured parent-child mappings import values from column-based Excel
    Given there is a user "" for an entity "entity_type=Investment Fund"
    And there is an existing portfolio company "name=MyFavStartup;category=Portfolio Company"
    And the following parent-child KPI mappings exist for the portfolio company:
      | parent_name    | reported_kpi_name |
      |                | Net Sales         |
      | Net Sales      | Enterprise        |
      | Net Sales      | Mid-Market        |
      | Net Sales      | SMB               |
      |                | Operating Cost    |
      | Operating Cost | Enterprise        |
      | Operating Cost | Mid-Market        |
    And the KPI workbook file "kpi_extraction/column_children.xlsx" for a kpi report
    When the KpiWorkbookReader processes the file
    Then KPI values should be imported for mapping "Net Sales - Enterprise"
    And KPI values should be imported for mapping "Net Sales - Mid-Market"
    And KPI values should be imported for mapping "Net Sales - SMB"
    And KPI values should be imported for mapping "Operating Cost - Enterprise"
    And KPI values should be imported for mapping "Operating Cost - Mid-Market"

  @rack_test
  Scenario: Apostrophe date format parsing
    Given there is a user "" for an entity "entity_type=Investment Fund"
    And there is an existing portfolio company "name=MyFavStartup;category=Portfolio Company"
    And the KPI workbook file "kpi_extraction/apostrophe_dates.xlsx" for a kpi report
    And the target KPIs are "Revenue"
    When the KpiWorkbookReader processes the file
    Then KPI reports should be created for months "2025-04-30, 2025-05-31, 2025-06-30"


  Scenario: Re-upload with parent-child KPIs is idempotent
    Given there is a user "" for an entity "entity_type=Investment Fund"
    And there is an existing portfolio company "name=MyFavStartup;category=Portfolio Company"
    And the following parent-child KPI mappings exist for the portfolio company:
      | parent_name    | reported_kpi_name |
      |                | Net Sales         |
      | Net Sales      | Enterprise        |
      | Net Sales      | Mid-Market        |
      | Net Sales      | SMB               |
    And the KPI workbook file "kpi_extraction/indent_children.xlsx" for a kpi report
    When the KpiWorkbookReader processes the file
    And I note the KPI count for the portfolio company
    When the KpiWorkbookReader processes the file again
    Then the KPI count should not have increased
