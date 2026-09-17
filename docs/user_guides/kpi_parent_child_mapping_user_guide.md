# KPI Parent-Child Mapping — Setup & Upload Guide

How to configure parent-child KPI hierarchies and upload Excel files with sub-category breakdowns.

> **Where to find it:** Sidebar → [**Stakeholders → View Stakeholders**](/investors) → open the portfolio company → **Kpi Mapping** tab. Add mappings one at a time with **New Investor Kpi Mapping** or in bulk with **Upload** (import type *InvestorKpiMapping*). Needs the *Enable Kpis* permission on your user; bulk upload also needs *Enable Import Uploads*.

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

Create a CSV/Excel file with these columns (optional extra columns: **Id**, **Lower Threshold**, **Upper Threshold**, **Auto Fill**, **Compute Formula**, **Update Only**):

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

3. **`Standard Kpi Name` = what the FM types.** For children in the bulk import, just type the child name (e.g., "Enterprise"). The import **auto-prefixes** it as "Parent - Child" (e.g., "Net Sales - Enterprise") to ensure uniqueness. This prefixing happens only in the bulk import: the **New Investor Kpi Mapping** / **Edit** form stores the standard name exactly as typed, so type the full prefixed name there.

4. **`Parent Standard Kpi Name`** = the standard name of the parent mapping. Leave blank for top-level KPIs.

5. **Same child name under different parents is fine.** "Enterprise" under "Net Sales" becomes "Net Sales - Enterprise". "Enterprise" under "Operating Cost" becomes "Operating Cost - Enterprise". The `Reported Kpi Name` stays as "Enterprise" for both — the parser uses parent context to match the right one.

### Import the Mapping File

**Path:** Portfolio company → **Kpi Mapping** tab → **Upload** (opens the import page with import type *InvestorKpiMapping* and a sample file pre-selected) → attach the file → save. You can also start from Company menu (house icon, top right) → **Imports**.

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

No duplicates are created, but every row whose mapping already exists is reported as a failed row ("InvestorKpiMapping already exists with Standard Kpi Name …") unless its **Update Only** column is `Yes`. With **Update Only** = `Yes`, the row updates the existing mapping (by **Id**, or by Stakeholder + names). New rows in the same file are still created.

The **Download** export on the **Kpi Mapping** tab heads its stakeholder column **Investor** (the import expects **Stakeholder**) and has no **Update Only** column, so rename that column and add **Update Only** before re-uploading an export.

A mapping that already has KPI values reported under it cannot be deleted, and deleting a parent mapping also deletes its child mappings.

### Verify in the UI

**Path:** Portfolio Company → **Kpi Mapping** tab

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

1. Open the [KPI Reports list](/kpi_reports) (fund logins have no sidebar entry; company logins use Sidebar → **Stakeholders → KPIs**) and click **New Kpi Report** (or edit an existing one)
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

**Path:** Portfolio Company → **Kpis** tab (or **Grid View** on the [KPI Reports list](/kpi_reports))

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

2. Import the CSV (upload just the new row, or set **Update Only** = `Yes` on existing rows — otherwise each existing row is reported as an "already exists" error, though nothing is duplicated)
3. Re-upload the Excel file with the new "West" row
4. "West" appears as a new child under "Net Sales" in the grid view

### Scenario 2: Same Child Name Under Multiple Parents

"Enterprise" appears under both "Net Sales" and "Operating Cost".

1. Configure both in the mapping CSV — the bulk import auto-prefixes:
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
2. Add new mappings for the skipped KPIs (bulk import of just the new rows, or **New Investor Kpi Mapping**)
3. Re-upload the same Excel → new KPIs are imported, existing ones updated (not duplicated)

---

## Troubleshooting

| Problem | Cause | Fix |
|---|---|---|
| "Target KPI 'X' not found in any sheet" | Mapping exists but Excel has no matching row, or the name doesn't match exactly | Check spelling in the mapping's `Reported Kpi Name` vs the Excel cell |
| Child values appear under the wrong parent | Children not listed directly below their parent in the Excel | Reorder the Excel so children follow their parent |
| "InvestorKpiMapping already exists with Standard Kpi Name …" on re-import | The row's mapping already exists | Remove existing rows from the file, or set **Update Only** = `Yes` to update them |
| "Parent KPI Mapping with standard name 'X' not found" during import | Parent row is listed after its children in the CSV | Move parent rows before their children |
| Child shows "N/A" in grid view | No `investor_kpi_mapping_id` set on the KPI record (pre-existing data) | Re-upload the Excel to create properly scoped records |

---

## Technical Reference

### Key Design Decisions

1. **No auto-creation of mappings.** The parser only imports values for pre-configured `InvestorKpiMapping` records. This prevents formatting artifacts (indents, merged cells, blank rows) from creating unwanted mappings.

2. **Auto-prefix `standard_kpi_name` (bulk import only).** The FM types "Enterprise" in the import file — the system stores "Net Sales - Enterprise". This ensures uniqueness without requiring the FM to type the full prefixed name. The single-mapping form does not prefix.

3. **Parent tracking via `@current_parent_mapping`.** Scans rows top-to-bottom. When a parent KPI row is encountered, it becomes the current parent. When a child with duplicate names is found, the current parent determines which mapping to use.

4. **Multi-column scan.** All columns before the first date column are checked for KPI name matches. This handles both single-column layouts (everything in column A) and two-column layouts (parents in A, children in B).

5. **Tag preservation.** Excel tag text (ACT, Forecast, IC Case) is stored as-is in `tag_list`. TAG_SYNONYMS is used only for detection, not normalization. This ensures the grid view filter matches what users typed in their Excel.

---

## Frequently Asked Questions

### Navigation and getting there

**Where do I find a portfolio company's KPI mappings?**
Sidebar → [**Stakeholders → View Stakeholders**](/investors), open the stakeholder whose **Category** is *Portfolio Company*, then click the **Kpi Mapping** tab. It lists every mapping in position order with **Show** and **Edit** buttons, plus **New Investor Kpi Mapping**, **Download**, **Upload** and **Generate From Last Report**.

**Where do I upload the mapping file?**
On the portfolio company's **Kpi Mapping** tab click **Upload**, which opens the upload form with import type *InvestorKpiMapping* and the [sample file](/sample_uploads/investor_kpi_mappings.xlsx). You can also start from Company menu (house icon, top right) → [**Imports**](/import_uploads). See [Import the Mapping File](#import-the-mapping-file).

**Where do I upload the KPI workbook once mappings exist?**
Fund logins open the [KPI Reports list](/kpi_reports) (there is no fund sidebar entry) and click [**New Kpi Report**](/kpi_reports/new); company logins use Sidebar → **Stakeholders → KPIs**. See [Upload Steps](#upload-steps) and the KPI Management & Workbook Upload guide.

**Where do I check the hierarchy and the imported values?**
The **Kpi Mapping** tab shows the mappings; the stakeholder's **Kpis** tab (or **Grid View** on the [KPI Reports list](/kpi_reports)) shows parent rows with a child-count badge and indented child rows. See [Step 3: Review Results](#step-3-review-results).

**I can't see the Kpi Mapping tab.**
The **Kpis** and **Kpi Mapping** tabs only appear on stakeholders whose **Category** is *Portfolio Company*, and only for users with *Enable Kpis*. A company admin switches that on at Company menu → [**User**](/users) → edit the user.

**What permissions do I need?**
*Enable Kpis* to see mappings; to create, edit or delete them you must be a *company_admin* or an employee with update access to the record. **Upload** additionally needs *Enable Import Uploads*.

### Creating, updating and managing mappings

**How do I create parent and child mappings in bulk?**
Prepare a sheet with **Stakeholder**, **Reported Kpi Name**, **Standard Kpi Name**, **Category**, **Data Type**, **Denomination**, **Parent Standard Kpi Name**, **Position**, **Show In Report** (optional: Lower/Upper Threshold, Auto Fill, Compute Formula, Update Only), list parents before children and upload it. See [Prepare the Mapping CSV](#prepare-the-mapping-csv).

**How do I add a single mapping by hand?**
On the **Kpi Mapping** tab click **New Investor Kpi Mapping**, fill **Reported kpi name**, **Standard kpi name**, category, data type and denomination, pick the parent in **Parent** for a child, and save. The form does not add the "Parent - " prefix, so type the full standard name (e.g. `Net Sales - Enterprise`) yourself.

**How do I edit a mapping?**
Click **Edit** on its row, change names, category, data type, denomination, **Parent**, **Position**, thresholds or the RAG rule, and save. Changing **Reported kpi name** changes which workbook label is matched from the next upload onward.

**How do I update many existing mappings from a file?**
Upload rows with **Update Only** = `Yes`. A row with an **Id** updates that mapping; without an **Id**, the mapping is found by **Stakeholder**, **Standard Kpi Name** and **Reported Kpi Name** (for a child, fill **Parent Standard Kpi Name** and the unprefixed child name is matched). Rows without **Update Only** = `Yes` are treated as new and fail if the mapping already exists.

**How do I export mappings?**
Click **Download** on the **Kpi Mapping** tab for an Excel file with **Id**, names, category, data type, parent and position. Its stakeholder column is headed **Investor**, so rename it to **Stakeholder** and add **Update Only** before re-uploading it.

**How do I delete a mapping?**
Open it with **Show** and click **Delete**. A mapping that already has KPI values reported under it cannot be deleted, and deleting a parent also deletes its child mappings.

**Can mappings be created from an existing report instead?**
Yes: **Generate From Last Report** on the **Kpi Mapping** tab creates a flat mapping (reported name = standard name, **Show In Report** on) for each KPI in the company's most recent KPI report. It does not create parent-child links; set **Parent** afterwards.

### Why use parent-child mappings

**Why should I set up parent-child mappings?**
Portfolio companies report totals with segment breakdowns (Net Sales by Enterprise / Mid-Market / SMB). Mappings let CapHive import each segment as its own KPI, keep the same child name under different parents apart, and show them grouped under the parent in the grid.

**What does it let me do that I cannot do otherwise?**
Track sub-category trends over time, collapse or expand them under the parent in the KPI grid, get a Workbook check hint when children do not add up to the parent, and accept all three common Excel layouts without asking companies to rename rows.

**What happens if I don't configure mappings before uploading?**
Nothing from unmapped rows is imported: the parser never creates mappings from indentation or column layout. If a company has no mappings at all, uploads are refused until mappings exist.

**Who typically sets up mappings?**
Fund portfolio-monitoring or operations staff, once per portfolio company and whenever the company starts reporting a new line or segment.

### What happens when I …

**What happens when I import a child row?**
The mapping is saved with **Reported Kpi Name** as typed (used for matching the workbook), **Standard Kpi Name** prefixed as `Parent - Child`, and linked to the parent found by its standard name. The parent's child count is refreshed. See [What Happens on Import](#what-happens-on-import).

**What happens if I re-import a mapping file that contains existing mappings?**
No duplicates are created, but each row that already exists is reported as an error ("InvestorKpiMapping already exists…") unless **Update Only** is `Yes`. New rows in the same file are still created. Review the row errors on the import upload page.

**What happens if a parent row comes after its child in the file?**
That child row fails with "Parent KPI Mapping with standard name 'X' not found". Rows are processed top to bottom, so move parents above children and re-upload the failed rows.

**What happens when I upload a KPI workbook for a company with parent-child mappings?**
The Workbook check matches labels in all columns before the first date column, tracks the current parent to resolve repeated child names, and stages one unapproved value per mapped KPI per period and tag. Values only reach dashboards once approved. See [How the Parser Matches](#how-the-parser-matches).

**What happens if children don't add up to the parent?**
When a parent and all of its (two or more) mapped children have values for a period and differ by more than 1%, the Workbook check shows a hint. It never blocks the upload.

**What happens if a child name is mapped under two parents and the sheet doesn't show which one?**
The row is skipped and a warning is shown in the Workbook check; the parser never guesses. Place the row directly under its parent row, or repeat the parent in the column to its left.

**What happens when I add a new child mapping after an upload?**
Existing values are unchanged. Re-upload the workbook: the new child's values are imported and existing ones are updated rather than duplicated. See [Scenario 3: Re-uploading After Adding New Mappings](#scenario-3-re-uploading-after-adding-new-mappings).

### Troubleshooting and edge cases

**"Target KPI 'X' not found in any sheet" after upload.**
The mapping exists but no workbook row matched its **Reported Kpi Name** exactly. Fix the spelling on either side; this is a data gap, not a configuration error. See [Troubleshooting](#troubleshooting).

**A row in the workbook was silently ignored.**
It has no mapping (or its label differs from every **Reported Kpi Name**). Add the mapping on the **Kpi Mapping** tab and re-upload the workbook.

**Child values appear under the wrong parent.**
Children must be listed directly below their parent, or carry the parent name in the column to the left (Layout C). A label in the parent column that is not a mapped KPI resets the current parent. See [Supported Excel Layouts](#supported-excel-layouts).

**I get an error for the same child appearing twice.**
The same child under the same parent has two different values for one period. The Workbook check blocks the upload until you keep only one.

**My grandchild row fails to find its parent on import.**
**Parent Standard Kpi Name** must be the parent's stored standard name, which for a child is already prefixed (e.g. `Net Sales - Enterprise`), not just `Enterprise`.

**Can I use tags such as Forecast or IC Case?**
Yes. A tag row above the dates (ACT, BUDGET, IC, Forecast…) creates a separate KPI report per tag, and the tag text is kept as written. See [ACT/BUDGET/IC Tag Columns](#actbudgetic-tag-columns).

**The child shows "N/A" in the grid view.**
The KPI was saved before it was linked to a mapping (older data). Re-upload the workbook so the values are stored against the correct mapping.

## Related Guides

- [KPI Management & Workbook Upload](kpi_upload_user_guide) — the upload, Workbook check and approval flow that uses these mappings.
- [KPI RAG Status](kpi_rag_status_user_guide) — red/amber/green rules configured on the same mapping.
- [KPI Flexible Charts](kpi_flexible_charts_user_guide) — chart parent and child KPIs from the grid.
- [Stakeholders (Investors)](investors_user_guide) — where portfolio companies and their Kpi Mapping tab live.
- [Custom Fields](custom_fields_user_guide) — extra fields on KPI mappings, carried as extra upload columns.
- [Agent Charts](agent_charts_user_guide) — AI charts that pick KPIs by their standard names.
