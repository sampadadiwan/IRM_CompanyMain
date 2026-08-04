# Portfolio Report (Legacy) User Guide

The **Portfolio Report (Legacy)** feature turns each portfolio company's KPIs and uploaded documents into a written, narrative report — the kind you'd put in front of an investment committee or send in an LP update — without you having to draft it by hand.

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
9. [What the AI Reads](#what-the-ai-reads)
10. [A Note on Privacy](#a-note-on-privacy)
11. [Frequently Asked Questions](#frequently-asked-questions)

---

## Before You Start

For a company to produce a meaningful report, three things need to be in place:

1. **The company is a Portfolio Company.** Only investors categorised as _Portfolio Company_ appear in the pickers.
2. **It has a documented KPI report.** The system pulls the company's most recent KPI report that falls inside your date range, along with the documents attached to it (KPIs spreadsheet, investor presentation, etc.). Without these, the report still generates, but the narrative sections will be largely empty.
3. **A report template exists.** At least one **Portfolio Report** with sections and a template must be set up for your entity. The template defines _which sections_ the report has (e.g. "Quarterly Update", "Financial Analysis", "Risk Factors") and _what the AI is told to write_ in each.

If no portfolio report exists yet, the "Portfolio Report (Legacy)" option won't appear on the company page — set up a report template first.

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
4. On the Options screen, choose your **Report**, **Start date**, and **End date**.
5. Click either **Generate Extracts Only** or **Generate Report** (see [The Options Screen Explained](#the-options-screen-explained)).
6. You're returned to the company page with a confirmation notice (e.g. _"Queued report generation for 1 company."_). Generation runs in the background.

> **Tip:** From the company page you can also click **Portfolio Report Extracts** (Misc menu) to review every extract that's been generated for that company.

---

## Generating for Many Companies (Bulk Page)

1. Go to **Portfolio Reports** and click **Bulk Generate (Legacy)**.
2. **Filter portfolio companies** (optional). Choose any combination of **Funds**, **Tags**, and **Sectors**, then click **Preview**. Preview _selects_ the companies matching your filters in the list below — it doesn't discard picks you've already made.
3. **Review & finalize.** Every portfolio company for your entity is listed in the multi-select. Add or remove any company by hand before continuing — the final selection is whatever is highlighted here, not the filter.
4. Click **Next** to move to the **Options** screen.
5. Choose your **Report**, **Start date**, and **End date**, then click **Generate Extracts Only** or **Generate Report**.
6. You're returned to the Portfolio Reports index with a confirmation notice telling you how many companies were queued.

---

## The Options Screen Explained

The Options screen has two side-by-side actions. Both use the **Report**, **Start date**, and **End date** you set at the top.

### Generate Extracts Only

Produces just the AI narrative (the extract) for each selected company — no formatted document. Use this when you want to review or edit the written content before committing to a full report.

- **Only generate for companies missing an extract** — when ticked, any company that _already has an extract_ for this report and date range is skipped. Handy for topping up a batch without regenerating work you've already reviewed. If every selected company already has one, you'll see _"Skipped extract generation: all companies already have extracts…"_ and nothing is regenerated.

### Generate Report

Produces the finished, formatted `.docx` report(s).

- **Generate missing report extracts** — when ticked, any company that doesn't yet have an extract gets one generated automatically as part of the run, so its report isn't blank. Leave it unticked if you only want reports for companies whose extracts you've already prepared.

When you generate a report for **more than one** company in a single run, each company gets its own report **and** a single **merged** document combining them all (see below).

---

## Extracts vs. Reports

It helps to know why there are two separate buttons:

- **Extracts** are cheap to review and safe to iterate on. Generating extracts first lets you sanity-check the AI's narrative before it's baked into a formatted document.
- **Reports** are the deliverable. A report needs an extract to fill its narrative sections. If you click **Generate Report** for a company with no extract and _don't_ tick "Generate missing report extracts", that company's narrative sections come out empty (the KPIs and portfolio-investment tables still populate).

**Recommended flow for a fresh batch:** Generate Extracts Only → review them via the Portfolio Report Extracts page → come back and Generate Report (with "Generate missing report extracts" unticked, since they now exist).

---

## Where Your Output Lands

- **Each company's own report** is saved under that company's own **Portfolio Reports** folder, exactly as a single-company report would be. Its name follows the pattern _`<Template> <start> to <end>`_.
- **The merged report** (only when you generate for 2+ companies at once) is saved under a shared folder: **Investors → Generated Portfolio Reports**. Its name follows _`<Template> <start> to <end> - <N> companies`_, and the companies inside it are ordered alphabetically so the combined deck reads the same way every time.
- **Extracts** don't produce a file — review them on the **Portfolio Report Extracts** page (Misc menu on a company, or the filtered link from the company page).

Generating for exactly one company never creates a merged document — you just get that company's report in its own folder.

---

## What the AI Reads

For each company, the system automatically finds the **latest non-generated KPI report** whose date falls inside your chosen range, and reads the documents attached to it (typically the KPIs spreadsheet and the investor presentation). You don't choose documents by hand — picking the right KPI report and its attachments is automatic based on the date range.

This is why the **date range matters**: it decides _which_ KPI report (and therefore which quarter's documents) the narrative is based on. If a company has no documented KPI report inside the range, its extract will have little to say.

---

## A Note on Privacy

Generating an extract or a report sends the company's KPI data and document contents to an **external LLM** for the narrative generation — this is flagged with a warning on the bulk page. Only trigger generation for data you're comfortable processing through an external AI service, in line with your entity's data-handling policies.

---

## Frequently Asked Questions

**Why is my report's narrative empty?**
The company has no extract for that report and date range, and you didn't tick "Generate missing report extracts". Either generate the extract first, or re-run the report with that box ticked.

**Why does an extract say there's no data?**
The company had no documented KPI report inside your date range, so the AI had nothing to read. Check that the company has a KPI report with attached documents whose date falls within Start–End.

**I ran "Generate Report" but nothing appeared immediately.**
Generation runs in the background. You'll get a confirmation notice when it's _queued_; the finished document appears in the folder once the job completes. For large batches this can take a little while.

**What's the difference between "Bulk Generate" and "Bulk Generate (Legacy)"?**
This guide covers the **Legacy** flow, which drives extracts and finished `.docx` reports directly and can merge multiple companies into one document. The non-legacy bulk flow is a separate, draft-based path.

**Can I regenerate just the companies I added to a batch?**
Yes — tick **Only generate for companies missing an extract** (for extracts) so companies that already have one are skipped, and only the new additions are processed.

**Where do I edit what the AI writes in each section?**
The section names and the instructions the AI follows live in the **Portfolio Report** template. Edit the report's sections to change what each part of the narrative covers.

**One company in my batch had no logo / different documents — will the merge break?**
No. The merged document handles companies with differing documents and logos; each company's section renders its own content (or leaves it out if absent).
