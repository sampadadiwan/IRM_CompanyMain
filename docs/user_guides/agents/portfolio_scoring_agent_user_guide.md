# Portfolio Scoring Agent — User Guide

The Portfolio Scoring Agent scores each portfolio company using a sector-specific scoring guide and AI. It gathers the company's documents, KPI data, valuations, and investment history, sends all of that to your configured AI model together with the matching scoring guide, and stores a structured 0–100 investment score on the company.

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

For each portfolio company, the agent works through four steps:

1. **Find the right scoring guide.** It looks at the company's sector and finds the matching scoring guide among the skill files you've uploaded for this agent. If the company has no sector set, or there's no matching guide (and no general fallback guide either), or the matched file can't be read as text, this step records an error — but the run continues anyway so you still get a report explaining what went wrong, rather than nothing at all.
2. **Gather the company's data.** The agent collects the company's KPI reports (limited to those tagged "Actual," filtered to your chosen frequency), its investment history, valuations (most recent first), its configuration fields, and the text of any documents attached to recent KPI reports. This step is skipped entirely if step 1 hit an error.
3. **Generate the score.** The agent combines the scoring guide with everything gathered in step 2 into a single request to your configured AI model, and expects back a structured score with an overall score, a grade, a summary, and a breakdown by dimension (plus strengths, risks, recommendations, and a note on how much data was available).
4. **Save the score.** Every run creates a **new** score report rather than overwriting the last one, so your scoring history builds up over time. This happens whether the run succeeded or recorded an error — either way, you get a report.

Companies with no sector set are left out of fund-wide runs entirely before the agent even starts — a batch run only looks at portfolio companies that have a sector assigned, so a company with no sector quietly never gets a report from a fund-wide run.

## 2. Inputs

| Field | Type | Default | What it controls |
|---|---|---|---|
| Generic Portfolio Skill | File upload | — | The fallback scoring guide used when no sector-specific guide matches the company's sector. Upload a `.md` or `.txt` file. **The name you give the upload must exactly match this field's label** — "Generic Portfolio Skill" — for the agent to find it. The agent looks up the uploaded file by the name you typed when uploading, not by the original filename from your computer. |
| Beauty & Skincare Skill | File upload | — | A sector-specific scoring guide, used when a company's sector is set to "Beauty & Skincare." Matched through the field's internal sector tag. Same `.md`/`.txt` requirement and same upload-name-matching rule as above applies. You can add similar fields for other sectors the same way. |
| Min points per section | Number | **5** (this is what a fresh setup actually gives you) | The minimum number of bullet points the AI must produce for each section of the score — both within each scoring dimension (positives/concerns) and in the overall strengths, risks, and recommendations lists. The system enforces a floor of 3 even if you set it lower, but a freshly set-up agent starts at 5, not 3. |
| KPI frequency filter | Select | All | Restricts which KPI reporting periods are sent to the AI as context (All, Month, Quarter, Half Year, Year, YTD). "All" applies no filter. |
| Documents from last N KPI reports | Number | **3** (this is what a fresh setup actually gives you) | How many of the most recent "Actual"-tagged KPI report periods the agent pulls document attachments from to include as context. If this field were ever left blank or zero, the system would fall back to just 1 — but a freshly set-up agent is seeded with 3. |
| Document name filter | Text | (blank) | A comma-separated, case-insensitive list of document names to include from the selected reports. Leave blank to include every document from those reports. |

> **A note on defaults you may have seen elsewhere:** an earlier version of this guide listed the defaults for "Min points per section" and "Documents from last N KPI reports" as 3 and 1. Those numbers are only the system's last-resort fallback if a field is ever missing or blank — they are not what you'll actually see. When the **Setup All Agents** process provisions this agent, it writes in 5 and 3 respectively, and that's what a freshly configured agent will use. Trust the values in this guide.

**Data the agent reads (not configuration, just records it pulls in):** the company's "Actual"-tagged KPI reports and their attached documents (PDF, Excel, PowerPoint, Word, plain text, Markdown, and CSV files are accepted for upload, though Word documents are accepted by the upload screen but currently have no text-reading support — see below), valuations, investment history, and the company's own configuration field values.

### Setup checklist and warnings

The agent's **General** tab shows a yellow warning banner whenever the scoring-guide setup is broken, before you run anything. For this agent the banner flags:

- **A scoring-guide field that is missing entirely** — re-run **Setup All Agents** to restore it.
- **A scoring-guide field that has lost its sector tag** — the internal tag that tells the agent which sector the file scores. Without it the agent can never match the file, even though the upload looks fine on the edit page. Re-running **Setup All Agents** repairs the tag automatically.
- **A scoring-guide field with no file uploaded** (including the General fallback) — upload a `.md` or `.txt` file named exactly after the field's label.

If a run fails anyway, the failed report now names the specific setup problem (for example "the field is not tagged as a skill") rather than only saying no guide was found — and failed runs are listed in the Scoring Reports tab alongside successful ones, with the error shown in the Status column.

## 3. Enabling the Agent

A Company Admin turns this agent on at **Admin → Edit Entity → Support Agents section**. While it's off, the **Run Now** button and the "Run Scoring Agent" / "Re-score" buttons on a Portfolio Company's page are disabled.

This agent requires an AI provider key, configured at **AI → Support Agents → LLM Keys** — it calls the AI model on essentially every run, unless it stops early due to a scoring-guide error. It uses this agent's own model setting if one is configured, otherwise your entity's default model.

Only **Company Admin** users can run **Setup All Agents** and edit this agent's configuration fields and uploaded scoring guides. The Run/Re-score buttons on a Portfolio Company's page follow that company record's normal edit permissions.

## 4. Accessing and Running the Agent

**From the agent's own page:** **AI → Support Agents → Portfolio Scoring Agent → Run Now**, on the General tab. Without targeting a specific company, this scores every portfolio company that has a sector set, as one sequential batch with no per-company progress view; you'll get a single summary notification once it's done.

**From a single Portfolio Company's page:** **Misc → Run Scoring Agent** (or **Re-score** from the score widget, once a score already exists). This scores just that one company.

**Batch run:** Select multiple companies from the Portfolio Agent Run screen and click "Run Agent on Selected Companies" to queue one job covering all of them, with a single summary notification — there's no individual progress view per company in this mode.

**Running on one company vs. everything:** A single-company run scores just that one company. A fund-wide or batch run scores every portfolio company that has a sector assigned, one after another. If one company hits a problem, it doesn't stop the rest — successes and errors are both tallied into the final summary.

## 5. Scheduling

This agent's page does have the standard **Schedule** tab, but **Setup All Agents does not turn on a default schedule** for it — it's designed to be run on demand or from the agent's screen, not on an automatic cadence out of the box. If you want recurring scoring, you'll need to configure the Schedule tab yourself. Keep in mind that scoring your full portfolio on every scheduled run means every company scored triggers an AI call — worth factoring into cost before turning on a frequent schedule.

## 6. Where to Find the Output

- **Scoring Reports tab** (only on this agent's own page) — every scoring report, across all companies. Failed runs appear here too, marked with a red **Failed** badge and the reason shown right in the table — you don't need to expand the row to see why a score didn't generate.
- **Execution History tab** — every run, with status and how long it took.
- **Company Score widget** on the Portfolio Company page — shows the latest completed score, or the most recent failure's error message if the last run failed, or a "Run Scoring Agent" prompt if no report exists yet.
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
- **No scoring guide matches the company's sector.** The agent looks for an uploaded file tagged for the company's exact sector (case-insensitive), falling back to a file tagged "General" if one exists. If neither is found, the report fails with a message naming the sector that had no match. To support a new sector, you need both a new upload field configured for that sector and a file uploaded to it whose **upload name matches that field's label exactly** — the lookup is purely a name match, not a filename match.
- **Wrong file format for a scoring guide or KPI document.** The agent can only read `.txt` and `.md` files as text — Word documents (`.doc`/`.docx`) and any other file type are accepted by the upload screen but have no text-reading logic, so they're silently treated as empty rather than causing an error. For a scoring guide, this surfaces as a message saying the file "is empty or could not be read." For a KPI document attachment, it just means that document contributes nothing to the AI's context, with no visible warning anywhere in the report.
- **The AI's response doesn't contain a usable score.** The agent looks for a structured score in the AI's reply in a few different ways before giving up. If the AI's answer is all prose with no structured score at all, or is missing required fields (overall score, grade, summary, dimension breakdown), the run is recorded as a failure with that error message — it will never silently save a report with incomplete or malformed data.
- **An out-of-range score or an empty dimension list** are caught the same way and also result in a failed report rather than a saved-but-wrong score.
- **KPI document gathering only looks at your most recent few "Actual" reports.** The "Documents from last N KPI reports" setting (3 by default) limits which report periods are scanned for documents. A document attached to an older report outside that window is never sent to the AI, even if your document name filter would otherwise have allowed it.
- **The document name filter is an exact, case-insensitive match — not a partial match.** A filter value that doesn't exactly match a document's stored name will silently exclude that document, with no error or warning — it just won't show up in the AI's context.
- **Re-running creates a new report; it never updates the previous one.** If you re-run scoring and it fails, the widget will show that new failure message in place of your last good score, since the widget always shows the most recent report. Re-run successfully to restore a visible score.
- **Changing a company's category away from "Portfolio Company" and back clears its sector.** The system automatically blanks out the sector field whenever a company's category changes away from "Portfolio Company" — so switching the category back later does not bring the old sector value back. You'll need to re-set the sector (and re-verify the scoring guide match) afterward.

## FAQ

**Q: A company has a sector set but never shows up when I run the agent for my whole fund. Why?**
A: Try running it directly from that company's own page instead. Fund-wide and batch runs only include companies that have a sector value saved at all — if the sector is set but doesn't exactly match a configured scoring guide (or the General fallback), the company is still included in the run, so check that company's individual report for the specific error rather than assuming it was skipped.

**Q: The score widget shows "Last scoring run failed" with no useful detail. What should I check first?**
A: Open the failed report and read the error message — it's also shown directly in the widget. The two most common causes are no scoring guide matching the company's sector, and the scoring guide being uploaded in an unsupported file format.

**Q: I uploaded a scoring guide file but the agent still says no skill is configured. What's wrong?**
A: The uploaded file's **display name** must exactly match the field's label (e.g. "Generic Portfolio Skill" or "Beauty & Skincare Skill"). The agent looks up the file by that name — not by which field it was attached through, and not by the original filename from your computer. Double-check the name shown on the uploaded document matches the field label exactly.

**Q: Can I use a Word document (.doc/.docx) as a scoring guide?**
A: No — only `.md` and `.txt` files are read as scoring guide text. Other file types accepted by the upload screen (PDF, Excel, etc.) are intended for KPI documents, not scoring guides; for scoring guides specifically, stick to `.md` or `.txt`.

**Q: Why does "Min points per section" show 5 in our agent when some documentation says the default is 3?**
A: 3 is only the system's last-resort fallback for when the field is blank or invalid. A freshly provisioned agent through Setup All Agents is actually seeded with 5 — that's the real default you'll see in the product.

**Q: Does scoring write anything back onto the Portfolio Company record itself?**
A: No. The score lives only on the scoring report tied to that company. The portfolio company record itself is never changed by this agent.
