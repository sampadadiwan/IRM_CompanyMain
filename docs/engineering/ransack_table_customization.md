# RansackTable Column Customization

This document explains how to customize CSS classes for columns in grids using the `RansackTable` component.

## Mechanism

The `RansackTableHeader` and `RansackTableRow` components support a semicolon-separated syntax in column definitions to specify CSS classes.

- **Header (`<th>`):** Uses the CSS class defined after the semicolon in the **Key** (Label).
- **Row (`<td>`):** Uses the CSS class defined after the semicolon in the **Value** (Attribute).

## Standard CSS Classes

Use these standardized classes to ensure consistent grid styling:

| Class | Usage | Alignment |
| :--- | :--- | :--- |
| `text-col` | General text data | Left |
| `num-col` | Numeric data, currency, percentages | Right |
| `date-col` | Dates and timestamps | Left/Center |
| `action-col` | Action buttons and links | Center/Right |

## Implementation

Update the column mapping (e.g., `STANDARD_COLUMNS`) in your model or where the columns are defined.

### Example: Model Definition

In `app/packs/core/investors/models/investor.rb`:

```ruby
# Before
STANDARD_COLUMNS = { 
  "Stakeholder" => "investor_name", 
  "Category"    => "category", 
  "Access"      => "investor_access_count" 
}.freeze

# After
STANDARD_COLUMNS = { 
  "Stakeholder; text-col" => "investor_name; text-col", 
  "Category; text-col"    => "category; text-col", 
  "Access; num-col"       => "investor_access_count; num-col" 
}.freeze
```

### Example: View Definition

If passing a custom map to `RansackTable` in a view:

```erb
<% custom_columns = { "Name; text-col" => "name; text-col", "Amount; num-col" => "amount; num-col" } %>
<%= render RansackTable.new(MyModel, q: @q, default_columns_map: custom_columns, ...) %>
```

## Grid Customization Locations

The following locations in the codebase use `RansackTable` and should be updated to use the standardized CSS classes.

| Domain | Model / Location | Column Constants to Update |
| :--- | :--- | :--- |
| **Core** | `Investor` | `STANDARD_COLUMNS` |
| | `InvestorKyc` | `STANDARD_COLUMNS`, `INVESTOR_TAB_STANDARD_COLUMNS`, `INVESTOR_STANDARD_COLUMNS` |
| | `Valuation` | `STANDARD_COLUMNS` |
| | `TaskTemplate` | `STANDARD_COLUMNS` |
| **Funds** | `CapitalRemittance` | `STANDARD_COLUMNS`, `ADDITIONAL_COLUMNS`, `INVESTOR_STANDARD_COLUMNS`, `FOR_COMMITMENT_COLUMNS` |
| | `CapitalCall` | `STANDARD_COLUMNS` |
| | `CapitalCommitment` | `STANDARD_COLUMNS`, `ADDITIONAL_COLUMNS`, `INVESTOR_TAB_STANDARD_COLUMNS`, `INVESTOR_STANDARD_COLUMNS` |
| | `CapitalDistributionPayment`| `STANDARD_COLUMNS`, `INVESTOR_STANDARD_COLUMNS` |
| | `Fund` | `STANDARD_COLUMNS` |
| | `FundFormula` | `STANDARD_COLUMNS` |
| | `FundRatio` | `STANDARD_COLUMNS`, `CONDENSED_COLUMNS` |
| | `FundUnitSetting` | `STANDARD_COLUMNS` |
| | `FundReport` | `STANDARD_COLUMNS` |
| | `AccountEntry` | `STANDARD_COLUMNS` |
| | `PortfolioInvestment` | `STANDARD_COLUMNS`, `ADDITIONAL_COLUMNS` |
| | `AggregatePortfolioInvestment`| `STANDARD_COLUMNS`, `ADDITIONAL_COLUMNS`, `STANDARD_COLUMNS_WITH_FUND`, `INVESTOR_TAB_STANDARD_COLUMNS` |
| | `InvestmentInstrument` | `STANDARD_COLUMNS` |
| **Startups** | `Investment` | `STANDARD_COLUMNS` |
| | `Kpi` | `STANDARD_COLUMNS` |
| | `KpiReport` | `STANDARD_COLUMNS` |
| | `DealInvestor` | `STANDARD_COLUMNS` |
| **Secondaries**| `Offer` | `STANDARD_COLUMNS`, `INVESTOR_STANDARD_COLUMNS` |
| | `Interest` | `STANDARD_COLUMNS` |

## How it Works (Internal)

The components use the following logic to extract the class:

```ruby
# RansackTableRow.html.erb
<% attribute, css_class = attribute.split(";").map(&:strip) %>
<td class="<%= css_class %>">
  ...
</td>
```

```ruby
# RansackTableHeader.html.erb
<% column_name, css_class = column_name.split(";").map(&:strip) %>
<th class="<%= css_class %>">
  ...
</th>
```

## Verification

1. Apply the semicolon and class name to the column definition.
2. Refresh the page and inspect the HTML.
3. Confirm that both `<th>` and `<td>` tags have the expected class.

---
*Updated: 2026-04-06*
