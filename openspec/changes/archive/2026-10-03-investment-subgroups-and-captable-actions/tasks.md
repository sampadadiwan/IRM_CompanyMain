## 1. Data model

- [x] 1.1 Add migration `20260921000000_add_subgroup_to_investments` (string, limit 100, nullable, indexed). Verify: `db/schema.rb` shows only the new column and index.
- [x] 1.2 `Investment`: validate subgroup length, clear `instrument_name`/`instrument_quantity` for Equity before save, add `subgroup` to `ransackable_attributes`. Verify: Cucumber `investment_subgroups.feature` (too long, Equity cleared, filter).

## 2. Form, page and controller

- [x] 2.1 Permit `:subgroup` in `InvestmentsController#investment_params`, add the Subgroup field to `_form` and relabel the type "Instrument Type". Verify: Cucumber "A subgroup entered on the investment form…".
- [x] 2.2 Show the subgroup on `investments/show`. Verify: same scenario.

## 3. Import

- [x] 3.1 `ImportInvestment` reads Subgroup (`SubGroup`/`Sub Group`), Instrument Name and Instrument Quantity on create and update-only rows, and ignores them as custom field headers. Verify: Cucumber `captable_sample_uploads.feature` header outline and update-only scenario.

## 4. Cap tables

- [x] 4.1 `GenerateCapTable`: group in Ruby, supporting composite `group_by_field` and the derived `:instrument` key. Split a Convertible's `instrument_quantity` into Quantity actual and the rest into dilution. Verify: Cucumber "A Convertible counts its instrument quantity…".
- [x] 4.2 `_funding_round` groups by `[investor_name, instrument]`. Verify: Cucumber "An investor holding Equity and a Convertible…".
- [x] 4.3 `GenerateHorizontalCapTable`: one row per investor, category and instrument, with the first non-blank subgroup, and Self rows summed. Verify: Cucumber subgroup nesting, single-round subgroup and two-category scenarios.
- [x] 4.4 `_horizontal_captable`: centre the Particulars column.

## 5. Cap table page actions

- [x] 5.1 `investments/index`: relabel Upload/Download Investments, move View Investments into the investment actions, and hide downloads for a company with no data. Verify: Cucumber `captable_actions.feature`.

## 6. Sample files

- [x] 6.1 Update `public/sample_uploads/investments.xlsx` and `public/sample_uploads/shareholder_positions.xlsx` to the current import formats. Verify: Cucumber sample import scenarios.

## 7. Cucumber coverage

- [x] 7.1 `features/startup/investment_subgroups.feature`: form, too-long subgroup, Equity cleared, filter, subgroup nesting, single-round subgroup, per-instrument rows, per-category rows, Convertible quantity split.
- [x] 7.2 `features/startup/captable_actions.feature`: no data, investments only, approved positions only, unapproved positions only, global list.
- [x] 7.3 `features/startup/captable_sample_uploads.feature`: investments sample, subgroup header spellings, update-only import, shareholder positions sample.
- [x] 7.4 Run the new features plus the existing cap table and investment import features with a random `TEST_ENV_NUMBER` and Redis up.
