# Report Builder User Guide

The **Report Builder** is a self-service tool for creating custom data exports — without writing any code. Pick a starting record type, pull in related data, summarise it (totals, counts, averages), filter and sort it, even pivot it into a cross-tab, and export the result to Excel.

This guide walks through building a report from scratch.

---

## Table of Contents

1. [What the Report Builder Does](#what-the-report-builder-does)
2. [Creating a Report](#creating-a-report)
3. [The Builder Layout](#the-builder-layout)
4. [Adding and Arranging Columns](#adding-and-arranging-columns)
5. [Pulling in Related Data](#pulling-in-related-data)
6. [Summarising Related Data](#summarising-related-data)
7. [Filtering and Sorting](#filtering-and-sorting)
8. [Pivot Tables](#pivot-tables)
9. [Preview and Export](#preview-and-export)
10. [Worked Example](#worked-example)
11. [Tips for Success](#tips-for-success)
12. [Walkthrough: Five Reports, From Simple to Complex](#walkthrough-five-reports-from-simple-to-complex)

---

## What the Report Builder Does

Start from one record type — say *Investor*, *Fund*, or *Capital Commitment* — and build outwards:

```mermaid
flowchart LR
    A[Pick a starting record<br/>e.g. Investor] --> B[Add related data<br/>e.g. their commitments]
    B --> C[Summarise<br/>totals, counts, averages]
    C --> D[Filter & sort]
    D --> E[Preview]
    E --> F[Export to Excel]
```

Everything is point-and-click; your work saves automatically.

---

## Creating a Report

1. Open the **Reports** list and click **New Custom Report**.
2. **Choose a starting record type** — the main subject of your report (e.g. *Investor*). This is the report's foundation.
3. You're taken into the builder.
4. Click the report name (default "Untitled Report") to rename it — changes save as you type.

---

## The Builder Layout

The builder has three panels:

| Panel | Purpose |
|-------|---------|
| **Available Columns** (left) | A searchable list of every field you can add, from your starting record and any related data you bring in. |
| **Selected Columns** (centre) | Your report's structure — reorder columns, rename them, and set how related data is summarised. |
| **Configuration** (right) | Bring in related data, apply filters, and set the default sort order. |

---

## Adding and Arranging Columns

- **Add** — click the **+** next to any field in the left panel.
- **Search** — use the search bar to find a field fast (there are hundreds).
- **Reorder** — drag the grip handle in the centre panel.
- **Remove** — click the trash icon next to a selected column.

---

## Pulling in Related Data

To include data connected to your starting record (e.g. an investor's commitments):

1. In the **Relations & Joins** section (right panel), pick a relationship from the dropdown.
2. Click **Add**.
3. That related data's fields now appear in the left panel, ready to add.

---

## Summarising Related Data

When a related record can have **many** rows for each starting record (an investor with several commitments), you choose how to summarise it:

| Summary | Result |
|---------|--------|
| **Sum** | The total (e.g. total committed amount). |
| **Count** | The number of records (e.g. number of commitments). |
| **Avg** | The average value. |
| **Min / Max** | The lowest / highest value. |
| **Latest** | The value from the most recent record (e.g. latest KYC status). |
| **List** | A comma-separated list of all unique values. |

---

## Filtering and Sorting

### Filters

You can filter the starting record and each related set independently:

1. In the **Filters** section, click **Add** under the relevant set.
2. Choose a **field**, an **operator** (equals, contains, greater than, any of…), and a **value**.
   - **Tip:** use **"any of"** with commas (e.g. `Individual, Institutional`) to match several values at once.
3. Click **Save All Filters**.

### Sorting

In **Default Sorting**, pick a column and a direction (ascending or descending) to set the order of rows in the export.

---

## Pivot Tables

Pivoting turns row values into columns — for example, showing each fund's committed amount as its own column.

1. In **Relations & Joins**, find the related set to pivot.
2. **Category** — the field that becomes the new column headers (e.g. Fund Name).
3. **Value** — the number to show (e.g. Amount).
4. **Aggregate** — how to combine it (usually Sum).
5. Click **Apply**.

---

## Preview and Export

- **Preview** — click **Preview** (or **Refresh Preview**) to see the first 50 rows and check your setup before exporting.
  - *Note:* a starting record with no matching related data shows `0` or blank in those columns, rather than being dropped.
- **Export** — click **Export XLSX** for a formatted Excel file. Large reports generate in the background, and you're notified when the download is ready.

---

## Worked Example

**Goal:** a one-row-per-investor report showing each investor's type and their total committed capital.

1. **New Custom Report** → start from **Investor**.
2. Add columns **Name** and **Investor Type** from the left panel.
3. In **Relations & Joins**, add the **Capital Commitments** relationship.
4. From the new fields, add **Committed Amount** and set its summary to **Sum** → "Total Committed".
5. Add a **filter**: Investor Type **any of** `Individual, Institutional`.
6. Set **Default Sorting** to Total Committed, descending.
7. **Preview** the first 50 rows; once it looks right, **Export XLSX**.

Result: a clean list of investors ranked by how much they've committed.

---

## Tips for Success

- **Start small** — add a few columns and preview often.
- **Check your summaries** — if a number looks off, confirm you're using **Sum** rather than **Count**.
- **Use search** — with hundreds of fields available, the search bar is the fastest way to find one.
- **Reports save automatically** — return to the Reports list any time to edit or re-run them.

---

## Walkthrough: Five Reports, From Simple to Complex

This section builds five real reports end to end, each one adding a new capability on top of the last. Follow them in order — by the end you'll have used every major feature: columns, joins, every summary type, pivot tables, filters, sorting, and formula columns.

> **Tip:** Sample versions of all five reports may already exist in your Reports list — look for the **Builder** tag on a report card. Building your own alongside them is a good way to check you get the same result.

### Report 1 (Simple): Distribution Payment Reconciliation

*New concepts: columns, filters, sorting, formula columns. No related data yet.*

1. Open **Reports** and click **New Custom Report**.
2. **Report Name**: `Distribution Payment Reconciliation`. **Root Model**: find **Capitaldistributionpayment** (under the *Funds* group — the dropdown runs the words together like this, that's expected) and select it. Click **Create & Configure**.
3. In the **Available** panel on the left, the top group (open by default) is your root model's own columns. Click the **+** next to each of: **Investing Entity**, **Folio No**, **Gross Payable**, **Net Payable**, **Payment Date**, **Completed**. Each one now appears in **Selected Columns** in the middle.
4. In the **Filters** card on the right, under the **Root** filters section, click **+ Add** and set: field **Completed**, operator **=**, value `true`. Click **+ Add** again: field **Net Payable**, operator **≥**, value `1`. Click **Save All Filters**.
5. In **Sorting & Grouping**, set **Default Sort** to **Payment Date**, direction **↓ DESC**.
6. In the **Formulas** card, click **+ Add Formula**. In the Formula Playground:
   - **Label**: `Fee Deducted`
   - **Expression**: type exactly `[gross_payable] - [net_payable]`
   - Click **Add Formula**.
7. Click **+ Add Formula** again:
   - **Label**: `Fee %`
   - **Expression**: type exactly `(([gross_payable] - [net_payable]) / [gross_payable]) * 100`
   - Click **Add Formula**.
8. Click **Refresh Preview** to check the numbers, then **Export XLSX** when you're happy with it.

You now have a filtered, sorted list of completed distribution payments with two computed columns showing the fee taken on each one.

### Report 2 (Add a Join and Summaries): KYC & AML Compliance Register

*New concepts: pulling in related data (a join), and every way to summarise it.*

1. **New Custom Report** → **Report Name**: `KYC & AML Compliance Register` → **Root Model**: **Investorkyc** (under *Core* — shown as one run-together word in the dropdown) → **Create & Configure**.
2. From **Available**, add root columns: **Investor**, **Investing Entity**, **Type**, **Kyc Verified**, **AML Status**.
3. In **Relations & Joins**, open the **+ Add new relation…** dropdown, choose **Capital commitments (has_many) ›**, and click **Add**. A new **Capital commitments** group now appears in the **Available** panel.
4. From that new group, add: **Committed**, **Called**, **Unit Type**, **Folio**, **Commitment date**.
5. Back in **Selected Columns**, each of those five new rows has an **Aggregate** dropdown (only related-data columns get one). Set:
   - **Committed** → `sum`
   - **Called** → `sum`
   - **Unit Type** → `list`
   - **Folio** → `count` (this gives you a commitment count — any column works for Count, since it just counts rows)
   - **Commitment date** → `min` (earliest commitment date)
6. In **Filters**, under the **Root** filters section, **+ Add**: field **AML Status**, operator **=**, value `potential_match`. **Save All Filters**.
7. In **Sorting & Grouping**, set **Default Sort** to **Kyc Verified**, **↑ ASC**.
8. In **Formulas**, **+ Add Formula**:
   - **Label**: `Call Coverage %`
   - **Expression**: type exactly `([capital_commitments.call_amount] / [capital_commitments.committed_amount]) * 100`
   - **Add Formula**.
9. **Refresh Preview**, then **Export XLSX**.

Each row is now a KYC record with that investor's commitment totals rolled up next to it — even though commitments live in a completely different part of the system.

### Report 3 (Pivot Table): Capital Call Collection Waterfall

*New concept: turning row values into their own columns.*

1. **New Custom Report** → **Report Name**: `Capital Call Collection Waterfall` → **Root Model**: **Capitalcall** (under *Funds* — again shown as one word) → **Create & Configure**.
2. From **Available**, add root columns: **Name**, **Due Date**, **Call Amount**, **Collected Amount**, **Due Amount**, **Approved**.
3. In **Relations & Joins**, add **Capital remittances (has_many) ›**.
4. On the new **Capital remittances** card, find **Pivot Configuration** and set:
   - **Categories (Multi-select)**: **Status**
   - **Value**: **Collected Amount**
   - **Aggregate**: `sum`
   - Click **Apply**.
5. In **Filters**, under the **Root** filters section, **+ Add**: field **Due Date**, operator **≥**, value a date a few years back (e.g. `2022-01-01`). **Save All Filters**.
6. In **Sorting & Grouping**, set **Default Sort** to **Due Date**, **↓ DESC**.
7. **Refresh Preview** — instead of one "Collected Amount" column, you'll now see one column *per remittance status* (e.g. Paid, Pending, Overdue), each showing the amount collected in that status for that call. **Export XLSX**.

This is the pivot in action: one join, turned sideways into a cross-tab instead of a single rolled-up total.

### Report 4 (Multiple Joins + Sort by Rolled-Up Data): LP Commitment & Capital Activity Summary

*New concepts: two joins at once, and sorting by a number that only exists after summarising.*

1. **New Custom Report** → **Report Name**: `LP Commitment & Capital Activity Summary` → **Root Model**: **Investor** (under *Core*) → **Create & Configure**.
2. From **Available**, add root columns: **Stakeholder**, **Tags**, **City**.
3. In **Relations & Joins**, add **Capital commitments (has_many) ›**, then add **Investor kycs (has_many) ›** as well — you now have two join cards.
4. From the **Capital commitments** group, add: **Committed**, **Called**, **Collected**, **Distributed**, **Folio**. Set aggregates: **Committed** → `sum`, **Called** → `sum`, **Collected** → `sum`, **Distributed** → `sum`, **Folio** → `count`.
5. From the **Investor kycs** group, add: **Kyc Verified**, **AML Status**. Set both aggregates to `latest` (the most recent KYC record's value).
6. In **Formulas**, **+ Add Formula**:
   - **Label**: `Uncalled Commitment`
   - **Expression**: type exactly `[capital_commitments.committed_amount] - [capital_commitments.call_amount]`
   - **Add Formula**.
7. In **Sorting & Grouping**, set **Default Sort** to **Committed** (the rolled-up total you just built), **↓ DESC**. Report Builder computes the totals first and then sorts by them — the report still comes back correctly even though "Committed" isn't a plain field on Investor.
8. **Refresh Preview**, then **Export XLSX**.

Result: one row per investor, ranked by total committed capital, with an uncalled-commitment figure and their latest KYC status alongside — all pulled from two different related tables.

### Report 5 (Capstone): Fund-Level Commitment & Call Activity Dashboard

*Combines everything above, plus currency labelling and a boolean filter.*

1. **New Custom Report** → **Report Name**: `Fund-Level Commitment & Call Activity Dashboard` → **Root Model**: **Fund** (under *Funds*) → **Create & Configure**.
2. From **Available**, add root columns: **Name**, **Category**, **Tags**.
3. In **Relations & Joins**, add **Capital commitments (has_many) ›** and **Capital calls (has_many) ›**.
4. From **Capital commitments**, add **Committed**, **Called**, **Collected**, **Distributed** — set all four aggregates to `sum`.
5. From **Capital calls**, add: **Name** (aggregate `count`, giving you a call count), **Call Amount** (aggregate `avg`, average call size), **Due Date** (aggregate `max`, most recent call's due date).
6. In **Filters**, under **Root: Fund**, **+ Add**: field **Snapshot**, operator **=**, value `false` — this excludes archived snapshot copies of funds. **Save All Filters**.
7. In **Sorting & Grouping**: set **Default Sort** to **Name**, **↑ ASC**. Set **Display Currency** to your entity's reporting currency (e.g. `INR`) — this just labels money columns with the right symbol, it doesn't convert anything.
8. **Refresh Preview**, then **Export XLSX**.

The result is a one-row-per-fund dashboard: commitment totals rolled up from every commitment, plus call activity (count, average size, most recent due date) rolled up from every capital call — the same techniques from Reports 2 and 4, combined on a single root.
