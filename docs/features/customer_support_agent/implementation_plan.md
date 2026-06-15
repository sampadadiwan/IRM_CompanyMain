# Customer Support Agent — Implementation Plan

**Source:** `requirements.md` (extracted from PRD)
**Status:** Draft — modules are sequential; design discussions needed before each module

---

## Phase 1 Scope (Web Only)

- **Web channel only** — no WhatsApp/WATI in Phase 1
- **Feedback review dashboard** serves as the single CS queue for both flagged responses and escalations (even when WhatsApp is added in Phase 2, escalations land here — not in WATI inbox)
- **8 modules** (Modules 5 and 7 from original 10-module plan moved to Phase 2)
- WhatsApp-specific columns (`wati_message_id`, `feedback_prompt_state`, `feedback_prompt_sent_at`) deferred to Phase 2 migration

---

## Overview

8 modules, each independently testable. Build in order — each module builds on the previous.
Design decisions to discuss before implementing are called out per module.

---

## Module 1 — Foundation (DB + Models) ✅ COMPLETE

**Goal:** Schema and model layer — no LLM, no channels, just the data backbone.

| # | Task | Notes |
|---|------|-------|
| 1 | Add `"CustomerSupportAgent"` to `AGENT_TYPES` in `SupportAgent` | One-line change |
| 2 | Migration: add `status` (enum: active/escalated/resolved, default: active) to `agent_chat_sessions` | Req §5 |
| 3 | Migration: add columns to `agent_chat_messages` — `channel` (string, default: "web"), `tool_calls_summary` (JSON text), `guide_search_hit` (boolean) | Req §3, §4, §8. `channel` tracks message origin (web now, whatsapp later). WhatsApp-specific columns (`wati_message_id`, `feedback_prompt_state`, `feedback_prompt_sent_at`) deferred to Phase 2. |
| 4 | Migration: create `agent_chat_message_feedbacks` — columns: `agent_chat_message_id`, `user_id`, `entity_id`, `channel`, `rating` (positive/negative), `notes` (text), `judge_completeness` (integer 0-3), `judge_grounding` (integer 0-3), `judge_actionability` (integer 0-3), `judge_total` (integer 0-9), `judge_issues` (JSON), `status` (enum: open/needs_review/resolved/dismissed/pending_engineering), `guide_files_searched` (JSON), `resolution_notes` (text), `reviewed_by_id` | Req §6, §7 |
| 5 | Migration: create `customer_support_escalations` — columns: `agent_chat_session_id`, `user_id`, `entity_id`, `reason` (enum: customer_requested/low_confidence/complex_issue/max_iterations), `summary` (text), `status` (enum: open/resolved/dismissed), `resolved_by_id`, `resolved_at` | Req §5 |
| 6 | Model: `AgentChatMessageFeedback` — associations, validations, scopes | |
| 7 | Model: `CustomerSupportEscalation` — associations, validations, scopes | |
| 8 | Update `AgentChatSession` — add `status` enum, `escalated?` / `resolved?` helpers, scope `active` | |
| 9 | Update `AgentChatMessage` — add `feedback_prompt_state` enum, `pending_feedback_for` scope, `tool_calls_summary` accessor | |

**Design decisions resolved:**
- Channel column: stored on `agent_chat_messages` (not sessions) — same session can span channels in Phase 2
- `tool_calls_summary` JSON structure: array of tool call objects with tool name, files searched, passages, queries, row counts

**Deliverable:** `rails db:migrate` passes, models load, no LLM involved yet. ✅

---

## Module 2 — Tools (testable in isolation) ✅ COMPLETE

**Goal:** The 4 tools the agent will use, each independently testable via `tool.execute(...)`.

| # | Task | Notes |
|---|------|-------|
| 1 | `FmRunQueryTool` — subclass of `RunQueryTool` | Wider table allowlist (add `investor_kycs`, `whatsapp_logs`, `noticed_notifications`, `investor_accesses`). Drop mandatory `{FUND_IDS}` — only `{ENTITY_ID}` required. Req §3 |
| 2 | `SearchUserGuidesTool` — keyword grep on `docs/user_guides/**/*.md` | Returns matching passages + file paths. Records hit/miss on the message for guide gap tracking. Req §3, §8 |
| 3 | `SearchPastMessagesTool` — search user's prior `AgentChatMessage` records | Scoped to `analyst_id = current_user.id`. Req §3 |
| 4 | `EscalateToHumanTool` — calls `CustomerSupportEscalationService` | LLM provides `reason` + `summary`. Tool returns confirmation text. Req §5 |

**Design decisions resolved:**
- **Open Question #2 RESOLVED:** 40 user guides already exist in `docs/user_guides/*.md`
- **Open Question #4:** Deferred — SearchPastMessagesTool only searches AgentChatMessage for now

**Deliverable:** Each tool can be instantiated and called with test params in `rails console`. ✅

---

## Module 3 — Chat Provider + Web Channel ⏳ IN PROGRESS

**Goal:** FM users can chat with the Customer Support Agent on web. End-to-end working.

| # | Task | Notes |
|---|------|-------|
| 1 | `FmCsChatProvider` — system prompt, `build_context` (entity + funds summary), `tools` (returns all 4), channel-aware formatting (Markdown for web, plain text for WhatsApp) | Req §3, §4 |
| 2 | System prompt must include: three data sources explained, out-of-scope behavior ("decline politely, offer to connect to CS, do NOT attempt a tool call"), response quality criteria (Complete, Grounded, Actionable), few-shot examples from `cs_examples.md` | Req §3 |
| 3 | Add `when "CustomerSupportAgent" then FmCsChatProvider` to `BaseChatProvider.resolve` | One-line addition |
| 4 | Add `sample_questions` for `"CustomerSupportAgent"` in `SupportAgent` | |
| 5 | Create `SupportAgent` record for test entity (seed or migration) | |
| 6 | Test web chat end-to-end: create agent → open chat panel → ask question → get response | |

**Design decisions resolved:**
- System prompt: three data sources, quality criteria, out-of-scope behavior, SQL placeholders, few-shot examples
- `cs_examples.md` loaded per-request (simple File.read, cached via provider instance)
- Agent record created via existing Support Agents UI

**Status:** ✅ COMPLETE. All tasks done. E2e tested — chat works, tools fire, grounded answers returned.

**Deliverable:** FM user can open chat, ask "how do I create a capital call?", get a grounded answer. ✅

---

## Module 4 — Escalation Flow ✅ COMPLETE

**Goal:** Agent can hand off to CS team. Session locked, CS notified via email. Escalation appears in feedback review dashboard (Module 7).

| # | Task | Notes |
|---|------|-------|
| 1 | `CustomerSupportEscalationService#escalate!` — creates record, locks session (`status: "escalated"`), emails CS via mailer | Req §5 |
| 2 | Wire `EscalateToHumanTool` → calls escalation service | Done in Module 2 |
| 3 | `CustomerSupportEscalationMailer` — emails `SUPPORT_EMAIL_TO` with entity, user, reason, summary, last 10 messages | Req §5 |
| 4 | Escalation guard in `GenericChatAgent#initialize_chat` — check `session.escalated?`, skip LLM, return canned message | Req §5 |
| 5 | **ReAct loop cap:** Configurable `max_tool_iterations` on `BaseChatProvider` (default nil), overridden to 15 in `FmCsChatProvider`. `before_tool_call` callback counts calls, raises `MaxToolIterationsExceeded`, auto-escalates with reason `max_iterations` | Req §3, §5 |
| 6 | **Resume from escalation:** `CustomerSupportEscalation#resolve!` flips session back to `status: "active"` | Req §5 |

**Design decisions resolved:**
- ReAct cap lives in `GenericChatAgent` (shared), configurable via `BaseChatProvider#max_tool_iterations`. CS-only override in `FmCsChatProvider`.
- Cap is 15 individual tool calls (not 6 LLM iterations) because `before_tool_call` fires per tool, not per round-trip.
- Escalation guard is in `initialize_chat` (not `execute_chat`) because `load_conversation_history` in `setup_ruby_llm_chat` crashes on sessions with prior tool-call messages.
- Phase 1 locks the entire session on escalation (Option A). Future Option B: per-message escalation so agent can still answer unrelated questions.
- Mailer sends to `ENV["SUPPORT_EMAIL_TO"]` directly, bypasses `setup_defaults`/`send_mail` (not an entity→user email).
- `customer_support_agent` added to `ai_view_paths` in `config/application.rb` for mailer template resolution.

**Bugs fixed during testing:**
- Trailblazer steps need `return true` (not bare `return`) to signal success
- `SearchUserGuidesTool` improved: filename-priority ranking + dedup overlapping matches (was returning only TOC lines)

**Phase 2 addition:** WATI `assignConversation` API call for WhatsApp escalations.

**Deliverable:** Ask "I need to talk to a human" → agent escalates, session locked, CS email sent. ✅

---

## Module 5 — User Feedback (Web) ✅ COMPLETE

**Goal:** Thumbs up/down on each assistant message in the web chat panel.

| # | Task | Notes |
|---|------|-------|
| 1 | `SupportAgentChatFeedbacksController` — `PATCH /support_agents/:id/chats/:message_id/feedback` | Req §6 |
| 2 | Pundit policy — FM users can rate their own messages only | Req §11 |
| 3 | Thumbs up/down rendered inline below each assistant message via `appendMessage()` in Stimulus | Req §6 |
| 4 | Stimulus feedback: optimistic UI, solid/outline icon toggle, `patchJSON` helper | |
| 5 | Inline text note on negative feedback, cleared on switch to positive | Req §6 |

**Design decisions resolved:**
- Inline after each reply (not end-of-session). Always-visible thumbs (not hover).
- Feedback gated to `CustomerSupportAgent` only via `feedbackEnabled` Stimulus value
- Font Awesome icons (`fa-regular`/`fa-solid fa-thumbs-up/down`) — Bootstrap Icons not loaded in app
- History load returns `feedback_rating` with eager-loaded feedback (no N+1)

**Deliverable:** Click thumbs-down → feedback saved → inline note input → optional note saved. ✅

---

## Module 6 — LLM-as-Judge ✅ COMPLETE

**Goal:** Every assistant response gets auto-scored on 3 dimensions.

| # | Task | Notes |
|---|------|-------|
| 1 | `ResponseJudgeJob` — async Sidekiq job, scores each assistant message | Req §7 |
| 2 | Judge prompt: rate Completeness (0-3), Grounding (0-3), Actionability (0-3), list issues | Req §7 |
| 3 | Enqueue from `GenericChatAgent#persist_conversation` — after saving assistant message, enqueue judge job | Req §7 |
| 4 | Upsert into `agent_chat_message_feedbacks` — creates or updates the feedback row (user rating may already exist) | |
| 5 | Auto-flag: if `judge_total < 5`, set `status: "needs_review"` | Req §7 |
| 6 | Migration: `cs_judge_enabled` (boolean, default true) + `cs_judge_model` (string) on `entity_settings` | Entity-configurable |
| 7 | `EntitySetting#cs_judge_enabled?` + `cs_judge_model_name` helper methods | Fallback: ENV → gpt-4o-mini |
| 8 | Entity settings UI: toggle + model select on entity edit form + show page | |

**Design decisions resolved:**
- **Open Question #7 RESOLVED:** Judge model is entity-configurable via `EntitySetting#cs_judge_model`. Fallback chain: entity setting → `ENV["CS_JUDGE_MODEL"]` → `gpt-4o-mini`.
- Judge runs for **CustomerSupportAgent only** — gated in `GenericChatAgent#persist_conversation` on `agent_type`.
- Enqueue in `GenericChatAgent` (shared file) with CS-only gate — keeps the hook close to message persistence.
- Entity admin can **disable** judging entirely via `cs_judge_enabled` toggle (saves LLM costs).
- Job queue: `:low` with 2 retry attempts. Upsert logic preserves user ratings when judge scores arrive.

**Deliverable:** Every CS agent response gets scored within ~10s. Low scores flagged. ✅

---

## Module 7 — Feedback Review Dashboard ✅ COMPLETE

**Goal:** CS team's single command center — reviews flagged responses, negative feedback, AND escalations (all in one queue).

| # | Task | Status |
|---|------|--------|
| 1 | Controller: `CsFeedbackReviewsController` at `/cs_feedback_reviews` (standalone AI route) | ✅ |
| 2 | List view — two tabs (Feedback + Escalation), filterable by status, rating, entity, judge score | ✅ |
| 3 | Detail view — question, response, tool calls, guide files, user rating, judge scores | ✅ |
| 4 | Actions: Resolve (with note), Dismiss, Pending Engineering — cascades to linked escalation | ✅ |
| 5 | Re-test button — replays question via `GenericChatAgent.call()`, side-by-side comparison | ✅ |
| 6 | Escalation queue — reason + summary, links to feedback detail, resolve unlocks session | ✅ |
| 7 | Pundit policy — `support?` role only, scoped by `SupportClientMapping` | ✅ |
| 8 | Session auto-expire — new session after 30 min idle (GenericChatAgent change) | ✅ |
| 9 | Threaded sessions — History/New buttons, session list sidebar, switch between sessions | ✅ |
| 10 | Migration: drop unique index on `agent_chat_sessions` for multiple sessions per user | ✅ |

**Design decisions resolved:**
- **Access:** Support users only (`support?`). No Entity Admin. CS Manager role deferred.
- **URL:** Standalone `/cs_feedback_reviews` — not entity-scoped.
- **Reply:** No inline reply Phase 1. Resolve/dismiss with notes only.

**Deliverable:** CS team opens dashboard → sees flagged responses + escalations → clicks Re-test → compares old vs new. Resolves escalation → session unlocked. ✅

---

## Module 8 — Guide Gap + Golden Test Set

**Goal:** Automated quality improvement loops.

| # | Task | Notes |
|---|------|-------|
| 1 | `GuideGapReportJob` — weekly Sidekiq cron, queries `agent_chat_messages` where `guide_search_hit = false`, clusters by topic (LLM or keyword), emails report | Req §8 |
| 2 | `GuideGapMailer` — sends clustered report to CS team | |
| 3 | Sidekiq cron entry: `guide_gap_report` every Monday 9am | |
| 4 | `cs_support_test_cases` table — `question` (text), `expected_answer_contains` (text array), `expected_tools` (text array), `category`, `status` (active/disabled) | Req §9 |
| 5 | `SupportAgentTestRunner` service — runs each test case through `GenericChatAgent`, compares output, reports pass/fail | Req §9 |
| 6 | Rake task: `rake cs_agent:run_test_set` — runs all active test cases, outputs results | Req §9 |
| 7 | `docs/user_guides/cs_examples.md` — skeleton with 5-10 curated Q&A examples loaded into system prompt | Req §10 |

**Design discussion needed:**
- **Open Question #8:** Golden test set as DB table (plan assumes this) vs. YAML file (version-controlled)?
- Guide gap clustering: LLM-based (better but costs tokens) vs. keyword frequency (free)?
- Test runner: advisory report only, or should it block deploys? (Industry standard: advisory only)

**Deliverable:** Monday morning email with guide gaps. `rake cs_agent:run_test_set` passes.

---

## Dependency Graph (Phase 1 — Web Only)

```
Module 1 (Foundation)
  └── Module 2 (Tools) ← blocked by Open Question #2 (user guides location)
        └── Module 3 (Chat Provider + Web)
              ├── Module 4 (Escalation) — email + dashboard
              ├── Module 5 (Feedback Web)
              └── Module 6 (LLM-as-Judge)
                    └── Module 7 (Feedback Review Dashboard) — also handles escalation queue
  Module 8 (Guide Gap + Golden Test) — needs Module 3 working
```

---

## Phase 2 — WhatsApp (deferred)

When ready to add WhatsApp, implement these:
- **WhatsApp Channel:** WATI inbound webhook, phone-to-user resolution, `CustomerSupportInboundJob`, plain-text delivery, idempotency via `wati_message_id`
- **WhatsApp Feedback:** YES/NO state machine, `CustomerSupportFeedbackJob`, timeout handling
- **Migration:** Add `wati_message_id`, `feedback_prompt_state`, `feedback_prompt_sent_at` to `agent_chat_messages`
- **WATI escalation:** `assignConversation` API call — but escalations still land in the feedback review dashboard (same queue as web)

Open questions for Phase 2: WATI HMAC algorithm (#5), phone-to-user field mapping, `assignConversation` API availability (#1).

---

## PRD Discrepancy Notes

Items from the original PRD that this plan handles differently or needs to explicitly address:

### Gaps to close before implementing

1. **"Resolved" definition logic (Req §12):** PRD defines a precise resolution formula: final answer + (positive feedback OR no follow-up within 10 min OR judge completeness >= 2 AND grounding >= 2). No module currently implements this. Needed for the "self-resolution rate" success metric.

2. **Out-of-scope behavior in system prompt (Req §3):** PRD specifies: decline politely, offer to connect to CS, do NOT attempt a tool call for out-of-scope questions. Must be encoded in `FmCsChatProvider` system prompt (Module 3).

3. **Response quality criteria in system prompt (Req §3):** PRD says agent should aim for Complete, Grounded, Actionable responses. These should be in the system prompt, not just the judge scoring rubric.

4. **`tool_calls_summary` JSON structure:** The feedback review dashboard (Module 7) needs to show which guide files were searched and which passages matched. A boolean `guide_search_hit` alone is insufficient — the `tool_calls_summary` JSON must capture file paths and passages. Define the schema before Module 1 migration.

### Deliberate deviations from PRD

1. **Web-only in Phase 1:** PRD treats web + WhatsApp as equally important. We defer WhatsApp to Phase 2 to reduce complexity. Core agent proves itself on web first.

2. **Single escalation queue (dashboard):** PRD routes WhatsApp escalations to WATI team inbox. We route ALL escalations (web and future WhatsApp) to the feedback review dashboard — single CS queue, no split monitoring.

3. **Golden test set as DB table, not YAML:** PRD left this as an open question (#8). Plan assumes DB table for in-app editability. Can revisit.

4. **Escalation resume:** PRD mentions "once CS resolves, agent can handle new messages." Plan adds explicit Module 4 task #6 for flipping session back to active — PRD didn't specify the mechanism.

5. **6-step ReAct cap:** PRD mentions "max 6 reasoning steps" as an escalation trigger. Plan adds it as Module 4 task #5 — explicit iteration counter in `execute_chat`. PRD didn't specify where this lives.

### Open questions that block modules (Phase 1)

| # | Question | Blocks |
|---|----------|--------|
| 2 | Where do FM-facing User Guides live? | Module 2 (item 2) — **hard blocker** |
| 3 | Should all FM-role users get access, or only Admins/Managers? | Module 3, Module 5 (Pundit policies) |
| 6 | Show feedback inline after each reply or at end of session? | Module 5 |
| 7 | Which model for LLM-as-judge? | Module 6 |
| 8 | Golden test set: DB table or YAML file? | Module 8 |
