# Dashboard Widgets User Guide

This guide explains how to configure each available dashboard widget, including all supported metadata options.

## Contents

- [How Widgets Work](#how-widgets-work)
- [Setting Up a Widget](#setting-up-a-widget)
- [Widget Reference by Dashboard](#widget-reference-by-dashboard)
  - [Fund Dashboard](#fund-dashboard)
  - [Investor Dashboard](#investor-dashboard)
  - [Portfolio Company Dashboard](#portfolio-company-dashboard)
  - [Portfolio Dashboard](#portfolio-dashboard)
  - [Aggregated Portfolio Dashboard](#aggregated-portfolio-dashboard)
  - [FM Landing Page](#fm-landing-page)
  - [LP Landing Page](#lp-landing-page)
  - [Ops Dashboard](#ops-dashboard)

---

## How Widgets Work

Each dashboard is made up of configurable widgets. You can add, reorder, enable, or disable widgets per fund/entity. Widgets can be customised via **metadata** — a Ruby-hash-style string that controls display options.

**Metadata format example:**
```ruby
{months: 36, chart_type: 'bar', series: 'Collected Capital'}
```

Strings must use single quotes. Boolean values are `true`/`false` (no quotes). Arrays use `['Item1', 'Item2']`.

---

## Setting Up a Widget

1. Navigate to **Settings → Dashboard Widgets** for the relevant fund or entity.
2. Click **New Widget** or edit an existing one.
3. Select the **Dashboard** from the dropdown.
4. Select the **Widget Name** — the form will display sample metadata for the selected widget.
5. Optionally enter **Metadata** to customise the widget's behaviour.
6. Set **Size** (XS / Small / Medium / Large / XL) to control the column width.
7. Set **Position** to control the display order.
8. **Enable** the widget to make it visible.

---

## Widget Reference by Dashboard

---

### Fund Dashboard

---

#### Fund Stats
- **Path:** `funds/fund_stats`
- **Size:** XL
- **Description:** Displays high-level statistics for the fund.
- **Metadata:** None required.

---

#### Fund Card
- **Path:** `funds/card`
- **Size:** XL
- **Description:** Shows the fund summary card with key details.
- **Metadata:** None required.

---

#### Fund Ratios
- **Path:** `funds/widgets/fund_ratios`
- **Size:** Medium
- **Description:** Displays fund performance ratios (XIRR, TVPI, DPI, etc.) as a list and/or chart.

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `title` | String | — | Custom title shown above the widget |
| `scenario` | String | `'Default'` | The scenario to use for ratio calculations |
| `condensed` | Boolean | `false` | Show a condensed/compact view |
| `chart` | Boolean | `true` | Show the chart view |
| `list` | Boolean | `true` | Show the list/table view |
| `months` | Integer | — | Number of months of history to display |
| `ratio_names` | Array | all | Which ratios to show, e.g. `['XIRR', 'TVPI', 'DPI']` |

**Example:**
```ruby
{title: 'Performance', scenario: 'Default', condensed: true, chart: false, list: true, months: 12, ratio_names: ['XIRR', 'TVPI', 'DPI']}
```

---

#### Fund Cashflows
- **Path:** `funds/widgets/fund_cashflows`
- **Size:** Medium
- **Description:** Bar/line chart of fund cashflow series over time.

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `months` | Integer | `36` | Number of months of history to display |
| `series` | String | all | Comma-separated series names to include, e.g. `'Collected Capital, Portfolio Investments'` |
| `chart_type` | String | `'bar'` | Chart style: `line`, `bar`, `area`, or `spline` |

**Example:**
```ruby
{months: 36, series: 'Collected Capital, Portfolio Investments', chart_type: 'line'}
```

---

#### Fund Distributions
- **Path:** `funds/widgets/fund_distributions`
- **Size:** Medium
- **Description:** Summary of fund-level distributions.
- **Metadata:** None required.

---

#### Fund Account Entries
- **Path:** `funds/widgets/fund_account_entries`
- **Size:** Medium
- **Description:** Lists account entries for the fund.
- **Metadata:** None required.

---

#### Fund Portfolios
- **Path:** `aggregate_portfolio_investments/widgets/portfolio_investments`
- **Size:** XL
- **Description:** Full portfolio investments table for the fund.
- **Metadata:** See [Portfolio Investments](#portfolio-investments) under Portfolio Company Dashboard.

---

#### Fund Portfolio Stats
- **Path:** `aggregate_portfolio_investments/widgets/stats`
- **Size:** XL
- **Description:** Aggregate statistics across all portfolio investments.

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `fields` | String | all | Comma-separated field names to display, e.g. `'Bought Amount,Sold Amount'` |
| `force_units` | String | — | Override display units: `Lakhs`, `Crores`, or `Millions` |

**Example:**
```ruby
{fields: 'Bought Amount,Sold Amount,FMV', force_units: 'Crores'}
```

---

#### Fund Report
- **Path:** `funds/widgets/fund_report`
- **Size:** XL
- **Description:** Embeds a saved report inside the dashboard.

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `report_id` | Integer | required | The ID of the report to embed |
| `other_report_args` | String | — | Additional arguments passed to the report |

**Example:**
```ruby
{report_id: 5}
```

---

#### Embed Document
- **Path:** `funds/widgets/embedded_doc`
- **Size:** XL
- **Description:** Embeds a document from the fund's document library.

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `name` | String | required | The name of the document to embed |

**Example:**
```ruby
{name: 'Quarterly Update Q1 2025'}
```

---

#### Commitment Deployment
- **Path:** `capital_commitments/widgets/deployment`
- **Size:** Medium
- **Description:** Shows how committed capital is being deployed over time.
- **Metadata:** None required.

---

#### Investor Concentration
- **Path:** `capital_commitments/widgets/investor_concentration`
- **Size:** Medium
- **Description:** Chart showing the top investors by commitment size.

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `top_n` | Integer | `10` | Number of top investors to display |

**Example:**
```ruby
{top_n: 5}
```

---

#### GP vs LP Commitment
- **Path:** `capital_commitments/widgets/gp_lp_commitment`
- **Size:** Medium
- **Description:** Breakdown of GP vs LP commitment amounts.
- **Metadata:** None required.

---

#### Unit Type Distribution
- **Path:** `capital_commitments/widgets/unit_type_distribution`
- **Size:** Medium
- **Description:** Distribution of commitments across unit types.
- **Metadata:** None required.

---

#### Onboarding Status
- **Path:** `capital_commitments/widgets/onboarding_status`
- **Size:** Medium
- **Description:** Status of investor onboarding for the fund.
- **Metadata:** None required.

---

#### Fundraising Timeline
- **Path:** `capital_commitments/widgets/fundraising_timeline`
- **Size:** Medium
- **Description:** Timeline chart of fundraising activity.
- **Metadata:** None required.

---

#### Currency Exposure
- **Path:** `capital_commitments/widgets/currency_exposure`
- **Size:** Medium
- **Description:** Breakdown of commitment exposure by currency.
- **Metadata:** None required.

---

#### Call Collection Status
- **Path:** `capital_calls/widgets/collection_status`
- **Size:** Medium
- **Description:** Current status of capital call collections.
- **Metadata:** None required.

---

#### Capital Call History
- **Path:** `capital_calls/widgets/call_history`
- **Size:** Medium
- **Description:** Historical record of capital calls.
- **Metadata:** None required.

---

#### Call Collection Efficiency
- **Path:** `capital_calls/widgets/collection_efficiency`
- **Size:** Medium
- **Description:** Tracks how efficiently capital calls are collected.
- **Metadata:** None required.

---

#### Call Fee Breakdown
- **Path:** `capital_calls/widgets/fee_breakdown`
- **Size:** Medium
- **Description:** Breakdown of fees included in capital calls.
- **Metadata:** None required.

---

#### Investor Call Dues
- **Path:** `capital_calls/widgets/investor_dues`
- **Size:** Medium
- **Description:** Investors with outstanding call dues.

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `top_n` | Integer | `10` | Number of investors to display |

**Example:**
```ruby
{top_n: 15}
```

---

#### Distribution Status
- **Path:** `capital_distributions/widgets/distribution_status`
- **Size:** Medium
- **Description:** Current status of capital distributions.
- **Metadata:** None required.

---

#### Distribution History
- **Path:** `capital_distributions/widgets/distribution_history`
- **Size:** Medium
- **Description:** Historical record of distributions.
- **Metadata:** None required.

---

#### Distribution Components
- **Path:** `capital_distributions/widgets/component_breakdown`
- **Size:** Medium
- **Description:** Breakdown of distribution components (return of capital, gains, etc.).
- **Metadata:** None required.

---

#### Investor Distributions
- **Path:** `capital_distributions/widgets/investor_distributions`
- **Size:** Medium
- **Description:** Distribution amounts per investor.

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `top_n` | Integer | `10` | Number of investors to display |

**Example:**
```ruby
{top_n: 10}
```

---

#### Cumulative Distributions
- **Path:** `capital_distributions/widgets/cumulative_distributions`
- **Size:** Medium
- **Description:** Cumulative distribution totals over time.
- **Metadata:** None required.

---

#### Remittance Status
- **Path:** `capital_remittances/widgets/status`
- **Size:** Medium
- **Description:** Current status of remittance payments.
- **Metadata:** None required.

---

#### Remittance Progress
- **Path:** `capital_remittances/widgets/collection_progress`
- **Size:** Medium
- **Description:** Progress bar/chart for remittance collections.
- **Metadata:** None required.

---

#### Delinquent Investors
- **Path:** `capital_remittances/widgets/delinquent_investors`
- **Size:** Medium
- **Description:** List of investors with overdue remittance payments.

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `top_n` | Integer | `10` | Number of investors to display |

**Example:**
```ruby
{top_n: 10}
```

---

#### Remittance Fees
- **Path:** `capital_remittances/widgets/fee_breakdown`
- **Size:** Medium
- **Description:** Fee breakdown across remittances.
- **Metadata:** None required.

---

#### Remittance Timeline
- **Path:** `capital_remittances/widgets/payment_timeline`
- **Size:** Medium
- **Description:** Timeline chart of remittance payments.

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `chart_type` | String | `'bar'` | Chart style: `bar`, `spline`, or `line` |

**Example:**
```ruby
{chart_type: 'spline'}
```

---

#### Portfolio Allocation
- **Path:** `aggregate_portfolio_investments/widgets/allocation`
- **Size:** Medium
- **Description:** Allocation breakdown of portfolio investments.
- **Metadata:** None required.

---

#### Investment Performance
- **Path:** `aggregate_portfolio_investments/widgets/performance`
- **Size:** Medium
- **Description:** Performance metrics across portfolio companies.
- **Metadata:** None required.

---

#### Realized vs Unrealized
- **Path:** `aggregate_portfolio_investments/widgets/gain_breakdown`
- **Size:** Medium
- **Description:** Gain breakdown between realised and unrealised returns.
- **Metadata:** None required.

---

#### Instrument Exposure
- **Path:** `aggregate_portfolio_investments/widgets/instrument_exposure`
- **Size:** Medium
- **Description:** Exposure breakdown by investment instrument.
- **Metadata:** None required.

---

#### Portfolio Income
- **Path:** `aggregate_portfolio_investments/widgets/income_by_company`
- **Size:** Medium
- **Description:** Income contributions broken down by portfolio company.
- **Metadata:** None required.

---

### Investor Dashboard

---

#### Documents
- **Path:** `investors/widgets/documents`
- **Size:** XL
- **Description:** Displays documents from a specified folder, with optional card or list view.

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `owner_type` | String | — | Scope documents to `'Investor'` or `'Valuation'` |
| `owner_id` | Integer | — | ID of the owner record to scope to |
| `folder_id` | Integer | — | Limit to a specific folder |
| `include_sub_folders` | Boolean | `false` | Include documents from sub-folders |
| `card_view` | Boolean | `false` | Show as card grid instead of list |
| `per_page` | Integer | — | Documents per page |
| `per_row` | Integer | — | Cards per row (used with `card_view: true`) |
| `show_owner` | Boolean | `true` | Show the owner column |
| `show_tags` | Boolean | `true` | Show the tags column |

**Example:**
```ruby
{owner_type: 'Investor', folder_id: 12, card_view: true, per_page: 6, per_row: 3, show_tags: false}
```

---

#### My Tasks
- **Path:** `dashboard_widgets/widgets/my_tasks`
- **Size:** Medium
- **Description:** Shows tasks assigned to the current user.
- **Metadata:** None required.

---

#### Upcoming Events
- **Path:** `dashboard_widgets/widgets/events`
- **Size:** Medium
- **Description:** Shows upcoming calendar events.
- **Metadata:** None required.

---

#### Notes
- **Path:** `dashboard_widgets/widgets/notes`
- **Size:** Medium
- **Description:** Displays recent notes.
- **Metadata:** None required.

---

#### KYCs
- **Path:** `investors/widgets/kycs`
- **Size:** Medium
- **Description:** KYC status summary for the investor.
- **Metadata:** None required.

---

#### Commitments
- **Path:** `investors/widgets/commitments`
- **Size:** Medium
- **Description:** Commitment summary for the investor.
- **Metadata:** None required.

---

#### Embed Document *(Investor)*
- **Path:** `investors/widgets/embedded_doc`
- **Size:** XL
- **Description:** Embeds a named document from the investor's library.

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `name` | String | required | Name of the document to embed |

---

### Portfolio Company Dashboard

---

#### Valuations
- **Path:** `investors/widgets/valuations`
- **Size:** XL
- **Description:** Valuation history for the portfolio company.
- **Metadata:** None required.

---

#### Fund Ratios *(Portfolio Company)*
- **Path:** `investors/widgets/fund_ratios`
- **Size:** XL
- **Description:** Fund-level ratios in the context of a portfolio company.

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `title` | String | — | Custom heading |
| `scenarios` | Boolean | `false` | Show scenario selector |
| `show_currency_filter` | Boolean | `false` | Show currency filter |
| `condensed` | Boolean | `false` | Compact layout |
| `chart` | Boolean | `true` | Show chart |
| `list` | Boolean | `true` | Show table |
| `months` | Integer | — | Months of history |
| `ratio_names` | Array | all | Ratios to include, e.g. `['XIRR', 'TVPI']` |

---

#### Kpis
- **Path:** `investors/widgets/kpis_grid_view`
- **Size:** XL
- **Description:** KPI grid showing actuals, budgets, and trends.

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `title_suffix` | String | — | Appended to the widget title |
| `chart` | Boolean | `true` | Show sparkline charts |
| `tag_list` | String | — | Comma-separated tags to filter by, e.g. `'Actual,Budget'` |
| `show_tags` | Boolean | `true` | Show tags in the grid |
| `compound` | Boolean | `false` | Show compound KPIs |
| `period` | String | `'Quarter'` | Period grouping: `Quarter` or `Year` |
| `no_of_periods` | Integer | `12` | Number of periods to show |
| `no_actions` | Boolean | `false` | Hide action buttons |
| `categories` | String | — | Comma-separated KPI categories to filter by |
| `force_units` | String | — | Override units: `Lakhs`, `Crores`, or `Millions` |
| `decimals` | Integer | `2` | Decimal places |
| `show_chart` | Boolean | `true` | Show the chart section |
| `show_table` | Boolean | `true` | Show the table section |

**Example:**
```ruby
{period: 'Quarter', no_of_periods: 8, categories: 'Income Statement', tag_list: 'Actual,Budget', force_units: 'Crores', decimals: 1}
```

---

#### Kpis Performance Table
- **Path:** `investors/widgets/performance_table`
- **Size:** XL
- **Description:** Tabular KPI performance view.

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `chart` | Boolean | `true` | Show chart alongside table |

---

#### Kpis Budget vs Actual
- **Path:** `investors/widgets/kpis_budget_vs_actual`
- **Size:** XL
- **Description:** Side-by-side budget vs actual comparison for KPIs.

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `categories` | String | — | KPI categories to include |
| `category` | String | — | Single category label (used as chart title) |
| `tag_list` | String | `'Actual,Budget'` | Tags to compare |
| `units` | String | — | Display units override (e.g. `'Lakhs'`) |
| `num_periods` | Integer | `2` | Number of periods to compare |
| `period` | String | `'Year'` | Period: `Year` or `Quarter` |
| `decimals` | Integer | `1` | Decimal places |

**Example:**
```ruby
{categories: 'Income Statement', category: 'IC P/L (INR Mn)', tag_list: 'Actual,Budget', units: 'Lakhs', num_periods: 2, period: 'Year', decimals: 1}
```

---

#### Data Card
- **Path:** `investors/widgets/data_card`
- **Size:** XL
- **Description:** Shows selected data fields for the portfolio company in a card layout.

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `cols` | Integer | `2` | Number of columns in the card layout |
| `fields` | String | required | Comma-separated `Label:field_path` pairs. Supports dot-notation for custom fields, e.g. `'City:city,Sector:custom_fields.sector'` |

**Example:**
```ruby
{cols: 1, fields: 'Category:category,City:city,Sector:custom_fields.sector,Founder:custom_fields.founder'}
```

---

#### Portfolio Investments
- **Path:** `aggregate_portfolio_investments/widgets/portfolio_investments`
- **Size:** XL
- **Description:** Full table of portfolio investments for the company.

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `ag` | Boolean | `false` | Use ag-grid for the table |
| `group_by_column` | String | — | Column to group rows by, e.g. `'investment_instrument_name'` |
| `show_fund_name` | Boolean | `false` | Show the fund name column |

---

#### Value Bridge
- **Path:** `investors/widgets/value_bridge`
- **Size:** XL
- **Description:** Waterfall chart showing value progression across instruments and periods.

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `instruments` | String | `'All'` | `'All'` or a stakeholder custom field name containing instrument list |
| `across` | String | `'First Last'` | Period range: `'First Last'` or `'Last 2'` |
| `show_form` | Boolean | `true` | Show configuration form |
| `hide_table` | Boolean | `false` | Hide the data table |

---

#### Captable
- **Path:** `investments/widgets/captable`
- **Size:** XL
- **Description:** Cap table showing ownership and funding rounds.

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `show_charts` | Boolean | `true` | Show charts section |
| `diluted_chart` | String | `'pie'` | Chart type: `pie`, `donut`, or `half_donut` |
| `custom_colors` | Boolean | `false` | Use custom colour palette |
| `show_investments` | Boolean | `false` | Show investment details |
| `show_captable` | Boolean | `true` | Show main cap table |
| `self_by_funding_round` | Boolean | `true` | Show self-investment by round |
| `amount_by_funding_round` | Boolean | `true` | Show amount raised by round |
| `diluted_share_holdings` | Boolean | `true` | Show diluted holdings |
| `amount_by_investor` | Boolean | `true` | Show amount by investor |
| `each_funding_round` | Boolean | `false` | Show each round separately |
| `show_quantity_actual` | Boolean | `false` | Show actual share quantities |
| `show_quantity_diluted` | Boolean | `false` | Show diluted share quantities |

---

#### Portfolio Company Report
- **Path:** `funds/widgets/fund_report`
- **Size:** XL
- **Description:** Embeds a saved report scoped to the portfolio company.

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `report_id` | Integer | required | The report to embed |
| `title` | String | — | Override report title |
| `show_prefix` | Boolean | `true` | Show entity prefix in title |
| `show_name` | Boolean | `true` | Show entity name |
| `show_inputs` | Boolean | `true` | Show report inputs |
| `show_tags` | Boolean | `true` | Show report tags |
| `show_instrument` | Boolean | `false` | Show instrument column |
| `other_report_args` | String | — | Additional arguments for the report |

---

#### Portfolio Report
- **Path:** `investors/widgets/portfolio_report`
- **Size:** XL
- **Description:** Renders a portfolio report with optional tabs.

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `tabs` | String | — | Comma-separated tab names |
| `portfolio_report_id` | Integer | required | ID of the portfolio report |

---

#### Key Kpis
- **Path:** `investors/widgets/kpi_key_numbers`
- **Size:** XL
- **Description:** Highlights a selected set of KPIs as large number tiles.

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `kpis` | String | — | Comma-separated KPI names to show |

**Example:**
```ruby
{kpis: 'Revenue,EBITDA,Net Profit'}
```

---

### Portfolio Dashboard

---

#### Portfolio Stats
- **Path:** `aggregate_portfolio_investments/widgets/stats`
- **Size:** XL
- **Description:** Aggregate statistics across all portfolio investments.

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `fields` | String | all | Comma-separated field names to display |
| `field_names` | String | — | Custom display names for fields, matching order of `fields` |
| `force_units` | String | — | Units override: `Lakhs`, `Crores`, or `Millions` |
| `tracking_currency` | Boolean | `false` | Show tracking currency column |

**Example:**
```ruby
{fields: 'Bought Amount,Sold Amount,FMV', field_names: 'Invested,Realised,Current Value', force_units: 'Crores'}
```

---

#### Portfolio Investments *(Portfolio Dashboard)*
- **Path:** `aggregate_portfolio_investments/widgets/portfolio_investments`
- **Size:** XL
- See options under [Portfolio Investments](#portfolio-investments).

---

#### FMV %
- **Path:** `aggregate_portfolio_investments/widgets/fmv_percentage`
- **Size:** Medium
- **Description:** Pie/bar chart of FMV percentage by company.
- **Metadata:** None required.

---

#### Holding Cost %
- **Path:** `aggregate_portfolio_investments/widgets/holding_costs_percentage`
- **Size:** Medium
- **Metadata:** None required.

---

#### Bought %
- **Path:** `aggregate_portfolio_investments/widgets/bought_percentage`
- **Size:** Medium
- **Metadata:** None required.

---

#### Sold %
- **Path:** `aggregate_portfolio_investments/widgets/sold_percentage`
- **Size:** Medium
- **Metadata:** None required.

---

#### Portfolio IRR
- **Path:** `aggregate_portfolio_investments/widgets/irr`
- **Size:** XL
- **Description:** IRR calculation and chart for the portfolio.

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `show_table` | Boolean | `true` | Show the data table |
| `show_chart` | Boolean | `true` | Show the chart |

---

#### Embed Document *(Portfolio)*
- **Path:** `investors/widgets/embedded_doc`
- **Size:** XL

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `name` | String | required | Document name to embed |
| `xlsx_as_grid` | Boolean | `false` | Render Excel files as an interactive grid |

---

#### Agent Chart
- **Path:** `investors/widgets/agent_chart`
- **Size:** XL
- **Description:** AI-generated chart rendered from agent output.

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `title` | String | — | Chart title |

---

### Aggregated Portfolio Dashboard

---

#### Aggre. Portfolio Investments
- **Path:** `aggregate_portfolio_investments/widgets/multicompany_portfolio_investments`
- **Size:** XL
- **Description:** Multi-company portfolio investments table, optionally grouped.

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `show_grouped` | Boolean | `false` | Group rows by a column |
| `group_by_column` | String | — | Column to group by, e.g. `'portfolio_company_name'` |
| `decimals` | Integer | `2` | Decimal places |

**Example:**
```ruby
{show_grouped: true, group_by_column: 'portfolio_company_name', decimals: 2}
```

---

#### Stats
- **Path:** `aggregate_portfolio_investments/widgets/stats`
- **Size:** XL

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `title` | String | — | Widget title |
| `decimals` | Integer | `2` | Decimal places |
| `currency` | String | — | Currency code, e.g. `'INR'` |
| `force_units` | String | — | Units: `Lakhs`, `Crores`, or `Millions` |

**Example:**
```ruby
{title: 'Portfolio Summary', decimals: 3, currency: 'INR', force_units: 'Lakhs'}
```

---

#### Company Charts
- **Path:** `aggregate_portfolio_investments/widgets/portfolio_company_charts`
- **Size:** XL
- **Description:** Sector-wise and company-wise breakdowns as charts and/or tables.

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `show_sector_wise` | Boolean | `true` | Show sector breakdown chart |
| `show_portfolio_company_wise` | Boolean | `true` | Show company breakdown chart |
| `show_table` | Boolean | `false` | Show data table |
| `show_chart` | Boolean | `true` | Show chart |
| `plot` | String | `'bought_amount'` | Metric to plot |
| `table_limit` | Integer | `8` | Max rows in table |
| `title` | String | — | Widget title |

**Example:**
```ruby
{show_sector_wise: true, show_portfolio_company_wise: true, show_chart: true, plot: 'bought_amount', table_limit: 8, title: 'FMV by Company'}
```

---

#### Fund Ratios *(Aggregated)*
- **Path:** `aggregate_portfolio_investments/widgets/fund_ratio_aggregate`
- **Size:** XL
- **Description:** Aggregated fund ratios across multiple funds, shown as table and/or chart.

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `show_table` | Boolean | `true` | Show table |
| `show_chart` | Boolean | `true` | Show chart |
| `ratio_names` | Array | — | Ratio names to show, e.g. `['Gross Portfolio IRR', 'Gross Portfolio MOIC']` |
| `titles` | Array | — | Display titles matching ratio_names order, e.g. `['IRR', 'MOIC']` |
| `chart_colors` | Array | — | Colours for each series, e.g. `['green', 'DarkOrange']` |

**Example:**
```ruby
{show_table: true, show_chart: true, ratio_names: ['Gross Portfolio IRR', 'Gross Portfolio MOIC'], titles: ['IRR', 'MOIC'], chart_colors: ['green', 'DarkOrange']}
```

---

#### Company Ratios
- **Path:** `aggregate_portfolio_investments/widgets/company_ratios_aggregate`
- **Size:** XL
- **Description:** Per-company ratios across the aggregated portfolio.

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `show_table` | Boolean | `true` | Show table |
| `show_chart` | Boolean | `true` | Show chart |
| `ratio_names` | Array | — | Ratio names to include |
| `titles` | Array | — | Display titles per ratio |
| `chart_colors` | Array | — | Positive value colours per series |
| `negative_colors` | Array | — | Negative value colours per series |

**Example:**
```ruby
{show_table: true, show_chart: true, ratio_names: ['IRR', 'MOIC'], titles: ['IRR', 'MOIC'], chart_colors: ['green', 'DarkOrange'], negative_colors: ['orange', 'red']}
```

---

### FM Landing Page

---

#### FM Stats
- **Path:** `entities/widgets/fm_stats`
- **Size:** XL
- **Description:** High-level statistics for the fund manager entity.
- **Metadata:** None required.

---

#### Funds *(FM)*
- **Path:** `entities/widgets/funds`
- **Size:** XL
- **Description:** List of funds managed by the entity.
- **Metadata:** None required.

---

#### Investment Opportunities
- **Path:** `entities/widgets/investment_opportunities`
- **Size:** XL
- **Description:** Active investment opportunities for the entity.
- **Metadata:** None required.

---

### LP Landing Page

---

#### Funds *(LP)*
- **Path:** `entities/widgets/lp_funds`
- **Size:** XL
- **Metadata:** None required.

---

#### Offers
- **Path:** `entities/widgets/lp_offers`
- **Size:** XL
- **Metadata:** None required.

---

#### Interests
- **Path:** `entities/widgets/lp_interests`
- **Size:** XL
- **Metadata:** None required.

---

#### Deals
- **Path:** `entities/widgets/lp_deals`
- **Size:** XL
- **Metadata:** None required.

---

#### Investment Opportunities *(LP)*
- **Path:** `entities/widgets/lp_investment_opportunities`
- **Size:** XL
- **Metadata:** None required.

---

#### Entities
- **Path:** `entities/widgets/lp_entities`
- **Size:** XL
- **Metadata:** None required.

---

#### Account Entries Chart
- **Path:** `capital_commitments/widgets/account_entries_chart`
- **Size:** Medium
- **Description:** Chart of account entries (fees, etc.) over time.

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `account_entry_names` | String | — | Comma-separated entry names to include, e.g. `'Management Fee, Setup Fee'` |
| `chart_type` | String | `'column'` | Chart style: `column`, `pie`, or `line` |
| `aggregate_by` | String | `'quarter'` | Grouping period: `quarter`, `year`, or `sum` |
| `number_of_periods` | Integer | `8` | Number of periods to display |

**Example:**
```ruby
{account_entry_names: 'Management Fee, Setup Fee', chart_type: 'column', aggregate_by: 'quarter', number_of_periods: 8}
```

---

### Ops Dashboard

---

#### My Tasks *(Ops)*
- **Path:** `dashboard_widgets/widgets/my_tasks`
- **Size:** Medium
- **Metadata:** None required.

---

#### Upcoming Events *(Ops)*
- **Path:** `dashboard_widgets/widgets/events`
- **Size:** Medium
- **Metadata:** None required.

---

#### Investors No Interaction
- **Path:** `dashboard_widgets/widgets/investors_no_interaction`
- **Size:** Medium
- **Description:** Investors who have had no recent interaction.
- **Metadata:** None required.

---

#### Notes *(Ops)*
- **Path:** `dashboard_widgets/widgets/notes`
- **Size:** Medium
- **Metadata:** None required.

---

## Showing All Options in the Widget Form

Currently the form displays a **"Sample:"** hint when you select a widget — this comes from the `metadata_help` field on each widget definition. The hint is read-only and shows the accepted metadata keys.

To make the form more user-friendly, a few approaches are possible:

1. **Pre-fill the metadata field** with the sample when a widget is selected (instead of just showing it as a hint). This would let users edit the defaults rather than typing from scratch.

2. **Structured metadata editor** — parse the `metadata_help` string into individual form fields (one input per key), then serialise back to the hash string on save. This is the most user-friendly but requires additional frontend work.

3. **Expand the metadata_help text** to include type hints and descriptions directly in the sample string so the hint panel is more informative.

The quickest win is option 1: when a widget is selected via the Stimulus controller, auto-populate the metadata textarea with the sample value so the user can modify it.
