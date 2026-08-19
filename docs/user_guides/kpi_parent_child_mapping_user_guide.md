# KPI Parent-Child Mapping — Setup & Upload Guide

How to configure parent-child KPI hierarchies and upload Excel files with sub-category breakdowns.

**Branch:** `feature/kpi-multi-column-detection`
**Supersedes:** PR #1560 (auto-creation approach)
**Date:** 2026-07-31

---

## Overview

Portfolio companies often report KPIs with sub-category breakdowns:

```
Net Sales
  Enterprise       500
  Mid-Market       300
  SMB              200
Operating Cost
  Enterprise       400
  Mid-Market       430
```

The system supports importing these breakdowns, but **all parent-child KPI mappings must be configured before uploading the Excel file**. The parser does not auto-create child mappings from indentation or column layout. It only imports values for KPIs that already have a matching `InvestorKpiMapping`.

This explicit approach prevents unwanted mappings from formatting artifacts and gives the fund manager full control over what gets tracked.

---

## Step 1: Configure Parent-Child Mappings via Bulk Import

### Prepare the Mapping CSV

Create a CSV/Excel file with these columns:

| Stakeholder | Reported Kpi Name | Standard Kpi Name | Category | Data Type | Denomination | Parent Standard Kpi Name | Position | Show In Report |
|---|---|---|---|---|---|---|---|---|
| Acme Corp | Net Sales | Net Sales | Income Statement | money | crores | | 1 | Yes |
| Acme Corp | Enterprise | Enterprise | Income Statement | money | crores | Net Sales | 2 | Yes |
| Acme Corp | Mid-Market | Mid-Market | Income Statement | money | crores | Net Sales | 3 | Yes |
| Acme Corp | SMB | SMB | Income Statement | money | crores | Net Sales | 4 | Yes |
| Acme Corp | Operating Cost | Operating Cost | Income Statement | money | crores | | 5 | Yes |
| Acme Corp | Enterprise | Enterprise | Income Statement | money | crores | Operating Cost | 6 | Yes |
| Acme Corp | Mid-Market | Mid-Market | Income Statement | money | crores | Operating Cost | 7 | Yes |

**Key rules:**

1. **Parents first:** Define the parent row before its children. The import looks up the parent by `Standard Kpi Name`, so it must already exist.

2. **`Reported Kpi Name` = what the portco's Excel says.** Use the exact name from the Excel file (e.g., "Enterprise", not "Net Sales - Enterprise"). This is what the parser matches against.

3. **`Standard Kpi Name` = what the FM types.** For children, just type the child name (e.g., "Enterprise"). The system **auto-prefixes** it as "Parent - Child" (e.g., "Net Sales - Enterprise") to ensure uniqueness. You do NOT need to type the prefix manually.

4. **`Parent Standard Kpi Name`** = the standard name of the parent mapping. Leave blank for top-level KPIs.

5. **Same child name under different parents is fine.** "Enterprise" under "Net Sales" becomes "Net Sales - Enterprise". "Enterprise" under "Operating Cost" becomes "Operating Cost - Enterprise". The `Reported Kpi Name` stays as "Enterprise" for both — the parser uses parent context to match the right one.

### Import the Mapping File

**Path:** Import Uploads → New → Import Type: "InvestorKpiMapping" → Upload the CSV → Import

### What Happens on Import

For each row with a `Parent Standard Kpi Name`:

```
CSV row:
  Reported Kpi Name = "Enterprise"
  Standard Kpi Name = "Enterprise"
  Parent Standard Kpi Name = "Net Sales"

System stores:
  reported_kpi_name  = "Enterprise"       (kept as-is for Excel matching)
  standard_kpi_name  = "Net Sales - Enterprise"  (auto-prefixed for uniqueness)
  parent_id          = <Net Sales mapping ID>     (linked via ancestry)
```

### Re-importing the Same CSV

Re-importing is safe. The system searches for the prefixed name first ("Net Sales - Enterprise") and finds the existing record. No duplicates are created.

### Verify in the UI

**Path:** Portfolio Company → KPI Mapping tab

You should see the parent-child hierarchy:

```
Net Sales
  ├── Enterprise
  ├── Mid-Market
  └── SMB
Operating Cost
  ├── Enterprise
  └── Mid-Market
```

---

## Step 2: Upload the KPI Excel File

### Supported Excel Layouts

The parser handles two common parent-child layouts:

#### Layout A: Indented Children (Same Column)

Parents and children are in the same column. Children are visually indented in the Excel but the parser matches by **name**, not by indent.

```
┌───────────────┬────────┬────────┬────────┐
│               │ Apr 25 │ May 25 │ Jun 25 │
├───────────────┼────────┼────────┼────────┤
│ Net Sales     │  1000  │  1100  │  1200  │
│   Enterprise  │   500  │   550  │   600  │
│   Mid-Market  │   300  │   330  │   360  │
│   SMB         │   200  │   220  │   240  │
│ Operating Cost│   800  │   850  │   900  │
│   Enterprise  │   400  │   420  │   440  │
│   Mid-Market  │   400  │   430  │   460  │
└───────────────┴────────┴────────┴────────┘
```

#### Layout B: Column-Based Children (Parent in Column A, Children in Column B)

Parents are in column A, children are in column B. Values start from column C onward.

```
┌──────────────┬─────────────┬────────┬────────┬────────┐
│              │             │ Apr 25 │ May 25 │ Jun 25 │
├──────────────┼─────────────┼────────┼────────┼────────┤
│ Net Sales    │             │  1000  │  1100  │  1200  │
│              │ Enterprise  │   500  │   550  │   600  │
│              │ Mid-Market  │   300  │   330  │   360  │
│              │ SMB         │   200  │   220  │   240  │
│ Operating Cost│            │   800  │   850  │   900  │
│              │ Enterprise  │   400  │   420  │   440  │
│              │ Mid-Market  │   400  │   430  │   460  │
└──────────────┴─────────────┴────────┴────────┴────────┘
```

#### Layout C: Parent Repeated on Every Child Row (Filled-Down)

Common in exports and pivot tables — the parent name is repeated in column A on each child row, with the child in column B. The parent's own total sits on a row with an empty column B.

```
┌──────────────┬─────────────┬────────┬────────┬────────┐
│ KPI          │ Segment     │ Apr 25 │ May 25 │ Jun 25 │
├──────────────┼─────────────┼────────┼────────┼────────┤
│ Net Sales    │             │  1000  │  1100  │  1200  │
│ Net Sales    │ Enterprise  │   500  │   550  │   600  │
│ Net Sales    │ Mid-Market  │   300  │   330  │   360  │
│ Net Sales    │ SMB         │   200  │   220  │   240  │
│ Operating Cost│            │   800  │   850  │   900  │
│ Operating Cost│ Enterprise │   400  │   420  │   440  │
└──────────────┴─────────────┴────────┴────────┴────────┘
```

A row that names both a parent and one of its own children is read as the **child** row; the parent label on it is treated as context.

### How the Parser Matches

The parser scans **all columns before the first date column** (left to right) and collects every cell that matches a configured "Reported KPI Name". If a row names a parent and one of that parent's children (Layout C) the child wins; otherwise the leftmost match is used.

```
Header:   [  KPI  |        | Apr 25 | May 25 | Jun 25 ]
                             ↑
                      first date column = index 2
                      
          columns 0-1 are scanned for KPI name matches
```

**Parent disambiguation:** The parser tracks which parent was most recently encountered. When "Enterprise" appears, it checks which parent is current:
- After "Net Sales" row → "Enterprise" resolves to "Net Sales - Enterprise"
- After "Operating Cost" row → "Enterprise" resolves to "Operating Cost - Enterprise"

This means the Excel file must list children **directly below their parent** (which is the natural layout in financial statements). Two safeguards apply:
- A row whose label in the parent column is **not a mapped KPI** (e.g. a "Customers" section) resets the current parent, so a following "Enterprise" is not silently attributed to the previous section.
- If a child name is mapped under **more than one** parent and the sheet gives no clue which section the row belongs to (for example the child appears before any parent row), the row is **skipped and a warning is shown** in the Workbook check panel — the parser never guesses. Put the row under its parent.

**Sum check:** when a parent and *all* of its mapped children (two or more) carry values for a period and the children do not add up to the parent (±1 %), the Workbook check shows a hint such as "Net Sales, Jun 2026: 1,000 but its 2 components add up to 900 (Enterprise + SMB)". It never blocks the upload.

### ACT/BUDGET/IC Tag Columns

If the Excel has Actual and Budget data side by side with a tag row:

```
┌───────────────┬────────┬────────┬────────┬────────┬────────┬────────┐
│               │ Apr 25 │ May 25 │ Jun 25 │ Apr 25 │ May 25 │ Jun 25 │
│               │  ACT   │  ACT   │  ACT   │ BUDGET │ BUDGET │ BUDGET │
├───────────────┼────────┼────────┼────────┼────────┼────────┼────────┤
│ Net Sales     │  1000  │  1100  │  1200  │   950  │  1050  │  1150  │
│   Enterprise  │   500  │   550  │   600  │   475  │   525  │   575  │
```

The parser detects the tag row (ACT/BUDGET/IC labels) and creates **separate KpiReports** per tag. The tag values from the Excel are preserved as-is (e.g., "Forecast" stays "Forecast", not mapped to "Budget").

### Upload Steps

1. Go to Sidebar → KPIs → "New Kpi Report" (or edit existing)
2. Select the Portfolio Company
3. Set As Of date, Period, and Tag
4. Attach the Excel file
5. Check "Upload new KPIs"
6. Click Save

### The Workbook Check

Before saving, the upload form shows the **Workbook check** panel — the same check the import itself runs, so what it shows is what will be stored. For parent-child files it reports:

- **Found / missing KPIs:** which mapped KPIs (parents and children) were found in the Excel and which were not
- **How we read your file:** one row per value with the resolved name (e.g. `Enterprise (Net Sales - Enterprise)`), what was in the file and what will be stored
- **Warnings:** a child skipped because its parent could not be determined, or a parent that does not equal the sum of its children
- **Errors:** the same child under the same parent appearing twice with different values for a period (blocks the upload until one is removed)

See the *KPI Management & Workbook Upload User Guide* for the full list of checks.

---

## Step 3: Review Results

### Grid View

**Path:** Portfolio Company → KPIs tab → Grid View

Parent-child KPIs are displayed with:
- Parent rows with expand/collapse toggle and a child count badge
- Child rows indented under their parent, showing `reported_kpi_name` (e.g., "Enterprise") instead of the full prefixed name
- All values staged as **unapproved** (shown in orange with "Pending" badge)

### What If a Child KPI Is Missing?

If a child mapping is configured but no matching row exists in the Excel:
- The import log reports: "Target KPI 'Enterprise' not found in any sheet"
- No data is imported for that mapping
- The grid view shows empty cells for that child
- This is a data gap in the Excel, not a configuration error

### What If a Child KPI Exists in Excel But Has No Mapping?

- The row is silently skipped
- No values are imported
- To fix: add the mapping via bulk import, then re-upload

---

## Common Scenarios

### Scenario 1: Adding a New Sub-Category

A portco starts reporting a new region ("West") under "Net Sales".

1. Add a new row to the mapping CSV:

   | Stakeholder | Reported Kpi Name | Standard Kpi Name | Parent Standard Kpi Name |
   |---|---|---|---|
   | Acme Corp | West | West | Net Sales |

2. Import the CSV (existing mappings won't be duplicated)
3. Re-upload the Excel file with the new "West" row
4. "West" appears as a new child under "Net Sales" in the grid view

### Scenario 2: Same Child Name Under Multiple Parents

"Enterprise" appears under both "Net Sales" and "Operating Cost".

1. Configure both in the mapping CSV — the system auto-prefixes:
   - "Enterprise" under "Net Sales" → `standard_kpi_name: "Net Sales - Enterprise"`
   - "Enterprise" under "Operating Cost" → `standard_kpi_name: "Operating Cost - Enterprise"`

2. In the Excel, children must be listed directly below their parent:
   ```
   Net Sales         ← parser sets current parent = Net Sales
     Enterprise      ← resolves to "Net Sales - Enterprise"
     Mid-Market
   Operating Cost    ← parser sets current parent = Operating Cost
     Enterprise      ← resolves to "Operating Cost - Enterprise"
     Mid-Market
   ```

3. Values are saved to the correct mapping — no cross-parent collision. (Layout C — the parent name repeated on each child row — works too.)

4. If "Enterprise" appears **without** a parent row above it, that row is skipped with a warning ("mapped under Net Sales and Operating Cost, but the sheet does not show which section this row belongs to") instead of being guessed.

### Scenario 3: Re-uploading After Adding New Mappings

1. Upload Excel → only mapped KPIs are imported, others skipped
2. Add new mappings via bulk import for the skipped KPIs
3. Re-upload the same Excel → new KPIs are imported, existing ones updated (not duplicated)

---

## Troubleshooting

| Problem | Cause | Fix |
|---|---|---|
| "Target KPI 'X' not found in any sheet" | Mapping exists but Excel has no matching row, or the name doesn't match exactly | Check spelling in the mapping's `Reported Kpi Name` vs the Excel cell |
| Child values appear under the wrong parent | Children not listed directly below their parent in the Excel | Reorder the Excel so children follow their parent |
| Duplicate mappings created on re-import | Re-import before this fix was applied | Delete duplicates manually, re-import with the fixed code |
| "Parent KPI Mapping with standard name 'X' not found" during import | Parent row is listed after its children in the CSV | Move parent rows before their children |
| Child shows "N/A" in grid view | No `investor_kpi_mapping_id` set on the KPI record (pre-existing data) | Re-upload the Excel to create properly scoped records |

---

## Technical Reference

### Files Changed in This Feature

| File | Change |
|---|---|
| `kpi_workbook_reader.rb` | Multi-column scan, `group_by` mappings, `resolve_mapping` with parent tracking, tag preservation, mapping-ID-scoped saves. No auto-creation. |
| `import_investor_kpi_mapping.rb` | Auto-prefix `standard_kpi_name` as "Parent - Child". Prefixed name lookup on re-import to prevent duplicates. |
| `kpis_helper.rb` | "Forecast" badge color (cyan/info). |
| `kpi_xlsx_report_controller.js` | Client-side preview scans all cells in row (not just column A). |
| `features/startup/kpi_workbook_reading.feature` | Cucumber scenarios updated for explicit mapping approach. |
| `features/step_definitions/kpi_workbook_steps.rb` | Step definitions for pre-configured parent-child mappings. |

### Key Design Decisions

1. **No auto-creation of mappings.** The parser only imports values for pre-configured `InvestorKpiMapping` records. This prevents formatting artifacts (indents, merged cells, blank rows) from creating unwanted mappings.

2. **Auto-prefix `standard_kpi_name`.** The FM types "Enterprise" — the system stores "Net Sales - Enterprise". This ensures DB uniqueness without requiring the FM to type the full prefixed name.

3. **Parent tracking via `@current_parent_mapping`.** Scans rows top-to-bottom. When a parent KPI row is encountered, it becomes the current parent. When a child with duplicate names is found, the current parent determines which mapping to use.

4. **Multi-column scan.** All columns before the first date column are checked for KPI name matches. This handles both single-column layouts (everything in column A) and two-column layouts (parents in A, children in B).

5. **Tag preservation.** Excel tag text (ACT, Forecast, IC Case) is stored as-is in `tag_list`. TAG_SYNONYMS is used only for detection, not normalization. This ensures the grid view filter matches what users typed in their Excel.
