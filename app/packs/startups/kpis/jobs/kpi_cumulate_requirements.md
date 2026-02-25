# KPI AutoFill & Aggregation Requirements

## Objective

Update the KPI cumulation logic to support different modes of data aggregation and calculation across time periods (Monthly -> Quarterly/YTD).

## Modes

### 1. Blank (Default)

- No automated aggregation or filling is performed.
- Only values explicitly uploaded or entered will exist.

### 2. Cumulate

- **Logic**: Summation of monthly values within the period.
- **Scope**: Actuals only.
- **Application**: Quarterly (Sum of 3 months) and YTD (Sum of months since start of Fiscal Year).

### 3. Forward Fill

- **Logic**: Pick the value of the last available month within the period.
- **Condition**: Only fill if the target period (Quarterly/YTD) does not already have a value.
- **Example**: If March has a value, use it for Q1. If March is missing but February has a value, use February.

### 4. Compute

- **Logic**: Use a mathematical formula defined in `investor_kpi_mapping.cumulate_formula`.
- **Condition**: Only compute if the value is not already present on the upload file.
- **Execution**: Must run **last**, after all 'Cumulate' and 'Forward Fill' operations are completed, to allow formulas to depend on aggregated values.
- **Implementation**: Simple arithmetic (+, -, \*, /) using `eval`. Formulas may reference other KPIs by name (e.g., `Revenue - Cost`).

## KPI Visibility & Approval Handling

- **Grid View Table**: In `app/packs/startups/kpis/views/kpi_reports/_grid_view_table.html.erb`, the visibility of KPIs depends on the `view_unapproved` parameter.
- **Approved vs. Unapproved**:
  - By default (or when `view_unapproved` is not 'true'), only **approved** KPIs are displayed.
  - If `view_unapproved=true`, **both** approved and unapproved KPIs for the same date and name are displayed in the same cell.
  - Unapproved KPIs are marked with a "Pending" badge, yellow text/border, and an "Approve" button (permission permitting).
  - Multiple KPIs in a cell are separated by a horizontal line.

## Technical Components

- **Model**: `InvestorKpiMapping` now has `autofill` (enum) and `compute_formula` (string).
- **Concern**: `KpiCumulative` needs to implement these 3 distinct logics.
- **Job**: `KpiCumulateJob` coordinates the execution, ensuring `Compute` runs last.
