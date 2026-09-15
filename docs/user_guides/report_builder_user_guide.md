# Report Builder User Guide

The **Report Builder** is a self-service tool for creating custom data exports — without writing any code. Pick a starting record type, pull in related data, summarise it (totals, counts, averages), filter and sort it, even pivot it into a cross-tab, and export the result to Excel.

> **Where to find it:** Sidebar → [**Funds → Reports**](/reports) (shown when your user has the *Reports* feature; other logins can open the [Reports page](/reports) from this link). Click **New Custom Report** to start the [guided wizard](/report_builder/wizard); the one-page [advanced form](/report_builder/new) has no button of its own. Reopen a report with **Edit** on its card. Any user of your company can create and edit builder reports.

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
13. [Frequently Asked Questions](#frequently-asked-questions)

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

Everything is point-and-click; your work saves automatically. Reports are shared: every user of your company with the same role can see and edit them, and report rows include every matching record of your company (individual record access rights are not applied).

---

## Creating a Report

1. Open the **Reports** list and click **New Custom Report**. This opens the [guided wizard](/report_builder/wizard).
2. Enter a name under **What should we call this report?**
3. **Choose a starting record type** under **What do you want to report on?** — the main subject of your report (e.g. *Investor*). This is the report's foundation.
4. Click **Start Building**. The wizard walks you through **Columns**, **Related Data**, **Summarize**, **Filters**, **Sort** and **Review**; click **Advanced Builder** at the top (or **Open My Report** on Review) to switch to the builder described below.

The one-page [advanced form](/report_builder/new) (**Report Name**, **Root Model**, **Create & Configure**) has no button on the Reports page; it takes you straight into the builder. In the builder, click the report name to rename it (Enter or click away saves, Escape cancels; a blank name becomes "Untitled Report").

---

## The Builder Layout

The builder header has **Guided Wizard**, a **Build** / **View** toggle, **Templates** (the Quick Start Gallery — applying one replaces the report's current configuration) and **Export XLSX**. Below it are three panels:

| Panel | Purpose |
|-------|---------|
| **Available Columns** (left) | A searchable list of every field you can add, from your starting record and any related data you bring in. |
| **Selected Columns** (centre) | Your report's structure — reorder and remove columns, and set how related data is summarised. Columns can't be renamed here; change a column's label on the wizard's **Columns** or **Summarize** step. |
| **Configuration** (right) | Bring in related data, apply filters, set the default sort order, add formulas, and schedule **Automated Delivery** by email. |

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

In **Sorting & Grouping**, pick a **Default Sort** column and a direction (ascending or descending) to set the order of rows in the export.

---

## Pivot Tables

Pivoting turns row values into columns — for example, showing each fund's committed amount as its own column.

1. In **Relations & Joins**, find the related set to pivot and open its **Pivot Configuration**.
2. **Categories (Multi-select)** — the field(s) that become the new column headers (e.g. Fund Name).
3. **Value** — the number to show (e.g. Amount).
4. **Aggregate** — how to combine it (usually Sum).
5. Click **Apply**.

---

## Preview and Export

- **Preview** — click **Refresh Preview** to see the first 20 rows and the total row count and check your setup before exporting. To see the full paginated table, click the report's name in the breadcrumb at the top of the builder.
  - *Note:* a starting record with no matching related data shows `0` or blank in those columns, rather than being dropped.
- **Export** — click **Export XLSX** for a formatted Excel file. Every export runs in the background; the file is saved as a document in your company's **Reports** folder and an on-screen alert links to it (no email is sent).

---

## Worked Example

**Goal:** a one-row-per-investor report showing each investor's type and their total committed capital.

1. Open the [advanced form](/report_builder/new), name the report and choose **Investor** as the **Root Model** → **Create & Configure**.
2. Add columns **Name** and **Investor Type** from the left panel.
3. In **Relations & Joins**, add the **Capital Commitments** relationship.
4. From the new fields, add **Committed Amount** and set its summary to **Sum** (to label it "Total Committed", change the label on the wizard's **Summarize** step).
5. Add a **filter**: Investor Type **any of** `Individual, Institutional`.
6. In **Sorting & Grouping**, set **Default Sort** to the committed total, descending.
7. **Refresh Preview** to check the first 20 rows; once it looks right, **Export XLSX**.

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

1. Open the [advanced form](/report_builder/new) (there is no button for it on the Reports page — **New Custom Report** opens the guided wizard instead).
2. **Report Name**: `Distribution Payment Reconciliation`. **Root Model**: find **Capital distribution payment** (under the *Funds* group) and select it. Click **Create & Configure**.
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

1. [Advanced form](/report_builder/new) → **Report Name**: `KYC & AML Compliance Register` → **Root Model**: **Investor kyc** (under *Core*) → **Create & Configure**.
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

1. [Advanced form](/report_builder/new) → **Report Name**: `Capital Call Collection Waterfall` → **Root Model**: **Capital call** (under *Funds*) → **Create & Configure**.
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

1. [Advanced form](/report_builder/new) → **Report Name**: `LP Commitment & Capital Activity Summary` → **Root Model**: **Investor** (under *Core*) → **Create & Configure**.
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

1. [Advanced form](/report_builder/new) → **Report Name**: `Fund-Level Commitment & Call Activity Dashboard` → **Root Model**: **Fund** (under *Funds*) → **Create & Configure**.
2. From **Available**, add root columns: **Name**, **Category**, **Tags**.
3. In **Relations & Joins**, add **Capital commitments (has_many) ›** and **Capital calls (has_many) ›**.
4. From **Capital commitments**, add **Committed**, **Called**, **Collected**, **Distributed** — set all four aggregates to `sum`.
5. From **Capital calls**, add: **Name** (aggregate `count`, giving you a call count), **Call Amount** (aggregate `avg`, average call size), **Due Date** (aggregate `max`, most recent call's due date).
6. In **Filters**, under **Root: Fund**, **+ Add**: field **Snapshot**, operator **=**, value `false` — this excludes archived snapshot copies of funds. **Save All Filters**.
7. In **Sorting & Grouping**: set **Default Sort** to **Name**, **↑ ASC**. Set **Display Currency** to your entity's reporting currency (e.g. `INR`) — this just labels money columns with the right symbol, it doesn't convert anything.
8. **Refresh Preview**, then **Export XLSX**.

The result is a one-row-per-fund dashboard: commitment totals rolled up from every commitment, plus call activity (count, average size, most recent due date) rolled up from every capital call — the same techniques from Reports 2 and 4, combined on a single root.

---

## Frequently Asked Questions

### Navigation and getting there

**Where do I find the Report Builder in CapHive?**
Sidebar → [**Funds → Reports**](/reports). The **Reports** item appears when your user has the *Reports* feature; if it is missing you can still open the [Reports page](/reports) from this link. Builder reports show on that page as cards alongside the standard reports.

**How do I start a new report?**
On the [Reports page](/reports) click **New Custom Report**; it opens the [guided wizard](/report_builder/wizard) where you name the report and answer "What do you want to report on?". The one-page advanced form with **Report Name**, **Root Model** and **Create & Configure** has no button; open the [advanced form](/report_builder/new) from this link. See [Creating a Report](#creating-a-report).

**How do I reopen a report I built?**
On the [Reports page](/reports) click the report's name, or **Edit** in its card menu, to open the advanced builder. **Guided Wizard** in the same menu reopens it step by step.

**How do I switch between the guided wizard and the advanced builder?**
In the wizard click **Advanced Builder** at the top, or **Open My Report** on the Review step. In the advanced builder click **Guided Wizard**; it starts on the Columns step and the progress bar lets you jump to any step.

**Where do exported files go?**
Each **Export XLSX** saves an Excel document named after the report in your company's **Reports** documents folder (or the top folder if there is none), and an on-screen alert links to it. Browse them under Sidebar → [**Documents**](/documents).

**Is there a full-page view of all rows?**
Yes. Click the report's name in the breadcrumb at the top of the builder to see it as a paginated table (100 rows per page) with **Edit Builder** and **Download** buttons; the builder's own preview shows only the first 20 rows.

### Creating, updating and managing reports

**What are the steps in the guided wizard?**
**Columns**, **Related Data**, **Summarize**, **Filters**, **Sort** and **Review**. **Summarize** is skipped automatically when you have not added any related data. Each step saves as you go; **Open My Report** on Review takes you to the advanced builder.

**How do I add, rename, reorder or remove columns?**
In the advanced builder click **+** beside a field in **Available**, drag the grip in **Selected Columns** to reorder, and use the trash icon to remove it. To rename a column, open **Guided Wizard** and change its label on the **Columns** (or **Summarize**) step. See [Adding and Arranging Columns](#adding-and-arranging-columns).

**How do I bring in related data?**
In **Relations & Joins**, choose a relationship from **+ Add new relation…** and click **Add**; its fields appear as a new group in **Available**. Remove a join from its card. See [Pulling in Related Data](#pulling-in-related-data).

**How do I summarise related data?**
Each related-data column in **Selected Columns** has an **Aggregate** dropdown: sum, count, avg, min, max, latest or list. See [Summarising Related Data](#summarising-related-data).

**How do I filter and sort?**
In **Filters**, click **+ Add** under the root or a related set, choose field, operator and value, then **Save All Filters**. In **Sorting & Grouping**, pick **Default Sort** and direction. See [Filtering and Sorting](#filtering-and-sorting).

**How do I add a formula column?**
In **Formulas** click **+ Add Formula**, enter a **Label** and an **Expression** using column keys in square brackets (e.g. `[gross_payable] - [net_payable]`), check the live preview and click **Add Formula**. Remove one with its delete button.

**How do I build a pivot table?**
On a related-data card in **Relations & Joins**, open **Pivot Configuration**, pick the **Categories**, **Value** and **Aggregate**, and click **Apply**. See [Pivot Tables](#pivot-tables).

**How do I start from a ready-made template?**
Click **Templates** in the builder header to open the **Quick Start Gallery** and pick one. Applying a template replaces the report's current columns, joins and summaries.

**How do I rename a report?**
Click the report name at the top of the advanced builder, type the new name and press Enter or click away (Escape cancels). A blank name becomes "Untitled Report".

**How do I schedule a report to be emailed?**
In the advanced builder's **Automated Delivery** card, switch on **Enable Scheduling**, choose **Frequency** (**Daily (9 AM)**, **Weekly (Mon 9 AM)** or **Monthly (1st 9 AM)**) and enter **Recipients** as comma-separated emails. Settings save when you change them.

**How do I delete a report?**
Open the report's **Show** page from its card on the [Reports page](/reports) and click **Delete**, then confirm. Only users of the company that owns the report can delete it.

**Who can create, edit and see builder reports?**
Any user of your company can create builder reports, and every user with the same role in your company sees and can edit the reports on the [Reports page](/reports). Report rows include every matching record of your company; individual record access rights are not applied.

### Why use the Report Builder

**Why use the Report Builder instead of exporting lists and combining them in Excel?**
It joins related records (for example investors with their commitments and KYCs), rolls them up with sums, counts or latest values, applies filters and formulas, and exports in one step, so the same report can be re-run or emailed on a schedule without rebuilding the spreadsheet.

**What can I do with the Report Builder?**
Build one-row-per-record reports from any supported record type, pull in related data, summarise or pivot it, add computed columns, filter and sort, preview, export to Excel, and email it automatically on a daily, weekly or monthly schedule. See [Walkthrough: Five Reports, From Simple to Complex](#walkthrough-five-reports-from-simple-to-complex).

**Who typically uses the Report Builder?**
Fund operations, finance and compliance teams who need ad-hoc or recurring data extracts, such as commitment summaries, KYC registers, call collection status or distribution reconciliations, without asking for a custom report to be developed.

### What happens when I…

**What happens when I create a report?**
A report record is saved for your company with the chosen root model and name ("Untitled Report" if left blank), and it appears on the [Reports page](/reports) for other users of your company with the same role. No data is exported and no one is notified.

**What happens when I change columns, joins, filters or sorting?**
The change is saved on the report immediately; there is no separate save or undo. The preview updates when you click **Refresh Preview**, and the next export or scheduled run uses the new configuration.

**What happens when I click Refresh Preview?**
The report runs against live data and shows the first 20 rows and the total row count. Nothing is saved as a file and no one is notified.

**What happens when I click Export XLSX?**
A background job runs the full report (all matching rows), builds the Excel file, saves it as a document in your company's **Reports** folder and shows an on-screen alert with a **Click here to download** link. No email is sent; if it fails you see a red alert with the error.

**What happens when a scheduled report runs?**
An hourly check picks up due schedules and runs the export as the report's creator: the Excel file is saved to the **Reports** folder as usual and emailed as an attachment, subject "Scheduled Report: <name>", to every recipient. The next run time is then set from the frequency.

**What happens when I apply a template?**
All existing columns are deleted and the report's joins, summaries and filters are replaced with the template's. This cannot be undone; rename the report or create a new one first if you want to keep the old setup.

**What happens when I delete a report?**
The report, its schedule and any AI analyses are permanently deleted, so scheduled emails stop. Excel files already exported stay in the documents folder.

**What happens if a filter value is typed wrong?**
The filter still saves but matches nothing or the wrong rows, so the preview and export come back short or empty. Check the row count shown with **Refresh Preview** before exporting or scheduling.

### Troubleshooting and edge cases

**Why is my preview empty or showing "Your report is empty"?**
Add at least one column to **Selected Columns**, then click **Refresh Preview**. If columns exist but no rows appear, remove filters one at a time to find the one excluding everything.

**Why does a related-data column show 0 or blank?**
That starting record has no matching related rows. Records are kept rather than dropped, so they show 0 or blank in those columns.

**Why doesn't the Aggregate dropdown appear on a column?**
Only columns from related data have one. Columns from the starting record are one value per row and need no summary.

**My totals look wrong — what should I check?**
Confirm the aggregate is **sum** rather than **count**, that filters on the related set are saved, and that two joins are not double-counting the same records. Preview often while you build. See [Tips for Success](#tips-for-success).

**Why was my formula rejected?**
The expression references a column key that is not in the report. Use the exact keys in square brackets (for related data, `[relation.column]`) and add the column or join first.

**Sorting by a summarised column seems slow or partial in the preview — why?**
Sorting by a rolled-up or joined value is done after the totals are computed, so the preview and view cap that work at 20,000 starting records. The Excel export sorts the full data set.

**I didn't get the scheduled email — why?**
Check that **Enable Scheduling** is on, the recipient addresses are correct and comma-separated, and that the first due time has passed (the scheduler checks hourly). Also check the recipients' spam folders for "Scheduled Report: <name>".

**Can someone else change my report?**
Yes. Builder reports are shared with every user of your company who has the same role, and any of them can edit or delete them. Agree naming conventions for important reports.

**Is money converted when I set Display Currency?**
No. **Display Currency** in **Sorting & Grouping** only labels money columns with that currency; values are not converted.

## Related Guides

- [Custom Fields](custom_fields_user_guide) — custom fields appear as columns you can report on.
- [Capital Commitments](capital_commitments_user_guide) — the commitment data most reports join to.
- [Capital Calls](capital_calls_user_guide) — calls and remittances used in collection reports.
- [Investor KYC](investor_kyc_user_guide) — the KYC records behind compliance registers.
- [Document Management](document_management_user_guide) — where exported Excel files are stored.
- [Account Entries Period Report](account_entries_period_report_user_guide) — a ready-made accounting report.
- [Portfolio Report Drafts](portfolio_report_drafts_user_guide) — AI-written portfolio company reports.
