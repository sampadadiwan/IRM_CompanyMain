# Portfolio Report (Legacy) User Guide

The **Portfolio Report (Legacy)** feature turns each portfolio company's KPIs and uploaded documents into a written, narrative report — the kind you'd put in front of an investment committee or send in an LP update — without you having to draft it by hand.

> **Where to find it:** For one company, open the portfolio company (Sidebar → [**Stakeholders → View Stakeholders**](/investors)) → **Misc** → **Portfolio Report (Legacy)**. For many, go to **Actions** → [**Portfolio Reports Setup**](/portfolio_reports) on the Stakeholders list → [**Bulk Generate (Legacy)**](/portfolio_reports/legacy_bulk_generate). Needs the *Fund Portfolios* feature and at least one Portfolio Report with a Word template on its **Templates (Legacy)** tab.

You pick one or many portfolio companies, a report template, and a date range. The system reads each company's latest KPI report and its attached documents, asks an AI analyst to write the narrative sections defined in your template, and produces a finished `.docx` report. When you generate for several companies at once, it also stitches all their reports into one combined document.

---

## Table of Contents

1. [Before You Start](#before-you-start)
2. [Key Concepts](#key-concepts)
3. [Two Ways In: Single Company vs. Bulk](#two-ways-in-single-company-vs-bulk)
4. [Generating for a Single Company (Show Page)](#generating-for-a-single-company-show-page)
5. [Generating for Many Companies (Bulk Page)](#generating-for-many-companies-bulk-page)
6. [The Options Screen Explained](#the-options-screen-explained)
7. [Extracts vs. Reports](#extracts-vs-reports)
8. [Where Your Output Lands](#where-your-output-lands)
9. [Deleting an extract](#deleting-an-extract)
10. [What the AI Reads](#what-the-ai-reads)
11. [A Note on Privacy](#a-note-on-privacy)
12. [Frequently Asked Questions](#frequently-asked-questions)

---

## Before You Start

For a company to produce a meaningful report, three things need to be in place:

1. **The company is a Portfolio Company.** Only investors categorised as _Portfolio Company_ appear in the pickers.
2. **It has a documented KPI report.** The system pulls the company's most recent KPI report that falls inside your date range, along with the documents attached to it (KPIs spreadsheet, investor presentation, etc.). Without these, the report still generates, but the narrative sections will be largely empty.
3. **A report and a Word template exist.** At least one **Portfolio Report** must be set up for your entity. Sections are optional; when it has them, they define _which sections_ the report has (e.g. "Quarterly Update", "Financial Analysis", "Risk Factors") and _what the AI is told to write_ in each. For the legacy flow the "template" is a `.docx` document uploaded on that report's **Templates (Legacy)** tab — not an output template from the drafts flow.

If no portfolio report exists yet, the "Portfolio Report (Legacy)" option won't appear on the company page. It appears as soon as any Portfolio Report exists, even before a Word template is uploaded — without one, the Options screen's **Report template** list is empty.

---

## Key Concepts

| Term                            | What it means                                                                                                                                                                          |
| ------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Portfolio Report (template)** | The reusable definition of a report: its named sections and the instructions the AI follows for each.                                                                                  |
| **Extract**                     | The AI-generated narrative for one company, for one report, for one date range. This is the _content_ — the written answers to each section — stored so it can be reviewed and reused. |
| **Report (document)**           | The finished, formatted `.docx` file, built by dropping an extract's narrative into the template's layout (with KPIs, portfolio investments, and optional source documents).           |
| **Source documents**            | The company's latest KPI-report attachments (KPIs, investor presentation) that the AI reads to write the extract.                                                                      |
| **Merged report**               | When you generate for multiple companies at once, the single combined `.docx` containing every company's report, one after another.                                                    |

The mental model: **documents → extract (narrative) → report (formatted document)**. An extract is generated once and can be reused across report runs; the report is the polished deliverable.

---

## Two Ways In: Single Company vs. Bulk

There are two entry points, and they meet at the same **Options** screen:

- **Single company** — from a portfolio company's own page (via **Misc → Portfolio Report (Legacy)**). The company is pre-selected; you skip straight to the options.
- **Bulk** — from the Portfolio Reports index, via the **Bulk Generate (Legacy)** page. You filter and pick many companies first, then continue to the options.

Both routes end on the same Options screen where you choose the template, date range, and whether to generate extracts only or a full report.

---

## Generating for a Single Company (Show Page)

1. Open the portfolio company's page.
2. Click the **Misc** menu.
3. Click **Portfolio Report (Legacy)**.
   - This jumps you straight to the **Options** screen with that company already selected — there's no company-picking step, since you're already on its page.
4. On the Options screen, choose the **Report** and **Template** in each row of the list (use **Add report** for more), then the **Start date** and **End date**.
5. Click either **Generate Extracts Only** or **Generate Report** (see [The Options Screen Explained](#the-options-screen-explained)).
6. You're returned to the company page with a confirmation notice (e.g. _"Queued report generation for 1 company."_). Generation runs in the background.

> **Tip:** From the company page you can also click **Portfolio Report Extracts** (Misc menu) to review every extract that's been generated for that company.

---

## Generating for Many Companies (Bulk Page)

1. Go to [**Portfolio Reports Setup**](/portfolio_reports) (Stakeholders list → **Actions** → **Portfolio Reports Setup**) and click **Bulk Generate (Legacy)**.
2. **Filter portfolio companies** (optional). Choose any combination of **Funds**, **Tags**, and **Sectors**, then click **Preview**. Preview _selects_ the companies matching your filters in the list below. Despite the hint on the page, it replaces the current selection with the matches, so any company you picked by hand before clicking Preview is deselected; Preview with no filters selects every portfolio company.
3. **Review & finalize.** Every portfolio company for your entity is listed in the multi-select. Add or remove any company by hand after the last Preview — the final selection is whatever is highlighted here, not the filter.
4. Click **Next** to move to the **Options** screen.
5. Choose the **Report** and **Template** in each row of the list (use **Add report** for more), then the **Start date** and **End date**, then click **Generate Extracts Only** or **Generate Report**.
6. You're returned to the Portfolio Reports index with a confirmation notice telling you how many companies were queued.

### Bulk Generate (Legacy) at a glance

The **Bulk Generate (Legacy)** button on the [Portfolio Reports list](/portfolio_reports) (beside **Bulk Generate Drafts**) is shown only to users with the *Company Admin* role on a company with the *Fund Portfolios* feature; the same role is needed for the Options screen, including from a company's **Misc** menu. It works on the companies you highlight, never on a whole filtered list.

| Action (exact label) | What it does | Shown when |
|---|---|---|
| **Preview** | Highlights the portfolio companies matching the chosen **Funds** (companies with an investment in any of them), **Tags** and **Sectors**, replacing the current selection. | Always, on the bulk page |
| **Next** | Opens the **Options** screen for the highlighted companies. With none highlighted you are sent back with "Select at least one portfolio company to continue." | Always, on the bulk page |
| **Generate Extracts Only** | Queues one background job that creates a new AI extract for each company (or only those without an extract holding data, when **Only generate for companies missing an extract** is ticked). | On the Options screen |
| **Generate Report** | Queues one background job that fills the chosen Word template for each company from its latest extract (creating missing ones if **Generate missing report extracts** is ticked, otherwise an empty one) and merges two or more companies into one document. | On the Options screen |

Both jobs run in the background on a low-priority queue and report only to you: progress alerts while it runs (one per company for extracts), then one completion alert (with a link to the merged or single document for **Generate Report**), plus an error email when anything failed. Nothing is emailed to investors. There is no undo for a run: generated documents stay until you delete them from the folder. A Company Admin can delete an extract from its details page (see [Deleting an extract](#deleting-an-extract)).

---

## The Options Screen Explained

The Options screen has two side-by-side actions. Both use the list of reports and the **Start date** and **End date** you set at the top. The **Template** list in each row shows only the Word documents uploaded on that row's report's **Templates (Legacy)** tab.

### The list of reports

The top of the screen is a list of rows, each with a **Report** and a **Template**. The screen starts with one row. Click **Add report** to add another row; click **Remove** to take a row away (the last row cannot be removed). **The order of the rows is the order of the parts in the final document.**

- A report marked **(Consolidated)** is built **once for all the selected companies** from a single template (for example a cover and summary page that lists every company, or a legal disclaimer). It does not use extracts. You mark a report as consolidated with the **Consolidated** tick on the report's form; reports you already had stay unticked.
- A consolidated template loops the companies (`portfolio_companies`). For each company it can use the company, its latest and earliest portfolio investment, the logo, and its funds; each fund has a name, currency, FMV, cost of investment, the cost invested and exited in the period, the company's IRR and MOIC, and the fund's own Gross Portfolio IRR (the same on every company in the fund), plus a list of ratios so you can loop companies, then funds, then ratios. Companies are listed A–Z. A company with no investments is still listed, with no funds. IRR, MOIC and Gross Portfolio IRR are the latest stored values on or before the end date, or _N/A_ if they were never run. The change in FMV (since the start of the period and since the financial year start) is the change in value per unit, weighted by each investment's value at the start, so buying or selling units in the period does not move it; the FMV amounts themselves are unchanged. KPIs and the cap table are not available in a consolidated template. For a totals row under the company table, loop `fund_totals`: one entry per fund, with its name, currency, FMV and cost of investment added up over the selected companies, the fund's own IRR, Gross Portfolio IRR, MOIC, TVPI, DPI and RVPI, and `custom_fields`, the total of each number or money custom field of the companies (a blank counts as zero). Use the same fund-name check as on the fund rows to keep the row to one fund.
- Any other report is built **once per company**, in alphabetical order, from that company's extract, as before. In its template each fund the company invested in has its own data block, named after the fund. Besides cost, FMV, IRR and MOIC, it has the fund's Gross Portfolio IRR and what the fund did in the period (the start date to the end date, both included): whether the company was bought or sold, and the cost of each, so a sentence such as "The fund invested a further INR 10.0 Cr during the quarter" can be shown only when it did. Each KPI row also carries its category.
- **Each template can be used only once** in the list. The page checks this before anything is sent: a row with no template, or a template that already appears in another row, is marked with a message beside it and **Generate Report** does not submit until you fix it. The message goes away as soon as you change the row.
- **Generate Extracts Only** ignores consolidated reports and runs once for each normal report in the list. If every row is a consolidated report, the page tells you there is nothing to generate.

### Generate Extracts Only

Produces just the AI narrative (the extract) for each selected company — no formatted document. Use this when you want to review or edit the written content before committing to a full report.

- **Only generate for companies missing an extract** — when ticked, any company that _already has an extract_ for this report and date range is skipped. Handy for topping up a batch without regenerating work you've already reviewed. If every selected company already has one, you'll see _"Skipped extract generation: all companies already have extracts…"_ and nothing is regenerated.

### Generate Report

Produces the finished, formatted `.docx` report(s).

- **Generate missing report extracts** — when ticked, any company that doesn't yet have an extract gets one generated automatically as part of the run, so its report isn't blank. When unticked, an empty extract record is created for each company without one and its report has empty narrative sections.

When you generate a report for **more than one** company in a single run, each company gets its own report **and** a single **merged** document combining them all (see below). With more than one row in the list, the merged document also holds the consolidated parts, in the order of the rows.

---

## Extracts vs. Reports

It helps to know why there are two separate buttons:

- **Extracts** are cheap to review and safe to iterate on. Generating extracts first lets you sanity-check the AI's narrative before it's baked into a formatted document.
- **Reports** are the deliverable. A report needs an extract to fill its narrative sections. If you click **Generate Report** for a company with no extract and _don't_ tick "Generate missing report extracts", an empty extract is created for that company and its narrative sections come out empty (the KPIs and portfolio-investment tables still populate).

**Recommended flow for a fresh batch:** Generate Extracts Only → review them via the Portfolio Report Extracts page → come back and Generate Report (with "Generate missing report extracts" unticked, since they now exist).

---

## Where Your Output Lands

- **Each company's own report** is saved under that company's own **Portfolio Reports** folder, exactly as a single-company report would be. Its name follows the pattern _`<Template> <Company> <start> to <end>`_. Re-running adds a new document; earlier documents are not replaced or deleted.
- **The combined document** is saved under a shared folder: **Portfolio Reports → Generated Portfolio Reports** (in the entity's Documents). It is made when the list has a consolidated report, more than one row, or more than one company. Its name follows _`<Template> <start> to <end> - <N> companies`_, where the template is the one in the **first row**. The parts follow the order of the rows, and within a normal report the companies are ordered alphabetically so the combined document reads the same way every time. Consolidated parts are not saved as separate files; they exist only inside the combined document.
- **The look of the combined document comes from the first row's template**: its styles, page setup and running header and footer are used for the whole document, and later parts contribute their content only. Put the template whose look you want first.
- **Extracts** don't produce a file — review them on the **Portfolio Report Extracts** page (Misc menu on a company, or the filtered link from the company page).

Generating one normal report for exactly one company never creates a combined document — you just get that company's report in its own folder.

---

## Deleting an extract

A Company Admin can delete an extract from the extract's details page: click **Delete** and confirm. You return to the list of extracts for that report with "Portfolio report extract deleted successfully." The extract is removed from the lists and from the company dashboard. The next report generated for that company and period creates a new extract if **Generate missing report extracts** is ticked, and otherwise shows "No data available" for that company.

The portfolio report widget on a company's dashboard shows the **latest extract that has data** for the report it is set up for. An extract with no data is skipped in favour of the one before it.

---

## What the AI Reads

For each company, the system automatically finds the **latest non-generated KPI report** whose date falls inside your chosen range, and reads the documents attached to it (typically the KPIs spreadsheet and the investor presentation). It also sends the company's notes dated within the range (filtered by the report's tags). You don't choose documents by hand — picking the right KPI report and its attachments is automatic based on the date range.

If a company has **no documents** in the range, its extract is built from its **notes** for the period and the **KPIs of its latest KPI report** in the range instead (the KPIs are used only in this case), and you see an amber warning that no documents were found (for a bulk extract run, one amber alert at the end lists all such companies). If a company has no documents, no notes and no KPIs in the range, its extract is left empty.

If a run has errors, the alert is red and the list of errors is also emailed to you.

This is why the **date range matters**: it decides _which_ KPI report (and therefore which quarter's documents) the narrative is based on. If a company has no documented KPI report inside the range, its extract will have little to say.

---

## A Note on Privacy

Generating an extract or a report sends the company's KPI data, document contents and notes in the date range to an **external LLM** for the narrative generation — this is flagged with a warning on the bulk page. Only trigger generation for data you're comfortable processing through an external AI service, in line with your entity's data-handling policies.

---

## Frequently Asked Questions

### Navigation and getting there

**Where do I start a legacy report for one company?**
Open the company from Sidebar → [**Stakeholders → View Stakeholders**](/investors), then **Misc** → **Portfolio Report (Legacy)**. The item shows only for Stakeholders with category *Portfolio Company* and only once at least one Portfolio Report exists. See [Generating for a Single Company (Show Page)](#generating-for-a-single-company-show-page).

**Where is the Bulk Generate (Legacy) page for portfolio reports?**
Sidebar → **Stakeholders → View Stakeholders** → **Actions** → [**Portfolio Reports Setup**](/portfolio_reports) → [**Bulk Generate (Legacy)**](/portfolio_reports/legacy_bulk_generate). See [Generating for Many Companies (Bulk Page)](#generating-for-many-companies-bulk-page).

**Why don't I see the Bulk Generate (Legacy) button on the Portfolio Reports list?**
Both bulk buttons on the Portfolio Reports list are shown only to users with the *Company Admin* role, on a company with the *Fund Portfolios* feature. Without the role the Options screen is refused too, including the **Misc** → **Portfolio Report (Legacy)** path. Ask a company admin to run the bulk generation or grant you the role.

**Where do I review extracts?**
From a company page, **Misc** → **Portfolio Report Extracts**, or open the Portfolio Report and use its **Extracts** tab. Click **View Details** to read one or **Edit** to change it.

**Where do I upload the Word template used by the legacy flow?**
Open the report on [**Portfolio Reports Setup**](/portfolio_reports) with **Show**, then the **Templates (Legacy)** tab, and add the `.docx` template document there. Only documents on that tab appear in the Options screen's **Report template** list.

**Where do the finished documents go?**
Each company's report goes into a **Portfolio Reports** folder inside that company's documents (company page → **Misc** → **Documents**). A multi-company run also saves a merged file under **Portfolio Reports → Generated Portfolio Reports** (in the entity's Documents) in your [documents](/documents). See [Where Your Output Lands](#where-your-output-lands).

### Creating, updating and managing legacy reports

**How do I set up a report for the legacy flow?**
On [**Portfolio Reports Setup**](/portfolio_reports) click **New Portfolio Report**, add sections with names and AI instructions, and save. Then open it, go to **Templates (Legacy)** and add a Word template document. See [Before You Start](#before-you-start).

**How do I generate extracts only?**
On the Options screen pick **Report**, **Report template**, **Start date** and **End date**, optionally tick **Only generate for companies missing an extract**, and click **Generate Extracts Only**. See [Generate Extracts Only](#generate-extracts-only).

**How do I generate the finished report?**
On the Options screen pick **Report**, **Report template** and the dates, tick **Generate missing report extracts** if some companies have no extract, and click **Generate Report**. See [Generate Report](#generate-report).

**How do I pick portfolio companies in bulk on Bulk Generate (Legacy)?**
On the bulk page choose **Funds**, **Tags** and **Sectors** and click **Preview** to select the matches, then add or remove companies in the list under "Review & finalize portfolio companies" and click **Next**. Preview replaces the selection, so make hand-picked changes after the last Preview.

**How do I bulk generate legacy portfolio reports for many companies at once?**
[Portfolio Reports list](/portfolio_reports) → **Bulk Generate (Legacy)**, highlight the companies (with **Preview** or by hand) and click **Next**. On the Options screen choose **Report**, **Report template**, **Start date** and **End date**, then click **Generate Extracts Only** or **Generate Report**. See [Generating for Many Companies (Bulk Page)](#generating-for-many-companies-bulk-page).

**How do I edit what an extract says?**
Open the extract (**View Details**) and click **Edit Data**, or **Edit** on the extracts list. Change the section content and save; the next **Generate Report** for that company and date range uses it.

**How do I change the sections the AI writes?**
Open the report on [**Portfolio Reports Setup**](/portfolio_reports) → **Edit** and change section names or instructions, add sections with **Add Section**, then save. New extracts follow the updated sections; existing extracts keep their old content until regenerated.

**Can I delete an extract or a generated report?**
A Company Admin can delete an extract from its details page (see [Deleting an extract](#deleting-an-extract)). Generated documents can be removed from the documents folder like any other document, subject to your document permissions.

**Who can use the legacy flow, including Bulk Generate (Legacy)?**
Your company needs the *Fund Portfolios* feature, and the bulk page and the Options screen (also used by the single-company **Misc** path) need the *Company Admin* role. Viewing and editing extracts needs access as an employee of the company; deleting one needs the *Company Admin* role.

### Why use the legacy flow

**Why use the legacy flow?**
It turns each company's latest KPI report attachments and notes into a narrative written against your own Word template, and can merge many companies into one committee or LP pack in a single run, which the newer draft flow does not do.

**What can I do with it?**
Generate AI extracts per company, review and edit them, produce formatted `.docx` reports from a template, merge a whole batch into one document, and build tear-sheet slides from an extract.

**Who typically uses it?**
Portfolio monitoring teams preparing combined IC or LP packs across many companies, especially where a firm-standard Word template already exists.

**Should I use this or Portfolio Report Drafts?**
Use [Portfolio Report Drafts](portfolio_report_drafts_user_guide) when you want an inline review, approval and single-company Word/PowerPoint export. Use the legacy flow when you need a custom Word template or one merged document for a batch.

### What happens when I…

**What happens when I use Bulk Generate (Legacy) → Generate Extracts Only?**
One background job creates a new extract per selected company (skipping those that already have one with data if **Only generate for companies missing an extract** is ticked), finds the latest KPI report in the date range with a matching attachment, sends that report's documents and the company's notes in the range (filtered by the report's tags) to the external AI model, and stores the section content. You see a progress alert per company and one completion alert; failures, and companies with nothing at all to build from (no documents, notes or KPIs), are listed in a red alert and emailed to you. Companies built from notes and KPIs only are listed together in one amber alert at the end.

**What happens if a company has no KPI documents in the range?**
If the company has notes or KPIs in the range, the extract is built from them and you see an amber warning "No documents found … Extract built from notes and KPIs." If it has none of those either, an extract is still created but left empty and you get a red on-screen alert "No documents found". At the end of the run any errors are also emailed to you.

**What happens when I use Bulk Generate (Legacy) → Generate Report?**
For each company the job uses the latest extract for that report and date range (or generates one if you ticked **Generate missing report extracts**), fills the chosen Word template and saves "<template> <company> <start> to <end>" in the company's **Portfolio Reports** folder. With two or more companies it then merges them alphabetically into one file.

**What happens if I generate a report without extracts?**
If **Generate missing report extracts** is unticked, an empty extract is created for each company without one and its report comes out with empty narrative sections; the KPI and portfolio-investment tables still populate. The completion alert lists the companies that had no extract.

**What happens when I run the same report again?**
New extracts (for extract runs) and new documents are created; earlier documents are not replaced or deleted, so the folder can hold several versions. The report run always uses the newest extract.

**What happens when a run finishes?**
You get an on-screen alert with the folder path and a link to the merged or single document. If anything failed, the alert is red and the list of errors is emailed to you. No one else is notified.

**What happens when I generate a tear sheet?**
From an extract's page, **Generate Tear Sheet** (or a **Palette** choice) starts a background job that builds presentation slides from the extract; once ready the page offers **View Slides** and **PDF**.

### Troubleshooting and edge cases

**Why is my report's narrative empty?**
The company has no extract for that report and date range, and you didn't tick "Generate missing report extracts". Either generate the extract first, or re-run the report with that box ticked.

**Why does an extract say there's no data?**
The company had no documents, notes or KPIs inside your date range, so the AI had nothing to read. Check that the company has a KPI report with attached documents (or notes, or KPIs) whose date falls within Start–End.

**I ran "Generate Report" but nothing appeared immediately.**
Generation runs in the background. You'll get a confirmation notice when it's queued; the finished document appears in the folder once the job completes. For large batches this can take a little while.

**What's the difference between "Bulk Generate" and "Bulk Generate (Legacy)"?**
This guide covers the **Legacy** flow, which drives extracts and finished `.docx` reports directly and can merge multiple companies into one document. **Bulk Generate Drafts** is the draft-based path described in [Portfolio Report Drafts](portfolio_report_drafts_user_guide).

**A Bulk Generate (Legacy) run finished but some portfolio companies have no report — why?**
A company whose extract could not be created, or whose template fill failed, is skipped and listed in the red completion alert and the error email; the others still generate and merge. A company with no extract is not skipped: its report is produced with empty narrative sections. Fix the cause (for example upload KPI documents in the date range) and run again for those companies.

**Does Bulk Generate (Legacy) apply to every portfolio company matching my filters?**
No. The legacy bulk run uses only the companies highlighted when you click **Next**, not the **Funds**, **Tags** or **Sectors** filters. Preview just highlights the matches, and you can add or remove companies before continuing; the Options screen lists the names it will generate for.

**Can I undo a Bulk Generate (Legacy) run?**
No. Generated documents (each company's report and the combined file) stay until you delete them from their folders like any other document. Re-running creates new extracts and documents rather than replacing them. A Company Admin can delete an extract from its details page (see [Deleting an extract](#deleting-an-extract)).

**Can I regenerate just the companies I added to a batch?**
Yes. Tick **Only generate for companies missing an extract** (for extracts) so companies that already have one are skipped, and only the new additions are processed.

**Where do I edit what the AI writes in each section?**
The section names and the instructions the AI follows live in the **Portfolio Report**. Open it → **Edit** to change what each part of the narrative covers, or edit a single company's extract with **Edit Data**.

**One company in my batch had no logo / different documents — will the merge break?**
No. The merged document handles companies with differing documents and logos; each company's section renders its own content (or leaves it out if absent).

**Why is Portfolio Report (Legacy) missing from the company's Misc menu?**
It appears only when the Stakeholder's category is *Portfolio Company* and your company has at least one Portfolio Report. Create a report on [**Portfolio Reports Setup**](/portfolio_reports) or fix the category.

**Why is the Report template list empty?**
Only documents uploaded on a report's **Templates (Legacy)** tab are offered, filtered to the selected **Report**. Upload a Word template there and reload the Options screen.

**Why did only one document appear for my batch?**
A combined file is made when the run produces more than one part: two or more company reports, more than one row in the list, or a consolidated report. If other companies failed, check the red alert or the error email for the reasons.

**Is my data sent outside CapHive?**
Yes. The KPI report documents and filtered notes are sent to your company's external AI model, as the warning on the bulk page says. See [A Note on Privacy](#a-note-on-privacy).

## Related Guides

- [Portfolio Report Drafts](portfolio_report_drafts_user_guide) — the newer review-and-approve report flow.
- [KPI Upload](kpi_upload_user_guide) — loading the KPI reports and attachments the AI reads.
- [Portfolio Investments](portfolio_investments_user_guide) — the investments tables included in the report.
- [Document Management](document_management_user_guide) — templates and generated report folders.
- [LP CRM](lp_crm_user_guide) — the notes that feed extracts.
- [LLM Configuration](llm_configuration_guide) — which AI model writes the extracts.
- [Portfolio Report Agent](agents/portfolio_report_agent_user_guide) — agent-driven portfolio reporting.
