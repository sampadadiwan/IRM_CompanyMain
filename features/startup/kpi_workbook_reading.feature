Feature: KPI Workbook Reading
  As a user
  I want to read KPI data from Excel workbooks
  So that I can analyze startup performance metrics accurately

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

  Scenario Outline: Generating a client-side KPI validation report from an uploaded workbook
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
      | kpi_extraction/validation/all_found.xlsx    | All 5 KPIs found.      | 5          | 0            |
      | kpi_extraction/validation/missing_kpis.xlsx | Missing: Returns%.     | 4          | 1            |

  Scenario Outline: Handling workbooks with structural errors during client-side validation
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
      | kpi_extraction/validation/invalid_header.xlsx  | Invalid or missing header row in sheet 'MIS'. Expected date-like values (e.g. Jan 24, FY24, Q1FY25). |
      | kpi_extraction/validation/empty_sheet.xlsx     | Sheet 'Sheet1' is empty  |

  Scenario: Future 'Actual' KPIs should not be imported
    Given there is a user "" for an entity "entity_type=Investment Fund"
    Given there is an existing portfolio company "name=MyFavStartup;category=Portfolio Company"
    Given the KPI workbook file "kpi_extraction/MIS sample.xlsx" for a "Actual" kpi report
    And the target KPIs are "Revenue"
    When the KpiWorkbookReader processes the file
    Then no KPI should be imported for future dates

  Scenario: Future 'Budget' KPIs should be imported
    Given there is a user "" for an entity "entity_type=Investment Fund"
    Given there is an existing portfolio company "name=MyFavStartup;category=Portfolio Company"
    Given the KPI workbook file "kpi_extraction/MIS sample.xlsx" for a "Budget" kpi report
    And the target KPIs are "Revenue"
    When the KpiWorkbookReader processes the file
    Then KPIs should be imported for future dates

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

  # --- New scenarios for KPI parser fixes (branch: feature/kpi-workbook-parser-fixes) ---

  Scenario: ACT/BUDGET/IC tag row creates separate KpiReports per tag
    Given there is a user "" for an entity "entity_type=Investment Fund"
    And there is an existing portfolio company "name=MyFavStartup;category=Portfolio Company"
    And the KPI workbook file "kpi_extraction/tag_columns.xlsx" for a "Actual" kpi report
    And the target KPIs are "Revenue, EBITDA"
    When the KpiWorkbookReader processes the file
    Then KPI reports should exist with tags "Actual, Budget, IC"
    And each tag should have KPI reports for the same periods

  Scenario: Indent-based parent-child detection creates child mappings
    Given there is a user "" for an entity "entity_type=Investment Fund"
    And there is an existing portfolio company "name=MyFavStartup;category=Portfolio Company"
    And the KPI workbook file "kpi_extraction/indent_children.xlsx" for a kpi report
    And the target KPIs are "Net Sales, Operating Cost"
    When the KpiWorkbookReader processes the file
    Then child mappings should be created under "Net Sales" with names "Enterprise, Mid-Market, SMB"
    And child mappings should be created under "Operating Cost" with names "Enterprise, Mid-Market"
    And the standard KPI name for "Enterprise" under "Net Sales" should be "Net Sales - Enterprise"
    And the standard KPI name for "Enterprise" under "Operating Cost" should be "Operating Cost - Enterprise"
    And child KPIs should have values imported for each child mapping

  Scenario: Column-based parent-child detection
    Given there is a user "" for an entity "entity_type=Investment Fund"
    And there is an existing portfolio company "name=MyFavStartup;category=Portfolio Company"
    And the KPI workbook file "kpi_extraction/column_children.xlsx" for a kpi report
    And the target KPIs are "Net Sales, Operating Cost"
    When the KpiWorkbookReader processes the file
    Then child mappings should be created under "Net Sales" with names "Enterprise, Mid-Market, SMB"
    And child mappings should be created under "Operating Cost" with names "Enterprise, Mid-Market"
    And child KPIs should have values imported for each child mapping

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
    And the KPI workbook file "kpi_extraction/indent_children.xlsx" for a kpi report
    And the target KPIs are "Net Sales"
    When the KpiWorkbookReader processes the file
    And I note the child mapping count under "Net Sales"
    When the KpiWorkbookReader processes the file again
    Then there should be no duplicate child mappings under "Net Sales"
