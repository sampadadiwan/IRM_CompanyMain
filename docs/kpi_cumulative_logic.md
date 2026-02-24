# KPI Cumulative Calculation Logic: YTD and Year

This document explains the calculation logic for **Year-to-Date (YTD)** and **Year** (Annual) cumulative KPI values as implemented in [`kpi_cumulative.rb`](app/packs/startups/kpis/models/concerns/kpi_cumulative.rb).

## 1. Data Source
Calculations are based on monthly "Actual" KPI data. The system fetches these records using the following criteria:
- **KPI Name**: Matches the target KPI.
- **Portfolio Company**: Matches the target company.
- **Tag**: Must have the `Actual` tag.
- **Period**: Must be `Month`.
- **Status**: Must be `approved`.

## 2. Fiscal Year Grouping
The logic uses the `fiscal_year_key` method to group monthly data into fiscal years.
- It determines the start of the financial year based on the entity's settings.
- **Default Boundary**: If not explicitly set, the fiscal year starts on **April 1st** (`month_offset_for_fy = 3`).
- **Grouping Logic**:
  - Dates from **January to March** belong to the *previous* calendar year's fiscal year.
  - Dates from **April to December** belong to the *current* calendar year's fiscal year.
  - *Example*: `2023-01-31` belongs to FY 2022, while `2023-04-30` belongs to FY 2023.

## 3. Calculation Modes
The calculation behavior depends on the `cumulate` mode defined in the KPI's mapping:

### A. Summation Mode (`:cumulate`)
This is the most common mode, used for flow variables like Revenue or Expenses.

#### Year-to-Date (YTD)
For every month available in the fiscal year, a YTD record is created:
1. The monthly records within a fiscal year are sorted chronologically.
2. For each month, the YTD value is the **sum of all monthly values from the start of the fiscal year up to that month**.
   - *Example*: June YTD = (April Value + May Value + June Value).
3. A `KpiReport` with period `YTD` is created or updated for that specific month's `as_of` date.

#### Year (Annual Cumulative)
The `Year` period represents the total for the entire fiscal year.
1. The system checks if **exactly 12 monthly records** exist within the **same fiscal year**.
2. If all 12 months are present, it takes the final YTD sum (sum of all 12 months).
3. A `KpiReport` with period `Year` is created or updated using the `as_of` date of the 12th month.

**Common Pitfall**: If your data spans a calendar year (e.g., Jan 2023 to Dec 2023) but the fiscal year starts in April, the records will be split across two different fiscal years (FY 2022 and FY 2023), and neither will have the required 12 records to trigger a `Year` cumulative.

### B. Forward Fill Mode (`:forward_fill`)
Used for state variables or snapshots like Headcount or Cash Balance.

#### Year-to-Date (YTD)
Instead of summing, the system takes the **latest available monthly value** in the fiscal year.
1. It identifies the last chronologically recorded month in the fiscal year.
2. The value of this last month is applied as the `YTD` value.

#### Year (Annual)
The `forward_fill` logic currently focuses on YTD updates; if a specific `Year` period record is needed, it typically follows the same "last value" logic if triggered.

## 4. Persistence Logic
Both calculations utilize the `process_cumulative_kpi` helper:
- **Find or Create**: It looks for an existing `KpiReport` for the specific `period` ('YTD' or 'Year'), `as_of` date, and `entity`. If missing, it creates one.
- **Update**: It finds or initializes the `Kpi` record within that report.
- **Optimization**: It only saves the record if the value has changed or if the `force` flag is enabled.
- **Notes**: Records are tagged with "Auto-generated YTD cumulative" or "Auto-generated Year cumulative".
