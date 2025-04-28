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