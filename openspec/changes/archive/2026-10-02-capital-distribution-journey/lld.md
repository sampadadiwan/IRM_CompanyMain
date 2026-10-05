# Capital Distribution Journey — Low-Level Design

> **Audience:** The developer who reviews the implementation plan before coding starts.
> **Companion documents:** [Design](design.md) · [Spec](specs/) · [Tasks](tasks.md)

> **Planning phase — no code changes.** This document records the implementation-level decisions
> a reviewing developer must check. It adds to [design.md](design.md): link to its diagrams and
> worked examples rather than repeating them.

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

- **Shared panel/setup/email-edit extraction touches live call code** — the call page must render identical
  markup; see [File Map](#file-map) ① and ⑦ and the phase-1 regression gate in tasks.md.
- **`setup_capital_call_journeys` route is replaced by `setup_journeys(kind)`** — button ids are kept so
  the call rollout feature still finds `setup_capital_call_journeys_btn`; see [Controllers](#controllers-params-and-responses).
- **Approver role on `approve?` is breaking** for 3 production entities — see [Configuration and Rollout](#configuration-and-rollout).
- **Generate notices goes stale by invalidation, not timestamps** (design Decision 11) — which actions call
  `WorkflowStepInvalidate`, see [Method Contracts](#method-contracts).
- **Document approval hooks** add one `pluck(:capital_distribution_id).distinct` per approval batch on the
  `documents` table — see [Queries and Indexes](#queries-and-indexes).

---

## File Map

| Boundary | File | New / Modified | Responsibility |
|---|---|---|---|
| ① Setup | `app/packs/core/workflow_templates/services/journey_setup.rb` | New | Trailblazer base: `plan`, `apply`, `find_or_seed`; `KINDS`; `.rollout(kind, execute:, entity_id:)` printing the report |
| ① | `app/packs/funds/capital_calls/services/capital_call_journey_setup.rb` | Modified | Subclass of `JourneySetup`; keeps `FULL_KEY`, `LIGHT_KEY`, `FULL_STEPS`, `LIGHT_STEP_NAMES` |
| ① | `app/packs/funds/capital_distributions/services/capital_distribution_journey_setup.rb` | New | Subclass: keys `capital_distribution_full/_light`, 9 steps, Light names |
| ① | `lib/tasks/capital_call_journeys.rake` | Modified | Delegates to `JourneySetup.rollout("capital_call")` |
| ① | `lib/tasks/capital_distribution_journeys.rake` | New | `capital_distribution_journeys:rollout` → `JourneySetup.rollout("capital_distribution")` |
| ① | `app/packs/core/entities/services/setup_company.rb` | Modified | `step :setup_capital_distribution_journeys` (Investment Fund) |
| ① | `app/packs/core/workflow_templates/controllers/workflow_templates_controller.rb` | Modified | `setup_journeys` replaces `setup_capital_call_journeys`; `@journey_setup_plans` per kind |
| ① | `app/packs/core/workflow_templates/policies/workflow_template_policy.rb` | Modified | `setup_journeys?` replaces `setup_capital_call_journeys?` |
| ① | `app/packs/core/workflow_templates/views/workflow_templates/_index.html.erb` | Modified | Loop over kinds → one button each |
| ① | `config/routes/core.rb` | Modified | `post :setup_journeys, on: :collection` |
| ② | `app/packs/core/workflow_templates/models/workflow_template.rb` | Modified | Add `CapitalDistribution` to `WORKFLOWABLE_TYPE_OPTIONS` |
| ② | `app/packs/core/workflow_templates/controllers/workflow_instances_controller.rb` | Modified | Add to `ALLOWED_WORKFLOWABLE_TYPES` |
| ③ | `app/packs/funds/capital_distributions/policies/capital_distribution_policy.rb` | Modified | `approve?` + approver; `payments_completed?` + approved; drop `mark_payments_completed?`; `journey?`; `assign_workflow?` |
| ③ | `app/packs/funds/capital_distributions/controllers/capital_distributions_controller.rb` | Modified | `journey` action; show evaluation; hooks in `approve`, `payments_completed`; `find_each` |
| ③ | `app/packs/funds/capital_distributions/views/capital_distributions/show.html.erb` | Modified | Panel, stream, DOM ids, notices link, `payments_completed?` |
| ③ | `app/packs/funds/capital_distributions/views/capital_distributions/_details.html.erb` | Modified | Workflow tab |
| ③ | `app/packs/funds/capital_distributions/views/capital_distributions/_form.html.erb` | Modified | Hint text |
| ③ | `app/packs/funds/capital_distributions/views/capital_distributions/_journey.html.erb` | New | Wrapper for the shared panel |
| ③ | `app/packs/funds/capital_distributions/jobs/capital_distribution_job.rb` | Modified | nil-safe error path; hook |
| ③ | `app/packs/funds/capital_distribution_payments/jobs/capital_distribution_payment_recompute_fees_job.rb` | Modified | Load before first message; `started_at`; invalidate + undo |
| ③ | `app/packs/funds/capital_distribution_payments/jobs/capital_distribution_date_change_job.rb` | Modified | Pass `started_at` to recompute |
| ③ | `app/packs/funds/capital_distribution_payments/controllers/capital_distribution_payments_controller.rb` | Modified | Hooks in create/update/destroy/payments_completed/send_notification |
| ③ | `app/packs/funds/capital_distribution_payments/jobs/capital_distribution_payment_doc_job.rb` | Modified | `evaluate_journey(had_notices, started_at)` |
| ③ | `app/packs/funds/capital_distribution_payments/jobs/capital_distribution_payment_notification_job.rb` | Modified | Hook at end |
| ③ | `app/packs/funds/capital_distribution_payments/jobs/import_capital_distribution_payments_fix_counts_job.rb` | New | Runs `ImportFixCountsJob`, then `journey_progress_for` |
| ③ | `app/packs/funds/funds/jobs/fund_units_job.rb` | Modified | Hook for `CapitalDistribution` |
| ③ | `app/packs/funds/funds/jobs/fund_units_bulk_action_job.rb` | Modified | Undo for distribution-owned units on delete |
| ③ | `app/packs/core/documents/models/document.rb` | Modified | `capital_distribution_id` ransacker + ransackable; `distribution_ids_for_notices` |
| ③ | `app/packs/core/documents/controllers/documents_controller.rb` | Modified | CDP branch in approve/unapprove hooks |
| ③ | `app/packs/core/documents/jobs/document_approval_job.rb`, `documents_bulk_action_job.rb` | Modified | Also re-check distributions |
| ③ | `app/packs/core/documents/views/documents/_approval_hint.html.erb` | Modified | Hint wording covers distribution notices |
| ④ | `app/packs/funds/capital_distributions/models/capital_distribution.rb` | Modified | `include Workflowable`; `journey_progress_for`; `broadcast_journey_change`; `workflow_default_owner`; pass `user_id` to job when known |
| ⑤ | `app/packs/funds/capital_distributions/workflow_checks/capital_distribution/*.rb` | New | `support`, 9 task checks, 5 skip checks (`no_email`, `notices_not_used`, `review_not_needed`, `imported`, `no_unit_prices`) |
| ⑤ | `app/packs/funds/capital_distributions/workflow_checks/capital_distribution_warnings.rb` | New | Panel warnings |
| ⑤ | `config/initializers/workflow_checks.rb` | Modified | Register 14 classes |
| ⑦ | `app/packs/core/workflow_templates/views/workflow_instances/_journey_panel.html.erb` | New | Body of the call's `_journey`, parameterised |
| ⑦ | `app/packs/funds/capital_calls/views/capital_calls/_journey.html.erb` | Modified | 3-line wrapper |
| ⑦ | `app/packs/core/workflow_templates/helpers/journey_helper.rb` | New (moved) | Was `CapitalCallJourneyHelper` |
| ⑦ | `config/routes/fund.rb` | Modified | `get 'journey', on: :member` for distributions |
| ⑦ | `app/packs/core/workflow_templates/models/concerns/workflowable.rb` | Modified | `has_journey` macro; shared `broadcast_journey_change`, `journey_frame_id`, `journey_progress_for`, creator default owner (design Decision 14) |
| ⑦ | `app/packs/core/workflow_templates/controllers/concerns/with_journey_panel.rb` | New | `evaluate_journey`, `render_journey_panel` for every journey page |
| ⑦ | `app/packs/core/workflow_templates/policies/workflowable_policy_methods.rb` | New | `journey?`, `assign_workflow?` — included by the 7 workflowable policies instead of their copies |
| ⑧ | `app/packs/core/workflow_templates/services/journey_email_edit.rb` | New (moved) | Was `CapitalCallJourneyEmailEdit`; per-type `CONFIGS` |
| ⑧ | `app/packs/core/notifications/controllers/custom_notifications_controller.rb` | Modified | Calls `JourneyEmailEdit` |
| Docs | `docs/user_guides/capital_distributions_user_guide.md` | Modified | Journey section, FAQs, fixed hint text |

**Reviewer checks**
- [ ] Every class in the design's class diagram has a file here, and nothing here is missing from it
- [ ] Files follow the pack layout and Packwerk boundaries (core never references `CapitalDistribution` except via `KINDS` / `CONFIGS` strings)
- [ ] `grep -rn CapitalCallJourneyHelper\|CapitalCallJourneyEmailEdit\|setup_capital_call_journeys app features` is empty after the move (except button ids)

---

## Schema Detail

N/A — no tables or columns change (design [Data model](design.md#data-model-and-schema-changes)).

**Reviewer checks**
- [ ] No migration in the diff; `schema.rb` / `schema_test.rb` untouched

---

## Method Contracts

**`JourneySetup`** (Trailblazer base)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `.call(entity:, execute: true)` | Entity, bool | Result with `[:report]` `{entity:, templates: [keys], rules: [names], flag: bool}` | `ActiveRecord::RecordInvalid` (rolled back) | Templates, steps, 2 rules, permission | Yes — keyed by `system_key`, rules only if none for the type |
| `.rollout(kind, execute:, entity_id:)` | `KINDS` key | nil (prints) | `KeyError` on unknown kind | Per entity `.call`, rescues and lists failures | Yes |
| Subclass constants | `WORKFLOWABLE_TYPE`, `KEY_PREFIX`, `FULL_KEY`, `LIGHT_KEY`, `FULL_NAME`, `LIGHT_NAME`, `DESCRIPTION`, `FULL_STEPS`, `LIGHT_STEP_NAMES`, `LIGHT_CONDITIONS` | — | — | — | — |

`KINDS = { "capital_call" => "CapitalCallJourneySetup", "capital_distribution" => "CapitalDistributionJourneySetup" }` (strings, constantized only from this hash).

**`CapitalDistribution`** (Model)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `.journey_progress_for(ids, actor: nil)` | ids or a select-relation | nil | never (per record rescue in `journey_progress!`) | Evaluates only ids with a live evaluated instance (`find_each`) | Yes |
| `#broadcast_journey_change` | — | — | logged by evaluator | `Turbo::StreamsChannel.broadcast_replace_to(self, :journey, target: "capital_distribution_journey", html: <empty frame src=journey path>)` | Yes |
| `#workflow_default_owner` | — | User or nil | — | — | Yes |

**`WorkflowChecks::CapitalDistribution::*`** (checks): `#call(::CapitalDistribution) → WorkflowChecks::Result`; read-only; never raise for missing data (return fail). `GenerateNotices` returns `passed_since: newest notice created_at`, `fresh_since: oldest notice created_at`.

**`Document`**

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `.distribution_ids_for_notices(documents)` | Document relation | `Array<Integer>` | — | one `SELECT DISTINCT` | Yes |

**`JourneyEmailEdit`**: `.call(notification:, actor:, started_at:)` — for each config whose `owner_type`/`for_type` matches, finds records with a live journey, skips those whose sent check passes, `WorkflowStepInvalidate(review keys)` then `journey_undo_evaluate`. Never raises (rescue + `ExceptionNotifier`). `CONFIGS`: `CapitalCall` → keys `capital_call.review_email/check_preview`, sent `capital_call.send_notices`, fund `for_type` "CapitalCall"; `CapitalDistribution` → `capital_distribution.review_email/check_preview`, sent `capital_distribution.email_investors`, `for_type` "CapitalDistribution".

**Invalidation of Generate notices** — `WorkflowStepInvalidate.call(record: cd, check_keys: %w[capital_distribution.generate_notices], reason:, actor:)` before `journey_undo_evaluate`, from: recompute job ("Fees recomputed"), payment `#update` when any of `income_cents cost_of_investment_cents reinvestment_cents payment_date` is in `saved_changes` ("Payment figures changed"), payment `#destroy` is not needed (Create payments fails instead).

**Reviewer checks**
- [ ] Every raised error is handled by a caller or listed in Error Mapping
- [ ] Anything a retry can repeat is idempotent (setup, hooks, invalidation = extra history rows only)
- [ ] `GenerateNotices` without notices returns fail, never a pass with nil `fresh_since`

---

## Controllers, Params and Responses

| Action | Permitted params | Policy method | Success response | Failure response |
|---|---|---|---|---|
| `WorkflowTemplatesController#setup_journeys` | `kind` (must be in `JourneySetup::KINDS`) | `setup_journeys?` | redirect index, notice "Capital distribution journeys set up: …" / "… were already set up." | unknown kind → redirect with alert "Unknown journey type."; failure → alert "… could not be set up." |
| `CapitalDistributionsController#journey` | `id` | `journey?` (= `show?`) | `render partial: "capital_distributions/journey"` | Pundit 403 |
| `CapitalDistributionsController#approve` | `id` | `approve?` (now with approver) | as today + `journey_progress!` | Pundit 403 |
| `CapitalDistributionsController#payments_completed` | `id` | `payments_completed?` (now approved) | as today + hook | Pundit 403 → "Access Denied" |
| `CapitalDistributionPaymentsController#create/update/destroy/payments_completed/send_notification` | unchanged | unchanged | as today + hook | unchanged |

Notice texts per kind live in a `KIND_LABELS` hash in the controller ("Capital call" / "Capital distribution"). Button ids: `setup_#{kind}_journeys_btn`.

**Reviewer checks**
- [ ] No action without `authorize`
- [ ] `kind` is looked up in a hash, never constantized from params
- [ ] The call rollout feature still passes with the renamed route (it clicks the button by id)

---

## Queries and Indexes

| Where | Query shape | Index used | Rows expected | Preload / batching |
|---|---|---|---|---|
| `CreatePayments` generated | `fund.capital_commitments.where.not(id: cd.capital_distribution_payments.select(:capital_commitment_id)).count` | `capital_commitments.fund_id`, `cdp.capital_distribution_id` | ≤ ~500 | count only |
| `CreatePayments` upload | `ImportUpload.where(id: payments.where.not(import_upload_id: nil).select(:import_upload_id))` | PK | few | exists? |
| Notice checks | `Document.not_templates.where(owner_type: "CapitalDistributionPayment", owner_id: emailable.select(:id), owner_tag: "Generated")` | `documents(owner_type, owner_id)` | ≤ payments | count / exists / min / max |
| `NoticesNotUsed` | fund `documents.templates.where(owner_tag: "Distribution Template").exists?` or commitments' | `documents(owner_type, owner_id)` | 0–few | exists? |
| `RedeemUnits` | completed payments joined to commitments with `unit_type` present, `cost_of_investment_with_fees_cents > 0`, `where.not(id: FundUnit.where(owner_type: "CapitalDistributionPayment").select(:owner_id))` | `fund_units(owner_type, owner_id)` | ≤ payments | count |
| `distribution_ids_for_notices` | `CapitalDistributionPayment.where(id: docs.where(owner_type: "CapitalDistributionPayment", owner_tag: "Generated").select(:owner_id)).distinct.pluck(:capital_distribution_id)` | PK | few ids | SQL distinct (CLAUDE.md) |
| `journey_progress_for` | `where(id: ids).where(id: WorkflowInstance.evaluated.where(workflowable_type: "CapitalDistribution").where.not(status: :archived).select(:workflowable_id)).find_each` | `workflow_instances(workflowable_type, workflowable_id)` | few | `find_each` |
| Warnings: subscribers | `investor.notification_users(fund, with_tag: "Distribution")` per distinct investor | existing | ≤ investors | only until emailed |
| Warnings: bank | `InvestorKyc.where(id: payments' kyc ids)` → `bank_account_number` blank, counted in Ruby (encrypted column) | PK | ≤ payments | `pluck`-free iteration with `find_each` |

**Reviewer checks**
- [ ] Every query is scoped by the distribution or its fund (entity implied)
- [ ] No `blank?`/`present?` on a relation (IRM/RelationBlankPresent)
- [ ] `capital_distribution_payments.each` in `payments_completed` replaced with `find_each`

---

## Transactions, Locking and Concurrency

| Operation | Transaction scope | Lock | Race it prevents | Idempotency key |
|---|---|---|---|---|
| Setup apply | templates + steps + rules + flag | none | double click → second plan sees templates; rule check by `exists?` | `[entity_id, system_key]` unique |
| Evaluation | evaluator's own | engine's (unchanged) | concurrent hooks | deterministic `step_results` |
| Hooks | after the action's commit | none | — | — |

**Reviewer checks**
- [ ] No hook runs inside the action's transaction (evaluation must see committed data)
- [ ] Evaluations in GET paths use `connected_to(role: :writing)`

---

## Background Jobs

| Job | Queue | Retry | Hook / change | Idempotent |
|---|---|---|---|---|
| `CapitalDistributionJob` | serial | default | `journey_progress!(actor:)` after `post_process`; `User.find_by(id:)` and skip error email when nil | Yes |
| `CapitalDistributionPaymentDocJob` | as today | default | `had_notices` + `started_at` before generating; `evaluate_journey` after | Yes |
| `CapitalDistributionPaymentNotificationJob` | as today | default | `journey_progress!` at end (also when preflight aborts: no-op) | Yes |
| `CapitalDistributionPaymentRecomputeFeesJob` | as today | default | load first; `started_at = args[:started_at] || now`; invalidate + undo | Yes |
| `CapitalDistributionDateChangeJob` | as today | default | captures `started_at`, passes to recompute | Yes |
| `ImportCapitalDistributionPaymentsFixCountsJob` | default | default | `ImportFixCountsJob.perform_now`, then `journey_progress_for` | Yes |
| `FundUnitsJob` | as today | default | `CapitalDistribution` branch | Yes |
| `FundUnitsBulkActionJob` (delete) | as today | default | collect distribution ids of `CapitalDistributionPayment` owners before delete → `journey_undo_evaluate` once each | Yes |
| `DocumentApprovalJob`, `DocumentsBulkActionJob` | as today | default | pluck distribution ids before approving → `journey_progress_for` | Yes |

**Reviewer checks**
- [ ] Every hook is after the job's work and wrapped (never fails the job)
- [ ] Bulk jobs evaluate each distribution once

---

## External Integrations

N/A — no external services.

**Reviewer checks**
- [ ] None

---

## Error Mapping and Logging

| Error | Where | Mapped to | Logged / alerted |
|---|---|---|---|
| Evaluation exception | any hook | swallowed | `Rails.logger.error` + `ExceptionNotifier` (engine) |
| Unknown `kind` | `setup_journeys` | alert redirect | — |
| Setup failure | `setup_journeys` | alert redirect | logged |
| Rake per-entity failure | rollout | printed summary | stdout |
| Generation error, no user | `CapitalDistributionJob` | — | `Rails.logger.error` with errors |
| Pundit refusal | approve, payments_completed | "Access Denied" | standard |

**Reviewer checks**
- [ ] No new rescue swallows an error silently without a log line

---

## Security Review

| Surface | Check |
|---|---|
| `GET journey` | `authorize @capital_distribution, :journey?`; `FundBasePolicy` entity scoping |
| Broadcast | stream name is the record (`signed_stream_name`); payload carries only a `src`; content fetched per viewer |
| `setup_journeys` | company admin + Investment Fund; `kind` whitelisted |
| Approve | approver role enforced in policy (menu and request) |
| Documents ransacker | added to `ransackable_attributes`; MCP ontology unchanged (not exposed) |

**Reviewer checks**
- [ ] Investors never get the panel (`!curr_role_investor?`) or the stream
- [ ] Other-entity users get 403 on `journey`

---

## Configuration and Rollout

1. Deploy (no migration).
2. **Before deploy:** give the Approver role to users who approve distributions without it. Production (IN)
   query on 2026-10-02: entity 6301 (10 approvals, 0 by approvers), 6420 (1/0), 3103 (11/6). Re-run on US.
3. Run per environment (IN and US separately):
   `bin/rails capital_distribution_journeys:rollout` (dry run) → review → `EXECUTE=1 …`.
4. Or let admins click "Set up capital distribution journeys".

**Reviewer checks**
- [ ] Release note mentions the Approver-role change
- [ ] Rollout command documented in the rake file header

---

## Test Plumbing

- New step file `features/step_definitions/capital_distribution_journey_steps.rb`: distribution setup,
  notice creation with `from_template_id`, CFO sign-off, live-update marker, `JourneyActivitySpy`
  prepended on `CapitalDistribution`.
- Generic call steps (step bar table, panel text, Mark reviewed, panel action) are reused; any that hard-code
  `capital_call_journey` take the frame id from the current page's record.
- `window_opened_by` for the notices link.
- Run with `TEST_ENV_NUMBER=$RANDOM`; Redis up.

**Reviewer checks**
- [ ] No RSpec files added
- [ ] Each worked example maps to exactly one scenario

---

## Project Rules Checklist

| Rule | Applies | How |
|---|---|---|
| No `blank?`/`present?` on relations | Applies | `exists?`/`none?` throughout checks and hooks |
| Dedup in SQL | Applies | `distinct.pluck` in `distribution_ids_for_notices` |
| Batch bulk operations | Applies | `find_each` in `payments_completed`, `journey_progress_for` |
| Select only needed columns (account_entries) | N/A | not read |
| No speculative eager loads | Applies | counts only |
| Doc-gen contexts keep relations | N/A | doc gen unchanged |
| Date formatting | Applies | panel uses `l(..., format: :abbr_date_time)` (shared partial, unchanged) |
| Emails force `:en` date format | N/A | no new emails |
| Tenant scoping | Applies | policies + record-scoped queries |
| MCP ontology | N/A | ransacker not added to ontology YAML |
| IRM cops / rubocop | Applies | run rubocop on changed files |
| Inline comments with worked-example refs | Applies | H/E/X ids + `design.md#worked-examples` |

---

## Sign-off

| Reviewer | Date | Decision |
|---|---|---|
| | | |
