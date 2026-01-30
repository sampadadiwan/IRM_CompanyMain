# KPI Cumulation & Aggregation Requirements

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
- **Implementation**: Simple arithmetic (+, -, *, /) using `eval`. Formulas may reference other KPIs by name (e.g., `[Revenue] - [Cost]`).

## Technical Components
- **Model**: `InvestorKpiMapping` now has `cumulate` (enum) and `cumulate_formula` (string).
- **Concern**: `KpiCumulative` needs to implement these 3 distinct logics.
- **Job**: `KpiCumulateJob` coordinates the execution, ensuring `Compute` runs last.
