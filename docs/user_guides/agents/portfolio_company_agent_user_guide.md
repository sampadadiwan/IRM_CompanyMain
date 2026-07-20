# Portfolio Company Agent — User Guide

The Portfolio Company Agent keeps an eye on the data health of every portfolio company in your fund — whether KPI reports have come in on time, whether required documents are on file, and whether a recent valuation has been recorded. It does not use AI to make judgment calls; it simply checks your data against the rules you've configured. You can run it across your whole portfolio at once, or against a single company.

## Table of Contents

1. [What This Agent Does](#1-what-this-agent-does)
2. [Inputs](#2-inputs)
3. [Enabling the Agent](#3-enabling-the-agent)
4. [Accessing and Running the Agent](#4-accessing-and-running-the-agent)
5. [Scheduling](#5-scheduling)
6. [Where to Find the Output](#6-where-to-find-the-output)
7. [Understanding the Report](#7-understanding-the-report)
8. [Where It Can Fail](#8-where-it-can-fail)
9. [Portfolio Company Dashboard](#9-portfolio-company-dashboard)
10. [FAQ](#10-faq)

---

## 1. What This Agent Does

For every company in your portfolio that is categorized as a "Portfolio Company," the agent checks four things, in order:

1. **Has the company submitted its KPIs for the current period?** (Quarterly, by default.) If not, this is flagged as a **blocking** issue.
2. **Should a reminder go out?** If KPIs are still missing and reminders are turned on, the agent emails the portfolio company a reminder — but only on the specific days you've configured, and never more than once per day.
3. **Are the required documents on file?** The agent checks whether the documents attached to the company's most recent KPI submission match the list of documents your fund requires.
4. **Has a valuation been entered for the current period?** (Quarterly, by default.) If not, this is also flagged as a **blocking** issue.

This agent never makes a call to an AI model — every check is rule-based, so there's no AI cost and no AI "judgment" involved. You don't need an AI provider key for this agent to work.

It also powers a few of the sample chat questions you'll see on a Portfolio Company's page (like "Show latest KPIs" or "What's the current valuation?"), but that's a separate conversational feature — not the run-and-report behavior this guide covers.

## 2. Inputs

| Field | Type | Default | What it controls |
|---|---|---|---|
| Send KPI submission reminder | Select (Yes/No) | Yes | When set to Yes, the agent emails the portfolio company a reminder whenever their KPIs are overdue for the current period. |
| Reminder days | Text | `7,14,21` | A comma-separated list of "days since the period started" on which a reminder is allowed to go out. The agent checks how many days have elapsed since the period began and only sends an email if that count matches one of these numbers — and only once per day, even if you run the agent more than once. |

Two additional settings exist behind the scenes but currently have **no field in the Edit page** — they can only be changed by your technical team directly in the agent's configuration data, not from any screen in the product:

| Setting | Default if not set | What it controls |
|---|---|---|
| Due period | Quarter | The reporting period used for the KPI submission check (Month, Quarter, or Year). |
| Days before due period ends | 15 | How many days before the period closes the KPI submission starts being considered "due." |
| Valuation period | Quarter | The period type used for the valuation check. |
| Days before valuation period ends | 15 | How many days before the period closes the valuation starts being considered "due." |

There is also no on-screen toggle for the document-check setting described below — see [Where It Can Fail](#8-where-it-can-fail) for what that means in practice.

**Data the agent looks at (not configuration, just the records it reads):**

- The company's submitted KPI reports — used to find the latest submission for the period, and (through that report's attachments) for the document check.
- The company's uploaded documents — compared against your fund's required-documents list.
- The company's valuations — used to find a recent valuation within the period.

## 3. Enabling the Agent

A Company Admin turns this agent on or off from **Admin → Edit Entity → Support Agents section**. While it's off, the **Run Now** button (and the matching trigger on a company's page) stay disabled.

No AI provider key is needed — this agent is fully rule-based.

Only users with the **Company Admin** role can configure and run support agents from the main Support Agents screen. When the agent is triggered from a Portfolio Company's own page instead, it follows that record's normal edit permissions.

Unlike most agents, this one isn't created from scratch when you run **Setup All Agents** — it's been part of the product since before that setup flow existed, and is provisioned separately. Running **Setup All Agents** will only fill in the "Send KPI submission reminder" and "Reminder days" fields if they're missing; it won't create the agent itself if it isn't already there.

## 4. Accessing and Running the Agent

**From the agent's own page:** Go to **AI → Support Agents** and open the **Portfolio Company Agent** card. On the **General** tab, click **Run Now**. Because this agent's natural scope is "the whole portfolio," running it from here processes every portfolio company in one batch — there's no step-by-step view for each individual company in this mode.

**From a single Portfolio Company's page:** Open the company record → **Misc → Run Portfolio Agent**. This runs the agent for just that one company, and you'll see a live progress panel walk through each check (KPI Submission Check → Send KPI Reminder → Document Presence → Valuation Check → Save Report).

**From the Portfolio Agent Run screen:** Filter your portfolio companies by tag, sector, or name, select one or more from the table, and click **Run Agent on Selected Companies**. This queues a single batch job covering everything you selected. There's no per-company progress view here either — you'll get one summary notification once all the selected companies have been processed.

**Running on one company vs. everything:** Targeting a single company gives you the full step-by-step view. Running against the agent generally, or against your whole fund, processes **every** portfolio company in sequence — if one company hits a problem, it doesn't stop the rest from being checked, and the portfolio dashboard refreshes once at the end for everything that succeeded.

## 5. Scheduling

This agent's page does have the standard **Schedule** tab (frequency, run time, timezone, notification toggles), and you can set up a recurring schedule just like with any other agent. However, **Setup All Agents does not turn on a default schedule** for this one — unlike the Note Summarizer, there's no pre-built cadence waiting for you. If you want it to run automatically, you'll need to set that schedule up yourself. Scheduled runs always process the whole portfolio in one batch, and they skip the summary notification (since there's no one actively waiting on the result).

## 6. Where to Find the Output

- **General tab → "View Report" link** — the most recent run's report.
- **Execution History tab** — every past run, manual or scheduled, with its status and how long it took; click any row to see the full report.
- **Portfolio Agent Reports tab** (only on this agent's own page) — reports organized by which portfolio company they belong to.
- **Portfolio Company Dashboard** — a standalone dashboard (Investors → Portfolio Company Agent Dashboard) showing stat cards, compliance chart, company table with search/filter/pagination, and Send Reminders. See [Section 9](#9-portfolio-company-dashboard) for details.
- Each report is attached to the portfolio company it covers, and the most recent run per company is always the one marked as current.

## 7. Understanding the Report

Each report has three groups of findings:

- **KPI findings** — submission status and reminder outcome for the period. A successful submission, or a note that no reminder was due yet, shows as a **success**. A missing submission shows as **blocking**.
- **Document findings** — one entry per required document that's missing (shown as **blocking**), or a single success entry if everything required is present.
- **Valuation findings** — either a recent valuation was found (**success**) or none was found (**blocking**).

The report's overall status is **"ready"** if nothing across all three groups is blocking, or **"blocked"** if anything is. That status feeds into the familiar Completed / Partial / Failed badges you see in Execution History.

The summary widget on the Portfolio Company page pulls three counters straight from these findings: how many KPI issues are blocking ("Missing KPIs"), how many valuation issues are blocking ("Missing Valuations"), and how many documents are flagged as missing ("Missing Documents").

## 8. Where It Can Fail

- **The document check quietly does nothing for almost everyone.** This check only actually runs if a particular setting has been turned on behind the scenes — and there's currently no field anywhere in the product UI to turn it on. It isn't on the Edit page, it isn't part of initial setup, and it isn't filled in automatically. Unless your technical team has switched it on manually, the document check will report "all good" every single time, even when documents are genuinely missing. If you're relying on this check to catch missing paperwork, verify with your team whether it's actually been turned on.
- **No KPI report on file means the document check is skipped, not failed.** If the agent can't find a KPI submission for the period, it deliberately skips the document check rather than reporting a confusing "document missing" message against a submission that doesn't exist. In that case, the missing-KPI flag is the only signal you'll see — the document check simply won't appear as an issue.
- **The wrong category on a company causes a silent skip.** If a company's category isn't set to "Portfolio Company" (case-insensitive — "portfolio company" also works), the agent stops before doing anything and records no findings at all — just a quiet log entry your technical team could look up. This can happen if someone changed a company's category partway through, or the run was pointed at the wrong record.
- **Reminder timing is based on the period, not the calendar date you might expect.** "Reminder days" counts days elapsed since the *start of the current period* (month, quarter, or year), measured against the application's configured time zone — not necessarily the time zone you or your server happen to be in. If your fund's configured time zone differs from what you'd expect, the day count — and therefore whether a reminder fires today — could be off by a day right around period boundaries.
- **Reminder "already sent today" tracking depends on having a prior report.** The agent checks the most recent report to see whether a reminder already went out today. If reports have been deleted, or you're working with a brand-new entity with no report history yet, that check has nothing to compare against — so a reminder could go out again on a day it normally wouldn't have.
- **Changing the due period or valuation period away from quarterly has no on-screen control.** If you need a different cadence, your technical team has to set it directly in the agent's underlying configuration — there's no field for this in the standard Edit form today.
- **One company's failure during a batch run is easy to overlook.** If a batch run hits a problem on a specific company, the rest of the batch keeps going — but that failure only shows up in the batch summary notification, not as its own separate failed report, unless that company's individual run also produced one.

## 9. Portfolio Company Dashboard

A standalone dashboard (separate from the agent's General tab) gives you a bird's-eye view of your entire portfolio's compliance health. Navigate to it via the **Investors** dropdown → **Portfolio Company Agent Dashboard**.

### Stat Cards (Row 1 — Overview)

| Card | What It Shows |
|------|---------------|
| **Total Companies** | All investors categorised as "Portfolio Company" in your entity — regardless of whether the agent has run against them. |
| **Validated** | Companies the agent has checked. Percentage bar shows how much of the portfolio has been processed. |
| **Up to Date** | Companies with zero blocking issues across KPIs, valuations, and documents. |
| **Not Yet Validated** | Companies the agent hasn't processed yet — run the agent to check them. |

### Stat Cards (Row 2 — Issue Breakdown)

| Card | What It Shows |
|------|---------------|
| **KPI Not Submitted** | Companies whose KPI reports for the current period are missing or overdue. |
| **Valuation Missing** | Companies without a recent valuation for the reporting period. |
| **Documents Not Uploaded** | Companies missing required compliance documents. If this shows 0 but KPIs are overdue, the subtitle explains that the document check requires KPI submission first. |

Every card is clickable — it filters the company table below to show only the matching companies.

### Company Table

- **Status filter dropdown:** Filter by All Statuses, Up to Date, Has Issues, KPI Not Submitted, Valuation Missing, or Documents Not Uploaded.
- **Search:** Type a company name to filter in real time.
- **Expandable rows:** Click the eye icon to see the full KPI, document, and valuation breakdown for a single company.
- **Pagination:** 10 companies per page.

### Actions

- **Run Validation:** Triggers the agent across all portfolio companies as a batch. The dashboard auto-refreshes when the batch completes.
- **Send Reminders:** Emails only companies with missing KPIs (not all companies with issues). Deduplicates — a company already reminded today is skipped. The button label shows the exact count of companies that will receive reminders.
- **View Pending Issues:** Filters the table to show only companies with at least one blocking issue.

### Report Statuses

The dashboard uses three simplified statuses:

| Status | Meaning |
|--------|---------|
| **Up to Date** | Agent ran and found zero blocking issues. |
| **Has Issues** | Agent ran and found at least one blocking issue (KPI, valuation, or document). |
| **Not Validated** | Agent has not yet processed this company. |

---

## 10. FAQ

**Q: I turned on "Send KPI submission reminder" but no email went out. Why?**
A: Check whether today's day-count since the period started matches one of the values in "Reminder days." The agent only sends on those specific days, and only once per calendar day — if a reminder already went out today (the agent checks the most recent report to know this), it won't send again.

**Q: The document check always says everything is fine, even when documents are clearly missing. Why?**
A: This check is controlled by a setting that has no field on the Edit page in the current product. Unless someone has explicitly turned it on behind the scenes, the check runs as a no-op and will always report no missing documents — regardless of what's actually on file.

**Q: I ran the agent on a Portfolio Company and got back an empty report with no issues. What happened?**
A: The company's category is probably not set to "Portfolio Company" (case-insensitive). The agent silently stops for any other category — check the company's category field.

**Q: Can I change the KPI/valuation period from quarterly to monthly?**
A: Not from the screen in this version of the product — both default to Quarter and can only be changed by having your technical team update the underlying configuration directly.

**Q: Does running this agent for my whole fund show a live progress view?**
A: No. Running against the whole portfolio, or from the Portfolio Agent Run screen, processes companies as a batch with no per-company progress view — you'll get a single summary notification once it's done. Only single-company runs (from a Portfolio Company's own page) show step-by-step progress.
