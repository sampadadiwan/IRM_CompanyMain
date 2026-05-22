# PRD: Note Summarizer Agent

**Status:** Implemented  
**Author:** Fund Operations  
**Date:** 2026-05-22

---

## 1. Problem Statement

Fund managers and analysts record notes for each investor throughout the year — meeting notes, call summaries, deal updates, relationship memos. These notes live in the system but are never surfaced in aggregate. Today there is no way to:

- Get a quick recap of what happened with an investor last month or last quarter.
- Identify action items buried across a dozen notes.
- Build a periodic "relationship health" picture without manually reading every note.

This creates friction at quarterly reviews, LP meetings, and board prep, where teams have to manually sift through unstructured note history.

---

## 2. Solution

**NoteSummarizerAgent** — a first-class support agent that runs on a monthly or quarterly schedule, per investor. It:

1. Auto-tags any untagged notes in the period using a configurable vocabulary (or LLM judgement when none is set).
2. Generates a structured LLM summary (key themes, action items, relationship status).
3. Saves the summary as a `SupportAgentReport` (visible in the agent's "Note Summaries" tab).
4. Writes the summary back as a `Note` tagged `summary,quarterly` (or `summary,monthly`) so it appears in the investor's standard notes feed.
5. Automatically excludes prior summary notes from future runs (no double-summarising).

Configurable via the existing custom-field system, scheduled via `AgentSchedule`, and triggerable manually or automatically.

---

## 3. Goals

| Goal | Success Metric |
|------|---------------|
| Reduce time spent manually reviewing notes at quarterly reviews | Reviewers report < 5 min to get per-investor summary |
| Surface action items automatically | ≥ 80% of action items from notes appear in LLM summary |
| Zero new infrastructure | Reuses `SupportAgentReport`, `AgentSchedule`, `Note` |
| Configurable per entity | Works across entities with different period preferences |

---

## 4. Out of Scope (v1)

- Summarizing notes that don't have an `investor` (entity-level or orphan notes).
- Chat-based interaction with the summary (no chat provider in v1).
- Summarizing across multiple investors into a single entity digest (per-investor only).
- Sentiment scoring or trend analysis across periods.

---

## 5. User Stories

**As a fund manager**, I want a monthly summary of all notes my team recorded for each portfolio company last month, viewable in the agent UI and in the investor's notes feed, so I can quickly catch up before team meetings.

**As an analyst**, I want to run the summarizer on-demand for a specific investor before a board meeting, so I can get a quick briefing without reading 20 notes.

**As an admin**, I want to configure whether summaries run monthly or quarterly, restrict them to notes tagged with specific labels, and control whether untagged notes are auto-tagged before summarising.

---

## 6. Functional Requirements

### 6.1 Agent Configuration (Custom Fields)

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `summary_period` | Select (Month / Quarter) | Quarter | Lookback window — previous complete month or quarter. |
| `tag_filter` | TextField | _(blank)_ | Comma-separated tags to restrict which notes are collected. Blank = all notes. |
| `auto_tag_notes` | Select (Yes / No) | Yes | When Yes, the agent assigns tags to any untagged notes in the period before summarising. |
| `available_tags` | TextField | `call,meeting,kpi,board-meeting,fundraising,risk,hiring,operations` | Vocabulary the LLM must use when auto-tagging. Blank = LLM uses its own judgement. |

### 6.2 Execution Pipeline (Steps)

| Step | Description |
|------|-------------|
| **Initialize** | Load `SupportAgent`, compute period date range from `summary_period`, set up LLM client. |
| **Auto-Tag Notes** | Find untagged notes in the period; call LLM once (batch) to assign tags from `available_tags`. Skipped if `auto_tag_notes = No`. |
| **Collect Notes** | Query `Note` scoped to the investor + entity + period. Applies `tag_filter` if set. Always excludes notes tagged `summary` (prior summaries). |
| **Generate Summary** | Format notes and send to LLM. Skipped (no LLM call) if no notes were collected. |
| **Save Note** | Write the summary back as a `Note` on the investor tagged `summary,quarter` or `summary,month`. Idempotent — overwrites an existing summary note for the same period date. |
| **Save Report** | Persist a `SupportAgentReport` with `summary_text`, `note_count`, `period_label`, `period_start`, `period_end` in `json_fields`. |

### 6.3 Auto-Tagging

- All untagged notes in the period are sent to the LLM in **one batch call** (not per-note).
- When `available_tags` is set, the LLM is constrained to that vocabulary only.
- When `available_tags` is blank, the LLM uses its own judgement to choose concise, lowercase tags appropriate for fund manager notes.
- LLM returns a JSON array: `[{"id": 123, "tags": "call,risk"}, ...]`. Only note IDs from the untagged set are honoured; hallucinated IDs are discarded.
- Auto-tagging is soft-fail — a tagging failure logs and continues without blocking the summary.

### 6.4 Summary Note

- Written to the `Note` table on the last day of the period (`period_end`).
- Tags: `summary,quarter` or `summary,month` (lowercase, matching `summary_period`).
- These notes are excluded from future runs via a REGEXP filter on `tags NOT REGEXP summary`.
- Re-running the agent for the same period overwrites the existing summary note rather than creating a duplicate.

### 6.5 LLM Prompt Contract

**Notes input format (per note):**
```
[YYYY-MM-DD] (tag1,tag2)
Note body plain text (truncated to 2,000 chars per note)
```

**Summary system prompt:**
> You are a fund manager's assistant. Summarize the following investor notes from {period} into:
> 1. **Key Themes** — recurring topics and discussion points (bullet points)
> 2. **Action Items** — specific follow-ups or commitments (bullet points, or "None identified")
> 3. **Relationship Status** — Active / In Discussion / Dormant, with one sentence of justification
>
> Be concise. Do not invent information not present in the notes. Output plain prose — no markdown code fences.

**Tagging system prompt:**
> You are a fund manager's assistant. Assign tags to each note from the provided vocabulary. Return ONLY a JSON array: `[{"id": N, "tags": "tag1,tag2"}, ...]`.

### 6.6 Scheduling

- Uses existing `AgentSchedule` — no new scheduling code.
- Default: `monthly`, `run_on_day: 1`, at `06:00 Asia/Kolkata`.
- Change to `quarterly` via the schedule editor in the agent UI.
- Manual on-demand trigger available from the Support Agents UI.

### 6.7 Batch Processing

- Iterates all investors for the entity (same pattern as `PortfolioCompanyAgent`).
- Sequential — one Trailblazer call per investor, no threading.
- One investor failing does not block others.
- Batch summary notification sent after all investors are processed (suppressed for scheduled runs).

### 6.8 Empty-Note Handling

If an investor has zero qualifying notes in the period:
- No LLM summary call is made (cost saved).
- Report saved with `final_status: "skipped"`, `note_count: 0`.
- No summary note is written to the `Note` table.

---

## 7. Non-Functional Requirements

- **LLM cost**: LLM is only called when `note_count > 0`. Auto-tagging batch is one call per investor (not per note).
- **Note body truncation**: Per-note body capped at 2,000 chars. Total prompt capped at 50,000 chars — oldest notes truncated first, with a warning logged.
- **Idempotency**: Re-running overwrites the `SupportAgentReport` and summary `Note` for the same investor + period, never duplicates.
- **Privacy**: Notes are sent only to the LLM configured for the entity (`@support_agent.effective_model`).
- **Soft failures**: Both auto-tagging and summary-note-write are soft-fail — errors are recorded in `json_fields` but don't block the report save.

---

## 8. Data Model

No new tables or migrations.

| Record | Change |
|--------|--------|
| `SupportAgent::AGENT_TYPES` | `"NoteSummarizerAgent"` added |
| `FormType` | New record: `name: "SupportAgent", tag: "NoteSummarizerAgent"` |
| `FormCustomField` | Four fields: `summary_period`, `tag_filter`, `auto_tag_notes`, `available_tags` |
| `SupportAgentReport#json_fields` | Stores `summary_text`, `note_count`, `period_label`, `period_start`, `period_end`, plus `tagging_issues`, `note_issues`, `summary_issues` arrays |
| `Note` | Summary notes written back with tags `summary,quarter` or `summary,month` |
| `DashboardWidget::PORTFOLIO_COMPANY_WIDGETS` | "Note Summaries" widget added |

---

## 9. UI

### Support Agent Show Page
A **"Note Summaries"** tab is added to the agent show page (alongside General, Schedule, Execution History). It displays a table of per-investor reports with:
- Investor name, period, note count, status, run date.
- Expandable detail row showing the full summary text, tagging outcome, and period metadata.

Partials: `_note_summaries_tab.html.erb`, `_note_summary_detail.html.erb`

### Dashboard Widget
A **"Note Summaries"** widget is available on the Portfolio Company Dashboard and the Investor Dashboard. It reuses `_note_summaries_tab.html.erb` directly, scoped to the current investor when rendered on either page.

Widget path: `dashboard_widgets/widgets/note_summaries`  
Metadata: `{title: 'Note Summaries'}`

### Investor Notes Feed
Summary notes appear as regular notes tagged `summary,quarter` / `summary,month` and are visible in the investor's standard notes tab and any dashboard Notes widget filtered by those tags.

### Chat Sample Questions (future)
- "Summarize last quarter's notes"
- "What are the action items?"
- "Show all meeting notes"

---

## 10. Provisioning

The agent is provisioned via the existing `support_agents:setup` rake task — no separate seed file:

```bash
rake 'support_agents:setup[ENTITY_ID]'

# Clone to another entity
rake 'support_agents:clone[TARGET_ENTITY_ID]'
```

---

## 11. Implementation Scope

| Artifact | Action |
|----------|--------|
| `app/packs/ai/support_agents/services/note_summarizer_agent.rb` | **Created** — 6-step Trailblazer service |
| `app/packs/ai/support_agents/models/support_agent.rb` | **Modified** — `AGENT_TYPES`, `sample_questions` |
| `app/packs/ai/support_agents/controllers/support_agents_controller.rb` | **Modified** — loads `@note_summaries` for show action |
| `app/packs/ai/support_agents/views/support_agents/show.html.erb` | **Modified** — Note Summaries tab |
| `app/packs/ai/support_agents/views/support_agents/_note_summaries_tab.html.erb` | **Created** |
| `app/packs/ai/support_agents/views/support_agents/_note_summary_detail.html.erb` | **Created** |
| `app/packs/core/base/views/dashboard_widgets/widgets/_note_summaries.html.erb` | **Created** — dashboard widget partial |
| `app/packs/core/base/models/dashboard_widget.rb` | **Modified** — widget registered on Portfolio Company Dashboard and Investor Dashboard |
| `lib/tasks/support_agents.rake` | **Modified** — `NoteSummarizerAgent` entry added to `SUPPORT_AGENT_FORM_CONFIGS` |

No migrations required.

---

## 12. Open Questions

| # | Question | Owner | Status |
|---|----------|-------|--------|
| 1 | Should summaries be scoped to notes from all users on the entity, or only the current user's notes? | Product | Open |
| 2 | Should the agent target all investors or only portfolio companies by default? Add an `investor_filter` field in v1.1? | Product | Open |
| 3 | What is the maximum acceptable LLM latency per investor before we need chunking or async streaming? | Engineering | Open |

---

## 13. Acceptance Criteria

- [x] Agent appears in the Support Agents index and can be created/edited via the UI.
- [x] Running the agent for an investor with notes produces a `SupportAgentReport` with non-empty `summary_text`.
- [x] Running the agent for an investor with zero notes saves a skipped report and writes no summary note.
- [x] `tag_filter` correctly restricts which notes are collected.
- [x] `summary_period = Month` and `summary_period = Quarter` each pull the correct date range.
- [x] Untagged notes are auto-tagged by the LLM before summarising when `auto_tag_notes = Yes`.
- [x] `available_tags` constrains the LLM tag vocabulary; blank field allows free-form tagging.
- [x] Summary is written back as a `Note` tagged `summary,quarter` or `summary,month`.
- [x] Summary notes are excluded from future runs (REGEXP filter on `tags`).
- [x] Re-running overwrites the previous report and summary note — no duplicates.
- [x] "Note Summaries" tab visible on the support agent show page.
- [x] "Note Summaries" dashboard widget available on the Portfolio Company Dashboard.
- [x] Provisioned via `rake 'support_agents:setup[ENTITY_ID]'` — no separate seed file needed.
- [ ] Scheduled monthly run executes without error across all active investors.
