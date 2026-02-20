# KPI Workbook Upload User Guide

To ensure your KPI data is processed accurately and without errors, please follow these guidelines when preparing your Excel workbook for upload.

## 📋 KPI Upload Checklist

### 1. Workbook Structure & Layout
*   **Header Identification:** The system scans the first row of each sheet to find the header. Ensure your date headers (e.g., "Jan 2024", "Q1 FY24") are within these top 10 rows.
*   **Header Row Requirement:** A valid header row must contain at least **two** date-like values to be recognized.
*   **KPI Name Column:** Place your KPI names in one of the first column. The system automatically detects which column contains the KPI names by matching them against your configured target KPIs.
*   **Data Rows:** KPI values should be placed in the rows directly beneath the identified header row.

### 2. KPI Naming
*   **Matching:** KPI names are matched using a case-insensitive and space-insensitive method (e.g., "Gross Profit" will match "gross profit" or "GrossProfit").
*   **Consistency:** Ensure the KPI names in your Excel file exactly match the "Reported KPI Names" configured in your mapping settings.

### 3. Supported Period (Date) Formats
Your column headers should use one of the following recognized formats:
*   **Monthly:** `Jan 2024`, `January 2024`, `Sep 23`.
*   **Quarterly:** `Q1 FY24`, `Q3 CY22`, `JFM 2024` (Jan-Feb-Mar), `Jan-Mar 2024`.
*   **Fiscal/Calendar Year:** `FY 2023-24`, `FY2024`, `CY2024`, or just `2024`.
*   **Half-Year:** `H1 2023`, `H2 FY24`.
*   **Year-to-Date (YTD):** `YTD Nov 23`, `YTD Jan-Sept 2023`.
*   **Standard Dates:** `DD-MM-YYYY` or `DD/MM/YYYY`.

### 4. Data Values
*   **Numeric Values:** Ensure KPI values are numeric.
*   **Empty Cells:** Blank cells are skipped. If a KPI is not applicable for a period, you can leave it blank or use `n/a`.
*   **Duplicates:** Avoid having duplicate period headers (e.g., two columns both labeled "Jan 2024") in the same sheet, as the system will skip the duplicates.

### 5. Common Pitfalls to Avoid
*   **Hidden Rows/Columns:** While the system attempts to clean the file, it's best to avoid hidden rows or columns that might contain "ghost" data.
*   **Invalid Characters:** Avoid using special characters or non-numeric text in cells designated for KPI values (other than `na` or `n/a`).
*   **Sheet Selection:** The system processes **all sheets** in the workbook. Ensure all sheets follow the supported layout or do not contain conflicting data.
