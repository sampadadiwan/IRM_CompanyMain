# Note Summarizer Agent — User Guide

The Note Summarizer Agent generates an AI-powered summary of an investor's notes over the past month or quarter. It runs across every investor in your entity, can optionally auto-tag untagged notes first, and writes the summary back as a regular Note on the investor record so it shows up right alongside everything else in that investor's notes feed.

> **Where to find it:** Company menu (house icon, top right) → [**Agents**](/support_agents) → **Note Summarizer** card → **Run Now** on the **General** tab; for one stakeholder, open the stakeholder page → **View Notes** → **Summarise Notes**. Needs the Company Admin role, the `note_summarization_agent` entity flag and an LLM key.

## Table of Contents

1. [What This Agent Does](#1-what-this-agent-does)
2. [Inputs](#2-inputs)
3. [Enabling the Agent](#3-enabling-the-agent)
4. [Accessing and Running the Agent](#4-accessing-and-running-the-agent)
5. [Scheduling](#5-scheduling)
6. [Where to Find the Output](#6-where-to-find-the-output)
7. [Understanding the Report](#7-understanding-the-report)
8. [Where It Can Fail](#8-where-it-can-fail)
9. [FAQ](#faq)
10. [Related Guides](#related-guides)

---

## 1. What This Agent Does

For each investor, the agent works through five steps:

1. **Auto-tag untagged notes.** It finds any notes in the lookback period that have no tags at all, sends all of them to the AI in one batch, and tags each one accordingly. If you've configured a list of allowed tags, the AI sticks to that list; otherwise it uses its own judgment. This step is skipped — not treated as a failure — if auto-tagging is turned off, or if there simply aren't any untagged notes in the period. Any failures here are treated gently: they show up as an informational note and never block the rest of the run.
2. **Collect the notes to summarize.** The agent gathers all notes for the investor within the period, leaving out anything already tagged as a previous summary (so it never summarizes its own prior output), and applying your tag filter if you've set one.
3. **Generate the summary.** The collected notes are sent to the AI in one request, asking for three sections: **Key Themes**, **Action Items** (or "None identified" if there aren't any), and **Relationship Status** (Active / In Discussion / Dormant, with a one-sentence explanation). This step is skipped — with no AI call at all — if there are no notes to summarize.
4. **Save the summary as a note.** The summary is written back as a regular Note on the investor, tagged to show it's a summary for that month or quarter, and dated to the last day of the period. Running the agent again for the same period overwrites that same note rather than creating a duplicate.
5. **Save the report.** A report is saved with the summary text, note count, and the exact period covered — this is what you'll see on the Note Summaries tab.

Investors with no qualifying notes in the period still get a report (with nothing flagged as blocking), but the AI is never called for them — so there's no cost incurred for investors with nothing to summarize.

## 2. Inputs

| Field | Type | Default | What it controls |
|---|---|---|---|
| Summary period | Select | Quarter | "Month" summarizes the previous full calendar month; "Quarter" summarizes the previous full calendar quarter. Either way, the agent always looks at the most recently **completed** period relative to when it's run — never the period that's still in progress. |
| Tag filter | Text | (blank) | A comma-separated list of tags to limit which notes get included, e.g. `call,meeting`. A note is included if it has at least one of the listed tags. Leave blank to include every note in the period except previous summaries. |
| Auto-tag untagged notes | Select | Yes | When set to Yes, any untagged notes in the period are sent to the AI for tagging before the summary step runs. These tags are saved permanently onto the notes themselves, so this affects your data beyond just this agent's run. |
| Available tags | Text | `call,meeting,kpi,board-meeting,fundraising,risk,hiring,operations` | The list of tags the AI must choose from when auto-tagging. Leave blank to let the AI pick any concise, lowercase tag it thinks fits. |

**Data the agent reads (not configuration, just records it pulls in):** the investor's notes within your entity, filtered to those dated inside the computed period, including the full text of each note.

### Setup checklist and warnings

The agent's **General** tab shows a yellow warning banner for two setup traps:

- **"Auto-tag untagged notes" never set** — an unset toggle counts as off, not Yes, so untagged notes are quietly left untagged. Set it explicitly to Yes or No.
- **A tag filter set while auto-tagging is off** — untagged notes never gain a tag, so they can never match your filter. Depending on how your team tags notes, summaries may quietly cover nothing at all. Either turn auto-tagging on or clear the filter.

## 3. Enabling the Agent

A CapHive administrator turns this agent on with the `note_summarization_agent` support-agent flag on your entity. While it's off, the **Run Now** button and the **Summarise Notes** button on a stakeholder's notes list are disabled.

This agent requires an AI provider key, configured at Company menu (house icon, top right) → **Agents** → [**LLM Keys**](/support_agents/llm_keys) — both the auto-tagging step and the summary step call the AI (unless skipped because there are no qualifying notes).

Only **Company Admin** users can run **Setup All Agents**, edit this agent's configuration fields and run it. The **Summarise Notes** button is shown to everyone who can see the notes, but the run itself is rejected for non-admins.

## 4. Accessing and Running the Agent

**From the agent's own page:** Company menu (house icon, top right) → **Agents** → **Note Summarizer** → **Run Now**. Without targeting a specific investor, this processes every investor in your entity, one after another, with a batch progress panel that counts investors as they are processed; you'll get a single summary notification once it's done.

**From an Investor's page:** click **View Notes** to open that record's notes list, then **Summarise Notes** → **Run Summariser**. Runs the agent for just that investor, with a live progress panel showing each step (Auto-Tag Notes → Collect Notes → Generate Summary → Save Note → Save Report).

**Running on one investor vs. everything:** Unlike the agents that only deal with portfolio companies, this one runs against **every** investor type in your entity — LPs, portfolio companies, prospects, everything — not just portfolio companies. During a batch run, if one investor's run hits a problem, it's recorded in the batch's error list without stopping the rest.

## 5. Scheduling

This agent comes with a default schedule already turned on from **Setup All Agents**: monthly, on the 1st, at 06:00 in the Asia/Kolkata time zone, with notifications on for failures and partial successes (but not for full successes). You can change the frequency, time, time zone, and notification preferences from the agent's **Schedule** tab. Scheduled runs process every investor in your entity in one pass and skip the usual summary notification (since there's no one actively waiting on the result) — instead, whatever failure or partial-success notifications you've configured on the schedule are sent.

## 6. Where to Find the Output

- **Note Summaries tab** (only on this agent's own page) — every summary report across all investors, showing investor name, period, note count, status, and run date; expand a row to read the full summary inline.
- **Execution History tab** — every run, with status and how long it took.
- **The investor's own Notes feed** — the summary is also written as a regular Note, so it shows up alongside every other note on that investor's record, not just inside this agent's reporting screens.
- Each report is tied to the investor it covers.

## 7. Understanding the Report

A report includes:

- **Summary text** — the full AI-generated summary (Key Themes / Action Items / Relationship Status), shown formatted in both the Note Summaries tab and the saved Note.
- **Note count** — how many notes were collected for the period.
- **Period label and boundaries** — the exact lookback window that was used.
- **Status notes** — for this agent, these are almost always informational rather than concerning, since most "nothing happened" situations (no notes found, auto-tagging turned off, an unreadable AI tagging response) are treated as normal, expected outcomes rather than problems. The one case that **is** treated as blocking is an AI error during the actual summary-generation step.
- The report's overall status is "ready" unless summary generation itself failed, in which case it's "blocked."

Summaries can be **manually edited** in place — double-click the summary text in the detail view to overwrite it. Edited summaries get a small "Edited" badge.

A report with no summary text and an informational "No notes found in period" note is the **expected, zero-cost outcome** for an investor with nothing to summarize that period. It's not an error — it just means no Note gets written for that investor that period.

## 8. Where It Can Fail

- **The agent always looks at the previous *complete* period, never the one still in progress.** For "Month," that's the entire previous calendar month; for "Quarter," it's the entire previous calendar quarter. Running the agent partway through the current month or quarter will not pick up any notes from the period that's still happening — this is intentional, but it can look like the agent "missed" recent notes if you expected it to include the period you're currently in.
- **Auto-tagging processes every untagged note in the period in one single AI request.** If the AI's response can't be read properly, or it tries to tag a note that wasn't actually part of the batch sent to it, those specific tag assignments are silently dropped — the step still reports as successful, just with fewer notes tagged than expected, rather than as a failure.
- **Notes tagged as a previous summary are always excluded going forward.** This is by design, so the agent never re-summarizes its own past output — but it also means a note you create and tag manually with that same tag will be silently excluded from all future summarization too, not just agent-generated notes.
- **The tag filter matches any note containing any of the listed tags as a substring, not as an exact tag.** For example, filtering on `kpi` will also match a note tagged `kpi-review`, because the match isn't restricted to whole tag names. Use precise, specific tag names to avoid unexpectedly pulling in notes you didn't mean to include.
- **The "don't duplicate the summary note" check is based purely on the period's exact end date, not on the agent's run history.** If you manually create a note tagged as a summary, dated exactly on what would be that period's last day, the agent's next run for that period will find your manually created note and **overwrite it** instead of creating a separate note.
- **Very large volumes of notes get cut off, not split into chunks.** The text sent to the AI is capped at 50,000 characters. If a period's notes are larger than that, the agent simply truncates rather than summarizing in batches — anything past that cutoff is invisible to the AI, with no visible warning in the report (only a technical log entry your team could check).
- **The very first user created in your entity is recorded as the author of new summary notes.** If that person later leaves or is deactivated, the listed author on older summary notes can look inconsistent — though this doesn't stop future runs from working.
- **Most failure paths are designed to look like success.** Both auto-tagging and saving the summary note are built to fail softly — they log an informational note rather than a blocking one if something goes wrong internally. Only a failure during the actual summary-generation step produces a blocking issue and a "blocked" status. So if a summary note silently failed to save for some other reason, you'd only notice by reading the report's notes carefully — the overall status wouldn't tell you.

## FAQ

**Where do I find the Note Summarizer Agent in CapHive?**
Click the house icon at the top right (tooltip "Company menu") to open the **Company menu**, then choose [**Agents**](/support_agents) and click the **Note Summarizer** card (it sits under the **Ops** category). There is no left-sidebar entry for agents. If the **Agents** menu item is greyed out with a lock icon, no agents are enabled for your entity yet; contact CapHive support.

**How do I enable the Note Summarizer Agent for my entity?**
Two things are needed. First, a CapHive administrator turns on the `note_summarization_agent` flag under the entity's **Support Agents** flags in the Admin panel. Second, a Company Admin opens [**Agents**](/support_agents) and clicks **Setup All Agents → Run Setup**, which creates the agent, its fields, and its default monthly schedule. The **General** tab then shows an **Enabled** badge and an active **Run Now** button. See [Enabling the Agent](#3-enabling-the-agent).

**How do I configure the agent (period, tag filter, auto-tagging, tags, AI model)?**
Open the agent card, and on the **General** tab click **Edit**. Set **Summary period** (Month or Quarter), **Tag filter**, **Auto-tag untagged notes** (Yes/No), **Available tags** and the **AI Model** override, then save. Only a Company Admin can edit. See [Inputs](#2-inputs).

**How do I run the agent for every stakeholder (investor) at once?**
On the agent's **General** tab click **Run Now** and confirm. This queues one background job that walks every Investor record in your entity, and a batch progress panel on the same tab counts investors as they are processed. See [Accessing and Running the Agent](#4-accessing-and-running-the-agent).

**How do I run the agent for a single stakeholder (investor)?**
Open the stakeholder page ([**Stakeholders → View Stakeholders**](/investors) → open the record) and click **View Notes**, which opens that record's notes list. Click **Summarise Notes**, read the description in the modal, then click **Run Summariser**. A live progress panel shows Auto-Tag Notes → Collect Notes → Generate Summary → Save Note → Save Report. The same **Summarise Notes** button appears on any notes list opened for one owner, such as a portfolio company's notes.

**Who is allowed to run the agent?**
Only users with the **Company Admin** role: the run action is authorised by the same policy as editing the agent. The **Summarise Notes** button on a notes list is shown to everyone who can see the notes, but the run itself is rejected for non-admins. Editing a saved summary text on the **Note Summaries** tab instead needs update permission on that stakeholder record.

**How do I schedule the agent or change its default schedule?**
Open the agent and click the **Schedule** tab. Tick **Enable scheduled runs for this agent**, choose **Frequency** (Daily, Weekly, Monthly, Bimonthly, Quarterly, Half-yearly), **Run On**, **Run At** and **Timezone**, optionally set **Retry on Failure**, tick the **Notify When** boxes and pick **Notification Recipients**, then click **Save Schedule**. Setup creates it as monthly on the 1st at 06:00 Asia/Kolkata. See [Scheduling](#5-scheduling).

**How do I stop the agent without deleting it?**
Untick **Enable scheduled runs for this agent** on the **Schedule** tab and save; manual runs still work. To block manual runs too, ask your administrator to switch off the entity flag, which greys out **Run Now** and **Summarise Notes**.

**How do I delete the agent, and what does that remove?**
On the **General** tab click **Delete** (Company Admin only). It only succeeds for an agent that has never run, because its reports and execution logs block the delete; pause the schedule instead. Summary Notes already written to stakeholders are never deleted.

**Where do I see the summaries and run history?**
Three places: the **Note Summaries** tab on the agent page (one row per stakeholder, expandable to the full text), the **Execution History** tab (each run with status and duration), and the stakeholder's own notes list (**View Notes** on the stakeholder page), where the summary appears as a normal note tagged `summary,quarter` or `summary,month`. See [Where to Find the Output](#6-where-to-find-the-output).

**Can I show summaries on a dashboard?**
Yes. A **Note Summaries** widget exists for both the Stakeholder (Investor) dashboard and the Portfolio Company dashboard. Add it from [**Company menu → Dashboard Widgets**](/dashboard_widgets); it embeds the agent's note summaries for the record being viewed and shows a notice if the agent is not configured.

**Why should I use the Note Summarizer Agent?**
Relationship notes pile up across calls, meetings and emails, and nobody re-reads them before the next touchpoint. The agent turns a period's notes into a short Key Themes / Action Items / Relationship Status brief per stakeholder, so the whole team sees the state of every relationship without reading the raw feed, and untagged notes get a consistent tag vocabulary for filtering.

**What does the agent let me do that I could not do otherwise?**
It gives every stakeholder (LPs, portfolio companies, prospects) a comparable monthly or quarterly relationship status, flags action items that were mentioned in notes but never tracked, and back-fills tags on notes that were saved without any. Because the output is a regular Note, it flows into the same notes list, search and dashboard widgets as everything else.

**Who typically uses it?**
Investor-relations and fund-management teams that log stakeholder interactions as Notes and want a periodic digest, and Company Admins who set the tag vocabulary. Investors never see it; nothing is sent outside the entity.

**What happens if I do not set it up?**
Nothing breaks: notes stay as they are, untagged notes stay untagged, and the **Note Summaries** widget shows "No Note Summarizer agent configured". You simply have no periodic summary and no relationship status view.

**What happens when I click Run Now on the agent page?**
A job is queued and, for each Investor in the entity, the agent may tag untagged notes in the period (if **Auto-tag untagged notes** is Yes), calls the AI on the collected notes, writes or overwrites one summary Note dated the last day of the period, and saves one SupportAgentReport per stakeholder. When the batch finishes you get an in-app toast with counts of processed and failed stakeholders; no email is sent, no task is created and no investor is contacted.

**What happens when I click Run Summariser for one stakeholder?**
The same five steps run for just that record with a live progress panel. The report for that stakeholder is created or replaced (marked as triggered manually by you) and appears on the **Note Summaries** tab, and the summary Note appears in that stakeholder's notes list. If a step raises an error, the report is marked failed and you get an in-app error toast so it can be re-run.

**What happens when the scheduled run fires?**
Every stakeholder is processed in one pass with no toast. The run is written to **Execution History**, and the **Notification Recipients** on the **Schedule** tab receive an in-app notification and email according to the **Notify When** boxes (by default failures and partial successes, not successes). CapHive's internal support team is also alerted on failure or partial success.

**What data does the agent change?**
Two kinds of records: Notes (it sets `tags` on untagged notes when auto-tagging is on, and creates or overwrites the summary Note) and SupportAgentReports. It does not touch stakeholder fields, commitments, tasks or documents, and it never emails anyone.

**What happens if I run the agent twice for the same period?**
The summary Note for that period is overwritten rather than duplicated (matched by the period's last day plus the `summary` tag), and the stakeholder's report is replaced, so the **Note Summaries** tab always shows the latest run. Tags already written by auto-tagging are left as they are.

**Can I undo a run?**
Partly. The summary Note can be deleted from the stakeholder's notes list like any other note, and a manually edited summary can be re-edited. Tags written to previously untagged notes are permanent until you edit those notes by hand, and reports are not deletable from the UI; set **Auto-tag untagged notes** to No before running if you do not want notes changed.

**What happens if no AI key is configured?**
The summary step fails with a blocking issue and the stakeholder's report shows **blocked**; the notes are still collected and the run does not crash. Add a key under [**Agents → LLM Keys**](/support_agents/llm_keys) or set the agent's **AI Model** to a provider that has a key, then re-run. See [Enabling the Agent](#3-enabling-the-agent).

**I ran the agent today but it didn't summarize this month's/quarter's notes. Why?**
The agent always summarizes the most recently **completed** period, never the one currently in progress. Wait until the period ends, or check the report's period start/end dates to confirm exactly which window was used.

**An investor shows "skipped" with no summary. Is that an error?**
No, that is the expected, zero-cost outcome when a stakeholder has no qualifying notes in the period. No AI call is made, and no Note is written for that period.

**I added a manual note with "summary" somewhere in its tags, and now it's missing from collection. What happened?**
Any note tagged as a summary is automatically excluded from collection. This exists to stop the agent from re-summarizing its own prior output, but it also catches manually tagged notes that happen to use the same tag.

**The auto-tagged note has the wrong tag, or didn't get tagged at all. Why?**
Auto-tagging is a single best-effort AI pass across all untagged notes in the period. If the AI's response can't be parsed, or it references a note that wasn't actually in that batch, that particular tag assignment is dropped silently rather than retried; the rest of the period's notes are still tagged normally.

**Does editing the summary in the UI re-run the agent?**
No. Double-clicking the summary text on the **Note Summaries** tab overwrites the saved text on the report and flags it as manually edited; it does not call the AI again, and it does not change the summary Note already written to the stakeholder's notes list.

**Why does the default schedule run at 06:00 Asia/Kolkata specifically?**
That is simply the default that comes pre-configured from **Setup All Agents**. Frequency, time and time zone are all editable on the agent's **Schedule** tab if you need a different cadence.

**The Run Now or Summarise Notes button is greyed out. What should I do?**
The `note_summarization_agent` entity flag is off, so both buttons render disabled with a lock or tooltip. Ask your CapHive administrator to enable the flag for your entity; no agent settings need to change afterwards.

**I set a tag filter and now summaries cover nothing. Why?**
If **Auto-tag untagged notes** is No, notes saved without tags can never match the filter, so the collected set may be empty. The **General** tab shows a yellow warning banner for exactly this case; either switch auto-tagging on or clear **Tag filter**. See [Setup checklist and warnings](#setup-checklist-and-warnings).

**Which stakeholders does a full run cover?**
Every Investor record in your entity, whatever its type: LPs, portfolio companies and prospects alike. There is no per-type filter; use the single-stakeholder **Summarise Notes** button when you only want one.

## Related Guides

- [Support Agents](../support_agents_user_guide) — shared setup, LLM keys, scheduling and report concepts for every agent.
- [LLM Configuration](../llm_configuration_guide) — where API keys and default models come from.
- [LP CRM](../lp_crm_user_guide) — the Notes feature whose entries this agent tags and summarises.
- [Investors (Stakeholders)](../investors_user_guide) — the stakeholder page where **View Notes** and the summary appear.
- [Dashboard Widgets](../dashboard_widgets_user_guide) — adding the Note Summaries widget to a dashboard.
- [Portfolio Company Agent](portfolio_company_agent_user_guide) — the other per-record agent commonly run from a stakeholder page.
