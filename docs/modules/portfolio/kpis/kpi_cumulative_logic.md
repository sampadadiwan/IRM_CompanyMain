# KPI Cumulative Calculation Logic: Quarterly, YTD, and Year

This document explains the calculation logic for **Quarterly**, **Year-to-Date (YTD)**, and **Year** (Annual) cumulative KPI values as implemented in [`kpi_cumulative.rb`](app/packs/startups/kpis/models/concerns/kpi_cumulative.rb).

## 1. Data Source

Calculations are based on monthly "Actual" KPI data. The system fetches these records using the following criteria:

- **KPI Name**: Matches the target KPI.
- **Portfolio Company**: Matches the target company.
- **Tag**: Must have the `Actual` tag (verified via `tag_list` on the `KpiReport`).
- **Period**: Must be `Month`.
- **Status**: Must be `approved`.

## 2. Fiscal Year Grouping

Monthly data is grouped into fiscal years by `KpiCumulationPlanner`, using `KpiDateUtils.fiscal_year_start`.

- The fiscal year start month comes from `KpiDateUtils.resolve_fiscal_year_start_month`: the portfolio company's setting first, then the entity setting, then the regional default.
- **Default Boundary**: If not set anywhere, the fiscal year starts in **April** on the India server and **January** on the US server.
- **Grouping Logic**: Dates are grouped by the start date of their fiscal year (e.g., 1 April 2024 for FY 2024-25).

## 3. Calculation Modes

The calculation behavior depends on the `autofill` mode defined in the KPI's mapping:

### A. Summation Mode (`:cumulate`)

Used for flow variables like Revenue or Expenses.

#### Quarterly
1. Monthly records are grouped by calendar quarter.
2. The value is the **sum of all monthly values within that quarter**.
3. A `KpiReport` with period `Quarter` is created/updated for the quarter's end date (e.g., March 31, June 30).

#### Year-to-Date (YTD)
For every month available in the fiscal year, a YTD record is created:
1. Monthly records within a fiscal year are sorted chronologically.
2. For each month, the YTD value is the **sum of all monthly values from the start of the fiscal year up to that month**.
3. A `KpiReport` with period `YTD` is created or updated for that specific month's `as_of` date.

#### Year (Annual Cumulative)
The `Year` period represents the total for the entire fiscal year.
1. The system checks if **exactly 12 monthly records** exist within the **same fiscal year**.
2. If all 12 months are present, it takes the final YTD sum.
3. A `KpiReport` with period `Year` is created or updated using the `as_of` date of the 12th month.

### B. Forward Fill Mode (`:forward_fill`)

Used for state variables or snapshots like Headcount or Cash Balance.

#### Quarterly
- Takes the **latest available monthly value** within the calendar quarter and applies it to the `Quarter` report.

#### Year-to-Date (YTD)
- Takes the **latest available monthly value** in the fiscal year and applies it to the `YTD` report for that date.

### C. Computation Mode (`:compute`)

Used for calculated KPIs (e.g., "Gross Margin %" or "Burn Rate").

1. **Formula Evaluation**: Uses a `compute_formula` defined in the KPI mapping (e.g., `Revenue - Cost`).
2. **Context**: Evaluates the formula within the context of an existing `KpiReport` (Quarterly or YTD).
3. **Variable Replacement**: Replaces KPI names in the formula with their actual values from that same report.
4. **Safety**: Only allows numbers and standard math operators (`+`, `-`, `*`, `/`, `.`, `(`, `)`).

## 4. Persistence Logic

Both calculations utilize the `process_cumulative_kpi` helper:

- **Find or Create**: It looks for an existing `KpiReport` for the specific `period`, `as_of` date, and `entity`. If missing, it creates one.
- **Update**: It finds or initializes the `Kpi` record within that report.
- **Optimization**: It only saves the record if the value has changed (checked with 6 decimal places of precision) or if the `force` flag is enabled.
- **Notes**: Records are tagged with notes like "Auto-generated Quarter cumulative", "Auto-generated YTD cumulative", "Auto-generated Forward Fill", or "Auto-generated Computed".
