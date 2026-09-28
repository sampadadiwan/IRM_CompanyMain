# Side Letter Obligation Agent

## Why

Side letters create legally binding obligations (covenants) — reporting deadlines, fee arrangements, co-investment rights, notice requirements — that today live in PDFs attached to commitments and in institutional memory. Nothing extracts them, tracks them, or alerts anyone before a deadline is missed; the first signal of a breach is an LP calling to enforce a term. The full feature intent is documented in `docs/gtm/us_gtm/side_letter_obligations.md`.

## What Changes

- New `funds/side_letters` pack with structured obligation models: `SideLetter` (anchored on `CapitalCommitment`), `SideLetterObligation`, `ObligationFulfillment`, `ObligationReminder`.
- New SupportAgent type `SideLetterObligationAgent` with two run modes:
  - **Extraction**: locates the side letter document on a commitment by configured label, LLM-extracts structured obligations (type, source clause, trigger type, frequency, deadline, suggested owner, confidence) into `pending_review` — never directly active.
  - **Enforcement**: daily scheduled run that alerts obligation owners on upcoming / due-today / overdue items (consolidated per owner), escalates overdue on a configured cadence, and logs every alert.
- Counsel review gate: approve / edit / reject each extracted obligation; only approved obligations produce tasks or alerts.
- Task projection: approved calendar-driven obligations create a `TaskRecurrenceRule` (existing RRULE machinery); one-time obligations create a single `Task`; event-triggered/ongoing obligations stay "armed" with no task until a user fires them.
- Fulfillment audit trail: completing a projected task records an `ObligationFulfillment` (who, when, method, optional evidence document).
- LP Obligation Matrix UI: per-fund table of all obligations across LPs with filters, plus the agent's report tab.
- Agent registration plumbing: `AGENT_TYPES` entry, `SUPPORT_AGENT_FORM_CONFIGS` config, entity license bitflag (appended at the end of the flag array), form-type-driven config UI, policies, routes.

Deferred (data model ready, not built): MFN comparison dashboard, automatic firing of event-triggered obligations from platform events, fee-notice enforcement hooks.

## Capabilities

### New Capabilities
- `side-letter-obligations`: structured side letter + obligation records on commitments, counsel review lifecycle, manual entry, fulfillment audit trail, and the LP Obligation Matrix view.
- `obligation-extraction-agent`: the `SideLetterObligationAgent` extraction mode — document location by label, LLM extraction with mandatory source-clause citations, re-extraction diffing, and per-commitment `SupportAgentReport`s.
- `obligation-task-projection`: projecting approved obligations into `Task`/`TaskRecurrenceRule`, firing armed obligations manually, teardown on reject/waive, and fulfillment recording on task completion.
- `obligation-due-date-alerts`: the daily enforcement run — upcoming/due/overdue detection, consolidated per-owner notifications via the Noticed stack, overdue escalation, and `ObligationReminder` logging.

### Modified Capabilities

(none — no existing specs in `openspec/specs/`)

## Impact

- **New pack** `app/packs/funds/side_letters/` (models, migrations, controllers, policies, views, matrix UI).
- **New agent service** in `app/packs/ai/support_agents/services/side_letter_obligation_agent.rb` + registration touches: `support_agent.rb` (`AGENT_TYPES`), `support_agents_setup_service.rb` (`SUPPORT_AGENT_FORM_CONFIGS`), `entity_enabled.rb` (bitflag at end of array), `agent_reports_query.rb`, show-page report tab, `user_guide_helper.rb`.
- **Tasks pack**: `Task` gains `SideLetterObligation` as a polymorphic owner type; task completion hook to record fulfillment; task board/list unaffected structurally.
- **Notifications**: new Noticed notifier + mailer for consolidated obligation alerts (existing stack; no new channels).
- **Scheduling**: relies on `AgentSchedule`/`SchedulerPollingJob` — production cron registration for `SchedulerPollingJob` must be verified/added (`config/initializers/sidekiq.rb`).
- **Docs**: `docs/gtm/us_gtm/side_letter_obligations.md` (already updated) is the product reference; `ai_document_intelligence.md` scope-note added.
- **Tests**: Cucumber features only (no RSpec), `:inline` ActiveJob adapter, dialect-portable SQL (test env runs SQLite).
