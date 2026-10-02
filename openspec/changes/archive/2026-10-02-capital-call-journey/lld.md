# Capital Call Journey — Low-Level Design

> **Audience:** The developer who reviews the implementation plan before coding starts.
> **Companion documents:** [Design](design.md) · [Spec](specs/) · [Tasks](tasks.md)

> **Planning phase — no code changes.** This document records the implementation-level decisions
> a reviewing developer must check. It adds to [design.md](design.md): link to its diagrams and
> worked examples rather than repeating them.

> **Reviewable, not descriptive.** Every section states concrete decisions (types, limits,
> indexes, locks, retries, error mappings) and ends with **Reviewer checks** to tick. Short
> snippets (a signature, a query shape, a config line) are fine. Full class bodies and full
> migrations are not.

---

## Contents

- [Review Summary](#review-summary)
- [File Map](#file-map)
- [Schema Detail](#schema-detail)
- [Method Contracts](#method-contracts)
- [Controllers, Params and Responses](#controllers-params-and-responses)
- [Queries and Indexes](#queries-and-indexes)
- [Transactions, Locking and Concurrency](#transactions-locking-and-concurrency)
- [Background Jobs](#background-jobs)
- [External Integrations](#external-integrations)
- [Error Mapping and Logging](#error-mapping-and-logging)
- [Security Review](#security-review)
- [Configuration and Rollout](#configuration-and-rollout)
- [Test Plumbing](#test-plumbing)
- [Project Rules Checklist](#project-rules-checklist)
- [Sign-off](#sign-off)

---

## Review Summary

These are the decisions most likely to be wrong or contested. Start here.

1. **One guard keeps legacy workflows unchanged.** Every new path checks
   `workflow_instances.evaluated`, which is set at launch only when the snapshot has a non-human step.
   Human-only instances take exactly today's code path. See [Method Contracts](#method-contracts).
2. **Sign-off reset uses the undo's start time** (design Decision 11). An undoing action captures
   `undo_started_at` *before* it mutates anything. Its evaluation archives later responses with
   `responded_at < undo_started_at`, whether or not the pointer moved in this run. See
   [Transactions](#transactions-locking-and-concurrency).
3. **Evaluation writes on GET** (call page) and from two scheduled jobs. GET requests read from the
   replica (`ActiveRecord::ReadOnlyError` otherwise), so the call page evaluates inside
   `ActiveRecord::Base.connected_to(role: :writing)`, the same pattern as `DealsController`, and renders
   from the in-memory results rather than re-reading a lagging replica. Every write happens under
   `instance.lock!`, nothing is written when nothing changed, and no caller wraps the evaluator in its own
   transaction. *(Found during implementation.)*
4. **`skip_doc_gen` is filtered in Ruby, not SQL.** Cucumber runs on SQLite, which has no `JSON_UNQUOTE`.
   We pluck `[id, json_fields]` from `capital_commitments` for the call's fund only. That is narrow, and is
   at most a few thousand rows. See [Queries](#queries-and-indexes).
5. **Recompute leaves a `recomputed` marker** only when no row failed, and "Create remittances" passes
   again on that marker rather than on row timestamps (design Decision 12).
8. **Real-time journey panel.** After an evaluation that changed something commits, the evaluator calls
   `workflowable.broadcast_journey_change` (no-op by default). `CapitalCall` broadcasts, over ActionCable
   (Redis adapter, so it works from Sidekiq), a Turbo Stream replacing the panel with an empty frame whose
   `src` is `GET /capital_calls/:id/journey`; each open browser re-fetches the panel as its own user, so
   per-viewer rights stay correct. The page subscribes with `turbo_stream_from @capital_call, :journey`.
   This required `step_results` to be deterministic: the notices link used `RansackQueryBuilder.multiple`,
   whose random keys made every evaluation a write (and would have looped the broadcast); it now uses
   plain ransack params. *(Added after implementation, on request.)*

   **Forward hooks.** Undo actions already evaluated synchronously (C4); forward work now does too, via
   `Workflowable#journey_progress!` (one call, no-op without a journey, never raises) or
   `CapitalCall.journey_progress_for(ids)` (bulk; selects only calls that have a live evaluated
   journey, so pre-rollout calls are skipped in SQL):

   | Where | Moves which task |
   |---|---|
   | `CapitalCallJob` (Generate / Notify) | Create remittances, Send notices |
   | `CapitalRemittanceDocJob` (existing `evaluate_journey`) | Generate notices |
   | `DocumentsController#update` (approve one), `DocumentsBulkActionJob` "approve", `DocumentApprovalJob` | Approve notices |
   | `CapitalCallApprove` | Approve call |
   | `CapitalRemittancesController#send_notification`, remittance bulk "mark notification sent" etc. | Send notices |
   | `CapitalRemittancePaymentsController` create/update/destroy, `ImportCapitalRemittancePaymentsFixCountsJob` | Collect payments |
   | `CapitalRemittanceVerify` (verify), `ImportCapitalRemittancesFixCountsJob` | Verify remittances, Create remittances |
   | `FundUnitsJob` (CapitalCall) | Allocate units |

   **Setup from the UI.** `POST /workflow_templates/setup_capital_call_journeys`
   (`WorkflowTemplatesController#setup_capital_call_journeys`, policy `setup_capital_call_journeys?`: a
   company admin of an Investment Fund entity) runs the same `CapitalCallJourneySetup` as the rake task.
   The Workflow Templates index shows the button only while the dry run reports something missing, and
   its confirmation lists that plan.

   Cost per hook: one indexed lookup for the instance; a call without a journey stops there. With a
   journey, one evaluation (a few COUNT/EXISTS queries) and a broadcast only if something changed.
7. **`WorkflowInstanceLaunch` no longer calls `workflowable.lock!`** — it locks a separate copy
   (`workflowable.class.lock.find(id)`). `lock!` reloads the caller's object and wipes `saved_changes`;
   auto-launch runs inside the record's create callbacks, so it silently disabled `CapitalCall`'s
   remittance generation (`saved_change_to_percentage_called?`). Latent in the existing engine; caught by
   the existing `capital_calls.feature`. *(Found during implementation.)*
6. **Rollout turns on `enable_workflow_templates`** for every entity it seeds, and **never launches
   journeys on existing calls**. See [Configuration and Rollout](#configuration-and-rollout).

---

## File Map

Grouped by the design's numbered boxes. Each task in `tasks.md` names the rows it touches.

| Box | File | New / Modified | Responsibility |
|---|---|---|---|
| ① template | `db/migrate/*_add_journey_fields_to_workflows.rb` | New | columns and indexes in [Schema Detail](#schema-detail) |
| ① template | `app/packs/core/workflow_templates/models/workflow_step.rb` | Modified | `kind` enum; validations (check required for system/ack; keys registered for the template's type; owner in entity); `evaluated?` |
| ① template | `app/packs/core/workflow_templates/models/workflow_template.rb` | Modified | `system_key`; `journey?` |
| ① template | `app/packs/core/workflow_templates/services/workflow_instance_launch.rb` | Modified | snapshot the six new step fields; set `instance.evaluated`; **no** evaluation (runs inside the record's create transaction); no activation mail when the first step is not human |
| ① template | `app/packs/core/workflow_templates/controllers/workflow_steps_controller.rb` + `views/workflow_steps/_form.html.erb` | Modified | permit and edit the new fields; Check / Skip lists from the registry; human fields shown only for human kind |
| ① template | `app/packs/funds/capital_calls/services/capital_call_journey_setup.rb` | New | seed Full and Light (by `system_key`), the two auto-assign rules, and the flag |
| ① template | `app/packs/core/entities/services/setup_company.rb` | Modified | call `CapitalCallJourneySetup` for fund-type entities |
| ① template | `lib/tasks/capital_call_journeys.rake` | New | `capital_call_journeys:rollout`: seeding only; dry run by default; `EXECUTE=1`; optional `ENTITY_ID` |
| ③ checks | `app/packs/core/workflow_templates/workflow_checks/{registry,result,base}.rb` | New | `Registry.register/fetch/keys_for/label_for`; `Result = Data.define(...)`; `Base#call(record)` |
| ③ checks | `app/packs/funds/capital_calls/workflow_checks/capital_call/*.rb` | New | 11 task checks and 3 skip checks (see [Queries](#queries-and-indexes)) |
| ③ checks | `app/packs/funds/capital_calls/workflow_checks/capital_call_warnings.rb` | New | readiness warnings (subscribers via `CapitalCallRuleContextProvider`; skip_doc_gen count) |
| ③ checks | `config/initializers/workflow_checks.rb` | New | register all keys in `to_prepare` |
| ② data | `app/packs/funds/capital_calls/models/capital_call.rb` | Modified | `workflow_default_owner` (user on the `create` audit) |
| ② data | `app/packs/funds/capital_commitments/models/capital_commitment.rb` | Modified | `self.skip_doc_gen_ids(scope)`: one place for the Ruby filter, reusing `skip_doc_gen?` |
| ④ evaluator | `app/packs/core/workflow_templates/services/workflow_evaluator.rb` | New | walk, pass/skip/current, stamping, move back, reset, persist, queue mails |
| ④ evaluator | `app/packs/core/workflow_templates/models/workflow_instance.rb` | Modified | `evaluated` scope, `step_result(pos)`, `last_events(to_state)` |
| ④ evaluator | `app/packs/core/workflow_templates/models/concerns/workflowable.rb` | Modified | `workflow_gated?` false for evaluated instances; `workflow_step_unlocked?`, `workflow_default_owner`, `journey_undo(cause_note:, actor:) { … }` helper |
| ⑤ panel | `app/packs/funds/capital_calls/views/capital_calls/_journey.html.erb` | New | step bar, panel, banner, warnings, Mark reviewed |
| ⑤ panel | `app/packs/funds/capital_calls/views/capital_calls/show.html.erb` | Modified | render `_journey` and subscribe to its real-time stream (confirmations unchanged) |
| ⑤ panel | `app/packs/funds/capital_calls/controllers/capital_calls_controller.rb` | Modified | `show` assigns `@journey` |
| ⑥ history | `app/packs/core/workflow_templates/models/workflow_state_change.rb` | Modified | `channel` adds `system: 3` |
| ⑥ history | `app/packs/core/workflow_templates/presenters/workflow_step_diagram_presenter.rb` + `views/workflow_instances/show.html.erb` | Modified | system/ack status; new `to_state` labels |
| ⑦ people | `app/packs/core/workflow_templates/services/workflow_acknowledge.rb` | New | Reviewed response + evaluate |
| ⑦ people | `app/packs/core/workflow_templates/services/workflow_advancer.rb` | Modified | for evaluated instances: rejection keeps the step current (archive votes, `rejected_step` change) and never sets `rejected`; evaluate after any move |
| ⑦ people | `app/packs/core/workflow_templates/controllers/workflow_instances_controller.rb` | Modified | `acknowledge` member action; evaluate after `advance` / `reset` on evaluated instances |
| ⑦ people | `config/routes/core.rb` | Modified | `post :acknowledge` member route |
| ⑧ undo | `app/packs/core/workflow_templates/services/workflow_step_invalidate.rb` | New | `invalidated` changes by check key; archive ack responses on those steps |
| ⑧ undo | `app/packs/funds/capital_calls/services/capital_call_unapprove.rb` | Modified | wrap in `journey_undo("Unapproved")` |
| ⑧ undo | `app/packs/funds/capital_calls/services/capital_call_action.rb` (used by `CapitalCallUpdate`) | Modified | `invalidate_if_figures_changed`: percentage/amount/closes/call date → invalidate `create_remittances`, `generate_notices` |
| ⑧ undo | `app/packs/funds/capital_remittances/jobs/capital_remittances_recompute_fees_job.rb` | Modified | at the end, if no row failed: `recomputed` marker + invalidate `generate_notices` + evaluate(undo). Covers Recompute Call and `CapitalCallDateChangeJob` |
| ⑧ undo | `app/packs/funds/capital_remittances/jobs/capital_remittance_doc_job.rb` | Modified | at the end of a call-level or single-remittance run: evaluate, `undo` if any notice was replaced, else `progress` |
| ⑧ undo | `app/packs/funds/capital_remittances/services/capital_remittance_verify.rb` | Modified | evaluate(undo) only when the toggle un-verifies, and not inside the bulk job |
| ⑧ undo | `app/packs/funds/capital_remittances/jobs/capital_remittances_bulk_action_job.rb` | Modified | suppress per-record hooks; one evaluation per affected call after Toggle Verify / Mark Unsent |
| ⑧ undo | `app/packs/core/documents/controllers/documents_controller.rb` | Modified | after an approved → unapproved change on a generated call notice (`apply_privileged_document_attrs!`): evaluate(undo) for its call |
| ⑧ undo | `app/packs/core/notifications/controllers/custom_notifications_controller.rb` | Modified | create/update/destroy of a CapitalCall notification (call-owned, or fund-owned with `for_type: "CapitalCall"`) → invalidate `review_email`, `check_preview` on that call / the fund's calls whose Send notices hasn't passed |
| ⑨ ticks | `app/packs/core/workflow_templates/jobs/workflow_evaluate_job.rb` | New | 15-minute tick |
| ⑨ ticks | `config/initializers/sidekiq.rb` | Modified | cron `workflow_evaluate` `*/15 * * * *` beside the reminder entry |
| ⑨ ticks | `app/packs/core/workflow_templates/jobs/workflow_auto_reminder_job.rb` | Modified | evaluated instances: evaluate first; owner reminders; human reminders timed from `current_step_since` |
| ⑨ ticks | `app/packs/core/workflow_templates/mailers/workflow_mailer.rb` + `views/workflow_mailer/{owner_reminder,sign_off_reset}.html.erb` | Modified / New | two emails |
| docs | `docs/user_guides/capital_calls_user_guide.md`, `docs/user_guides/workflow_templates_user_guide.md` | Modified | journey section for each variant; step kinds |

**Reviewer checks**
- [ ] Every class in the design's class diagram and every hook in card ⑧ has a row here
- [ ] The engine (`core/workflow_templates`) never names `CapitalCall`; it reaches checks only through the registry
- [ ] Files follow the pack layout and Packwerk boundaries

---

## Schema Detail

The business reason for each change is in [design → Data model and schema changes](design.md#data-model-and-schema-changes).
The rows below give the type-level reason: why this type, limit, null and default.

**`workflow_steps`** (existing): steps must say how they complete, what decides it, who is chased, and
what they unlock.

| Column | Change | Type | Limit | Null | Default | Index / FK | Why it's needed |
|---|---|---|---|---|---|---|---|
| `kind` | Added | integer (enum) | — | no | 0 | — | Integer enum like `quorum_rule`. NOT NULL default 0 makes every existing row `human` without a data migration |
| `check_key` | Added | string | 100 | yes | — | — | Null for human steps. Holds `<type>.<check>` keys (longest planned is 38 chars). A string, not an FK, because checks are code |
| `skip_key` | Added | string | 100 | yes | — | — | Optional on any kind. Same format |
| `owner_user_id` | Added | bigint | — | yes | — | index + FK `users` | Null = record's default owner. FK keeps owners real |
| `unlocks` | Added | string | 255 | yes | — | — | CSV, mirroring `workflow_templates.gated_button_labels`, so the same parser is reused |
| `keep_on_regress` | Added | boolean | — | no | false | — | NOT NULL so the evaluator never treats nil specially; false is the safe default |

**`workflow_templates`** (existing): seeded journeys need an identity that survives a rename.

| Column | Change | Type | Limit | Null | Default | Index / FK | Why it's needed |
|---|---|---|---|---|---|---|---|
| `system_key` | Added | string | 50 | yes | — | unique `[entity_id, system_key]` | Idempotent, race-safe seeding. MySQL and SQLite unique indexes both allow many NULLs |

**`workflow_instances`** (existing): instances remember the last evaluation and are cheap to select.

| Column | Change | Type | Limit | Null | Default | Index / FK | Why it's needed |
|---|---|---|---|---|---|---|---|
| `evaluated` | Added | boolean | — | no | false | composite `[evaluated, status]` | Set at launch. The tick selects on it; the "legacy path unchanged" guard is a column check, not JSON parsing |
| `step_results` | Added | json | — | yes | — | — | Native json like `template_snapshot`; no `serialize` on top. Shape below |
| `current_step_since` | Added | datetime | — | yes | — | — | Reminder intervals for system, ack *and* human steps in journeys |
| `completed_at` | Added | datetime | — | yes | — | — | Set on `→ complete`; the tick stops 30 days after it |

**`workflow_state_changes`** (existing): no new columns.

| Column | Change | Type | Limit | Null | Default | Index / FK | Why it's needed |
|---|---|---|---|---|---|---|---|
| `to_state` | Changed (values only) | string | existing | no | — | — | New values: `passed`, `skipped`, `regressed`, `invalidated`, `reopened`, `owner_reminded`, `recomputed`, `rejected_step`. No DDL |
| `channel` | Changed (enum value only) | integer | — | no | 0 | — | Adds `system: 3` in the model. No DDL |
| `[workflow_instance_id, step_position, to_state, created_at]` | New index | — | — | — | — | composite | "Latest invalidated / recomputed per step" lookups on every evaluation |

**`step_results` shape:** `{ "<position>" => { "status" => "passed|current|not_yet|na|error",
"message" => String, "action_label" => String?, "action_path" => String?, "passed_at" => ISO8601?,
"since" => ISO8601?, "regressed" => bool, "regressed_reason" => String?, "regressed_by" => user_id? } }`.
`passed_at` is written once, when the step first passes (design Decision 17).

**Migration safety:**
- All tables are tiny (production had 0 workflow rows in the 2026-09-18 dump), and the change is
  additive with defaults, so DDL is instant.
- It is reversible.
- Update `db/schema.rb` and `schema_test.rb` by hand after migrating, per the local-migrate drift memory.

**Reviewer checks**
- [ ] Every new or changed column and index has a "why", and none is unjustified
- [ ] FKs indexed; unique indexes enforce the uniqueness rules
- [ ] Migration reversible; both schema files updated

---

## Method Contracts

**`WorkflowEvaluator`** (Trailblazer operation)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `.call(instance:, cause: :progress, actor: nil, note: nil, undo_started_at: nil, persist: true)` | `cause` ∈ `:progress`, `:undo`; `undo_started_at` required when `cause: :undo` | ctx `[:results]`: ordered `{position, name, kind, status, message, action_label, action_path, passed_at, since, regressed, regressed_reason}` | nothing; per-step errors become `status: "error"` and stop the walk | when persisting and something changed: instance update, state changes, archived responses; mails after commit | Yes |
| `.for(record, cause:, actor: nil, note: nil, undo_started_at: nil)` | any Workflowable | results or nil | — | as above | Yes |

The guard returns cached `step_results` and does nothing unless `instance.evaluated`. It also does nothing
when the status is `archived`, or `complete` with `completed_at` more than 30 days ago (passive causes
only; an undo always evaluates).

**`WorkflowStepInvalidate`**

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `.call(record:, check_keys:, actor:, reason:, only_if_not_passed: nil)` | `only_if_not_passed` is a check key: skip records whose step with that key has passed (fund email edit) | ctx `[:invalidated_positions]` | — | `invalidated` change per matching step; archive active responses on matching ack steps. **Does not evaluate**: the caller's `journey_undo` block does | Repeat writes another change; harmless |

**`Workflowable#journey_undo(note:, actor:) { … }`**: the single undo wrapper used by every card ⑧ hook.

| Step | Detail |
|---|---|
| 1 | `started = Time.current` **before** the block runs |
| 2 | yield (the action mutates data) |
| 3 | `WorkflowEvaluator.for(self, cause: :undo, actor:, note:, undo_started_at: started)` |
| 4 | rescue `StandardError` from step 3 only: log + Sentry, never fail the action |

**`WorkflowAcknowledge`**

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `.call(instance:, step_position:, user:)` | — | ctx `[:results]` | fails with `ctx[:errors]` if the step is not current or not acknowledge | `WorkflowActorResponse(state: "Reviewed", channel: :ui)`; evaluate(progress) | Yes (active-response uniqueness) |

**`WorkflowChecks::Base` subclasses**

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `#call(record)` | the workflowable | `Result(passed:, message:, action_label:, action_path:, passed_since:, fresh_since:)` | may raise; the evaluator rescues | none | Yes |

**`Workflowable`** additions

| Method | Returns | Notes |
|---|---|---|
| `workflow_gated?` | false when `current_workflow_instance&.evaluated`; else unchanged | advisory phase |
| `workflow_step_unlocked?(label)` | true when the step listing `label` in `unlocks` is passed/na, or none lists it | |
| `workflow_default_owner` | User or nil | `CapitalCall`: `audits.where(action: "create").first&.user` |

**`CapitalCallJourneySetup`**

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `.call(entity:, execute: false)` | — | `{templates:, rules:, flag:}` describing what it would do / did | `ActiveRecord::RecordInvalid` (rolled back per entity) | Full + Light by `system_key`; rule priority 200 `manual_generation eq true` → Light; rule priority 100 `[]` → Full; `enable_workflow_templates` on. Skips any rule that already exists for CapitalCall | Yes |

**`WorkflowEvaluateJob`** / **`WorkflowAutoReminderJob`**: see [Background Jobs](#background-jobs).

**Reviewer checks**
- [ ] Every card ⑧ hook goes through `journey_undo`, so `undo_started_at` is always captured before mutation
- [ ] Every raised error is handled by a caller or listed in Error Mapping
- [ ] Human-only `workflow_gated?` behaviour is byte-for-byte the old code path

---

## Controllers, Params and Responses

| Action | Permitted params | Policy method | Success response | Failure response |
|---|---|---|---|---|
| `WorkflowInstancesController#acknowledge` | `step_position` (integer) | `authorize instance, :show?` then `authorize instance.workflowable, :update?` | Turbo Stream replacing `capital_call_journey`; HTML redirect back, notice "Marked as reviewed" | redirect back with alert from `ctx[:errors]`; Pundit error via the standard handler |
| `WorkflowInstancesController#advance`, `#reset` | existing | existing | existing, then evaluate when `instance.evaluated` | existing |
| `WorkflowStepsController#create/update` | adds `:kind, :check_key, :skip_key, :owner_user_id, :unlocks, :keep_on_regress` | existing (`company_admin`) | existing | 422 with model errors (X1, X2) |
| `CapitalCallsController#show` | — | existing `show?` | `@journey` = evaluator results, run inside `connected_to(role: :writing)`; then `forget_current_workflow_instance!` | the evaluator never raises |

**Reviewer checks**
- [ ] No action without `authorize` / `policy_scope`
- [ ] `owner_user_id` validated against the template's entity

---

## Queries and Indexes

"Notifiable" means remittances whose commitment is not in `CapitalCommitment.skip_doc_gen_ids(fund)`, a
Ruby filter over `pluck(:id, :json_fields)` of the fund's commitments.

| Key | Query shape | `passed_since` / `fresh_since` | Index used | Rows touched |
|---|---|---|---|---|
| `capital_call.create_remittances` | generated basis: `call.applicable_to.where("committed_amount_cents > 0")` minus those with a remittance (`where.not(id: remittances.select(:capital_commitment_id))`); upload basis: `remittances.exists?` and no linked `ImportUpload` running (`status IS NULL AND processed_row_count < total_rows_count AND created_at > 1.day.ago`) or failed (`status` present and not "Completed"); plus, after an invalidation, a `recomputed` change newer than it | passed = MAX remittance `created_at` (or the `recomputed` time); fresh = the `recomputed` time | `capital_remittances[capital_call_id]`; state-change index | counts |
| `capital_call.add_call_notice_template` | `call.fund.documents.templates.where(owner_tag: "Call Template").exists?` | template `created_at` | documents owner index | 1 |
| `capital_call.generate_notices` | notifiable remittances (including unverified KYC ones, so they block with a message) vs those with a document `owner_tag: "Generated"`; plus the unverified-KYC count for the message | passed = MAX, fresh = MIN generated `documents.created_at` | documents owner index | counts |
| `capital_call.approve_notices` | `Document.where(owner: call remittances, owner_tag: "Generated", approved: false).count`. Uses `owner_tag` explicitly, because `Document.generated` is defined twice | MAX `documents.updated_at` (later-only) | documents owner index | count |
| `capital_call.review_email`, `capital_call.check_preview` | always passes (ack; the response is what counts) | — | — | 0 |
| `capital_call.approve_call` | `call.approved` | passed = `approved` audit `created_at` | audits on auditable | 1 |
| `capital_call.send_notices` | notifiable `where(notification_sent: false).count` | detection time (no timestamp) | `capital_call_id` | count |
| `capital_call.collect_payments` | per remittance: no remittance with `collected_amount_cents < call_amount_cents + other_fee_cents - 10` (the call's own `collected_amount` only counts verified remittances, so it can't be used; 10-cent tolerance as in `CapitalRemittance#set_status`) | MAX payment `created_at` | `capital_call_id` | count + sums |
| `capital_call.verify_remittances` | `capital_remittances.where(verified: false).count` | MAX remittance `updated_at` (later-only) | `capital_call_id` | count |
| `capital_call.allocate_units` | `capital_remittances.verified.where.not(id: FundUnit.where(owner_type: "CapitalRemittance").select(:owner_id)).exists?` | MAX `fund_units.created_at` | `fund_units[owner_type, owner_id]` | 1 |
| skip `capital_call.notices_not_applicable` | `manual_generation \|\| !send_call_notice_flag` | — | — | 0 |
| skip `capital_call.imported` | `manual_generation` | — | — | 0 |
| skip `capital_call.no_unit_prices` | `unit_prices.blank?` (a Hash, not a relation) | — | — | 0 |
| skip `capital_call.send_notices_passed` | the instance's `step_results` show the send step passed (used by both review tasks) | — | — | 0 |
| warnings | `CapitalCallRuleContextProvider#investors_without_notification_subscribers` + skip_doc_gen count; only before Send notices passes | — | — | provider's existing cost |
| tick selection | `WorkflowInstance.where(evaluated: true).where("status = ? OR (status = ? AND completed_at > ?)", active, complete, 30.days.ago).find_each` | — | `[evaluated, status]` | tens |

**Reviewer checks**
- [ ] Every query is reached through the call (entity-scoped); no unscoped `CapitalRemittance.where`
- [ ] No relation `.present?`/`.blank?`; counts and `exists?` only; `pluck` of two narrow columns for skip_doc_gen
- [ ] No MySQL-only SQL (tests run on SQLite)
- [ ] `passed_since` is never earlier than the truth (approximations use `updated_at`, which only moves later)

---

## Transactions, Locking and Concurrency

| Operation | Transaction scope | Lock | Race it prevents | Idempotency key |
|---|---|---|---|---|
| Evaluate | instance update + state changes + response archiving | `instance.lock!` then reload | two evaluations (tick + page view + job) double-writing history | "no change → no write" on position, status and `step_results` |
| Undo | the action commits first; then the evaluation in its own transaction | instance lock | a passive evaluation mid-job "using up" the move back | `undo_started_at` captured before mutation; reset compares `responded_at` to it |
| Advancer → evaluator | separate transactions; the evaluator is called after `advance_step` commits | instance lock each | — | — |
| Acknowledge | response create, then evaluate | instance lock | double click | active-response uniqueness |
| Seeding | one transaction per entity | none | — | unique `[entity_id, system_key]` |

**Reviewer checks**
- [ ] No email inside a transaction (queued in ctx, sent after commit)
- [ ] Only one row is ever locked (the instance), so there is no lock-order risk
- [ ] No caller wraps the evaluator in `ActiveRecord::Base.transaction`

---

## Background Jobs

| Job | Queue | Trigger | Retry / backoff | Discard on | Concurrency guard | Timeout |
|---|---|---|---|---|---|---|
| `WorkflowEvaluateJob` (new) | `:default` | sidekiq-cron `*/15 * * * *` (both regions, non-local envs) | `retry: 0`; the next tick is the retry | per-instance `RecordNotFound` (skip, log) | per-instance lock; idempotent | — |
| `WorkflowAutoReminderJob` (modified) | `:default` | existing cron `30 0 * * *` (IN, 06:00 IST) / `30 10 * * *` (US) | Sidekiq default | — | reminder only if the last `owner_reminded` / `auto_reminder` for that step is older than the interval, measured from `current_step_since` | — |
| `CapitalRemittancesRecomputeFeesJob`, `CapitalRemittanceDocJob`, `CapitalRemittancesBulkActionJob` (modified) | existing | existing | existing | existing | evaluation at the end through `journey_undo` | — |

**Reviewer checks**
- [ ] Running either cron twice is harmless
- [ ] Cron entries are registered in `config/initializers/sidekiq.rb` next to the existing reminder entry

---

## External Integrations

N/A: there are no third-party calls.

---

## Error Mapping and Logging

| Exception | Raised in | Handled by | User sees | Logged / alerted |
|---|---|---|---|---|
| any error in a check, or `KeyError` for an unknown key | `WorkflowChecks::*`, `Registry.fetch` | evaluator per-step rescue | "Could not check this step — support has been notified"; the walk stops there | `Rails.logger.error` (entity, instance, key, record) + Sentry |
| any error in the evaluation after an undoing action | `journey_undo` | rescued; the action still succeeds | nothing extra | Sentry (cause, actor) |
| `ActiveRecord::RecordInvalid` in setup | `CapitalCallJourneySetup` | rake loop | rake output line | failures listed in the summary |
| owner nil or inactive | reminder job | skip | panel "Owner unavailable — update the journey template" | info log |

**Reviewer checks**
- [ ] No bare rescue without a log line and a Sentry report
- [ ] Log lines carry entity_id, instance id, workflowable type/id and check key

---

## Security Review

| Concern | Decision |
|---|---|
| Authorization | Acknowledge needs instance `show?` and workflowable `update?`. Template and step editing keeps the existing `company_admin` policies |
| Tenant isolation | Instances are loaded through the policy scope; checks only traverse from the record; owner and template are validated against the entity |
| Secrets | none |
| Input / output sanitisation | Messages are built server-side from counts and names, ERB-escaped; `unlocks` labels escaped; rejection notes escaped |
| Mass assignment | Add-list only in `step_params`; keys validated against the registry for the template's type |

**Reviewer checks**
- [ ] A user from another entity cannot acknowledge, view, or be made owner of another entity's journey step

---

## Configuration and Rollout

| Item | Value / location |
|---|---|
| Credentials / env vars | none. IN and US are rolled out independently by running the rake on each |
| Feature flag | `entity.permissions.enable_workflow_templates` (existing), turned on by setup |
| Cron / schedules | new `workflow_evaluate` every 15 min; the existing reminder cron is unchanged |
| Deploy order | migration → code → `capital_call_journeys:rollout` dry run → review → `EXECUTE=1` per region |
| Scope | Seeding only. **No journey is launched on any existing call**; only calls created afterwards get one |
| Rollback | remove the `workflow_evaluate` cron entry; delete the two CapitalCall auto-assign rules; archive journey instances (`WorkflowArchiver`). Code is inert without evaluated instances |

**Reviewer checks**
- [ ] With no rollout run, production behaviour is unchanged
- [ ] The dry run prints, per entity, the templates, rules and flag it would create, and writes nothing
- [ ] The rake has no code path that launches journeys on existing calls

---

## Test Plumbing

| Feature file (phase) | Stubs / fixtures | Factories | New step definitions |
|---|---|---|---|
| `features/core/workflow_step_kinds.feature` (1) | test check `test.flag` registered in `features/support/workflow_test_checks.rb` | existing workflow factories | `Given a workflow template with steps:` (table incl. kind/check) |
| `features/core/workflow_evaluated_steps.feature` (2), `workflow_button_gating.feature` (2) | test check; `travel_to` | existing | `When I mark step "…" reviewed`, `Then the journey current step is "…"`, `Then the history shows "…"` |
| `features/core/workflow_ticks_and_reminders.feature` (3) | `travel_to`; `perform_enqueued_jobs` for the tick | existing | `When the 15-minute tick runs`, `When the daily reminder job runs`, `Then "…" receives an owner reminder for "…"` |
| `features/fund/capital_call_journey.feature` (4) | Background: Alpha Capital seeded via `CapitalCallJourneySetup` | existing call/remittance/document steps | `Then the journey shows:` (task → mark table) |
| `features/fund/capital_call_journey_ui.feature` (5) | same Background; JS driver for the confirm dialogs | existing | `Then the step bar shows:`, `Then the panel says "…"` |
| `features/fund/capital_call_journey_undo.feature` (6) | same Background | existing | reuse phases 2–5 |
| `features/fund/capital_call_journey_rollout.feature` (7) | `Rake::Task` invocation; one pre-existing call | existing | `When I run the journey rollout` / `with EXECUTE` |
| E19 | existing `features/support/sql_query_counter.rb` | bulk-insert 5,000 remittances | `Then no query selects all capital_remittances columns` |

---

## Project Rules Checklist

| Rule | Applies? | How it is met |
|---|---|---|
| No `blank?`/`present?` on relations; use `exists?`/`none?` | Applies | counts / `exists?` only; `unit_prices` is a Hash |
| Dedup in SQL (`distinct.pluck`), batch bulk operations (`find_each`/`in_batches`) | Applies | tick and setup use `find_each`; no `pluck.uniq` |
| Select only needed columns when loading many `account_entries`; no speculative `includes` of big associations | Applies (partly) | no account_entries; skip_doc_gen plucks two columns |
| Screen dates via `l(...)`; emails render `Mon dd, yyyy` via `EmailDateLocalization`; no human-format `strftime` | Applies | panel and banner use `l(...)`; mailer views use bare `l(...)` |
| Date inputs use `f.date_field` / `date_field_tag`; JS dates via `locale_date_format.js` | N/A | no date inputs or JS dates |
| Every query entity-scoped; Pundit `authorize`/`policy_scope` on every action | Applies | see Security Review |
| MCP tool surfaces changed only via the ontology YAML | N/A | no MCP or ransackable changes |
| Cucumber only (no RSpec); `TEST_ENV_NUMBER=$RANDOM` on every run | Applies | one feature per phase |
| `bundle exec rubocop` clean, including `IRM/RelationBlankPresent` | Applies | run on all changed files |

---

## Sign-off

| Reviewer | Date | Decision | Notes |
|---|---|---|---|
| | | | |
