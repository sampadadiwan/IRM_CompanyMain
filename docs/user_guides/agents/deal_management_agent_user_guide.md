# Deal Management Agent — User Guide

The Deal Management Agent monitors the health of a single open deal: stagnant investors, overdue activity steps, missing data-room documents, extracted deal terms, per-investor note summaries, and AI scores. It runs scoped to one deal at a time — either on demand from the deal page or on a weekly schedule — and finishes with a pipeline digest email.

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

Each run walks through one deal and checks it from several angles:

1. **Gets started** — loads its settings and confirms the deal is still Open. If the deal is closed, the run stops immediately and nothing changes — there's no report to look at for a closed deal.
2. **Checks deal progress** — for every investor who hasn't been marked Declined or Complete, the agent checks for **stagnation on a per-step basis**. Each deal step can have its own configured number of days (the expected time an investor should spend on that step). The agent uses that step-level duration as the stagnation threshold for investors currently on that step. For example, an investor sitting 5 days on a step configured for 3 days is flagged as stagnant, while an investor sitting 5 days on a step configured for 30 days is not. If a step doesn't have a configured duration, the agent falls back to the global stagnant threshold (default 14 days). The agent also calls out any activity step that's still open past its due date as an overdue, blocking issue.
3. **Checks the document checklist** — looks in the deal's data room for each document name on your "Required documents" list (matching is not case-sensitive). Anything missing is flagged as blocking; anything found is logged as a pass.
4. **Extracts deal terms** — sends every readable document in the deal's data room to the AI and asks it to pull out structured deal terms (valuation, instrument type, closing date, board seats, and more) as a clean set of fields. This step can reuse a previous result instead of re-reading everything — see [Where It Can Fail](#8-where-it-can-fail) for when that happens.
5. **Runs the investor pipeline** — for each active investor, the agent gathers documents from that investor's folder and from their completed activity attachments, can summarize them with the AI (Key Themes / Action Items / Investor Engagement), and can score the investor from 0–100 against your scoring rubric. Scores are saved straight back to the investor's record.
6. **Sends an email digest** — sends one consolidated pipeline summary to whoever is set as the notify recipient, covering overdue activities, document gaps, extracted terms, and a leaderboard of investor scores. If anything blocking turned up anywhere in the run, an alert banner is added automatically.
7. **Saves the report** — stores the deal-level report and a separate report for each active investor.

Every one of these checks (other than the final save) has its own on/off switch, so turning one off won't stop the others from running.

## 2. Inputs

| Field | Type | Default | What it controls |
|---|---|---|---|
| Check deal progress | Select (Yes/No) | Yes | Turns on stagnation detection and overdue-activity flagging. |
| Stagnant threshold (days) | Number | 14 | The global fallback threshold. An investor is flagged stagnant when they've gone untouched for longer than this many days — but if the deal step the investor is currently on has its own configured number of days, **that step's duration takes priority** over this global value. This field only applies to investors on steps that don't have their own duration set. |
| Check document checklist | Select (Yes/No) | Yes | Turns on the required-document presence check. |
| Required documents | Text (comma-separated) | NDA, Term Sheet, Pitch Deck | Document names checked against the data room (not case-sensitive). Leave blank to skip this check entirely — nothing gets flagged. |
| Extract deal terms | Select (Yes/No) | Yes | Turns on AI extraction of deal terms from every document in the data room. |
| Term extraction prompt | Text area | blank | Custom instructions for what to extract. Leave blank to use the built-in instructions, which look for valuation (pre- and post-money), equity percentage, investment amount, instrument type, closing date, board seats, pro-rata rights, anti-dilution, right of first refusal, drag-along rights, and lock-up period. |
| Summarize investor notes & docs | Select (Yes/No) | Yes | Turns on the three-part AI summary per investor. Only runs for investors who have at least one document. |
| Note period | Select (Month/Quarter) | Quarter | How far back the agent looks when gathering an investor's documents and activity attachments. Does **not** affect term extraction, which always reads the entire data room regardless of this setting. |
| Score investors | Select (Yes/No) | Yes | Turns on AI scoring of each active investor from 0–100. Can still produce a score for investors with no documents at all — their activity history and notes provide enough signal on their own. |
| Scoring Skill File | File | seeded default | The document that defines your scoring rubric. See the note below. |
| Min bullet points per section | Number | 3 | The minimum number of bullet points the AI must write for each scoring rationale (positives/concerns) and for each top-level list (strengths/risks/recommendations). |
| Weekly summary | Select (Yes/No) | Yes | Turns on the weekly summary content — charts, task lists, and the digest email itself. With this off, no digest is sent even when Notify email is set. Agents set up before this option existed may have it unset, which counts as off — see the setup checklist below. |
| AI insight | Select (Yes/No) | Yes | Turns on the AI-written insight section inside the weekly summary. Only applies when Weekly summary is on. |
| Notify email | Text | blank | Who receives the post-run pipeline digest. Leave blank and **no email at all** goes out for this agent. |

**Scoring Skill File.** This should be a plain text or Markdown document describing your scoring dimensions and how much each one should count. The built-in default rubric uses four weighted dimensions: Engagement & Responsiveness (30%), Document Readiness (25%), Commitment Signals (25%), and Pipeline Health (20%). Running **Setup All Agents** uploads this default for you automatically. If you upload your own file, it completely replaces the default — the agent reads whatever text is in your document and hands it to the AI as scoring instructions, word for word. If the file you uploaded turns out to be empty or unreadable, the agent quietly falls back to the built-in default rubric instead of failing the run.

**Other things the agent looks at** (not settings you configure directly):
- Documents sitting in the deal's data-room folder (used by the document checklist and term extraction).
- Documents in each investor's own folder, plus attachments on their **completed** activity steps within the Note Period window (used by the note summaries and scoring).
- Each investor's activity steps, including due dates and status (used by deal progress checks and scoring).
- Investor notes, tier, status, and committed amount (used as extra context for scoring).

Supported document formats throughout: PDF, TXT, Markdown, Excel (XLSX/XLS), PowerPoint (PPTX/PPT), Word (DOCX/DOC), and CSV. Anything in another format is silently left out of whatever the AI sees.

### Setup checklist and warnings

An unset Yes/No toggle counts as **off**, not on — a step whose toggle was never given a value is silently skipped, which is easy to mistake for the agent working normally. The agent's **General** tab shows a yellow warning banner listing anything in this state. For this agent it flags:

- **Any of the seven check toggles that has never been set** (deal progress, document checklist, term extraction, note summaries, investor scoring, weekly summary, AI insight). Agents provisioned before the Weekly summary and AI insight options existed commonly have those two unset — re-running **Setup All Agents** fills them in as Yes.
- **A blank Notify email** — the pipeline digest, this agent's main output, will never be sent.
- **A Scoring Skill File field with no uploaded document** — scoring will quietly use the built-in default rubric instead of yours.

Resolve the banner items before relying on the digest or on custom scoring.

## 3. Enabling the Agent

1. An administrator needs to turn on the **Deal Management Agent** toggle for your organization from **Admin → Edit Entity → Support Agents**.
2. An AI provider key needs to be set up at **AI → Support Agents → LLM Keys**. Every feature here except the plain document checklist relies on the AI — the progress check and document checklist are deterministic on their own, but term extraction, note summaries, and scoring all need a working key.
3. The agent uses your organization's default AI model unless someone sets a specific model override on the agent's own edit page.
4. Only users with the **Company Admin** role can change the agent's settings; running it from a deal page just requires permission to edit that deal.

If the organization-wide toggle is off, the **Run Now** button on the agent's own page is disabled — but the "Run Agent" button on an individual deal page is only checked against your permission to edit that deal, not the organization toggle. See [Where It Can Fail](#8-where-it-can-fail) for what that means in practice.

## 4. Accessing and Running the Agent

**From the Deal page (the normal path):** open a deal, find the "Run Agent" button in the deal's agent settings area, and confirm. This only runs against that one deal — there's no "run for every deal" option here. For a portfolio-wide view across every open deal, use the **Deals Report Agent** instead.

**From AI → Support Agents:** open the Deal Management Agent card, go to the **General** tab, and click **Run Now**. You'll be asked to pick which deal to run it against.

**Scheduled runs:** kick off automatically per the Schedule tab settings (see below), always against whichever deal the schedule was set up for.

This agent doesn't show a live, step-by-step progress panel while it runs — after you trigger it, you'll see a "queued" notice, and the result shows up once the run finishes. Refresh the Deal Reports tab or the deal page itself to see the new report.

## 5. Scheduling

A weekly schedule is set up automatically by **Setup All Agents**: every **Monday at 07:00 (Asia/Kolkata)**, with failure notifications on, success notifications off, and CapHive support notified if something errors. **It ships turned off** — nothing runs automatically until someone enables it.

To turn it on: open the agent's **Schedule** tab, confirm or adjust the frequency/day/time/timezone, switch **Enabled** on, and save.

## 6. Where to Find the Output

- **Deal-level report**: a fresh report is created every time the agent runs against the deal — history builds up over time, and the most recent one is always marked as the latest. You'll find it on the agent's **Deal Reports** tab and on the deal's own Agent/AI tab.
- **Per-investor reports**: one report per active investor, but these are **replaced** each run rather than kept as history — only the latest result per investor is available.
- **Score write-back**: when scoring succeeds, the investor's AI score (0–100) and letter grade are updated directly on their record.
- **Email**: the pipeline digest goes to whoever's set in **Notify email**. The subject line gets an "[ALERT]" prefix if anything blocking was found anywhere in the run, or "[Digest]" otherwise. No email goes out if Notify email is left blank.
- **Execution History tab**: shows every run, including failed ones, with status and how long it took.

## 7. Understanding the Report

The deal-level report includes:

- **Progress issues, document issues, and digest issues** — lists of problems found by each check, each with a type, a message, and a severity (Blocking, Warning, Info).
- **Extracted terms** — the structured set of deal terms returned by the AI (empty if extraction was turned off, there were no documents to read, or the AI's response couldn't be understood).
- **Term extraction tracking info** — internal markers the agent uses to decide whether it can reuse a previous extraction instead of running it again (see [Where It Can Fail](#8-where-it-can-fail)).
- **Score leaderboard** — every investor with their name, status, AI score, and grade, sorted highest score first.
- **Health scores** — a snapshot of each investor's health, captured at the time of the progress check.
- **Overall status** — "blocked" if anything blocking turned up anywhere in the run, otherwise "ready."

Each per-investor report includes the written summary, the full score breakdown (overall score, grade, a short summary, the scoring dimensions with positives/concerns, plus top-level strengths/risks/recommendations), how many documents and activity items were found, and a status of "ready" (documents were found), "skipped" (none were), or "failed" (something went wrong).

## 8. Where It Can Fail

- **Re-running the agent and seeing the same extracted terms — this is by design, not a bug.** Term extraction remembers what it read last time. If nothing in the data room has been added, removed, or changed since the last run, and the extraction instructions haven't changed either, the agent reuses last time's extracted terms instead of paying to re-read everything with the AI. That's a deliberate cost-saving measure, but it can look like the run "did nothing" if you were expecting fresh output. **To force a fresh read**, add, remove, or change a document in the data room, or edit the extraction instructions text — even a small change is enough.
- **Closed deals are skipped entirely.** If the deal isn't marked Open, the agent stops right at the start with a warning and produces no report at all — there's nothing to inspect.
- **No required documents configured means the checklist quietly does nothing.** Leave "Required documents" blank and you'll get a single success note saying "no required documents configured" rather than any real check.
- **No documents in the data room means term extraction is skipped, not failed.** The agent records "no documents in data room" and moves on; extracted terms stay empty.
- **Investors with no documents aren't scored for free, but they aren't blocked either.** The note-summary step needs at least one document and is skipped for any investor who doesn't have one. Scoring is different — if it's turned on, it can still produce a score using just activity history and notes, so an investor with zero documents may still get scored, just without a summary feeding into it.
- **A missing or empty Scoring Skill File quietly falls back to the built-in rubric** instead of throwing an error. If you uploaded a custom rubric and the scores don't seem to reflect it, double-check that the file actually contains readable text.
- **Very large data rooms can hit size limits.** Each document is capped at 5,000 characters and the whole data room context is capped at 50,000 characters per investor/deal; once that's reached, the oldest-processed documents are the ones left out. That can quietly leave recent or large files out of term extraction and scoring without any warning in the UI — only a technical log captures it.
- **Leaving Notify email blank silences the digest entirely** — the run still finishes and the report still saves, but nobody gets told, even if blocking issues were found. There's no separate "always notify on blockers" setting independent of this field.
- **The "Run Agent" button on a deal page isn't checked against the organization-wide toggle the same way the agent's own page is** — it only checks your permission to edit that deal. So if the toggle is off, the agent's own Run Now button is disabled, but it's worth confirming with an administrator that the feature is actually turned on for your organization before relying on the deal-page button.
- **Old references to reminder settings no longer do anything.** An earlier version of this agent sent per-activity email reminders through separate settings. Those have since been folded into the single post-run digest described above, and Setup All Agents removes the old settings automatically. If you come across documentation or notes mentioning them, they're outdated and have no effect.

## FAQ

**Q: I re-ran the agent and the extracted terms didn't change even though I expected new values. Why?**
A: Term extraction reuses its previous result when nothing has changed. If no document in the data room was added, removed, or modified, and the extraction instructions are the same, the agent skips the AI call and reuses what it found last time. Touch a document or edit the instructions to force a fresh read.

**Q: An investor has no score even though Score investors is turned on. What happened?**
A: Check that investor's report for its status and score details. Scoring can fail quietly (logged but not shown) if the AI's response wasn't in the expected format, or if the score it returned was outside the 0–100 range — in either case, no score or grade gets saved for that investor.

**Q: I uploaded a new Scoring Skill File but scores look unchanged.**
A: Make sure the file actually has text in it, and that the upload replaced the existing file on the agent's edit page rather than sitting alongside it. An empty or unreadable file silently falls back to the default rubric with no error shown.

**Q: Why didn't I get a digest email after a run that found blockers?**
A: Notify email was probably left blank. The run still completes and the report still saves — there's just nobody to send it to. Set an email address on the agent's edit page.

**Q: Can I run this for every deal in the pipeline at once?**
A: No — this agent always targets one deal at a time. Use the **Deals Report Agent** for a portfolio-wide fundraising summary across every open deal.
