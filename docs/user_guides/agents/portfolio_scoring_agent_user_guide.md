# Portfolio Scoring Agent — User Guide

The Portfolio Scoring Agent scores each portfolio company using a sector-specific scoring guide and AI. It gathers the company's documents, KPI data, valuations, and investment history, sends all of that to your configured AI model together with the matching scoring guide, and stores a structured 0–100 investment score on the company.

> **Where to find it:** Company menu (house icon, top right) → [**Agents**](/support_agents) → **Portfolio Scoring Agent** → **Run Now**; for one company, open its stakeholder page → **Misc → Run Scoring Agent**; for a chosen set, [**Stakeholders → View Stakeholders → Actions → Portfolio Scoring Dashboard**](/portfolio_scoring_dashboard) → **Run Scoring**. Needs the Company Admin role, the `portfolio_scoring_agent` entity flag, an LLM key and an uploaded scoring guide.

## Table of Contents

1. [What This Agent Does](#1-what-this-agent-does)
2. [Inputs](#2-inputs)
3. [Enabling the Agent](#3-enabling-the-agent)
4. [Accessing and Running the Agent](#4-accessing-and-running-the-agent)
5. [Scheduling](#5-scheduling)
6. [Where to Find the Output](#6-where-to-find-the-output)
7. [Understanding the Report](#7-understanding-the-report)
8. [Where It Can Fail](#8-where-it-can-fail)
9. [Frequently Asked Questions](#frequently-asked-questions)

---

## 1. What This Agent Does

For each portfolio company, the agent works through four steps:

1. **Find the right scoring guide.** It looks at the company's sector and finds the matching scoring guide among the skill files you've uploaded for this agent. If the company has no sector set, or there's no matching guide (and no general fallback guide either), or the matched file can't be read as text, this step records an error — but the run continues anyway so you still get a report explaining what went wrong, rather than nothing at all.
2. **Gather the company's data.** The agent collects the company's KPI reports (limited to those tagged "Actual," filtered to your chosen frequency), its investment history, valuations (most recent first), its configuration fields, and the text of any documents attached to recent KPI reports. This step is skipped entirely if step 1 hit an error.
3. **Generate the score.** The agent combines the scoring guide with everything gathered in step 2 into a single request to your configured AI model, and expects back a structured score with an overall score, a grade, a summary, and a breakdown by dimension (plus strengths, risks, recommendations, and a note on how much data was available).
4. **Save the score.** Every run creates a **new** score report rather than overwriting the last one, so your scoring history builds up over time. This happens whether the run succeeded or recorded an error — either way, you get a report.

Companies with no sector set are left out of fund-wide runs entirely before the agent even starts — a batch run only looks at portfolio companies that have a sector assigned, so a company with no sector quietly never gets a report from a fund-wide run.

## 2. Inputs

| Field | Type | Default | What it controls |
|---|---|---|---|
| Generic Portfolio Skill | File upload | — | The fallback scoring guide used when no sector-specific guide matches the company's sector. Upload a `.md` or `.txt` file. The agent looks the file up by its document name, which must exactly match this field's label — "Generic Portfolio Skill" — not by the original filename from your computer. Uploading through this field on the agent's **Edit** page names the document after the label automatically. |
| Beauty & Skincare Skill | File upload | — | A sector-specific scoring guide, used when a company's sector is set to "Beauty & Skincare." Matched through the field's internal sector tag. Same `.md` or `.txt` recommendation and same name-matching rule as above apply. You can add similar fields for other sectors the same way. |
| Min points per section | Number | **5** (this is what a fresh setup actually gives you) | The minimum number of bullet points the AI must produce for each section of the score — both within each scoring dimension (positives/concerns) and in the overall strengths, risks, and recommendations lists. A blank or zero value falls back to 3, but any value of 1 or more is used as entered; a freshly set-up agent starts at 5. |
| KPI frequency filter | Select | All | Restricts which KPI reporting periods are sent to the AI as context (All, Month, Quarter, Half Year, Year, YTD). "All" applies no filter. |
| Documents from last N KPI reports | Number | **3** (this is what a fresh setup actually gives you) | How many of the most recent "Actual"-tagged KPI report periods the agent pulls document attachments from to include as context. If this field were ever left blank or zero, the system would fall back to just 1 — but a freshly set-up agent is seeded with 3. |
| Document name filter | Text | (blank) | A comma-separated, case-insensitive list of document names to include from the selected reports. Leave blank to include every document from those reports. |

> **A note on defaults you may have seen elsewhere:** an earlier version of this guide listed the defaults for "Min points per section" and "Documents from last N KPI reports" as 3 and 1. Those numbers are only the system's last-resort fallback if a field is ever missing or blank — they are not what you'll actually see. When the **Setup All Agents** process provisions this agent, it writes in 5 and 3 respectively, and that's what a freshly configured agent will use. Trust the values in this guide.

**Data the agent reads (not configuration, just records it pulls in):** the company's "Actual"-tagged KPI reports and their attached documents (PDF, Excel, PowerPoint, plain text, Markdown, and CSV files are read as text; Word documents are accepted by the upload screen but currently have no text-reading support — see below), valuations, investment history, and the company's own configuration field values.

### Setup checklist and warnings

The agent's **General** tab shows a yellow warning banner whenever the scoring-guide setup is broken, before you run anything. For this agent the banner flags:

- **A scoring-guide field that is missing entirely** — re-run **Setup All Agents** to restore it.
- **A scoring-guide field that has lost its sector tag** — the internal tag that tells the agent which sector the file scores. Without it the agent can never match the file, even though the upload looks fine on the edit page. Re-running **Setup All Agents** repairs the tag automatically.
- **A scoring-guide field with no file uploaded** (including the General fallback) — upload a `.md` or `.txt` file through that field on the agent's **Edit** page, which names it after the field's label.

If a run fails anyway, the failed report now names the specific setup problem (for example "the field is not tagged as a skill") rather than only saying no guide was found — and failed runs are listed in the Scoring Reports tab alongside successful ones, with the error shown in the Status column.

## 3. Enabling the Agent

CapHive support turns this agent on with the `portfolio_scoring_agent` support-agent flag on your entity. While it's off, the **Run Now** button is disabled and the stakeholder page's **Misc → Run Scoring Agent** item is greyed out with a lock.

This agent requires an AI provider key, configured at Company menu (house icon, top right) → **Agents** → [**LLM Keys**](/support_agents/llm_keys) — it calls the AI model on essentially every run, unless it stops early due to a scoring-guide error. It uses this agent's own model setting if one is configured, otherwise your entity's default model.

Only **Company Admin** users can run **Setup All Agents**, edit this agent's configuration fields and uploaded scoring guides, and run the agent from any screen, including a Portfolio Company's page.

## 4. Accessing and Running the Agent

**From the agent's own page:** Company menu (house icon, top right) → **Agents** → **Portfolio Scoring Agent** → **Run Now**, on the General tab. Without targeting a specific company, this scores every portfolio company that has a sector set, as one sequential batch with a live batch progress panel; you'll get a single summary notification once it's done.

**From a single Portfolio Company's page:** **Misc → Run Scoring Agent**. This scores just that one company. (The score widget itself has no re-score button; only its failed and empty states offer **Re-run Scoring Agent** / **Run Scoring Agent**.)

**Batch run for a chosen set:** [**Stakeholders → View Stakeholders → Actions → Portfolio Scoring Dashboard**](/portfolio_scoring_dashboard) → **Run Scoring**, choose which companies to run on (all with a sector, never scored, specific companies, by sector or by tag), then **Start Scoring**. The **Portfolio Agent Run** screen does not run this agent.

**Running on one company vs. everything:** A single-company run scores just that one company. A fund-wide or batch run scores every portfolio company that has a sector assigned, one after another. If one company hits a problem, it doesn't stop the rest — but a company whose scoring failed still counts as a success in the final summary, because a failed report is saved rather than stopping the run.

## 5. Scheduling

This agent's page does have the standard **Schedule** tab, but **Setup All Agents does not turn on a default schedule** for it — it's designed to be run on demand or from the agent's screen, not on an automatic cadence out of the box. If you want recurring scoring, you'll need to configure the Schedule tab yourself. Keep in mind that scoring your full portfolio on every scheduled run means every company scored triggers an AI call — worth factoring into cost before turning on a frequent schedule.

## 6. Where to Find the Output

- **Scoring Reports tab** (only on this agent's own page) — every scoring report, across all companies. Failed runs appear here too, marked with a red **Failed** badge and the reason shown right in the table — you don't need to expand the row to see why a score didn't generate.
- **Execution History tab** — every run, with status and how long it took.
- [**Portfolio Scoring Dashboard**](/portfolio_scoring_dashboard) — the latest score per company, with tiers and score movement.
- **Company Score widget** — the **Scoring Report** dashboard widget on the company's dashboard (stakeholder page → **Misc → Dashboard**) once it has been added; shows the latest completed score, or the most recent failure's error message if the last run failed, or a "Run Scoring Agent" prompt if no report exists yet.
- The score is **not** saved onto the portfolio company record itself — it lives entirely inside that company's scoring report. Every run creates a brand-new report rather than overwriting the last one, so your scoring history accumulates over time (the widget always shows the most recent one).

## 7. Understanding the Report

A successful report includes:

- **Overall score** — a whole number from 0 to 100.
- **Grade** — a free-form label (e.g. "B+") from the AI. The product also derives its own qualitative label (Exceptional/Strong/Good/Adequate/Mixed/Underperforming/Distressed) purely from the numeric score band — independent of whatever grade text the AI returned.
- **Summary** — a narrative overview shown as the headline statement.
- **Dimensions** — a breakdown by scoring category, each with a name, score, weight, rationale, and lists of positives and concerns. Each dimension is required to include at least the configured minimum number of points in both its positives and concerns lists.
- **Strengths, risks, recommendations** — top-level lists, each expected to have at least the configured minimum number of items.
- **Data coverage** — counts of how many KPI periods, valuations, and documents were actually used, shown as badges next to the score.

A failed report instead shows an error message, with the report marked as failed. The score widget displays that error text directly, so you can see why a company has no score — most commonly, a missing or unreadable scoring guide for that company's sector.

Scores can be **manually edited** in place — double-click any field in the widget to overwrite it. Edited fields get a small "Edited" badge next to the score.

## 8. Where It Can Fail

- **No sector set means a company is silently left out, not flagged as a problem.** Before the agent even starts, fund-wide and batch runs filter out any portfolio company with no sector value — so these companies never get a report, failed or otherwise, from that kind of run. They simply don't appear anywhere in the results. If you run the agent directly from that company's own page instead, it does proceed and fails with a clear "no sector configured" message.
- **No scoring guide matches the company's sector.** The agent looks for an uploaded file tagged for the company's exact sector (case-insensitive), falling back to a file tagged "General" if one exists. If neither is found, the report fails with a message naming the sector that had no match. To support a new sector, you need both a new upload field configured for that sector and a file uploaded to it whose **document name matches that field's label exactly** — the lookup is purely a name match, not a filename match. Uploading through the field on the agent's **Edit** page sets that name for you.
- **Wrong file format for a scoring guide or KPI document.** The agent reads `.txt`, `.md`, PDF, Excel (`.xlsx` or `.xls`), CSV and PowerPoint files as text — but Word documents (`.doc` or `.docx`) and any other file type are accepted by the upload screen and have no text-reading logic, so they're silently treated as empty rather than causing an error. For a scoring guide, this surfaces as a message saying the file "is empty or could not be read." For a KPI document attachment, it just means that document contributes nothing to the AI's context, with no visible warning anywhere in the report.
- **The AI's response doesn't contain a usable score.** The agent looks for a structured score in the AI's reply in a few different ways before giving up. If the AI's answer is all prose with no structured score at all, or is missing required fields (overall score, grade, summary, dimension breakdown), the run is recorded as a failure with that error message — it will never silently save a report with incomplete or malformed data.
- **An out-of-range score or an empty dimension list** are caught the same way and also result in a failed report rather than a saved-but-wrong score.
- **KPI document gathering only looks at your most recent few "Actual" reports.** The "Documents from last N KPI reports" setting (3 by default) limits which report periods are scanned for documents. A document attached to an older report outside that window is never sent to the AI, even if your document name filter would otherwise have allowed it.
- **The document name filter is an exact, case-insensitive match — not a partial match.** A filter value that doesn't exactly match a document's stored name will silently exclude that document, with no error or warning — it just won't show up in the AI's context.
- **Re-running creates a new report; it never updates the previous one.** If you re-run scoring and it fails, the widget will show that new failure message in place of your last good score, since the widget always shows the most recent report. Re-run successfully to restore a visible score.
- **Changing a company's category away from "Portfolio Company" and back clears its sector.** The system automatically blanks out the sector field whenever a company's category changes away from "Portfolio Company" — so switching the category back later does not bring the old sector value back. You'll need to re-set the sector (and re-verify the scoring guide match) afterward.

## Frequently Asked Questions

### Navigation and getting there

**Where do I find the Portfolio Scoring Agent in CapHive?**
Open the Company menu (house icon, top right) → [**Agents**](/support_agents) and click the **Portfolio Scoring Agent** card in the Portfolio category. Its page has **General**, **Schedule**, **Execution History** and **Scoring Reports** tabs. If **Agents** is locked, no agent is enabled for your entity; contact CapHive support.

**How do I score a single portfolio company?**
Open the company's stakeholder page ([**Stakeholders → View Stakeholders**](/investors) → open the record), click **Misc → Run Scoring Agent**, read the description and click **Run Agent**. The menu item only appears for stakeholders of category *Portfolio Company*. See [Accessing and Running the Agent](#4-accessing-and-running-the-agent).

**Where is the Portfolio Scoring Dashboard?**
Go to [**Stakeholders → View Stakeholders**](/investors), open the **Actions** dropdown and choose [**Portfolio Scoring Dashboard**](/portfolio_scoring_dashboard). The item only appears once the Portfolio Scoring Agent exists for your entity (after **Setup All Agents**).

**How do I score several companies at once?**
On the Portfolio Scoring Dashboard click **Run Scoring**, choose **Run on**: all portfolio companies with a sector, only companies never scored, specific companies, by sector or by tag, then click **Start Scoring**. **Run Now** on the agent's **General** tab scores every portfolio company that has a sector.

**Where do I see a company's score?**
Three places: the **Scoring Reports** tab on the agent page (every report for every company, with a red **Failed** badge and the reason for failures), the Portfolio Scoring Dashboard table (latest score per company), and the **Company Score** widget on the company's own dashboard (stakeholder page → **Misc → Dashboard**) once the **Scoring Report** widget has been added. See [Where to Find the Output](#6-where-to-find-the-output).

**The Run Scoring Agent item is greyed out with a lock. Why?**
The `portfolio_scoring_agent` flag is off for your entity, so the item shows the tooltip "Portfolio Scoring Agent is disabled. Contact support to enable it", and **Run Now** on the agent page is disabled with a red **Disabled** badge. Only CapHive support can switch the flag on.

### Creating, updating and managing the agent

**How do I set the agent up?**
Ask CapHive support to enable the `portfolio_scoring_agent` flag, add an LLM key under [**Agents → LLM Keys**](/support_agents/llm_keys), then click **Setup All Agents → Run Setup** on the [**Agents**](/support_agents) page. Setup creates the agent with the **Generic Portfolio Skill** and **Beauty & Skincare Skill** file fields and the default settings, but no schedule. See [Enabling the Agent](#3-enabling-the-agent).

**How do I upload or replace a scoring guide (skill file)?**
Open the agent, click **Edit** on the **General** tab, choose a `.md` or `.txt` file in the matching skill field (for example **Generic Portfolio Skill**) and save. Uploading through the field names the document after the field label automatically, which is exactly the name the agent looks up. See [Inputs](#2-inputs).

**How do I add a scoring guide for a new sector?**
A new sector needs its own File field tagged with `skill: true, sector: <Sector name>` on the agent's configuration form, which your CapHive administrator adds. Then upload the guide to that field on the agent's **Edit** page and make sure each company's **Sector** value matches the sector name.

**How do I change the scoring settings?**
On the agent's **Edit** page set **Min points per section**, **KPI frequency filter**, **Documents from last N KPI reports**, **Document name filter** and the **AI Model** override, then save. Only a Company Admin can edit, and changes apply from the next run.

**How do I set a company's sector so it can be scored?**
Edit the company's stakeholder record and fill in **Sector** with the exact sector name of a scoring guide, or any value if you rely on the **Generic Portfolio Skill** fallback. Companies with no sector are left out of every multi-company run.

**How do I schedule scoring?**
Open the agent's **Schedule** tab, tick **Enable scheduled runs for this agent**, choose **Frequency** (daily, weekly, monthly, bimonthly, quarterly or half-yearly), **Run On**, **Run At** and **Timezone**, pick **Notify When** and **Notification Recipients**, and click **Save Schedule**. Setup does not create a schedule for this agent. See [Scheduling](#5-scheduling).

**How do I correct a score by hand?**
On the **Company Score** widget, double-click the overall score, grade, summary, a dimension score or a bullet point, type the new value and confirm. You need edit permission on that company; edited reports show an **Edited** badge with the date.

**How do I stop or delete the agent?**
Untick **Enable scheduled runs for this agent** on the **Schedule** tab to stop scheduled scoring. **Delete** on the **General** tab only works for an agent that has never run; once scoring reports exist, pause it instead.

**Who can run and configure the agent?**
Only users with the **company_admin** role can run it (from any screen), edit its settings, upload skill files and schedule it. Other employees of your entity can open the Portfolio Scoring Dashboard, and anyone with edit rights on a company can hand-edit its score in the widget.

### Why use the Portfolio Scoring Agent

**Why should I use the Portfolio Scoring Agent?**
It turns each company's KPIs, valuations, investment history and recent KPI documents into a comparable 0 to 100 score with a grade, dimension breakdown, strengths, risks and recommendations, using your own sector-specific rubric. That makes a whole portfolio reviewable in one place instead of company-by-company reading.

**What does it let me do that I could not do otherwise?**
Apply the same written scoring rubric to every company in a sector, track how scores move between runs (the dashboard shows improved, declined, unchanged and stale companies), and triage the portfolio into **Outperformers** (80 to 100), **On Track** (60 to 79), **Watch List** (40 to 59) and **At Risk** (0 to 39).

**Who typically uses it?**
Portfolio monitoring and investment teams preparing periodic portfolio reviews or investment committee packs, with a Company Admin maintaining the sector scoring guides. Scores are internal and are never shown to portfolio companies or investors.

**What happens if I don't upload a scoring guide?**
Every run fails for every company: the report records "No skill file configured for sector: …" and lists the configuration problem, and the **General** tab and dashboard show a yellow warning banner naming the missing upload. Uploading at least the **Generic Portfolio Skill** gives every sector a fallback.

### What happens when I...

**What happens when I run the agent on one company?**
A progress panel shows Initialize, Load Skill, Gather Data, Score and Save Score. A new scoring report is saved for that company (failures are saved too, with the error), it appears on the **Scoring Reports** tab, the dashboard and the **Company Score** widget, and you get an in-app alert when the job completes. No email is sent and the company is not contacted.

**What happens when I click Run Now or Start Scoring?**
One background job scores each qualifying company in turn, with a live batch progress panel. When it ends you get an in-app summary of how many companies were processed and failed, and a separate report is saved per company. Each company scored is one AI call, so large portfolios take time and cost accordingly.

**What happens when a scheduled run fires?**
All portfolio companies with a sector are scored, the run is logged in **Execution History** as scheduled, and only the **Notification Recipients** are told, by email and in-app, for the outcomes ticked under **Notify When**. No batch summary alert is sent to anyone else.

**What happens to earlier scores when I re-run?**
Nothing: every run adds a new report and never overwrites the previous one, so history builds up and the dashboard can compute score movement. The widget and dashboard always show the most recent report, including a failure, so a failed re-run hides the last good score until the next successful run.

**What happens when I edit a score by hand?**
The edited value is written to that scoring report and the report is flagged as manually edited with the date, shown as an **Edited** badge. The AI is not called again, and the next run creates a fresh report without your edits.

**Does scoring write anything onto the portfolio company?**
No. The score lives only in the scoring report linked to the company; the company's fields, KPIs, valuations and documents are only read. See [Where to Find the Output](#6-where-to-find-the-output).

**What happens when I change a setting such as Min points per section?**
Only future runs use it; existing reports keep the output they were produced with. For **Min points per section**, a blank or zero value falls back to 3, but any value of 1 or more is used as entered.

### Troubleshooting and edge cases

**A company has a sector set but never shows up when I run the agent for my whole portfolio. Why?**
Multi-company runs only include stakeholders whose category is exactly *Portfolio Company* and whose **Sector** is not blank. If both are true the company is scored, so check its report on the **Scoring Reports** tab for an error such as no matching guide rather than assuming it was skipped.

**The score widget shows "Last scoring run failed". What should I check first?**
Read the error shown under the heading; it is also in the **Status** column of the **Scoring Reports** tab. The most common causes are no scoring guide matching the company's sector, an unreadable guide file, or a missing LLM key.

**I uploaded a scoring guide file but the agent still says no skill is configured. What's wrong?**
The agent looks for a document named exactly like the field's label and a field whose tag names the company's sector (or General). Upload through the skill field on the agent's **Edit** page rather than elsewhere, check the company's **Sector** spelling, and read the yellow banner, which flags an untagged field or missing upload; re-running **Setup All Agents** repairs missing tags.

**Can I use a Word document (.doc/.docx) as a scoring guide?**
No. Word files are not read, so a Word guide shows up as "empty or could not be read". Use `.md` or `.txt` for scoring guides; PDF, Excel, CSV and PowerPoint KPI documents are read as text.

**My KPI documents seem to be ignored. Why?**
Only documents attached to the most recent **Documents from last N KPI reports** Actual-tagged KPI reports are read, and if **Document name filter** is set a document's name must match an entry exactly (case-insensitive). Word attachments contribute nothing.

**The batch summary says every company succeeded but some have no score. Why?**
A company whose scoring failed still counts as processed in the summary, because the agent saves a failed report rather than stopping. Check the **Scoring Reports** tab or the dashboard's **Not Scored** tier for the failures.

**Why does "Min points per section" show 5 when some documentation says the default is 3?**
3 is only the fallback when the field is blank or below 1. **Setup All Agents** seeds the field with 5, which is what you will see on a fresh agent.

**Can I use the Portfolio Agent Run screen to score companies?**
No. **Stakeholders → View Stakeholders → Actions → Portfolio Agent Run** runs a fixed agent, not the scoring agent. Use **Run Scoring** on the Portfolio Scoring Dashboard for a chosen set of companies.

**I changed a company's category and its score stopped appearing in runs. Why?**
Changing a stakeholder's category away from *Portfolio Company* clears its **Sector**, and switching back does not restore it. Set the sector again before the next run.

## Related Guides

- [Support Agents](../support_agents_user_guide) — shared setup, LLM keys, scheduling and run history for every agent.
- [LLM Configuration](../llm_configuration_guide) — the AI provider keys scoring runs on.
- [Investors (Stakeholders)](../investors_user_guide) — setting a portfolio company's category and sector.
- [KPI Upload](../kpi_upload_user_guide) — the Actual KPI reports and documents the agent reads.
- [Valuations](../valuations_user_guide) — valuation history included in the score.
- [Dashboard Widgets](../dashboard_widgets_user_guide) — adding the Scoring Report widget to a company dashboard.
- [Portfolio Company Agent](portfolio_company_agent_user_guide) — compliance checks that complement the investment score.
- [Presentation Analyst Agent](presentation_analyst_agent_user_guide) — AI analysis of board presentations for the same companies.
