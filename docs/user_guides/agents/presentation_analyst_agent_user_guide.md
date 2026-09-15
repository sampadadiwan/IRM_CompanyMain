# Investor Presentation Analyst — User Guide

The Investor Presentation Analyst reads a portfolio company's investor presentations across reporting periods, extracts structured intelligence from each one, compares periods to surface commitment misses and dropped risks, and produces a pre-board briefing plus a Management Accountability Score — all scoped to one portfolio company at a time.

> **Where to find it:** Company menu (house icon, top right) → [**Agents**](/support_agents) → **Investor Presentation Analyst** → **Run Now**; for one company, open its stakeholder page → **Misc → Run Presentation Analyst**; for a chosen set, [**Stakeholders → View Stakeholders → Actions → Presentation Analyst Dashboard**](/presentation_analyst_dashboard) → **Run Analysis**. Needs the Company Admin role, the `presentation_analyst_agent` entity flag and a large-context LLM key.

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

Each run works through one portfolio company and walks through these stages:

1. **Gets started** — loads its settings. If the target isn't actually a portfolio company, or the agent isn't enabled, it stops cleanly with no error.
2. **Collects presentations** — looks at the most recent KPI reports of your configured type (Actual, by default), and on each one finds the first attached document whose name in CapHive (not the uploaded file name) contains one of your configured keywords (matching isn't case-sensitive). Reports are read oldest to newest, so later steps understand the timeline correctly.
3. **Extracts intelligence** — reads each matching document **in full**, with no shortening or skipping, and asks the AI to pull out eight categories of information per period: management narrative, commitments, risks, accomplishments, forward plans, strategic objectives, key metrics, and initiatives.
4. **Runs cross-period analysis** — compares the extracted periods against each other to produce five comparison views: commitment tracking, risk evolution, objective drift, an "initiative graveyard" of abandoned plans, and metric anomalies. This only runs once at least two periods have been extracted.
5. **Generates the briefing** — produces 8–12 grounded pre-board questions, each one citing a specific number, date, or quote so it's clearly tied to real evidence. This step can reuse the previous question set if nothing meaningful has changed since the last run — see [Where It Can Fail](#8-where-it-can-fail).
6. **Scores the company** — calculates the **Management Accountability Score** (0–100) using simple arithmetic on the comparison results — no AI call needed for this part. It's a weighted blend: Commitment 35%, Risk 25%, Coherence 25%, Narrative 15%.
7. **Saves everything** — stores the full result as a new report.

A small chat panel on the agent's own page (turned on by **Setup All Agents**) lets a fund manager ask follow-up questions about the latest run's findings in plain language, without re-running the whole analysis. See [Where to Find the Output](#6-where-to-find-the-output) for what the chat panel can see.

## 2. Inputs

| Field | Type | Default | What it controls |
|---|---|---|---|
| Presentation document names | Text (comma-separated) | Investor Update, Board Deck, Management Presentation, Quarterly Update, Investor Presentation | Keywords matched (not case-sensitive) against the names of documents on each KPI report (the document's name in CapHive, not the uploaded file name). A document counts as a presentation if its name contains **any** of these keywords. |
| Max periods to analyze | Number | 8 | The maximum number of the most recent reporting periods scanned. Anything below 1 quietly falls back to 8. |
| KPI report tag | Select (Actual/Budget/IC) | Actual | Which type of KPI report is scanned for presentation documents. |
| Comparison strategy | Select (All periods/Sliding window) | All periods | "All periods" sends every extracted period to the AI in one go — most accurate, since it sees the whole arc at once. "Sliding window" instead makes one comparison per adjacent pair of periods — cheaper as the number of periods grows, but less holistic. |
| AI Model | Text | gemini-3.7-flash | The agent's **AI Model** field, which the agent actually uses. Needs to support a very large context window (roughly 500K tokens or more). The separate **LLM model** configuration field is stored but never read. See the note below. |

**Why the AI model matters here.** The Extract Intelligence step sends each presentation's full text to the AI with no shortening at all — the whole design assumes a model that can handle roughly a million tokens of context, which is what the default model provides. If you switch to a smaller-context model: long presentations may get silently cut off or rejected by the AI provider, extraction quality will degrade or fail document-by-document (each failure is handled quietly and logged, not shown as a hard error), and the cross-period comparison step — when using "All periods" mode — sends every period's extracted data in one request, which can itself get close to a smaller model's limits even though the original documents are no longer part of that payload (only the extracted summaries are).

**Other things the agent looks at** (not settings you configure directly):
- The KPI reports and their attached documents for the target portfolio company.
- Document formats it can read: PDF, TXT, Markdown, Excel (XLSX/XLS), PowerPoint (PPTX/PPT), and Word (DOCX/DOC). PowerPoint and Word files go through a layered extraction process that tries a few different methods in sequence to get the best possible text out.
- The previous run's report (used for the question-reuse logic and for the chat panel's context).

Two additional on/off switches exist behind the scenes beyond the fields above: one to turn off scoring, and one to turn off question generation (both on by default). These let you disable the Score and/or Briefing sections independently without affecting the rest of the agent. Ask an administrator if you need either of these changed, since they aren't exposed on the standard settings screen.

## 3. Enabling the Agent

1. CapHive support turns on the `presentation_analyst_agent` support-agent flag for your entity.
2. An AI provider key needs to be set up at Company menu (house icon, top right) → **Agents** → [**LLM Keys**](/support_agents/llm_keys) — every meaningful step in this agent relies on the AI.
3. The default model set in **AI Model** (gemini-3.7-flash) supports a roughly 1-million-token context window — keep it unless you have a specific reason to switch and a comparably large-context replacement in mind; see the failure-mode note above.
4. Running the agent, from any screen, requires the **Company Admin** role.

## 4. Accessing and Running the Agent

**From a Portfolio Company page:** open the company's stakeholder page → **Misc → Run Presentation Analyst** and click **Run Agent**. The "Investor Presentation Analysis" widget (once added to the company's dashboard) shows recent reports for that company (periods covered, score, grade, question count, status, and run time) and also offers **Run Presentation Analyst** for a first run, or **Re-run** after that.

**From Company menu (house icon, top right) → Agents:** open the agent card → General tab → **Run Now**. There is no company picker: this analyses every portfolio company in your entity as one batch.

**From the Presentation Analyst Dashboard:** [**Stakeholders → View Stakeholders → Actions → Presentation Analyst Dashboard**](/presentation_analyst_dashboard) → **Run Analysis**, choose which companies to run on (all, never analysed, specific companies, by sector or by tag), then **Start Analysis**.

**Scope:** each company is analysed separately — a batch run from **Run Now**, the dashboard or the schedule saves one report per company.

**Watching it run:** a single-company run shows a live, 7-step progress panel (Initialize → Collect Presentations → Extract Intelligence → Cross-Period Analysis → Generate Briefing → Score → Save), so you can watch each stage complete — or flag an issue — in real time. A batch run shows a batch progress panel that counts through the companies.

## 5. Scheduling

A monthly schedule is set up automatically by **Setup All Agents**: the **1st of each month at 06:00 (Asia/Kolkata)**, with failure and partial-success notifications on, success notifications off, and CapHive support notified if something errors. **It ships turned off** by default — nothing runs automatically until someone enables it. Turn it on from the agent's **Schedule** tab so fresh briefings are ready ahead of board meetings.

## 6. Where to Find the Output

- **Report**: a new report is saved every time this agent runs for a portfolio company — full history is kept, and the most recent one is always marked as the latest automatically.
- **Portfolio company widget**: the **Presentation Analyst** dashboard widget ("Investor Presentation Analysis") on the company's dashboard (stakeholder page → **Misc → Dashboard**, once added) shows the most recent runs with score, grade, and question count inline, and can be expanded for full detail.
- [**Presentation Analyst Dashboard**](/presentation_analyst_dashboard): companies grouped into accountability tiers, with score movement between runs.
- **Presentation Reports tab**: on the agent's own page, grouped by portfolio company.
- **Chat panel** (if turned on): shown only on the agent's own page. It looks at the single most recent Presentation Analyst report for your entity — whichever company that run was for, not a company you choose — including any reused questions, and can search the full extracted detail for quotes that didn't make it into the summarized findings.
- **No email goes out for this agent.** Output is only available through the UI and the chat panel. The schedule's notification toggles control internal alerts to administrators and CapHive support if something fails — they don't send a digest to a fund manager's inbox.

## 7. Understanding the Report

Each saved report includes:

| Field | Meaning |
|---|---|
| Period records | The eight categories of extracted intelligence for each period, in chronological order. |
| Cross-period flags | The five comparison views: commitment tracking, risk evolution, objective drift, initiative graveyard, and metric anomalies. Empty if fewer than two periods were extracted, or if the comparison step ran into an error. |
| Analyst questions | 8–12 grounded pre-board questions, each with the question text, its category, which period it came from, and the supporting evidence. |
| Periods analyzed | A readable list of which reporting periods were included. |
| Change tracking marker | An internal fingerprint of the cross-period flags, used to decide whether the question set needs to be regenerated next run. |
| Score | Overall score, grade, and the four component scores (commitment, risk, coherence, narrative) — blank if scoring was turned off or failed. |
| Collection / extraction / analysis issues | Per-step issue logs, shown in the report's expandable detail panels. |
| Overall status | "Blocked" if anything blocking turned up anywhere in the run (for example, zero presentations found or zero periods successfully extracted), otherwise "Ready." |

**How the Management Accountability Score is built** (calculated purely from the cross-period comparison, with no AI call involved):
- **Commitment (35%)** — rewards commitments that were met or partially met, and subtracts points for any commitment that was quietly dropped and never mentioned again.
- **Risk (25%)** — starts at 100 and moves based on what happened to each previously flagged risk: a meaningful penalty for a dropped risk with no resolution, a smaller penalty for an escalated risk, a smaller penalty still for a newly introduced risk, and a bonus for any risk that was actually resolved.
- **Coherence (25%)** — starts at 100 and tracks strategic objectives and initiatives: a penalty for a removed objective, a smaller penalty for one that was reframed, a penalty for an abandoned initiative, and a bonus for an objective that stayed stable across three or more periods.
- **Narrative (15%)** — reduced based on how many metric anomalies were detected in that period.

The overall score maps to a letter grade from fixed bands: A (90–100), B+ (80–89), B (70–79), C+ (60–69), C (50–59), D (below 50). This is not the same as the Portfolio Scoring Agent's grade, which is free text written by the AI, so compare the numeric scores rather than the letters.

## 8. Where It Can Fail

- **No presentations found is the single most common reason for an empty result.** A presentation only counts if it's attached to the right kind of report — specifically a KPI report, not just uploaded somewhere general on the portfolio company — and its document name in CapHive (not the uploaded file name) contains one of your configured keywords (like "Board Deck" or "Investor Update"). If the document's name doesn't match, the agent finds nothing for that period. When that happens, the run still completes and produces a report, but it's marked "Blocked" with no further AI calls made. If you're seeing an empty result, check that the presentation is attached to a KPI report and that its document name actually contains one of the configured keywords.
- **"All periods" comparison cost/accuracy tradeoff.** With many periods configured, "All periods" mode sends every extracted record to the AI in a single request — most accurate, but the request size grows with the number of periods and could approach a smaller model's limits. It also means a single failed request loses the entire cross-period analysis for that run, not just one period pair (it fails gracefully to an empty result, but you lose all the signal at once).
- **"Sliding window" strategy trades cost for more individual AI calls.** This mode makes one AI request per adjacent pair of periods — for 8 periods, that's 7 separate requests instead of one. On a rate-limited AI key, or when many portfolio companies are scheduled to run around the same time, this increases both how long it takes and the chance of hitting provider rate limits. The upside is that failures are more contained — only one period pair is affected at a time — but there are more of them to track down if something does go wrong.
- **Reusing last time's questions can look like "nothing happened" on a re-run.** If the comparison results come out identical to the previous run, the briefing step reuses the previous question set rather than generating new ones, at no extra cost. This is intentional for portfolio companies that haven't changed much, but if you added a new presentation and expected fresh questions, check whether that new period actually introduced anything new — if extraction didn't find any meaningful change, the questions legitimately stay the same.
- **A smaller AI model risks silent truncation.** Extraction sends the full document text with nothing shortened, so switching to a model with a smaller context window than the recommended ~1M tokens risks the provider quietly cutting off long documents, incomplete extraction, or outright failures on large presentations like dense board decks or financial appendices. This fails quietly — per-document issues are logged as "skipped" rather than raised as an error that stops the run.
- **Turning off scoring or question generation removes whole sections with little visible warning.** These two switches aren't on the standard settings screen, so if an administrator turns one off directly, the Score section simply disappears from the report, with only a log entry and a low-severity note — not an obvious warning in the UI.
- **There's no email option for fund managers.** Even with the schedule's failure notifications turned on, those only alert administrators and CapHive support — there's no "send the briefing straight to the GP's inbox" feature. Anyone waiting on a result needs to check the UI or the chat panel directly.
- **Extraction quality for PowerPoint and Word files depends on what's available in the runtime environment.** The agent tries a few different extraction methods in sequence, and the weakest fallback can miss speaker notes and table cells entirely — which can quietly drop context (for example, a key metric mentioned only in a speaker note might never reach the AI).

## Frequently Asked Questions

### Navigation and getting there

**Where do I find the Investor Presentation Analyst in CapHive?**
Open the Company menu (house icon, top right) → [**Agents**](/support_agents) and click the **Investor Presentation Analyst** card in the Portfolio category. Its page has **General**, **Schedule**, **Execution History** and **Presentation Reports** tabs. If **Agents** is locked, no agent is enabled for your entity; contact CapHive support.

**How do I run the analyst on one portfolio company?**
Open the company's stakeholder page ([**Stakeholders → View Stakeholders**](/investors) → open the record), click **Misc → Run Presentation Analyst**, read the description and click **Run Agent**. The item only appears for stakeholders of category *Portfolio Company*. See [Accessing and Running the Agent](#4-accessing-and-running-the-agent).

**Where is the Presentation Analyst Dashboard?**
Go to [**Stakeholders → View Stakeholders**](/investors), open **Actions** and choose [**Presentation Analyst Dashboard**](/presentation_analyst_dashboard). It appears once the agent exists for your entity and groups companies into **High Accountability**, **Reliable**, **Watch** and **At Risk** tiers by Management Accountability Score.

**How do I run the analyst on several companies at once?**
On the Presentation Analyst Dashboard click **Run Analysis**, choose **Run on**: all portfolio companies, only companies never analysed, specific companies, by sector or by tag, then click **Start Analysis**. **Run Now** on the agent's **General** tab analyses every portfolio company in your entity.

**Where is the Investor Presentation Analysis widget?**
It is the **Presentation Analyst** dashboard widget for a portfolio company's dashboard (stakeholder page → **Misc → Dashboard**). Add it from Company menu (house icon, top right) → [**Dashboard Widgets**](/dashboard_widgets); it lists the company's recent runs with periods, score, grade, question count, status and run time.

**Where is the chat panel for this agent?**
On the agent's own page, as a chat bubble, because **Setup All Agents** turns on **Enable Chat Assistant** for it. It is not shown on the stakeholder page or the widget.

**The Run Presentation Analyst item is greyed out with a lock. Why?**
The `presentation_analyst_agent` flag is off for your entity, so the item is locked with the tooltip "Presentation Analyst Agent is disabled. Contact support to enable it", and **Run Now** is disabled with a red **Disabled** badge on the agent page. Only CapHive support can switch the flag on.

### Creating, updating and managing the agent

**How do I set the agent up?**
Ask CapHive support to enable the `presentation_analyst_agent` flag, add a key for a large-context provider (Gemini by default) under [**Agents → LLM Keys**](/support_agents/llm_keys), then click **Setup All Agents → Run Setup** on [**Support Agents**](/support_agents). Setup creates the agent with default settings and a monthly schedule that is switched off. See [Enabling the Agent](#3-enabling-the-agent).

**How do I get presentations in front of the agent?**
Attach each presentation to the portfolio company's KPI report for that period, with a document name containing one of the **Presentation document names** keywords (for example "Q2 Board Deck"). Only KPI reports with the configured **KPI report tag** (Actual by default) are scanned, and only the first name-matching document per report is used; if that one is not a PDF, TXT, Markdown, Excel, PowerPoint or Word file, the period is skipped.

**How do I change the agent's settings?**
On the agent's **General** tab click **Edit** and change **Presentation document names**, **Max periods to analyze**, **KPI report tag**, **Comparison strategy** or **AI Model**, then save. Only a Company Admin can edit; changes apply from the next run. See [Inputs](#2-inputs).

**How do I change the AI model the agent uses?**
Set the **AI Model** field on the agent's **Edit** page; new agents get `gemini-3.7-flash`. The separate **LLM model** configuration field is stored but not read by the agent, so changing only that field has no effect.

**How do I schedule the analyst before board meetings?**
Open the **Schedule** tab, tick **Enable scheduled runs for this agent**, choose **Frequency** (daily, weekly, monthly, bimonthly, quarterly or half-yearly), **Run On**, **Run At** and **Timezone**, set **Notify When** and **Notification Recipients**, and click **Save Schedule**. Setup prepares a monthly run on the 1st at 06:00 Asia/Kolkata but leaves it disabled. See [Scheduling](#5-scheduling).

**How do I turn off the score or the pre-board questions?**
The `enable_scoring` and `enable_questions` switches are not on the **Edit** page, so ask CapHive support to set them. Both default to on; when off, the Score or Briefing section is left empty and the report records that the step was disabled.

**How do I stop or delete the agent?**
Untick **Enable scheduled runs for this agent** on the **Schedule** tab to stop automatic runs. **Delete** on the **General** tab only works for an agent that has never run; once reports exist, pause it instead.

**Who can run and configure the agent?**
Running from any screen and editing, scheduling or deleting the agent need the **company_admin** role. The widget's run buttons are also hidden from users without edit rights on the company, and other employees can view the dashboard and reports.

### Why use the Investor Presentation Analyst

**Why should I use the Investor Presentation Analyst?**
Management decks change quarter to quarter, and promises, risks and initiatives quietly disappear between them. The agent reads every period's deck, lines them up and flags missed commitments, dropped risks, drifting objectives, abandoned initiatives and metric anomalies, so a board member does not have to re-read eight decks before a meeting.

**What does it let me do that I could not do otherwise?**
Walk into a board meeting with 8 to 12 evidence-backed questions citing specific numbers, dates or quotes, compare management credibility across the portfolio with a 0 to 100 Management Accountability Score, and see which companies moved between runs on the dashboard.

**Who typically uses it?**
Investment professionals and board observers preparing for portfolio company board meetings, and portfolio monitoring teams reviewing management accountability across the book. The output is internal and never sent to the company or to investors.

**What happens if presentations are not attached to KPI reports?**
The agent finds nothing: the run completes, but the report is marked **Blocked** (failed) with "No presentation documents found matching: …" and no AI calls are made. Decks uploaded elsewhere on the company, such as its documents folder, are never read.

### What happens when I...

**What happens when I run the analyst on one company?**
A live progress panel shows Initialize, Collect Presentations, Extract Intelligence, Cross-Period Analysis, Generate Briefing, Score and Save. A new report is saved for the company and marked latest, appearing on the **Presentation Reports** tab, the dashboard and the widget, and you get an in-app alert when the job completes. No email is sent.

**What happens when I click Run Now or Start Analysis?**
One background job analyses each selected portfolio company in turn with a live batch progress panel, saving a separate report per company. When it ends you get an in-app summary of processed and failed companies. Each company costs several AI calls (one per period, plus comparison and questions), so large batches take time.

**What happens when a scheduled run fires?**
Every portfolio company in your entity is analysed, the run is logged in **Execution History** as scheduled, and only the **Notification Recipients** get an email and in-app notification for the outcomes ticked under **Notify When**. CapHive support is also alerted on errors; the briefing itself is never emailed.

**What happens to earlier reports when I re-run?**
They are kept: each run adds a new report and the newest is marked latest, so the dashboard can show score movement. If the cross-period flags are unchanged since the last run, the previous question set is reused rather than regenerated.

**Does the agent change any company data?**
No. It only reads KPI reports and their documents and writes its own reports; KPIs, documents and the company record are untouched, and nothing is sent to the company.

**What happens if only one period is found?**
Extraction still runs for that period, but cross-period analysis needs at least two periods, so the comparison flags are empty and the score has little to work with. Attach earlier decks to earlier KPI reports and re-run.

### Troubleshooting and edge cases

**The agent ran and reported "no presentation documents found." What should I check first?**
Confirm the deck is attached to a KPI report for that company, that the report's tag matches **KPI report tag** (default Actual), that it is within the last **Max periods to analyze** reports, and that the document's name in CapHive (not the uploaded file name) contains one of the **Presentation document names** keywords, ignoring case.

**I added a new quarter's presentation but the pre-board questions look identical to last time. Is that a bug?**
Probably not. Questions are only regenerated when the cross-period flags change; if the new period introduced no new commitment misses, dropped risks, drift, abandoned initiatives or anomalies, the previous question set is reused at no extra cost.

**Should I switch the AI model to save cost?**
Only to another large-context model. Presentations are sent in full with no truncation, so a model with much less than about 500K tokens of context can cut off or reject long decks, and "All periods" comparison sends every period in one request.

**When should I use "Sliding window" instead of "All periods"?**
When a company has many periods and you want to limit request size. It makes one comparison per adjacent pair of periods, which is less holistic and makes more AI calls per run (more rate-limit risk), but a single failure only loses one pair.

**Where do fund managers see the output if there's no email?**
On the company's **Investor Presentation Analysis** widget, the Presentation Analyst Dashboard, the agent's **Presentation Reports** tab, or by asking the chat panel on the agent page. Schedule notifications only report run outcomes, not the briefing.

**The chat panel answers about a different company. Why?**
The chat uses the most recent Presentation Analyst report for your entity, whichever company it was for, not a company you choose. Run the agent on the company you want to discuss immediately before chatting.

**The batch summary says a company succeeded but its report is Blocked. Why?**
A company with no presentations still completes the pipeline and saves a blocked report, so it counts as processed in the summary. Check the **Status** column on the **Presentation Reports** tab or the dashboard for blocked companies.

## Related Guides

- [Support Agents](../support_agents_user_guide) — shared setup, LLM keys, scheduling and run history for every agent.
- [LLM Configuration](../llm_configuration_guide) — adding the Gemini or other large-context provider key.
- [KPI Upload](../kpi_upload_user_guide) — the KPI reports that presentations must be attached to.
- [Investors (Stakeholders)](../investors_user_guide) — the portfolio company page with the **Misc** menu.
- [Dashboard Widgets](../dashboard_widgets_user_guide) — adding the Presentation Analyst widget to a company dashboard.
- [Portfolio Scoring Agent](portfolio_scoring_agent_user_guide) — the investment score shown alongside accountability.
- [Portfolio Company Agent](portfolio_company_agent_user_guide) — KPI and document compliance checks for the same companies.
