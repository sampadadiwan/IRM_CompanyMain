# KPI Currency Conversion — Technical Design

## Overview

Adds automatic currency conversion to the KPI upload pipeline. When a portfolio company reports in a different currency (e.g., USD) than the fund's base currency (e.g., INR), uploaded KPI values are converted at upload time using configurable FX methods per KPI mapping.

## Architecture

### Conversion Pipeline

```
Excel Upload
    └─> KpiWorkbookReader#save_kpi_entry
            ├─> KpiValueNormalizer (denomination scaling) — existing
            ├─> KpiFxConverter.convert(kpi, mapping, portco, entity)
            │       ├─> Check: kpi_currency != entity.currency?
            │       ├─> Check: fx_conversion_method != "not_applicable"?
            │       ├─> Resolve FX rate (spot or average)
            │       ├─> kpi.original_value = value (pre-conversion)
            │       ├─> kpi.fx_rate_used = rate
            │       └─> kpi.value = value * rate
            └─> Kpi#save!
```

### Recompute Pipeline

```
FM clicks "Recompute FX Conversion"
    └─> KpiReportsController#recompute_fx
            └─> KpiCurrencyRecomputeJob.perform_later(portco_id, user_id)
                    └─> For each Kpi where original_value IS NOT NULL:
                            ├─> Re-resolve FX rate using current ExchangeRate table
                            ├─> kpi.value = original_value * new_rate
                            ├─> kpi.fx_rate_used = new_rate
                            └─> kpi.save!
```

### Currency Toggle (Client-Side)

```
Stimulus: kpi_currency_toggle_controller.js
    └─> toggle()
            ├─> Swap data-fund-value ↔ data-kpi-value on each cell
            ├─> Remove data-bs-original-title (Bootstrap stale tooltip)
            ├─> Update tooltip title (swap FX info)
            └─> Update button text (Fund ↔ KPI Currency)
```

## Data Model Changes

### Migration 1: `investor_kpi_mappings`

```ruby
# db/migrate/20260730070030_add_fx_conversion_method_to_investor_kpi_mappings.rb
add_column :investor_kpi_mappings, :fx_conversion_method, :string, default: 'not_applicable', null: false
```

**Enum on model:**
```ruby
enum :fx_conversion_method, {
  not_applicable: 'not_applicable',
  report_date: 'report_date',
  average_rate: 'average_rate'
}, prefix: true, default: :not_applicable
```

### Migration 2: `kpis`

```ruby
# db/migrate/20260730115611_add_currency_conversion_fields_to_kpis.rb
add_column :kpis, :original_value, :decimal, precision: 20, scale: 6
add_column :kpis, :fx_rate_used, :decimal, precision: 20, scale: 8
```

Both columns NULL by default — no overhead for same-currency portfolio companies.

### No migration for `kpi_currency`

Stored as `Investor.json_fields["kpi_currency"]` via existing `FormCustomField` system. If blank or nil, treated as same as `entity.currency` — no conversion occurs.

## Key Components

### KpiFxConverter (New Service)

**Path:** `app/packs/startups/kpis/services/kpi_fx_converter.rb`

Extracted from `KpiWorkbookReader` to be reusable by the recompute job.

**Key methods:**
- `convert(kpi, mapping, portfolio_company, entity)` — main entry point
- `resolve_fx_rate(method, from, to, as_of, period, entity)` — dispatches to spot or average
- `period_start_date(as_of, period)` — calculates opening date for average rate

**Average rate calculation:**
```
opening_rate = ExchangeRate.get_rate(from, to, period_start, entity_id)
closing_rate = ExchangeRate.get_rate(from, to, as_of, entity_id)
rate = (opening_rate + closing_rate) / 2.0   # Full float precision, no rounding
```

**Period start mapping:**

| KPI Report Period | Opening Date |
|---|---|
| Month | `as_of.beginning_of_month` |
| Quarter | `as_of.beginning_of_quarter` |
| Half Year | `as_of - 6.months + 1.day` |
| Year | `as_of.beginning_of_year` |
| YTD | `start_of_financial_year_date(as_of)` |

### KpiCurrencyRecomputeJob (New Job)

**Path:** `app/packs/startups/kpis/jobs/kpi_currency_recompute_job.rb`

- Inherits from `ApplicationJob` (Sidekiq, default queue)
- Recomputes all KPIs with `original_value IS NOT NULL` for a given portfolio company
- Skips KPIs where `original_value` is nil (manually edited or never converted)
- Uses `KpiFxConverter` for rate resolution
- Sends notification on completion via `ApplicationJob#send_notification`

### Smart Default Logic (InvestorKpiMapping)

**Callback:** `before_validation :set_default_fx_conversion_method, on: :create`

```ruby
def set_default_fx_conversion_method
  return if import_upload_id.present?         # Skip during bulk import (explicit value provided)
  return if fx_conversion_method_changed?     # Skip if explicitly set by FM
  return self.fx_conversion_method = 'not_applicable' if percentage?

  case category&.downcase
  when 'balance sheet'     then self.fx_conversion_method = 'report_date'
  when 'income statement'  then self.fx_conversion_method = 'average_rate'
  when 'cash flow'         then self.fx_conversion_method = 'average_rate'
  else                          self.fx_conversion_method = 'not_applicable'
  end
end
```

### Bulk Import (ImportInvestorKpiMapping)

**FX Conversion column handling:**
- Header normalization: `ImportUtil#get_headers` calls `.downcase.titleize` on all headers, so "FX Conversion" becomes "Fx Conversion" — hash key must match
- Friendly aliases via `FX_CONVERSION_ALIASES` constant:
  ```ruby
  FX_CONVERSION_ALIASES = {
    "na" => "not_applicable", "n/a" => "not_applicable", "none" => "not_applicable",
    "spot" => "report_date", "spot_rate" => "report_date",
    "average" => "average_rate", "avg" => "average_rate"
  }.freeze
  ```
- Blank/missing defaults to `"not_applicable"` for backward compatibility
- Invalid values raise descriptive error with valid options listed

**Denomination column:** Also accepts "NA"/"na" as blank (no denomination).

### Currency Toggle (Stimulus Controller)

**Path:** `app/javascript/controllers/kpi_currency_toggle_controller.js`

- Reads `data-fund-value` and `data-kpi-value` attributes set by ERB on each grid cell
- Toggle swaps displayed text content between the two values
- Removes `data-bs-original-title` attribute before updating Bootstrap tooltip to prevent stale tooltip bug
- Updates button label to show current viewing currency
- No server round-trip — purely client-side swap

### FX Tooltip (KpisHelper)

**Path:** `app/packs/startups/kpis/helpers/kpis_helper.rb`

- `fx_tooltip_wrap(content, kpi, mapping, portco, params:)` — wraps grid cell content with tooltip showing conversion details
- `fx_format_original_value(kpi, mapping, kpi_currency, params:)` — formats original value with denomination via `money_to_currency`
- Tooltip shows: original value in KPI currency, FX rate (4 decimal places), conversion method

## Exchange Rate Infrastructure (Existing — Reused)

| Component | Path | Purpose |
|---|---|---|
| `ExchangeRate` model | `app/packs/core/entities/models/exchange_rate.rb` | Stores `from→to` rates per `as_of` date, scoped by entity |
| `ExchangeRateShared` concern | `app/packs/core/entities/models/concerns/exchange_rate_shared.rb` | `convert()`, `get_rate()`, `latest_rates_before()` |
| `ImportExchangeRate` | `app/packs/core/entities/services/import_exchange_rate.rb` | CSV bulk import |
| `entity.currency` | Entity model | Fund's base currency (defaults to "INR") |

## Files Changed

### New Files
- `app/packs/startups/kpis/services/kpi_fx_converter.rb`
- `app/packs/startups/kpis/jobs/kpi_currency_recompute_job.rb`
- `app/javascript/controllers/kpi_currency_toggle_controller.js`
- `db/migrate/20260730070030_add_fx_conversion_method_to_investor_kpi_mappings.rb`
- `db/migrate/20260730115611_add_currency_conversion_fields_to_kpis.rb`

### Modified Files
- `app/packs/startups/kpis/models/investor_kpi_mapping.rb` — enum, smart default callback, import_upload_id guard
- `app/packs/startups/kpis/services/kpi_workbook_reader.rb` — delegates conversion to KpiFxConverter
- `app/packs/startups/kpis/services/import_investor_kpi_mapping.rb` — FX Conversion column parsing, aliases, denomination NA handling
- `app/packs/startups/kpis/helpers/kpis_helper.rb` — `fx_tooltip_wrap`, `fx_format_original_value` with denomination params
- `app/packs/startups/kpis/views/kpi_reports/_grid_view.html.erb` — recompute button, toggle setup
- `app/packs/startups/kpis/views/kpi_reports/_grid_view_table.html.erb` — toggle button in header, tooltip with params
- `app/packs/startups/kpis/views/kpi_reports/_grid_view_simple_table.html.erb` — toggle button, tooltip with params
- `app/packs/startups/kpis/views/kpi_reports/_budget_view_table.html.erb` — tooltip with params
- `app/packs/startups/kpis/controllers/kpi_reports_controller.rb` — `recompute_fx` action
- `app/packs/startups/kpis/views/investor_kpi_mappings/_form.html.erb` — FX Conversion dropdown
- `config/routes/startup.rb` — recompute_fx route
- `public/sample_uploads/investor_kpi_mappings.xlsx` — template with FX Conversion column

## Design Decisions

1. **`kpi_currency` on portco (Investor), not per-mapping** — a company reports in one currency
2. **`fx_conversion_method` on InvestorKpiMapping** — BS/P&L/OpMetrics need different methods
3. **Conversion at upload time, not display time** — post-processing (cumulation, compute) operates on converted values
4. **Store `original_value` + `fx_rate_used`** — enables recompute, audit, and "view in original currency"
5. **Convert to `entity.currency`, not fund.currency** — entities share one base currency across all funds
6. **Missing rate → store unconverted + log error** — graceful degradation
7. **Manual recompute only** — no auto-trigger on exchange rate changes (Product confirmed)
8. **Percentage/ratio KPIs always `not_applicable`** — 25% is 25% in any currency
9. **Average rate uses full float precision** — no rounding during computation; tooltip displays 4 decimal places

## Testing

### Local Testing (2026-09-17, verified)

- Portco "AX" (kpi_currency=USD), fund currency=INR
- Revenue $5M → ₹473,250,000 (avg rate 94.65 = (95.0 + 94.3) / 2) — average_rate correct
- Working Capital $3M → ₹282,900,000 (spot rate 94.3) — report_date correct
- `original_value` and `fx_rate_used` populated correctly
- Old KPIs (pre-feature) have NULL fields — no regression

### Staging Testing (2026-09-22, verified)

- Dashboard denomination applies correctly to currency-toggled values
- FX import with friendly aliases (na, spot, avg) works correctly
- Bulk import backward compatible (templates without FX Conversion column work unchanged)

### Cucumber Tests

Feature file: `features/startup/kpi_currency_conversion.feature`
Step definitions: `features/step_definitions/kpi_currency_conversion_steps.rb`
