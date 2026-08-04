# Note Summarizer Agent — User Guide

The Note Summarizer Agent generates an AI-powered summary of an investor's notes over the past month or quarter. It runs across every investor in your entity, can optionally auto-tag untagged notes first, and writes the summary back as a regular Note on the investor record so it shows up right alongside everything else in that investor's notes feed.

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

A Company Admin turns this agent on at **Admin → Edit Entity → Support Agents section**. While it's off, the **Run Now** button and the "Summarize Notes" trigger on an investor's page are disabled.

This agent requires an AI provider key, configured at **AI → Support Agents → LLM Keys** — both the auto-tagging step and the summary step call the AI (unless skipped because there are no qualifying notes).

Only **Company Admin** users can run **Setup All Agents** and edit this agent's configuration fields. The "Summarize Notes" trigger on an investor's page follows that record's normal edit permissions.

## 4. Accessing and Running the Agent

**From the agent's own page:** **AI → Support Agents → Note Summarizer → Run Now**. Without targeting a specific investor, this processes every investor in your entity, one after another, with no per-investor progress view; you'll get a single summary notification once it's done.

**From an Investor's page:** **Misc → Summarize Notes**. Runs the agent for just that investor, with a live progress panel showing each step (Auto-Tag Notes → Collect Notes → Generate Summary → Save Note → Save Report).

**Batch run:** Selecting multiple investors and running the agent on that selection queues one job covering all of them, with a single summary notification — no per-investor progress view in that mode.

**Running on one investor vs. everything:** Unlike the agents that only deal with portfolio companies, this one runs against **every** investor type in your entity — LPs, portfolio companies, prospects, everything — not just portfolio companies. During a batch run, if one investor's run hits a problem, it's recorded in the batch's error list without stopping the rest.

## 5. Scheduling

This is the one agent that **does** come with a default schedule already turned on from **Setup All Agents**: monthly, on the 1st, at 06:00 in the Asia/Kolkata time zone, with notifications on for failures and partial successes (but not for full successes). You can change the frequency, time, time zone, and notification preferences from the agent's **Schedule** tab. Scheduled runs process every investor in your entity in one pass and skip the usual summary notification (since there's no one actively waiting on the result) — instead, whatever failure or partial-success notifications you've configured on the schedule are sent.

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

**Q: I ran the agent today but it didn't summarize this month's/quarter's notes. Why?**
A: The agent always summarizes the most recently **completed** period, never the one currently in progress. Wait until the period ends, or check the report's period start/end dates to confirm exactly which window was used.

**Q: An investor shows "skipped" with no summary. Is that an error?**
A: No — that's the expected, zero-cost outcome when an investor has no qualifying notes in the period. No AI call is made, and no Note is written for that period.

**Q: I added a manual note with "summary" somewhere in its tags, and now it's missing from collection. What happened?**
A: Any note tagged as a summary is automatically excluded from collection — this exists to stop the agent from re-summarizing its own prior output, but it also catches manually tagged notes that happen to use the same tag.

**Q: The auto-tagged note has the wrong tag, or didn't get tagged at all. Why?**
A: Auto-tagging is a single best-effort AI pass across all untagged notes in the period. If the AI's response can't be parsed, or it references a note that wasn't actually in that batch, that particular tag assignment is dropped silently rather than retried — the rest of the period's notes are still tagged normally.

**Q: Does editing the summary in the UI re-run the agent?**
A: No. Double-clicking the summary text lets you overwrite the saved text directly on the report (and flags it as manually edited) — it doesn't call the AI again or regenerate anything.

**Q: Why does the default schedule run at 06:00 Asia/Kolkata specifically?**
A: That's simply the default that comes pre-configured from Setup All Agents — frequency, time, and time zone are all editable on the agent's Schedule tab if you need a different cadence for your fund.
