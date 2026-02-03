# KPI Budget View - User Guide

The KPI Budget View provides a comprehensive comparison table for Key Performance Indicators (KPIs) across different time periods and reporting tags. It allows you to analyze performance against budgets, internal cases, or any other custom reporting scenarios.

## Accessing the View
1. Navigate to the **KPI Reports** section.
2. Ensure the **Budget View** toggle or option is enabled.
3. Select the desired Portfolio Company to view its data.

## Filter Parameters

The filter bar at the top allows you to customize the data displayed in the grid. Below are the available parameters:

### 1. No of Periods
- **Description**: Determines how many historical time periods to display in the table.
- **Default**: 2
- **Usage**: Enter a number (e.g., "4" to see the last 4 quarters or months). The system will fetch the most recent unique reporting dates across all selected tags.

### 2. Category
- **Description**: Filters the displayed KPIs based on their assigned category (e.g., Financial, Operational, ESG).
- **Usage**: Select a category from the dropdown to narrow down the "Particulars" column. Leave blank to see all mapped KPIs.

### 3. Period
- **Description**: Sets the time frequency for the report.
- **Options**:
    - **Month**: View reports grouped by individual months.
    - **Quarter**: View reports grouped by quarters (e.g., Mar, Jun, Sep, Dec).
    - **Year**: View annual performance reports.
    - **YTD**: View Year-to-Date cumulative reports.

### 4. Units
- **Description**: Scales the numeric values in the table for better readability.
- **Options**: Crores, Lakhs, or Million.
- **Usage**: Select a unit to automatically convert the raw data values.

### 5. Tags
- **Description**: A multi-select field that determines which reporting scenarios to display side-by-side.
- **Common Tags**: Actual, Budget, IC Case, Audited Financials.
- **Usage**: You can select multiple tags. The table will create a sub-column for each tag under every reporting date.
- **Comparison Logic**: If you select **exactly two tags**, the system will automatically generate a **Ratio/Achievement Column** (e.g., "Actual / Budget"). This column calculates the percentage difference between the first and second selected tags.

## Understanding the Table

### Particulars
This column lists the names of the KPIs being tracked. If a mapping exists, the name may be clickable, leading to the detailed mapping configuration for that KPI.

### Time Period Headers
The top headers show the selected Period type and the specific reporting dates (e.g., "Mar-24").

### Reporting Tags
Under each date, you will see sub-columns for each tag you selected in the filter.
- If data exists for a tag, it is displayed according to the selected units.
- If data is missing for a specific tag in a period, the cell remains blank, but the period is still shown if other tags have data.

### Achievement / Ratio Column
When two tags are selected for comparison:
- **Calculation**: (Tag 1 Value / Tag 2 Value) * 100
- **Blank Ratios**: If either of the two tags is missing data for a specific period, the achievement cell will be blank, as a valid comparison cannot be performed.
- **Negative Values**: Values that are negative (e.g., loss or negative growth) are highlighted in **red** for quick identification.

## Actions

### Filter
Click the **Filter** button to apply your changes and refresh the grid.

### Export Visible
Click the **Export Visible** button to download the current view (as filtered) into an Excel file. The exported file will maintain the structure of the grid, including all periods and tags currently visible on your screen.
