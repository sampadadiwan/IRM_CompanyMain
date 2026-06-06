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

1. Open the **Reports** list and click **New Report (Builder)**.
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

1. **New Report (Builder)** → start from **Investor**.
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
