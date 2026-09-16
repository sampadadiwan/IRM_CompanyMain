# KPI Parser Fixes — User Guide

## Overview

This document describes the changes made to the KPI Excel upload parser on branch `feature/kpi-workbook-parser-fixes`. The changes improve how the system handles parent-child KPI hierarchies, duplicate KPI names, and the grid view display.

**Branch:** `feature/kpi-workbook-parser-fixes`
**Files changed:** 6 code + 1 doc + 4 test fixtures + 1 generator script
**Date:** 2026-07-24

---

## What Changed (Summary)

| # | Fix | File(s) | Problem | Solution |
|---|-----|---------|---------|----------|
| 0 | Header row detection | `kpi_workbook_reader.rb`, `kpi_date_utils.rb` | Multi-row headers picked wrong row | Score all rows, pick highest distinct date count |
| 1 | ACT/BUDGET columns | `kpi_workbook_reader.rb` | Single tag per report; mixed sheets ignored | Per-column tag detection, separate reports per tag |
| 2 | Indent detection | `kpi_workbook_reader.rb` | Indented child KPIs silently skipped | rubyXL reads cell indent, auto-creates child mappings |
| 3 | Method scoping | `kpi_workbook_reader.rb` | Method defined outside class block | Moved inside class |
| 4 | ISO date headers | `kpi_workbook_reader.rb` | Headers like "2022-04-01" not detected | Relaxed filter to allow ISO dates |
| 5 | Duplicate child names | `kpi_workbook_reader.rb`, `kpis_helper.rb`, `_grid_view_table.html.erb` | Same name under different parents collided | Parent-prefixed naming, row-level mapping, mapping_id scoping |
| 6 | tag_list.first bug | `kpi_workbook_reader.rb` | Tag "Actual" read as "A" | Removed `.first` (tag_list is a string, not array) |
| 7 | Column-based children | `kpi_workbook_reader.rb` | Parent in col A, children in col B not detected | Auto-detect two-column layout, register child mappings |
| 8 | Child display name | `_grid_view_table.html.erb`, `_grid_view_simple_table.html.erb` | "Net Sales - Enterprise" too verbose in grid | Show `reported_kpi_name` for children (indent provides context) |

---

## Detailed Changes

### Fix 5: Duplicate Child Name Handling (Primary fix this session)

#### The Problem

When an Excel file has the same KPI name under different parents — for example, "Enterprise" appears under both "Net Sales" and "Operating Cost" — several bugs cascaded:

1. **Parent stealing:** `create_child_mapping` used `find_or_create_by!` with the raw name "Enterprise". When the second parent ("Operating Cost") tried to create its own "Enterprise" child, it found the first one (under "Net Sales") and `update!(parent: operating_cost)` stole it away from its original parent.

2. **Hash overwrite:** `@kpi_name_to_kpi_mappings` is keyed by normalized name. Both "Enterprise" entries mapped to `"enterprise"`. The second write overwrote the first, so the parser lost track of which mapping belonged to which parent.

3. **Value overwrite:** `save_kpi_entry` used `first_or_initialize` querying only by `name`. Both "Enterprise" rows had the same KPI name, so the second row's value overwrote the first row's KPI record.

#### The Solution

**Three coordinated changes across three files:**

##### 1. `kpi_workbook_reader.rb` — Parser logic

**Parent-prefixed naming (`create_child_mapping`):**
- Child mappings now get `standard_kpi_name` in "Parent - Child" format
- Example: "Enterprise" under Net Sales becomes "Net Sales - Enterprise"
- Example: "Enterprise" under Operating Cost becomes "Operating Cost - Enterprise"
- `reported_kpi_name` stays as the raw Excel name ("Enterprise") for future import matching
- Three-way lookup: (1) find by prefixed name (idempotent re-upload), (2) adopt flat parentless mapping, (3) create new

**Row-level mapping (`@row_to_mapping`):**
- New hash initialized in constructor: `@row_to_mapping = {}`
- Keyed by `[sheet_name, row_index]` → `InvestorKpiMapping`
- `detect_parent_child_relationships` stores each child's mapping by its row position
- `save_kpi_entry` checks `@row_to_mapping` first before falling back to name-based lookup
- This provides positional disambiguation: even though both rows say "Enterprise", the parser knows which mapping to use based on where the row is in the sheet

**Mapping-scoped KPI queries (`save_kpi_entry`):**
- `first_or_initialize` now includes `investor_kpi_mapping_id` in the query
- Approved KPI duplicate check also scoped by `investor_kpi_mapping_id`
- This ensures "Net Sales - Enterprise" and "Operating Cost - Enterprise" each get their own KPI records

##### 2. `kpis_helper.rb` — Mapping ordering

**`set_investor_kpi_mappings` method:**
- Previously: `investor&.investor_kpi_mappings || []` — flat list, no ordering guarantee
- Now: `raw.sort_by_ancestry(raw)` — uses the ancestry gem's tree sorting so children appear immediately after their parent in the grid view
- Also added `.order(:position)` to respect the user's configured display order

##### 3. `_grid_view_table.html.erb` — Grid view display

**KPI lookup changed from name-based to mapping-based:**
- Previously: `kpis.group_by { |k| k.name.downcase }` and `kpis_by_report_and_name.dig(kpi_report.id, ikm.standard_kpi_name.downcase)`
- Now: `kpis.group_by(&:investor_kpi_mapping_id)` and `kpis_by_report_and_mapping.dig(kpi_report.id, ikm.id)`
- This correctly handles duplicate names under different parents

**Visual hierarchy indicators:**
- Child rows get a `child-row` CSS class on the `<tr>` element
- Child rows display a `└` tree connector prefix before the KPI name
- Parent rows show a child count badge (e.g., "3") when they have children

### Fix 6: `tag_list.first` Bug

#### The Problem

Line 276 had: `effective_tag = col_tag || @kpi_report.tag_list.first`

`tag_list` on `KpiReport` is a **String** column (e.g., `"Actual"`), not an Array. Calling `.first` on a String returns the first character — so `"Actual".first` returns `"A"`.

All auto-created KpiReports got `tag_list: "A"` instead of `"Actual"`. These reports wouldn't match the default `tag_list: ["Actual"]` filter, making their KPIs invisible in the grid view.

#### The Fix

Changed to: `effective_tag = col_tag || @kpi_report.tag_list`

Removed `.first` — the string value is used directly.

---

## How the Parent-Child Flow Works End-to-End

### Prerequisites

1. Fund manager creates **parent KPI mappings** for a portfolio company (e.g., Net Sales, Operating Cost, EBITDA, PAT) via the KPI Mappings page or CSV import
2. Portfolio company sends an Excel MIS file where child KPIs (e.g., Enterprise, Mid-Market, SMB) are indented under their parent rows

### Upload Flow

```
Fund manager uploads Excel → ImportKpiWorkbookJob → KpiWorkbookReader
```

### Parser Steps

1. **`build_indent_map`** — Opens the file with rubyXL (separate from the Roo gem) and reads `cell.text_indent` formatting. Builds a hash: `{ [sheet_name, row_index] => indent_level }`. Only rows with indent > 0 are stored.

2. **`detect_header_row`** — Scans first 10 rows, scores each by distinct date-like cell count, picks the highest-scoring row as the header.

3. **`detect_tag_row`** — Checks 1-2 rows below the header for ACT/BUDGET/ACTUAL/PROJECTED labels. If found, builds per-column tag assignments.

4. **`detect_parent_child_relationships`** — For each data row:
   - Reads the KPI name and indent level from `@indent_map`
   - Maintains a parent stack (`[indent_level, kpi_name]` pairs)
   - When an indented row is under a known parent mapping:
     - Calls `create_child_mapping` to create/find the child `InvestorKpiMapping`
     - Sets `standard_kpi_name` to "Parent - Child" format
     - Registers the mapping in `@kpi_name_to_kpi_mappings` and `@target_kpis`
     - Stores in `@row_to_mapping[[sheet, row_index]]` for positional lookup
   - Subtotal rows (matching `/\Atotal\s/i`) are skipped unless they're in `@target_kpis`

5. **`process_data_rows`** — For each data row:
   - Normalizes the KPI name and checks against `@target_kpis`
   - Extracts values from each date column
   - Calls `save_kpi_entry` for each value

6. **`save_kpi_entry`** — For each KPI value:
   - Looks up the mapping: first from `@row_to_mapping` (positional), then from `@kpi_name_to_kpi_mappings` (name-based fallback)
   - Uses the mapping's `standard_kpi_name` (parent-prefixed for children) as the KPI name
   - Queries for existing KPI by name + `investor_kpi_mapping_id` (prevents duplicate-name collisions)
   - Creates/updates the KPI record as unapproved

### Result

Given this Excel structure:

```
| KPI              | Q1 2024 | Q2 2024 |
| Net Sales        |     100 |     120 |
|   Enterprise     |      60 |      70 |
|   SMB            |      40 |      50 |
| Operating Cost   |      80 |      90 |
|   Enterprise     |      50 |      55 |
|   SMB            |      30 |      35 |
```

The parser creates:

**InvestorKpiMapping records:**
| standard_kpi_name | reported_kpi_name | parent |
|---|---|---|
| Net Sales | Net Sales | (none) |
| Net Sales - Enterprise | Enterprise | Net Sales |
| Net Sales - SMB | SMB | Net Sales |
| Operating Cost | Operating Cost | (none) |
| Operating Cost - Enterprise | Enterprise | Operating Cost |
| Operating Cost - SMB | SMB | Operating Cost |

**Kpi records (per report):**
| name | value | investor_kpi_mapping_id |
|---|---|---|
| Net Sales | 100 | (Net Sales mapping) |
| Net Sales - Enterprise | 60 | (Net Sales - Enterprise mapping) |
| Net Sales - SMB | 40 | (Net Sales - SMB mapping) |
| Operating Cost | 80 | (Operating Cost mapping) |
| Operating Cost - Enterprise | 50 | (Operating Cost - Enterprise mapping) |
| Operating Cost - SMB | 30 | (Operating Cost - SMB mapping) |

### Grid View Display

```
┌─────────────────────────────┬──────────┬──────────┐
│ KPI                         │ Q1 2024  │ Q2 2024  │
├─────────────────────────────┼──────────┼──────────┤
│ ☐ Net Sales            [3]  │      100 │      120 │
│   └ Net Sales - Enterprise  │       60 │       70 │
│   └ Net Sales - SMB         │       40 │       50 │
│ ☐ Operating Cost       [3]  │       80 │       90 │
│   └ Operating Cost - Ent.   │       50 │       55 │
│   └ Operating Cost - SMB    │       30 │       35 │
└─────────────────────────────┴──────────┴──────────┘
```

- `[3]` = child count badge on parent rows
- `└` = tree connector on child rows
- Each row links to its InvestorKpiMapping detail page

---

## Key Technical Notes

### Ancestry Gem Gotchas

The `InvestorKpiMapping` model uses `has_ancestry` for parent-child hierarchy:

- Hierarchy is stored in a string `ancestry` column (e.g., `"1030"` means parent ID is 1030)
- `parent`, `parent_id`, `parent=` are **virtual methods** provided by the gem — they are NOT database columns
- You **cannot** use `parent:` in ActiveRecord `where` or `find_by` queries (causes `Mysql2::Error: Unknown column`)
- You **can** use `parent:` in `update!`, `create!`, and assignment — these invoke the gem's setter
- Use `ancestry: nil` to query for root-level (parentless) records

### `tag_list` Is a String

`KpiReport.tag_list` is a plain string column, not an array. Values are "Actual", "Budget", or "IC". Do not call `.first`, `.split`, or treat it as an array.

### Soft Delete (acts_as_paranoid)

Both `Kpi` and `KpiReport` use `acts_as_paranoid` via the `Trackable` concern. This means:
- `delete_all` only sets `deleted_at` (soft delete) — records remain in the database
- Use `Kpi.unscoped.where(...).delete_all` for hard delete
- Use `really_destroy!` on individual records for hard delete
- Default scopes automatically add `WHERE deleted_at IS NULL`

### Re-upload Idempotency

The `create_child_mapping` method is designed to be idempotent:
- First upload: creates new child mappings with "Parent - Child" naming
- Re-upload: finds existing mappings by `standard_kpi_name` and returns them
- Previously flat mapping: adopts it under the parent and renames

---

### Fix 7: Column-Based Parent-Child Detection

#### The Problem

Some Excel files use a two-column layout instead of indentation: parent KPIs in column A, child KPIs in column B. When column A has a value, column B is blank; when column B has a value, column A is blank.

#### The Solution

New `detect_column_based_children` method scans the first 20 data rows. If it finds rows where the primary KPI column (A) is blank but the next column (B) has a non-numeric, non-date text value, it sets `@child_col`. The existing `detect_parent_child_relationships` method then handles both indent-based and column-based children in a unified flow, with `effective_indent = 1` for column-based children.

`process_data_rows` uses `value_start_col = @child_col ? @child_col + 1 : 1` to skip the child name column during value extraction.

### Fix 8: Child Display Name Shortening

Grid views now show `reported_kpi_name` (raw Excel name, e.g., "Enterprise") for child rows instead of the full prefixed `standard_kpi_name` ("Net Sales - Enterprise"). The `└` indent already communicates the parent-child relationship, so repeating the parent name is redundant. The full prefixed name is retained in the database for uniqueness, search, exports, and chart labels.

---

## Cucumber Test Coverage

5 new scenarios added to `features/startup/kpi_workbook_reading.feature`:

| Scenario | Fixture File | What It Tests |
|---|---|---|
| ACT/BUDGET/IC tag row | `tag_columns.xlsx` | Per-column tag detection, separate KpiReports per tag |
| Indent parent-child | `indent_children.xlsx` | Cell indent detection, "Parent - Child" naming, duplicate child handling |
| Column parent-child | `column_children.xlsx` | Two-column layout detection, child mapping creation |
| Apostrophe dates | `apostrophe_dates.xlsx` | `Apr'25` format parsing into correct Date objects |
| Re-upload idempotency | `indent_children.xlsx` | No duplicate mappings on second upload |

Fixture files generated via `script/generate_kpi_test_fixtures.rb` using rubyXL (same gem the parser uses for indent reading).

---

### Fix 15: Child KPI Values Overwritten by Unmapped Parent Sections (2026-08-03)

#### The Problem

When the same child KPI name appears under multiple parent sections in the Excel — for example, "North" appears under both Revenue (row 12) and Contribution (row 33) — but only Revenue's children have configured mappings, the parser would silently overwrite the correct Revenue-North value with Contribution-North's value.

This happened because the parser reads top-to-bottom:
1. Hits Revenue → North (row 12) → saves correct value (254,637)
2. Hits Contribution → North (row 33) → finds "Revenue - North" mapping (the only one for "North") → overwrites with 201,623

#### The Fix

The `resolve_mapping` method now checks parent context before returning a mapping:

- **Single-mapping path:** If a child mapping exists but its parent doesn't match the current parent section being scanned, skip the row (return `nil`). E.g., "Revenue - North" won't be returned when the parser is inside Contribution's section.
- **Multi-mapping fallback:** Same parent check — if parent context is set but no mapping matches, skip instead of returning the first available mapping.
- **Parent KPIs are unaffected:** The check only applies when `mapping.parent_id` is present (child mappings). Parent KPIs like Revenue and Contribution themselves are never skipped.

#### Note on Decimal Values

Grid values like Revenue - North may show `254,636.50` instead of the Excel-displayed `254,637`. This is not a bug — Excel cells often contain raw decimal values (e.g., `254636.504552268`) displayed as whole numbers due to cell formatting. The parser reads the actual cell value, not the display format.

---

## Known Issues

1. **`KpiCumulateJob` missing `investor_kpi_mapping_id`:** The cumulation job creates Quarter/YTD KPI records without setting `investor_kpi_mapping_id`. These show as N/A in the grid view which groups by mapping ID. Pre-existing issue.

2. **`detect_period_type` defaults to "Month" for date-format headers:** Headers like "6/30/2024" don't match any named period pattern and default to "Month". Excel files should use named headers (e.g., "Q1 2024", "Jun 2024") for correct period detection.

3. **Children not collapsed by default:** The grid view shows all children expanded. Per product feedback, children should be collapsed by default with an expand toggle.

4. **"Actual" tag badge invisible on blue grid header:** The Actual tag badge uses `bg-primary-subtle` (light blue) which is invisible against the blue grid header background. Forecast (cyan) and IC Case (orange) badges are visible. Pending fix: change Actual badge to `bg-light text-dark` for contrast.

---

## Testing Checklist

### Prerequisites
- [ ] Portfolio company has parent KPI mappings configured (via KPI Mappings page or CSV import)
- [ ] Excel file has indented child rows with `text_indent` formatting (not just spaces)
- [ ] Excel file uses named period headers (e.g., "Q1 2024") — not date-format headers ("6/30/2024")

### After Upload
- [ ] Child `InvestorKpiMapping` records created with "Parent - Child" `standard_kpi_name`
- [ ] Each child mapping has correct `ancestry` (parent relationship)
- [ ] `Kpi` records created for all parents AND children
- [ ] Each `Kpi` has correct `investor_kpi_mapping_id`
- [ ] All KPIs have correct values (check denomination multiplier)
- [ ] Tag is "Actual" (not "A")

### Grid View
- [ ] Children appear immediately after their parent
- [ ] Children have `└` prefix
- [ ] Parents show child count badge
- [ ] Values displayed for both parents and children (not N/A)
- [ ] Duplicate names under different parents show correct (different) values

### Re-upload
- [ ] No duplicate mappings created
- [ ] Values updated correctly
- [ ] Parent-child relationships preserved
