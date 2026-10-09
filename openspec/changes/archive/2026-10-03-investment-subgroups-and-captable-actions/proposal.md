# Investment Subgroups and Cap Table Actions

## Why

A portfolio company's cap table can be built from Investments or from Shareholder Position
uploads. Shareholder Positions already carry a subgroup and an instrument, so the horizontal cap
table nests them under subgroups and shows each instrument. Investments had neither:

- An investor's Equity and CCPS holdings were blended into one row.
- The same investor under two categories collapsed into one row.
- There was no way to put investors under a subgroup such as "Institutional" or "Angel".

The cap table page also showed download buttons for a company with no data to download. The
sample upload files did not match the current import format.

## What Changes

- **`investments.subgroup`** (string, max 100, indexed) is added. It is:
  - on the investment form, next to the type field, which is relabelled **Instrument Type**
  - on the investment page
  - permitted by the controller and Ransack-searchable
  - imported from a `Subgroup` column (also accepted as `SubGroup` or `Sub Group`)
- **The investment import also reads `Instrument Name` and `Instrument Quantity`.** These
  columns and `Subgroup` are never turned into custom fields.
- **An Equity investment's `instrument_name` and `instrument_quantity` are cleared on save.**
  The form only shows them for a Convertible.
- **Cap table grouping:**
  - The funding round cap table groups by investor and instrument.
  - The horizontal cap table groups by investor, category and instrument, so each combination
    gets its own row.
  - An Equity investment's instrument is shown as "Equity".
  - An investor is nested under the first subgroup found on any of their investments.
- **Convertible quantities:** a Convertible's `instrument_quantity` counts as held (Quantity
  actual). Only the rest of its `quantity` counts as dilution, the same way Shareholder
  Position quantity actuals are split. Because this split happens inside `GenerateCapTable`,
  every caller built on top of it inherits the changed Quantity/Percentage figures, not just
  the cap table pages - namely the fund portfolio reports (Word/PDF), the AI assistant's
  portfolio answers, and the Ownership Trend chart. Entering or editing a Convertible's
  Instrument Quantity therefore changes numbers in those surfaces too, with no separate
  recompute step.
- **Cap table page buttons:**
  - The investment buttons are labelled "Upload Investments" and "Download Investments".
  - "View Investments" sits with the investment actions.
  - A portfolio company with neither investments nor approved shareholder positions shows no
    download buttons.
- **Sample files:** `public/sample_uploads/investments.xlsx` and
  `public/sample_uploads/shareholder_positions.xlsx` are updated to the current import
  formats.

## Capabilities

### New Capabilities
- `startups/investment-subgroups`: the investment subgroup and instrument fields, and how the
  cap tables group and total investments by subgroup, category and instrument.
- `startups/cap-table-actions`: which upload, view and download actions the cap table page
  offers for a portfolio company.
- `startups/cap-table-sample-uploads`: the sample upload files offered on the investment and
  shareholder position upload pages import as-is.

### Modified Capabilities

(none — `openspec/specs/` has no startups specs yet)

## Impact

- **Data:** migration `20260921000000_add_subgroup_to_investments`.
- **Model:** `Investment` (validation, `clear_instrument_name_for_equity`, Ransack attributes).
- **Services:** `GenerateCapTable` (composite and derived `:instrument` grouping keys, Ruby-side
  grouping), `GenerateHorizontalCapTable` (per-instrument and per-category rows, subgroup),
  `ImportInvestment`.
- **Downstream `GenerateCapTable`/`GenerateHorizontalCapTable` callers, not directly changed but
  affected by the Convertible quantity split above:** `PortfolioAssistantDataManager`,
  `PortfolioReportSablonWordService`, `PortfolioReportDocGenerator`, and the Ownership Trend
  chart (`investment_statistics_helper.rb`, `_charts_content.html.erb`).
- **Views:** investment `_form`, `show`, `index`, `_funding_round`, `_horizontal_captable`.
- **Sample files:** `public/sample_uploads/investments.xlsx`,
  `public/sample_uploads/shareholder_positions.xlsx`.
- **Tests:** Cucumber features `features/startup/investment_subgroups.feature`,
  `features/startup/captable_actions.feature` and
  `features/startup/captable_sample_uploads.feature`. No RSpec.
