# Deal Management Agent — User Guide

The Deal Management Agent monitors the health of a single open deal: stagnant investors, overdue activity steps, missing data-room documents, extracted deal terms, per-investor note summaries, and AI scores. It runs scoped to one deal at a time — either on demand from the deal page or on a weekly schedule — and finishes with a pipeline digest email.

> **Where to find it:** Company menu (house icon, top right) → [**Agents**](/support_agents) → **Deal Management** card; configure it with **Edit** and run it with **Run Now**. To run it on one deal: Sidebar → [**Deals**](/deals) → open the deal → **Deal** tab → **Run Deal Agent**; the deal header's **Weekly Summary** button opens the results. Needs the *Deal Management Agent* support-agent flag (set by CapHive support), the **Company Admin** role and an LLM key for the AI steps.

## Table of Contents

1. [What This Agent Does](#1-what-this-agent-does)
2. [Inputs](#2-inputs)
3. [Enabling the Agent](#3-enabling-the-agent)
4. [Accessing and Running the Agent](#4-accessing-and-running-the-agent)
5. [Scheduling](#5-scheduling)
6. [Where to Find the Output](#6-where-to-find-the-output)
7. [Understanding the Report](#7-understanding-the-report)
8. [Where It Can Fail](#8-where-it-can-fail)
9. [Frequently Asked Questions](#9-frequently-asked-questions)

---

## 1. What This Agent Does

Each run walks through one deal and checks it from several angles:

1. **Gets started** — loads its settings and confirms the deal is still Open. If the deal isn't Open (or the agent's own **Enabled** box is unticked), the run stops immediately and nothing changes — there's no report to look at for a closed deal.
2. **Checks deal progress** — for every investor who hasn't been marked Declined or Complete, the agent checks for **stagnation** using the single **Stagnant threshold (days)** setting (default 14 days): an investor is flagged as stagnant, and blocking, only when neither the deal investor record nor any of its activities has been updated within that many days. Per-step durations configured on the deal's steps are not used here; they only feed the stagnation breakdown in the Weekly Summary. The agent also calls out any activity step that's still open past its due date as an overdue, blocking issue.
3. **Checks the document checklist** — looks in the deal's data room for each document name on your "Required documents" list (matching is not case-sensitive). Anything missing is flagged as blocking; anything found is logged as a pass.
4. **Extracts deal terms** — sends every readable document in the deal's data room to the AI and asks it to pull out structured deal terms (valuation, instrument type, closing date, board seats, and more) as a clean set of fields. This step can reuse a previous result instead of re-reading everything — see [Where It Can Fail](#8-where-it-can-fail) for when that happens.
5. **Runs the investor pipeline** — for each active investor, the agent gathers documents from that investor's folder and from their completed activity attachments, can summarize them with the AI (Key Themes / Action Items / Investor Engagement), and can score the investor from 0–100 against your scoring rubric. Scores are saved straight back to the investor's record.
6. **Sends an email digest** — sends one consolidated pipeline summary to whoever is set as the notify recipient, covering overdue activities, document gaps, extracted terms, and a leaderboard of investor scores. If anything blocking turned up anywhere in the run, an alert banner is added automatically. When the weekly summary is on, a second "Weekly Summary" email is sent to the same recipient.
7. **Saves the report** — overwrites the deal's single deal-level report and adds a new report for each active investor.

Every one of these checks (other than the final save) has its own on/off switch, so turning one off won't stop the others from running.

## 2. Inputs

| Field | Type | Default | What it controls |
|---|---|---|---|
| Check deal progress | Select (Yes/No) | Yes | Turns on stagnation detection and overdue-activity flagging. |
| Stagnant threshold (days) | Number | 14 | The only threshold used by the blocking progress check. An investor is flagged stagnant when neither the deal investor record nor any of its activities has been updated for longer than this many days. Per-step durations are not used by this check. |
| Check document checklist | Select (Yes/No) | Yes | Turns on the required-document presence check. |
| Required documents | Text (comma-separated) | NDA, Term Sheet, Pitch Deck | Document names checked against the data room (not case-sensitive). Leave blank to skip this check entirely — nothing gets flagged. |
| Extract deal terms | Select (Yes/No) | Yes | Turns on AI extraction of deal terms from every document in the data room. |
| Term extraction prompt | Text area | blank | Custom instructions for what to extract. Leave blank to use the built-in instructions, which look for valuation (pre- and post-money), equity percentage, investment amount, instrument type, closing date, board seats, pro-rata rights, anti-dilution, right of first refusal, drag-along rights, and lock-up period. |
| Summarize investor notes & docs | Select (Yes/No) | Yes | Turns on the three-part AI summary per investor. Only runs for investors who have at least one document. |
| Note period | Select (Month/Quarter) | Quarter | The previous full calendar month or quarter. It only limits which completed-activity attachments are gathered; documents in the investor's own folder are always all included. Does **not** affect term extraction, which always reads the entire data room regardless of this setting. |
| Score investors | Select (Yes/No) | Yes | Turns on AI scoring of each active investor from 0–100. Can still produce a score for investors with no documents at all — their activity history and notes provide enough signal on their own. |
| Scoring Skill File | File | seeded default | The document that defines your scoring rubric. See the note below. |
| Min bullet points per section | Number | 3 | The minimum number of bullet points the AI must write for each scoring rationale (positives/concerns) and for each top-level list (strengths/risks/recommendations). Values below 3 are raised to 3. |
| Weekly summary | No field on the Edit page (set by Setup All Agents or CapHive support) | Yes | Turns on the weekly summary content — step transitions, stagnation breakdown, charts, task lists — and the extra "Weekly Summary" email. With this off, the pipeline digest is still sent when Notify email is set. Agents set up before this option existed may have it unset, which counts as off — see the setup checklist below. |
| Report period (days) | No field on the Edit page (set only by CapHive support) | 1 | How many days back the weekly summary looks when calculating step transitions, new investors, status changes, and completed tasks. Setup All Agents does not set it, so it defaults to 1 day — meaning only today's changes appear — until CapHive support sets it to 7 for a true weekly view. |
| AI insight | No field on the Edit page (set by Setup All Agents or CapHive support) | Yes | Turns on the AI-written insight section inside the weekly summary. Only applies when Weekly summary is on. |
| Notify email | Text | blank | Who receives the post-run pipeline digest (and the Weekly Summary email). Leave blank and **no email at all** goes out for this agent. |
| Target Deal | Select | — Select a Deal — | The deal that **Run Now** and scheduled runs cover (only non-closed deals are listed). Leave unselected to cover every non-closed deal in your entity. |
| Step Transitions | Checkboxes | none ticked | Shown after you pick a Target Deal. Ticked step pairs are the only transitions shown in the weekly summary; leave all unticked to include every transition. |

**Scoring Skill File.** This should be a plain text or Markdown document describing your scoring dimensions and how much each one should count. The built-in default rubric uses four weighted dimensions: Engagement & Responsiveness (30%), Document Readiness (25%), Commitment Signals (25%), and Pipeline Health (20%). Running **Setup All Agents** uploads this default for you automatically. If you upload your own file, it completely replaces the default — the agent reads whatever text is in your document and hands it to the AI as scoring instructions, word for word. If the file you uploaded turns out to be empty or unreadable, the agent quietly falls back to the built-in default rubric instead of failing the run.

**Other things the agent looks at** (not settings you configure directly):
- Documents sitting in the deal's data-room folder (used by the document checklist and term extraction).
- All documents in each investor's own folder, plus attachments on their **completed** activity steps within the Note Period window (used by the note summaries and scoring).
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

1. CapHive support needs to turn on the *Deal Management Agent* support-agent flag for your entity.
2. An AI provider key needs to be set up at Company menu (house icon, top right) → **Agents** → [**LLM Keys**](/support_agents/llm_keys). Every feature here except the plain document checklist relies on the AI — the progress check and document checklist are deterministic on their own, but term extraction, note summaries, and scoring all need a working key.
3. The agent uses your organization's default AI model unless someone sets a specific model override on the agent's own edit page.
4. Only users with the **Company Admin** role can change the agent's settings or run it — including from a deal page.

If the flag is off, the **Run Now** button on the agent's own page is disabled and the **Run Deal Agent** button on a deal page is shown locked with the tooltip "Deal Management Agent is disabled. Contact support to enable it". If the flag is on but the agent hasn't been created or its **Enabled** box is unticked, **Run Deal Agent** doesn't appear at all.

## 4. Accessing and Running the Agent

**From the Deal page (the normal path):** open a deal, go to its **Deal** tab, click **Run Deal Agent** (next to Edit/Delete), and click **Run Agent** in the modal. This only runs against that one deal. (The deal page's **Agent Settings** tab belongs to the Deals Report Agent, not this one.) For one consolidated email across every open deal, use the **Deals Report Agent** instead.

**From Company menu (house icon, top right) → Agents:** open the Deal Management Agent card, go to the **General** tab, and click **Run Now**. You aren't asked to pick a deal: it runs the **Target Deal** chosen on the Edit page, or every non-closed deal in your entity if none is chosen, each as its own run.

**Scheduled runs:** kick off automatically per the Schedule tab settings (see below), covering the same deals as **Run Now**.

A run from the deal page streams a live step-by-step progress panel into the **Deal** tab, with a toast alert for each step. **Run Now** across several deals shows a batch progress panel that counts through them.

## 5. Scheduling

A weekly schedule is set up automatically by **Setup All Agents**: every **Monday at 07:00 (Asia/Kolkata)**, with failure notifications on, success notifications off, and CapHive support notified if something errors. **It ships turned off** — nothing runs automatically until someone enables it.

To turn it on: open the agent's **Schedule** tab, confirm or adjust the frequency/day/time/timezone, tick **Enable scheduled runs for this agent**, and click **Save Schedule**.

## 6. Where to Find the Output

- **Weekly Summary dashboard**: open the deal and click the **Weekly Summary** button in the deal page header. This shows the latest report's data: step transitions, stagnation breakdown, period deltas (new/dropped investors), tasks (overdue, upcoming, pending, completed), charts, and AI insight. A report selector dropdown appears only when the deal has more than one report, which is rare because the deal-level report is overwritten each run. The button is locked unless the Deal Management Agent is enabled for your entity.
- **Deal-level report**: one report per deal, reused and **overwritten** every time the agent runs against it — no history of earlier deal-level results is kept. You'll find it on the agent's **Deal Reports** tab.
- **Per-investor reports**: a **new** report is created for each active investor on every run and marked as the latest, so history builds up over time and earlier reports keep the previous scores.
- **Score write-back**: when scoring succeeds, the investor's AI score (0–100) and letter grade are updated directly on their record.
- **Email**: the pipeline digest goes to whoever's set in **Notify email**. The subject line gets an "[ALERT]" prefix if anything blocking was found anywhere in the run, or "[Digest]" otherwise. When the weekly summary is on, a second "Weekly Summary" email follows. No email goes out if Notify email is left blank.
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
- **Running from a deal page needs the Company Admin role.** Permission to edit the deal is not enough — a user without the role gets a not-authorised error when clicking **Run Agent**, and the button is locked when the entity flag is off.
- **Old references to reminder settings no longer do anything.** An earlier version of this agent sent per-activity email reminders through separate settings. Those have since been folded into the single post-run digest described above, and Setup All Agents removes the old settings automatically. If you come across documentation or notes mentioning them, they're outdated and have no effect.

---

## 9. Frequently Asked Questions

### Navigation and getting there

**Where do I find the Deal Management Agent in CapHive?**
Open the Company menu (house icon, top right) → [**Agents**](/support_agents) and click the **Deal Management** card in the **Portfolio** group. Its page has **General**, **Schedule**, **Execution History** and **Deal Reports** tabs.

**How do I run the agent for one deal?**
Sidebar → [**Deals**](/deals), open the deal, go to the **Deal** tab and click **Run Deal Agent**. The modal describes the checks; click **Run Agent** and the step progress panel appears below the buttons. See [Accessing and Running the Agent](#4-accessing-and-running-the-agent).

**Where is the Weekly Summary dashboard?**
On the deal page, click **Weekly Summary** in the header next to **Download Excel**. It opens the weekly summary with step transitions, stagnation, tasks, charts and the AI insight from the deal's latest report.

**Where do I see the full deal report?**
On the agent page, open the **Deal Reports** tab: each deal shows its issues, extracted terms and investor score leaderboard. The pipeline digest email to **Notify email** carries the same content.

**Why is Run Deal Agent or Weekly Summary greyed out with a lock?**
The *Deal Management Agent* flag is not enabled for your entity; the tooltip says "Deal Management Agent is disabled. Contact support to enable it". If the flag is on but **Run Deal Agent** is missing entirely, the agent has not been created or its **Enabled** box is unticked.

**Is the Agent Settings tab on the deal page for this agent?**
No. **Agent Settings** on the deal page configures the Deals Report Agent. This agent's settings are on its own **Edit** page under Company menu → **Agents**.

### Creating, updating and managing the agent

**How do I create the Deal Management Agent?**
A company admin opens Company menu → **Agents** → **Setup All Agents** → **Run Setup**. It creates the agent with all checks set to Yes, required documents "NDA, Term Sheet, Pitch Deck", the default scoring rubric file, a blank **Notify email** and a weekly Monday 07:00 Asia/Kolkata schedule that starts disabled.

**How do I configure the agent?**
Open the agent and click **Edit**. Set the Yes/No checks, **Stagnant threshold (days)**, **Required documents**, **Term extraction prompt**, **Note period**, **Scoring Skill File**, **Min bullet points per section** and **Notify email**, then save. See [Inputs](#2-inputs).

**How do I choose which deal the scheduled run monitors?**
On the **Edit** page, pick a deal under **Deal Management Configuration → Target Deal** (only non-closed deals are listed) and save. Leave it on "— Select a Deal —" and scheduled runs and **Run Now** cover every non-closed deal in your entity.

**What are the Step Transitions checkboxes on the Edit page?**
After you choose a Target Deal, **Step Transitions** lists each pair of that deal's steps. Ticked pairs are the only transitions shown in the weekly summary progress section; leave all unticked to include every transition.

**How do I replace the scoring rubric?**
On the **Edit** page, upload a plain text or Markdown file in **Scoring Skill File** and save. The file's text replaces the built-in rubric word for word; an empty or unreadable file quietly falls back to the default.

**How do I turn on the weekly schedule?**
On the **Schedule** tab tick **Enable scheduled runs for this agent**, check the frequency, **Run On**, **Run At** and **Timezone**, and click **Save Schedule**. It ships disabled, so nothing runs automatically until you do this. See [Scheduling](#5-scheduling).

**How do I stop the agent or delete it?**
Untick the schedule to stop automatic runs, or untick **Enabled** on the **Edit** page to hide **Run Deal Agent** on deal pages. **Delete** on the General tab only succeeds for an agent that has never run.

**What permissions and keys does it need?**
The *Deal Management Agent* flag (set by CapHive support), the **Company Admin** role to run or configure it, including from the deal page, and an LLM key under [**Agents → LLM Keys**](/support_agents/llm_keys) for term extraction, summaries, scoring and the AI insight.

### Why use the Deal Management Agent

**Why should I use the Deal Management Agent?**
It watches a live deal for you: investors who have gone quiet, deal steps past their due date, missing data-room documents, and who is most likely to commit. Without it someone has to open every deal investor, activity and document by hand each week.

**What does it let me do that I cannot do otherwise?**
It pulls deal terms out of the data room with AI, scores every active investor from 0 to 100 against your rubric, writes that score back to the investor, and emails one digest with blockers highlighted. The Weekly Summary adds step transitions and stagnation trends for the period.

**Who typically uses it?**
Deal and fundraising teams running an active raise or investment process, usually on a weekly cadence before their pipeline meeting. A company admin configures it.

**What happens if I skip the setup items?**
With **Notify email** blank the run completes but nobody is emailed, even about blockers. Without an LLM key the AI steps fail softly and you get only the progress and document checks. The yellow banner on the **General** tab lists the gaps.

### What happens when I…

**What happens when I click Run Agent on a deal?**
The deal's report is reset and a background job runs twelve steps, streaming the progress panel and a toast per step to you. It saves AI scores on the deal investors, a new per-investor report for each active investor, overwrites the deal-level report and adds a Manual row to **Execution History**. Deal data and documents are otherwise unchanged.

**What happens when I click Run Now on the agent page?**
It runs the Target Deal from the **Edit** page, or every non-closed deal if none is chosen, each as its own run. With several deals a batch progress panel counts through them and you get a summary alert at the end.

**What happens when the run finds a blocker?**
Stagnant investors, overdue deal steps and missing required documents are recorded as blocking, the report is marked blocked, and the digest subject starts with "[ALERT]". Nothing is fixed or sent to investors; you act on the list yourself.

**Who is emailed after a run?**
Only the addresses in **Notify email**: one "[ALERT]" or "[Digest] Deal — Deal Management Report" email, plus a "Deal — Weekly Summary" email when the weekly summary is on. Investors are never emailed. Scheduled-run success or failure notices go to **Schedule → Notification Recipients**.

**What happens to investor scores?**
Each scored investor's AI score and grade are written straight onto the deal investor record and listed in the leaderboard. A later run overwrites them; there is no undo, but earlier per-investor reports keep the previous scores.

**What happens when the deal is not Open?**
The run stops at Initialize with a warning toast such as "'Deal' is Closed — skipping". No checks run, no email is sent and nothing is saved.

**What happens when I change the Term extraction prompt?**
The next run re-reads the whole data room with the AI because the prompt no longer matches the cached one. If neither the prompt nor any data-room document changed, the previous terms are reused without an AI call.

**Can I cancel a run?**
While the progress panel shows the run in progress, click **Cancel**; the report is marked cancelled with who and when. The background job may still finish, so scores and the email can still be produced.

### Troubleshooting and edge cases

**I re-ran the agent and the extracted terms didn't change even though I expected new values. Why?**
Term extraction reuses its previous result when nothing has changed. If no document in the data room was added, removed or modified and the extraction prompt is the same, the agent skips the AI call; touch a document or edit the prompt to force a fresh read. See [Where It Can Fail](#8-where-it-can-fail).

**An investor has no score even though Score investors is turned on. What happened?**
Scoring fails quietly if the AI reply was not valid JSON with the expected keys or the score was outside 0 to 100; no score or grade is saved. Also check that an LLM key is set and the investor is not Declined or Complete, since those investors are skipped.

**I uploaded a new Scoring Skill File but scores look unchanged.**
Make sure the file actually has text and that the upload replaced the file in **Scoring Skill File** on the **Edit** page. An empty or unreadable file silently falls back to the default rubric with no error shown.

**Why didn't I get a digest email after a run that found blockers?**
**Notify email** is probably blank; the run still completes and the report still saves. Set an address on the agent's **Edit** page; the **General** tab banner flags a blank value.

**Can I run this for every deal in the pipeline at once?**
Yes, with **Run Now** on the agent page when no Target Deal is selected: each non-closed deal runs separately. For one consolidated fundraising email across all open deals, use the [Deals Report Agent](deals_report_agent_user_guide) instead.

**An investor sits on a step longer than that step's days but is not flagged stagnant. Why?**
The blocking Deal Progress check uses only **Stagnant threshold (days)**, and an investor counts as stagnant only when neither the investor record nor any of its activities was updated within it. Per-step days are applied only in the Weekly Summary stagnation breakdown.

**I clicked Run Deal Agent and got a not-authorised error. Why?**
Running the agent requires the **Company Admin** role, even from the deal page. Ask a company admin to run it or to grant you the role.

**The Weekly Summary page says no summary is available. Why?**
The agent has not completed a run for this deal, or the weekly summary is switched off in the agent's configuration. Run the agent on the deal, and ask CapHive support if weekly summary data is still missing.

**Why does the weekly summary only show today's changes?**
The report period defaults to 1 day unless `report_period` is set, and it has no field on the Edit page. Ask CapHive support to set it to 7 for a weekly view.

**Why are some documents missing from term extraction or scoring?**
Only PDF, TXT, MD, XLSX, XLS, PPTX, PPT, DOCX, DOC and CSV files are read, each document is cut at 5,000 characters and the total at 50,000. Files over the limit are dropped without a warning in the UI.

---

## Related Guides

- [Support Agents](../support_agents_user_guide) — setup, LLM keys, schedules, Execution History and the warning banner shared by every agent.
- [Deals Management](../deals_management_user_guide) — deals, deal investors, deal steps and the data room the agent reads.
- [Deals Report Agent](deals_report_agent_user_guide) — one consolidated pipeline email across every open deal.
- [Tasks](../tasks_user_guide) — the deal tasks counted in the Weekly Summary.
- [Document Management](../document_management_user_guide) — uploading the data-room documents the checklist and term extraction use.
- [LLM Configuration](../llm_configuration_guide) — the AI keys needed for terms, summaries and scoring.
- [Note Summarizer Agent](note_summarizer_agent_user_guide) — AI summaries of stakeholder notes outside a deal.
