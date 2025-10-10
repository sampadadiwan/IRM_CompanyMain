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
      | kpi_extraction/validation/all_found.xlsx    | All KPIs found.         | 5          | 0            |
      | kpi_extraction/validation/missing_kpis.xlsx | Missing KPIs: Returns%  | 4          | 1            |

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
      | kpi_extraction/validation/invalid_header.xlsx  | Invalid or missing header row in sheet 'Sheet1'. Expected date-like values (e.g., Jan 24, FY24, Q1FY25, H1FY25).      |
      | kpi_extraction/validation/no_kpi_names.xlsx    | Missing KPI names in sheet 'Sheet1'. The first column should contain KPI names.                                     |
      | kpi_extraction/validation/empty_sheet.xlsx     | Sheet 'Sheet1' is empty.                                                                                          |