# Investor Presentation Analyst — User Guide

The Investor Presentation Analyst reads a portfolio company's investor presentations across reporting periods, extracts structured intelligence from each one, compares periods to surface commitment misses and dropped risks, and produces a pre-board briefing plus a Management Accountability Score — all scoped to one portfolio company at a time.

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

Each run works through one portfolio company and walks through these stages:

1. **Gets started** — loads its settings. If the target isn't actually a portfolio company, or the agent isn't enabled, it stops cleanly with no error.
2. **Collects presentations** — looks at the most recent KPI reports of your configured type (Actual, by default), and on each one finds the first attached document whose file name contains one of your configured keywords (matching isn't case-sensitive). Reports are read oldest to newest, so later steps understand the timeline correctly.
3. **Extracts intelligence** — reads each matching document **in full**, with no shortening or skipping, and asks the AI to pull out eight categories of information per period: management narrative, commitments, risks, accomplishments, forward plans, strategic objectives, key metrics, and initiatives.
4. **Runs cross-period analysis** — compares the extracted periods against each other to produce five comparison views: commitment tracking, risk evolution, objective drift, an "initiative graveyard" of abandoned plans, and metric anomalies. This only runs once at least two periods have been extracted.
5. **Generates the briefing** — produces 8–12 grounded pre-board questions, each one citing a specific number, date, or quote so it's clearly tied to real evidence. This step can reuse the previous question set if nothing meaningful has changed since the last run — see [Where It Can Fail](#8-where-it-can-fail).
6. **Scores the company** — calculates the **Management Accountability Score** (0–100) using simple arithmetic on the comparison results — no AI call needed for this part. It's a weighted blend: Commitment 35%, Risk 25%, Coherence 25%, Narrative 15%.
7. **Saves everything** — stores the full result as a new report.

A small chat panel can optionally be turned on for this agent so a fund manager can ask follow-up questions about the latest run's findings in plain language, without re-running the whole analysis. See [Where to Find the Output](#6-where-to-find-the-output) for what the chat panel can see.

## 2. Inputs

| Field | Type | Default | What it controls |
|---|---|---|---|
| Presentation document names | Text (comma-separated) | Investor Update, Board Deck, Management Presentation, Quarterly Update, Investor Presentation | Keywords matched (not case-sensitive) against document file names on each KPI report. A document counts as a presentation if its name contains **any** of these keywords. |
| Max periods to analyze | Number | 8 | The maximum number of the most recent reporting periods scanned. Anything below 1 quietly falls back to 8. |
| KPI report tag | Select (Actual/Budget/IC) | Actual | Which type of KPI report is scanned for presentation documents. |
| Comparison strategy | Select (All periods/Sliding window) | All periods | "All periods" sends every extracted period to the AI in one go — most accurate, since it sees the whole arc at once. "Sliding window" instead makes one comparison per adjacent pair of periods — cheaper as the number of periods grows, but less holistic. |
| AI model | Text | gemini-3-flash-preview | Needs to support a very large context window (roughly 500K tokens or more). See the note below. |

**Why the AI model matters here.** The Extract Intelligence step sends each presentation's full text to the AI with no shortening at all — the whole design assumes a model that can handle roughly a million tokens of context, which is what the default model provides. If you switch to a smaller-context model: long presentations may get silently cut off or rejected by the AI provider, extraction quality will degrade or fail document-by-document (each failure is handled quietly and logged, not shown as a hard error), and the cross-period comparison step — when using "All periods" mode — sends every period's extracted data in one request, which can itself get close to a smaller model's limits even though the original documents are no longer part of that payload (only the extracted summaries are).

**Other things the agent looks at** (not settings you configure directly):
- The KPI reports and their attached documents for the target portfolio company.
- Document formats it can read: PDF, TXT, Markdown, Excel (XLSX/XLS), PowerPoint (PPTX/PPT), and Word (DOCX/DOC). PowerPoint and Word files go through a layered extraction process that tries a few different methods in sequence to get the best possible text out.
- The previous run's report (used for the question-reuse logic and for the chat panel's context).

Two additional on/off switches exist behind the scenes beyond the fields above: one to turn off scoring, and one to turn off question generation (both on by default). These let you disable the Score and/or Briefing sections independently without affecting the rest of the agent. Ask an administrator if you need either of these changed, since they aren't exposed on the standard settings screen.

## 3. Enabling the Agent

1. An administrator turns on the **Investor Presentation Analyst** toggle for your organization from **Admin → Edit Entity → Support Agents**.
2. An AI provider key needs to be set up at **AI → Support Agents → LLM Keys** — every meaningful step in this agent relies on the AI.
3. The default model (gemini-3-flash-preview) supports a roughly 1-million-token context window — keep it unless you have a specific reason to switch and a comparably large-context replacement in mind; see the failure-mode note above.
4. Running the agent against a specific portfolio company requires permission to edit that company's record.

## 4. Accessing and Running the Agent

**From a Portfolio Company page:** the "Investor Presentation Analysis" widget shows recent reports for that company (periods covered, score, grade, question count, status, and run time). Click **Run Presentation Analyst** for a first run, or **Re-run** for any run after that, to open the confirmation prompt.

**From AI → Support Agents:** open the agent card → General tab → Run Now, and pick the target portfolio company.

**Scope:** this agent always runs against **one portfolio company at a time** from the screens described here — there's no "run for every portfolio company at once" button in the UI, though the scheduled/automatic run does work through every portfolio company in your organization on its own.

**Watching it run:** running this agent shows a live, 7-step progress panel (Initialize → Collect Presentations → Extract Intelligence → Cross-Period Analysis → Generate Briefing → Score → Save), so you can watch each stage complete — or flag an issue — in real time.

## 5. Scheduling

A monthly schedule is set up automatically by **Setup All Agents**: the **1st of each month at 06:00 (Asia/Kolkata)**, with failure and partial-success notifications on, success notifications off, and CapHive support notified if something errors. **It ships turned off** by default — nothing runs automatically until someone enables it. Turn it on from the agent's **Schedule** tab so fresh briefings are ready ahead of board meetings.

## 6. Where to Find the Output

- **Report**: a new report is saved every time this agent runs for a portfolio company — full history is kept, and the most recent one is always marked as the latest automatically.
- **Portfolio company widget**: the "Investor Presentation Analysis" widget on the company page shows the most recent runs with score, grade, and question count inline, and can be expanded for full detail.
- **Presentation Reports tab**: on the agent's own page, grouped by portfolio company.
- **Chat panel** (if turned on): only ever looks at the single most recent report for that company, so it always reflects the latest run — including any reused questions — and can search the full extracted detail for quotes that didn't make it into the summarized findings.
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

The overall score maps to the same letter-grade scale (A/B+/B/C+/C/D) used by the Portfolio Scoring Agent, so the two scores can be compared side by side.

## 8. Where It Can Fail

- **No presentations found is the single most common reason for an empty result.** A presentation only counts if it's attached to the right kind of report — specifically a KPI report, not just uploaded somewhere general on the portfolio company — and its file name contains one of your configured keywords (like "Board Deck" or "Investor Update"). If the file's name doesn't match, the agent finds nothing for that period. When that happens, the run still completes and produces a report, but it's marked "Blocked" with no further AI calls made. If you're seeing an empty result, check that the presentation is attached to a KPI report and that its file name actually contains one of the configured keywords.
- **"All periods" comparison cost/accuracy tradeoff.** With many periods configured, "All periods" mode sends every extracted record to the AI in a single request — most accurate, but the request size grows with the number of periods and could approach a smaller model's limits. It also means a single failed request loses the entire cross-period analysis for that run, not just one period pair (it fails gracefully to an empty result, but you lose all the signal at once).
- **"Sliding window" strategy trades cost for more individual AI calls.** This mode makes one AI request per adjacent pair of periods — for 8 periods, that's 7 separate requests instead of one. On a rate-limited AI key, or when many portfolio companies are scheduled to run around the same time, this increases both how long it takes and the chance of hitting provider rate limits. The upside is that failures are more contained — only one period pair is affected at a time — but there are more of them to track down if something does go wrong.
- **Reusing last time's questions can look like "nothing happened" on a re-run.** If the comparison results come out identical to the previous run, the briefing step reuses the previous question set rather than generating new ones, at no extra cost. This is intentional for portfolio companies that haven't changed much, but if you added a new presentation and expected fresh questions, check whether that new period actually introduced anything new — if extraction didn't find any meaningful change, the questions legitimately stay the same.
- **A smaller AI model risks silent truncation.** Extraction sends the full document text with nothing shortened, so switching to a model with a smaller context window than the recommended ~1M tokens risks the provider quietly cutting off long documents, incomplete extraction, or outright failures on large presentations like dense board decks or financial appendices. This fails quietly — per-document issues are logged as "skipped" rather than raised as an error that stops the run.
- **Turning off scoring or question generation removes whole sections with little visible warning.** These two switches aren't on the standard settings screen, so if an administrator turns one off directly, the Score section simply disappears from the report, with only a log entry and a low-severity note — not an obvious warning in the UI.
- **There's no email option for fund managers.** Even with the schedule's failure notifications turned on, those only alert administrators and CapHive support — there's no "send the briefing straight to the GP's inbox" feature. Anyone waiting on a result needs to check the UI or the chat panel directly.
- **Extraction quality for PowerPoint and Word files depends on what's available in the runtime environment.** The agent tries a few different extraction methods in sequence, and the weakest fallback can miss speaker notes and table cells entirely — which can quietly drop context (for example, a key metric mentioned only in a speaker note might never reach the AI).

## FAQ

**Q: The agent ran and reported "no presentation documents found." What should I check first?**
A: Confirm the document is attached to a KPI report for that portfolio company — not just uploaded generally — that the report's type matches your **KPI report tag** setting (default: Actual), that it falls within the most recent periods you've configured, and that its file name contains one of the keywords in **Presentation document names** (matching isn't case-sensitive).

**Q: I added a new quarter's presentation but the pre-board questions look identical to last time. Is that a bug?**
A: Probably not. Questions are only regenerated when the comparison results actually change from last time. If the new period didn't introduce any new commitment misses, dropped risks, drift, abandoned initiatives, or metric anomalies relative to what was already flagged, the agent reuses the previous question set at no extra cost.

**Q: Should I switch the AI model to save cost?**
A: Only to another large-context model. Anything with meaningfully less than about 500K tokens of context risks silently truncating long presentations during extraction, and can also struggle with the full multi-period payload sent in "All periods" comparison mode.

**Q: When should I use "Sliding window" instead of "All periods"?**
A: When you have a lot of periods configured and want to control cost — it trades one request per adjacent pair of periods for less holistic reasoning across the whole timeline, and exposes you to more AI requests overall (and therefore more rate-limit risk) per run.

**Q: Where do fund managers see the output if there's no email?**
A: On the portfolio company's "Investor Presentation Analysis" widget, the agent's Presentation Reports tab, or by asking the chat panel directly if it's been turned on for that agent.
