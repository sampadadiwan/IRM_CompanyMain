# Portfolio Company Agent — User Guide

The Portfolio Company Agent keeps an eye on the data health of every portfolio company in your fund — whether KPI reports have come in on time, whether required documents are on file, and whether a recent valuation has been recorded. It does not use AI to make judgment calls; it simply checks your data against the rules you've configured. You can run it across your whole portfolio at once, or against a single company.

> **Where to find it:** Company menu (house icon, top right) → [**Agents**](/support_agents) → **Portfolio Company Agent** card → **Run Now**; for one company, open its stakeholder page → **Misc → Run Portfolio Company Agent**; the dashboard is at [**Stakeholders → View Stakeholders → Actions → Portfolio Company Agent Dashboard**](/portfolio_company_dashboard). Needs the Company Admin role and the `portfolio_company_agent` entity flag; no LLM key.

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
11. [Related Guides](#related-guides)

---

## 1. What This Agent Does

For every company in your portfolio that is categorized as a "Portfolio Company," the agent checks four things, in order:

1. **Has the company submitted its KPIs for the most recently completed period?** (Quarterly, by default.) If not, this is flagged as a **blocking** issue.
2. **Are the required documents on file?** The agent checks whether the documents attached to the company's most recent KPI submission match the list of documents your fund requires.
3. **Has a valuation been entered for the same period?** If not, this is also flagged as a **blocking** issue.
4. **Should a reminder go out?** If any items are still missing and reminders are turned on, the agent emails a single consolidated reminder for that company, listing exactly what's missing, to the addresses in **KPI reminder email recipients** — but never more than once per day. Selected-company batch runs and scheduled runs never send reminders.

This agent never makes a call to an AI model — every check is rule-based, so there's no AI cost and no AI "judgment" involved. You don't need an AI provider key for this agent to work.

It also powers a few of the sample chat questions you'll see on a Portfolio Company's page (like "Show latest KPIs" or "What's the current valuation?"), but that's a separate conversational feature — not the run-and-report behavior this guide covers.

## 2. Inputs

| Field | Type | Default | What it controls |
|---|---|---|---|
| Reporting Period | Select | Quarterly | How often companies report: Monthly, Quarterly, Half-Yearly, Annually. |
| Start Checking After | Select | 15 days | How many days after a period ends before the agent begins checking (T+start). |
| Stop Checking After | Select | 60 days | How many days after a period ends before the agent stops checking and sending reminders (T+end). |
| Send KPI submission reminder | Select (Yes/No) | Yes | When Yes, sends a consolidated reminder email per company listing all its missing items (KPIs, documents, valuations). |
| KPI reminder email recipients | Text (comma-separated) | blank | The addresses every company's reminder is sent to — one agent-wide list, not looked up per company. If blank, no reminder is sent. |

The old "Reminder days" setting (comma-separated day offsets like "7,14,21") is no longer used — reminders are sent on each reminder-sending run (Run Now, a single-company run, or the dashboard) within the active window.

There is also no on-screen toggle for the document-check setting described below — see [Where It Can Fail](#8-where-it-can-fail) for what that means in practice.

### Setup checklist and warnings

The agent's **General** tab shows a yellow warning banner when reminder setup can't work:

- **"Send KPI submission reminder" never set** — an unset toggle counts as off, so reminders silently never go out. Set it explicitly to Yes or No (an explicit No is not flagged).

Reminder cadence needs no extra setup: reminders go out on each **Run Now**, single-company run or dashboard **Send Reminders** inside the active checking window (at most once per day). Scheduled runs validate only and never send reminders. Re-running **Setup All Agents** fills the reminder toggle with its default on agents that never had it.

**Data the agent looks at (not configuration, just the records it reads):**

- The company's submitted KPI reports — used to find the latest submission for the period, and (through that report's attachments) for the document check.
- The company's uploaded documents — compared against your fund's required-documents list.
- The company's valuations — used to find a recent valuation within the period.

## 3. Enabling the Agent

A CapHive administrator turns this agent on or off with the `portfolio_company_agent` support-agent flag on your entity. While it's off, the **Run Now** button (and the matching trigger on a company's page) stay disabled.

No AI provider key is needed — this agent is fully rule-based.

Only users with the **Company Admin** role can configure and run this agent — from the Agents page, a Portfolio Company's own page, the Portfolio Agent Run screen or the dashboard. A non-admin who sees a run button gets a permission error when they click it.

Unlike most agents, this one isn't created from scratch when you run **Setup All Agents** — it's been part of the product since before that setup flow existed, and is provisioned separately. Running **Setup All Agents** will only add the "Send KPI submission reminder" and "KPI reminder email recipients" fields if they're missing; it won't create the agent itself if it isn't already there.

## 4. Accessing and Running the Agent

**From the agent's own page:** Go to Company menu (house icon, top right) → **Agents** and open the **Portfolio Company Agent** card. On the **General** tab, click **Run Now**. Because this agent's natural scope is "the whole portfolio," running it from here processes every portfolio company in one batch, with a batch progress panel counting companies — there's no step-by-step view for each individual company in this mode. Reminders can be sent.

**From a single Portfolio Company's page:** Open the company record → **Misc → Run Portfolio Company Agent**. This runs the agent for just that one company, and you'll see a live progress panel walk through each check (KPI Submission Check → Document Presence → Valuation Check → Send Reminder → Save Report).

**From the Portfolio Agent Run screen:** Filter your portfolio companies by tag, sector, or name, select one or more from the table, and click **Run Agent on Selected Companies**. This queues a single batch job covering everything you selected. There's no per-company progress view here either, and no reminders are sent — you'll get a "Portfolio Validation" digest email and one summary notification once all the selected companies have been processed.

**Running on one company vs. everything:** Targeting a single company gives you the full step-by-step view. Running against the agent generally, or against your whole fund, processes **every** portfolio company in sequence — if one company hits a problem, it doesn't stop the rest from being checked, and the portfolio dashboard refreshes once at the end for everything that succeeded.

## 5. Scheduling

This agent's page does have the standard **Schedule** tab (frequency, run time, timezone, notification toggles), and you can set up a recurring schedule just like with any other agent. However, **Setup All Agents does not turn on a default schedule** for this one — unlike the Note Summarizer, there's no pre-built cadence waiting for you. If you want it to run automatically, you'll need to set that schedule up yourself. Scheduled runs always process the whole portfolio in one batch with reminders switched off, are skipped entirely when today is outside the checking window, and skip the summary notification (since there's no one actively waiting on the result).

## 6. Where to Find the Output

- **Execution History tab** — every past run, manual or scheduled, with its status, how long it took and processed/failed counts; expanding a row shows a short summary, not the full report.
- **Portfolio Agent Reports tab** (only on this agent's own page) — reports organized by which portfolio company they belong to.
- **Portfolio Company Dashboard** — a standalone dashboard (**Stakeholders → View Stakeholders → Actions → Portfolio Company Agent Dashboard**) showing stat cards, compliance chart, company table with search/filter/pagination, and Send Reminders. See [Section 9](#9-portfolio-company-dashboard) for details.
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
- **Reminder timing is based on the checking window, not any specific calendar date.** Reminders are sent on each reminder-sending run (Run Now, a single-company run, or the dashboard's Send Reminders) within the active window (T+start to T+end after the period ended), at most once per day. Scheduled and selected-company runs never send reminders, so scheduling the agent alone does not remind anyone. The window boundaries are calculated using the application's configured time zone — not necessarily the time zone you or your server happen to be in. This could cause a one-day difference right around period boundaries.
- **Reminder "already sent today" tracking depends on having a prior report.** The agent checks the most recent report to see whether a reminder already went out today. If reports have been deleted, or you're working with a brand-new entity with no report history yet, that check has nothing to compare against — so a reminder could go out again on a day it normally wouldn't have.
- **Changing the reporting period affects all three checks.** When you change the "Reporting Period" from Quarterly to Monthly (or any other cadence), KPIs, valuations, and documents are all checked against the same period. There is no way to use different periods for different check types.
- **One company's failure during a batch run is easy to overlook.** If a batch run hits a problem on a specific company, the rest of the batch keeps going — but that failure only shows up in the batch summary notification, not as its own separate failed report, unless that company's individual run also produced one.

## 9. Portfolio Company Dashboard

A standalone dashboard (separate from the agent's General tab) gives you a bird's-eye view of your entire portfolio's compliance health. Navigate to it via [**Stakeholders → View Stakeholders**](/investors) → **Actions** → **Portfolio Company Agent Dashboard**.

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

- **Run Validation:** Triggers the agent as a batch for the companies you scope (all, or by tag, sector or company) for the chosen **Check period**; reminders are sent only if you tick **Send reminders to companies with missing items**. The dashboard auto-refreshes when the batch completes, and you get a "Portfolio Validation" summary email.
- **Send Reminders:** Emails a reminder for each company with any missing items (KPIs, documents, or valuations) to the **KPI reminder email recipients**. Each email lists only what's missing for that company. Deduplicates — a company already reminded today, or opted out, is skipped. With no recipients configured, nothing is sent. The button label shows the exact count of companies that will receive reminders. After clicking, you'll see a confirmation message: "Reminders sent to N companies" if emails went out, or "Reminders were already sent today" if all companies were skipped.
- **View Pending Issues:** Filters the table to show only companies with at least one blocking issue.

There is also a **"Send Now"** shortcut in the **Recommended Next Steps** section at the bottom of the dashboard. It does exactly the same thing as the main Send Reminders button and shows the same last-sent date and confirmation dialog.

### Report Statuses

The dashboard uses three simplified statuses:

| Status | Meaning |
|--------|---------|
| **Up to Date** | Agent ran and found zero blocking issues. |
| **Has Issues** | Agent ran and found at least one blocking issue (KPI, valuation, or document). |
| **Not Validated** | Agent has not yet processed this company. |

---

## 10. FAQ

**Where do I find the Portfolio Company Agent in CapHive?**
Click the house icon at the top right (tooltip "Company menu") to open the **Company menu**, choose [**Agents**](/support_agents) and open the **Portfolio Company Agent** card. There is no left-sidebar entry for agents; if the **Agents** item is greyed out with a lock, no agents are enabled for your entity yet.

**How do I enable the Portfolio Company Agent for my entity?**
A CapHive administrator switches on the `portfolio_company_agent` flag under the entity's **Support Agents** flags in the Admin panel. Unlike other agents, **Setup All Agents** does not create this agent's record; it only adds the **Send KPI submission reminder** and **KPI reminder email recipients** fields to an agent that already exists. If the card is missing entirely, contact CapHive support. See [Enabling the Agent](#3-enabling-the-agent).

**How do I configure the checks and reminders?**
Open the agent card and click **Edit** on the **General** tab. Set **Reporting Period**, **Start Checking After**, **Stop Checking After**, **Send KPI submission reminder** (Yes/No) and **KPI reminder email recipients** (comma-separated addresses), then save. Only a Company Admin can edit. See [Inputs](#2-inputs).

**How do I run the agent across the whole portfolio?**
On the agent's **General** tab click **Run Now** and confirm. A job walks every stakeholder whose category is "Portfolio Company", and a batch progress panel on the same tab counts companies as they complete. See [Accessing and Running the Agent](#4-accessing-and-running-the-agent).

**How do I run the agent for one portfolio company?**
Open the company's stakeholder page ([**Stakeholders → View Stakeholders**](/investors) → open the record, category must be Portfolio Company), click the **Misc** dropdown and choose **Run Portfolio Company Agent**, then confirm in the modal. A live progress panel shows KPI Submission Check → Document Presence → Valuation Check → Send Reminder → Save Report.

**How do I run the agent for a selected group of companies?**
Go to [**Stakeholders → View Stakeholders**](/investors), open the **Actions** dropdown and choose [**Portfolio Agent Run**](/investors?portfolio_agent_run=true). Filter by tag, sector or name, tick the companies you want and click **Run Agent on Selected Companies**. This queues one batch job with no per-company progress view.

**How do I open the Portfolio Company Dashboard?**
From [**Stakeholders → View Stakeholders**](/investors) open the **Actions** dropdown and choose [**Portfolio Company Agent Dashboard**](/portfolio_company_dashboard). The item only appears once the agent record exists for your entity. See [Portfolio Company Dashboard](#9-portfolio-company-dashboard).

**How do I schedule the agent?**
Open the agent, click the **Schedule** tab, tick **Enable scheduled runs for this agent**, pick **Frequency**, **Run On**, **Run At** and **Timezone**, choose **Notify When** and **Notification Recipients**, and click **Save Schedule**. No default schedule is created for this agent, so nothing runs automatically until you do this. See [Scheduling](#5-scheduling).

**Who is allowed to run or configure the agent?**
Only users with the **Company Admin** role. Every launch point (agent page **Run Now**, the stakeholder page **Misc** item, **Portfolio Agent Run** and the dashboard's **Run Validation** / **Send Reminders**) authorises against the agent itself, so a non-admin who sees the button gets a permission error when they click it.

**How do I stop reminders for one specific company?**
If the stakeholder record has a custom field named `skip_kpi_reminder` set to Yes, both the agent's reminder step and the dashboard's **Send Reminders** skip that company and count it as "opted out". To stop reminders for everyone, set **Send KPI submission reminder** to No or clear **KPI reminder email recipients**.

**Where do I see the results?**
On the agent page: **Execution History** (every run, with counts) and **Portfolio Agent Reports** (grouped by company). Outside it: the **Portfolio Company Agent Dashboard**, and a summary card on each company's stakeholder page once a report exists for it. See [Where to Find the Output](#6-where-to-find-the-output).

**How do I delete the agent, and can I get it back?**
On the **General** tab click **Delete** (Company Admin only); it only succeeds for an agent that has never run, because its reports and execution logs block the delete. **Setup All Agents** does not recreate this agent, so a deleted one needs CapHive support to re-provision it; prefer disabling the schedule or the entity flag instead.

**Why should I use the Portfolio Company Agent?**
Chasing KPI packs, valuations and compliance documents from dozens of companies by hand is slow and inconsistent. The agent applies the same rule-based checks to every company after each reporting period, records exactly what is missing, and can send one consolidated reminder per company, so the team spends its time on the exceptions rather than on the audit.

**What does the agent let me do?**
See at a glance which companies are up to date, which are missing KPIs, valuations or documents for the last completed period, filter and drill into them on the dashboard, and email reminders with one click. It uses no AI and needs no LLM key, so results are deterministic and cost nothing to run.

**Who typically uses it?**
Portfolio-monitoring and finance teams at the fund who collect periodic KPI reports and valuations from portfolio companies, plus the Company Admin who owns the reminder settings. Portfolio companies only ever see the reminder email.

**What happens if I don't set it up?**
Nothing is checked automatically; missing KPI reports and valuations are only noticed when someone opens the company record. The **Portfolio Company Agent Dashboard** item does not appear, the stakeholder page shows no compliance summary, and no reminders are sent.

**What happens when I click Run Now on the agent page?**
Each Portfolio Company stakeholder is checked in turn and one SupportAgentReport per company is created or replaced. If **Send KPI submission reminder** is Yes, recipients are set, today is inside the checking window, the company has blocking items, is not opted out and was not reminded today, a reminder email goes out for that company. When the batch ends you get an in-app toast with success and failure counts; no other email is sent.

**What happens when I run it for a single company from the Misc menu?**
The same five steps run for that company with a live progress panel and the report is created or replaced (recorded as triggered manually by you). A reminder email can be sent under the same conditions as above. When it finishes you get an in-app toast with a **View Report** link; if a step fails the report is marked failed so you can re-run it.

**What happens when I use Run Agent on Selected Companies or a scheduled run?**
Both go through the batch runner with reminders switched off, so these runs validate and write reports only; no reminder email is sent even when **Send KPI submission reminder** is Yes. A selected-companies run also emails you a "Portfolio Validation" digest and shows an in-app toast; a scheduled run sends neither, and is skipped entirely when today is outside the checking window.

**What happens when I click Run Validation on the dashboard?**
A background job checks the companies you scoped (all, or by tag / sector / company) for the chosen **Check period**, replaces their reports and refreshes the dashboard when done. Reminders are sent only if you ticked **Send reminders to companies with missing items**. You then receive a "[Summary]" or "[Alert] Portfolio Validation — N companies checked" email plus an in-app toast.

**What happens when I click Send Reminders on the dashboard?**
For each selected company with blocking items, one reminder email listing its missing items (KPIs, Documents, Valuations) is queued to the **KPI reminder email recipients**, and the company's latest report records today's date so it cannot be reminded again today. You see "Reminders sent to N companies" with counts of companies skipped as already sent today or opted out. Nothing else changes.

**Who receives the reminder emails?**
The addresses in the agent's **KPI reminder email recipients** field, and only those. The list is agent-wide, so every company's reminder goes to the same addresses; it is not looked up per company. If the field is blank no reminder is sent at all, and the step is recorded as "No recipient emails configured".

**Does the agent change any stakeholder, KPI or valuation data?**
No. It only reads KPI reports, their attached documents and valuations, and writes SupportAgentReport records (plus the date of the last reminder on that report). It never creates tasks, never edits KPI or valuation records and never emails investors.

**Can I undo a run?**
There is nothing to roll back in your data: re-running simply replaces each company's report. A reminder email that has already been queued cannot be recalled, so check the dashboard's "last sent" dates and the recipients field before clicking **Send Reminders**.

**What happens if the KPI reminder email recipients field is blank?**
The reminder step is skipped with the message "No recipient emails configured" even when **Send KPI submission reminder** is Yes, and the dashboard's **Send Reminders** redirects with "No recipient emails configured. Add recipients in the agent settings." Fill the field on the agent's **Edit** page.

**I turned on "Send KPI submission reminder" but no email went out. Why?**
Work through the conditions in order: **KPI reminder email recipients** must not be blank; today must fall inside the checking window (T+start to T+end after the period ended); the company must have at least one blocking item; it must not have a `skip_kpi_reminder` opt-out; and it must not already have been reminded today. Also check which launch path you used, since selected-company batches and scheduled runs never send reminders.

**The document check always says everything is fine, even when documents are clearly missing. Why?**
The check runs only when the agent's configuration contains `validate_documents` = Yes, and that key has no field on the **Edit** page and is not seeded by setup. Unless your technical team set it directly, the check is a no-op and reports no missing documents. When it is on, it compares the File fields of the latest KPI report (plus any `required_docs` names) against the documents attached to that report.

**I ran the agent on a Portfolio Company and got back an empty report with no issues. What happened?**
The company's category is probably not set to "Portfolio Company" (case-insensitive). The agent silently stops for any other category, so check the category field on the stakeholder record.

**Can I change the KPI/valuation period from quarterly to monthly?**
Yes. The **Reporting Period** dropdown on the agent's **Edit** page offers Monthly, Quarterly, Half-Yearly and Annually. KPIs, valuations and documents are all checked against the same period.

**I clicked "Send Reminders" but nothing seemed to happen. Why?**
If every selected company was already reminded today or has opted out, you see "No new reminders sent" with the counts; if none of the selected companies has blocking items you see "No overdue companies to send reminders to". Wait until tomorrow, or re-check the companies with **Run Validation** first.

**Does running this agent for my whole fund show a live progress view?**
No. Whole-portfolio, selected-company and scheduled runs process companies as a batch with a running counter but no per-company step view; you get a single toast (or, for scheduled runs, the Schedule tab notifications) when it is done. Only single-company runs from the stakeholder page show step-by-step progress.

**The Run Now button or the Misc menu item is greyed out. What should I do?**
The `portfolio_company_agent` entity flag is off; the buttons render disabled with a lock icon and a tooltip. Ask your CapHive administrator to enable the flag for your entity.

**I can't see "Portfolio Company Agent Dashboard" in the Actions menu on the stakeholders list. Why?**
That item is rendered only when a Portfolio Company Agent record exists for your entity. If the agent was deleted or never provisioned, contact CapHive support; enabling the entity flag alone does not create the record.

**How does the agent decide which KPI report and valuation count?**
It computes the last completed period from **Reporting Period**, then looks for a KPI report whose "as of" date and a valuation whose valuation date fall inside that period. A submission dated outside the period, even a recent one, does not count, which is the usual reason a company that "just reported" is still flagged.

## Related Guides

- [Support Agents](../support_agents_user_guide) — shared setup, scheduling, LLM keys and report concepts for every agent.
- [KPI Upload](../kpi_upload_user_guide) — how portfolio companies' KPI reports get into CapHive.
- [Valuations](../valuations_user_guide) — the valuation records the agent checks for each period.
- [Document Management](../document_management_user_guide) — documents attached to KPI reports for the document check.
- [Investors (Stakeholders)](../investors_user_guide) — the stakeholder page with the **Misc** launch menu and the Actions dropdown.
- [Portfolio Scoring Agent](portfolio_scoring_agent_user_guide) — grades portfolio companies once their data is complete.
- [Presentation Analyst Agent](presentation_analyst_agent_user_guide) — analyses the decks attached to the same KPI reports.
