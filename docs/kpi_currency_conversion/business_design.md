# KPI Currency Conversion — Business Design

## Purpose

Funds that invest across currencies (e.g., an INR-denominated fund investing in a USD-reporting portfolio company) need KPI values automatically converted from the portfolio company's reporting currency to the fund's base currency. Without this, the fund manager must manually convert every KPI value before comparing performance across portfolio companies — error-prone and time-consuming.

## User Stories

### US-1: Configure FX Conversion Per KPI Mapping
**As a** fund manager,
**I want to** set an FX conversion method (Not Applicable / Spot Rate / Average Rate) on each KPI mapping,
**so that** the system knows which exchange rate to apply when importing KPI values.

**Acceptance criteria:**
- A new "FX Conversion" dropdown appears on the KPI mapping form (below Denomination)
- Three options: Not Applicable (default), Report Date (spot rate), Average Rate
- Smart defaults based on category:
  - Income Statement / Cash Flow → Average Rate
  - Balance Sheet → Report Date (spot rate)
  - Operating Metrics / Percentage → Not Applicable
- Smart default applies only on creation — editing the category later does not override the FM's explicit choice
- Bulk import supports the FX Conversion column with friendly aliases ("na", "n/a", "spot", "avg", etc.)

### US-2: Automatic Conversion on KPI Upload
**As a** fund manager,
**I want** KPI values to be automatically converted from the portfolio company's currency to my fund's base currency when I upload an Excel workbook,
**so that** all KPI values in the grid view are in a consistent currency without manual intervention.

**Acceptance criteria:**
- Conversion uses the exchange rate from the ExchangeRate table, scoped to the entity
- **Spot rate** (Report Date method): uses the rate on or closest before the KPI report's `as_of` date
- **Average rate** method: averages the opening rate (start of period) and closing rate (`as_of` date). Period start depends on the KPI report's period (Month → beginning of month, Quarter → beginning of quarter, YTD → start of financial year)
- Original value and FX rate used are stored for audit trail
- If the exchange rate is missing, the value is stored unconverted with an error logged — the FM can add the rate and re-upload
- Percentage/ratio KPIs are never converted (25% is 25% in any currency)

### US-3: View in KPI Currency (Toggle)
**As a** fund manager,
**I want to** toggle the KPI grid view between fund currency and the portfolio company's reporting currency,
**so that** I can review values in the original currency for verification or discussion with the portfolio company.

**Acceptance criteria:**
- A toggle button appears in the grid table header when the portfolio company has a different `kpi_currency` from the fund currency
- Button shows "Viewing: INR (Fund)" or "Viewing: USD (KPI Currency)"
- Toggling swaps displayed values between `kpi.value` (fund currency) and `kpi.original_value` (KPI currency)
- Tooltips update to show the converted value and FX rate information
- Toggle works on both the full grid view and the simple (non-fund) grid view
- Dashboard KPI widgets also respect the toggle
- Denomination (Millions/Crores/Lakhs) applies correctly to both fund and KPI currency views

### US-4: Recompute FX Conversion
**As a** fund manager,
**I want to** recompute all FX conversions for a portfolio company when exchange rates are corrected,
**so that** KPI values reflect accurate conversion without re-uploading the workbook.

**Acceptance criteria:**
- A "Recompute FX Conversion" button appears in the KPI grid view actions menu
- Clicking triggers a background job that recalculates all converted KPI values using current exchange rates
- Only KPIs that have `original_value` (i.e., were previously converted) are recomputed
- Manually edited values (where `original_value` was cleared) are skipped
- The FM sees a notification when recomputation completes
- Recompute is manual only — changing an exchange rate does not auto-trigger recomputation

## UI Behavior

### KPI Mapping Form
- "FX Conversion" dropdown positioned below the existing "Denomination" dropdown
- Options: Not Applicable, Report Date, Average Rate
- Visible for all entities (safe default "Not Applicable" for entities that don't need it)

### Grid View
- Currency toggle button in the table header, next to the "KPI" column label
- Button text dynamically shows the currently displayed currency
- Converted values show a tooltip on hover with: original value, FX rate, conversion method
- Toggle is client-side only (Stimulus controller) — no server round-trip
- Only appears when `kpi_currency` differs from fund currency

### Dashboard Widgets
- KPI key numbers widget respects the denomination setting in widget metadata
- Currency toggle applies when widget is viewed with currency toggle active

### Bulk Import
- New "FX Conversion" column in the KPI mapping import template
- Accepts: exact enum values ("not_applicable", "report_date", "average_rate") and friendly aliases ("NA", "N/A", "None", "Spot", "Spot Rate", "Average", "Avg")
- Blank or missing → defaults to "Not Applicable" (backward compatible with existing templates)
- "Denomination" column also accepts "NA" as blank (no denomination)

## Benefits

1. **Time savings** — eliminates manual currency conversion for cross-currency portfolio companies
2. **Accuracy** — uses system exchange rates consistently, avoiding manual conversion errors
3. **Audit trail** — original value and FX rate stored for verification
4. **Flexibility** — per-KPI conversion method respects accounting standards (IAS 21, AS 11, ASC 830)
5. **Backward compatible** — zero impact on same-currency portfolio companies (no conversion occurs, no new fields displayed)

## Accounting Standards Alignment

| Method | Standard | Use Case |
|--------|----------|----------|
| Spot rate (Report Date) | IAS 21 / AS 11 / ASC 830 | Balance sheet items — snapshot values at reporting date |
| Average rate | IAS 21 / AS 11 / ASC 830 | Income statement / cash flow items — accumulate over a period |
| Not applicable | — | Non-monetary KPIs (headcount, percentages, ratios) |
