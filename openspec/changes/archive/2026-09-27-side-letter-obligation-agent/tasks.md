# Tasks — side-letter-obligation-agent

## 1. Data models (`funds/side_letters` pack)

- [x] 1.1 Migrations for `side_letters`, `side_letter_obligations`, `obligation_fulfillments`, `obligation_reminders` (dialect-portable; SQLite in test, MySQL in dev/prod)
- [x] 1.2 `SideLetter` model: belongs_to commitment + document, extraction_status enum, validation that document belongs to the same commitment
- [x] 1.3 `SideLetterObligation` model: enums (obligation_type, trigger_type, review_status, status, owner_team, mfn_review_status), owner-required-for-approval validation, review state transitions (approve/reject)
- [x] 1.4 `ObligationFulfillment` (required method description, optional evidence document, task link) and `ObligationReminder` (kind enum, uniqueness/idempotency guard)
- [x] 1.5 Factories + model-level Cucumber coverage for the review gate (approve blocked without owner, reject never projects)

## 2. Task projection

- [x] 2.1 Projection service as a Trailblazer operation: approved calendar_event → `TaskRecurrenceRule` from `frequency_rrule` (store rule id); one_time → single `Task`; event/ongoing → none
- [x] 2.2 Projected task attributes: polymorphic owner = SideLetterObligation, assigned_to = owner_user_id, category "Compliance"
- [x] 2.3 Task completion hook: obligation-owned task → `done` creates `ObligationFulfillment`; one-time obligations become `fulfilled`
- [x] 2.4 Manual "fire" action for armed obligations (due date input → dated task)
- [x] 2.5 Teardown on reject/waive/expire: remove recurrence rule + incomplete tasks, keep completed history
- [x] 2.6 Cucumber: recurring projection through `RecurringTaskGeneratorJob`, one-time projection, firing, teardown, fulfillment on completion

## 3. Agent — extraction mode

- [x] 3.1 `SideLetterObligationAgent < SupportAgentService` (Trailblazer step DSL, STEP_LABELS, targets(entity_id) = commitments with configured side-letter doc, process_batch dispatch)
- [x] 3.2 Document location by `side_letter_doc_label` exact name match; info-level "no side letter" issue
- [x] 3.3 Text extraction (FolderDocumentExtractor pattern) + LLM prompt returning structured obligations with source clauses; standard fence-strip/JSON-parse idiom; discard citation-less items
- [x] 3.4 Upsert into `pending_review` with re-extraction diffing keyed on (side_letter, source_clause, obligation_type); never touch approved rows; flag deltas
- [x] 3.5 Per-commitment `SupportAgentReport` + batch summary; `self.config_issues` validating config fields
- [x] 3.6 Cucumber: extraction happy path (stub LLM), citation discard, idempotent rerun, amendment delta

## 4. Agent — enforcement mode

- [x] 4.1 Enforcement run: scan approved obligations' tasks → upcoming (`reminder_days_before`), due today, overdue (`overdue_escalation_days` cadence)
- [x] 4.2 `ObligationAlertNotifier < BaseNotifier` + `SideLetterObligationMailer < SupportAgentBaseMailer` with consolidated per-owner email view; `notify_tag` fallback and escalation recipients
- [x] 4.3 `ObligationReminder` logging as idempotency guard (no duplicate alerts on rerun)
- [x] 4.4 Enforcement `SupportAgentReport` + `AgentExecutionLog` summary
- [x] 4.5 Verify `SchedulerPollingJob` production wiring; register cron if genuinely missing; default `AgentSchedule` (daily) in setup config
- [x] 4.6 Cucumber (`:inline` adapter, assert `ActionMailer::Base.deliveries`): upcoming/due/overdue classification, consolidation, escalation cadence, suppression at `reminder_days_before = 0`, idempotent rerun

## 5. Agent registration

- [x] 5.1 `AGENT_TYPES` entry + `SUPPORT_AGENT_FORM_CONFIGS` entry (category "Ops", config fields: side_letter_doc_label, auto_extract_on_upload, default_reminder_days_before, overdue_escalation_days, notify_tag; default schedule)
- [x] 5.2 Entity license bitflag appended to the END of the `flag :support_agents` array in `entity_enabled.rb`; Administrate dashboard entry
- [x] 5.3 `AgentReportsQuery` method + show-page report tab; DESCRIPTION/LONG_DESCRIPTION constants; `user_guide_helper.rb` mapping

## 6. Matrix UI + controllers

- [x] 6.1 `SideLettersController` / `SideLetterObligationsController` (CRUD, approve/reject, fire, fulfill) with a Pundit policy method for every action; routes
- [x] 6.2 Per-fund LP Obligation Matrix view (Ransack filters: type, owner team, due range, review status, MFN flag) as shared partials, SCSS in stylesheets (no inline styles, consistent font sizes)
- [x] 6.3 Review UI: pending-review queue with approve/edit/reject; delta highlighting for re-extractions
- [x] 6.4 Commitment show page: side letter + obligations section; agent report tab renders the matrix partial
- [x] 6.5 Cucumber feature for matrix filters, review flow, and firing an armed obligation from the UI

## 7. Wrap-up

- [x] 7.1 Business-facing user guide in `docs/user_guides/` (no class names/file paths/code)
- [x] 7.2 Run full Cucumber suite for touched packs (random TEST_ENV_NUMBER < 40000); fix fallout
- [ ] 7.3 /code-review gate before marking the phase complete
