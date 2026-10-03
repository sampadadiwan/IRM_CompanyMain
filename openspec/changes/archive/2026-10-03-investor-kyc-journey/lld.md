# Investor KYC Journey — Low-Level Design

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

- **STI fix in shared code** — 10 `class.name` call sites become `workflowable_type_name` (base class). The
  existing `investor_kyc_workflow_auto_assignment.feature` passes today only because its step builds
  `InvestorKyc.new` (class `InvestorKyc` in memory); the controller builds `IndividualKyc`, whose rules never
  match. See [Method Contracts → Workflowable](#method-contracts).
- **`WorkflowChecks::Result` gains a `review` field** (`nil` / `:confirmed` / `:requested`). `Data.define`
  positional order changes — every `Result.new` caller must use keywords. See [Method Contracts](#method-contracts).
- **Closing check** walks the snapshot twice (find the closer, then the normal walk) — one extra check call
  per evaluation for KYC only. See [Queries and Indexes](#queries-and-indexes).
- **Validate documents freshness from audits** — relies on `doc_question_answers` / `all_docs_valid` being
  audited by `Trackable`. See [Queries and Indexes](#queries-and-indexes).
- **As built:** hooks live in `InvestorKycAction#journey_hook` (create/update services) rather than per controller action, so Verify, UnVerify, bulk Verify/Unverify and imports share one decision; document replacement uses a narrow `Document#after_update_commit` for KYC owners; the send-form / reminder button targets switch to `…_custom_0_btn` when the entity has a custom KYC notification.
- **`update_columns` writers** (`send_kyc_form`, `request_updates`, `sync_boolean_fields_from_status`) get
  explicit hooks. See [Background Jobs](#background-jobs) and design [⑧](design.md#⑧-hooks).
- **`JourneySetup` generalisation** — `LIGHT_KEY` nil, `ENTITY_TYPES`, sign-off constants; the setup menu's
  confirm text and policy become per kind. Defaults keep calls/distributions identical.

---

## File Map

| Boundary | File | New / Modified | Responsibility |
|---|---|---|---|
| ① Setup | `app/packs/core/workflow_templates/services/journey_setup.rb` | Modified | `KINDS["investor_kyc"]`; optional `LIGHT_KEY`; `ENTITY_TYPES`; `SIGN_OFF_NAME/DESCRIPTION/BEFORE` with CFO defaults; rollout filters by `ENTITY_TYPES` |
| ① Setup | `app/packs/core/investor_kycs/services/investor_kyc_journey_setup.rb` | New | Constants only (design [①](design.md#①-setup)) |
| ① Setup | `lib/tasks/investor_kyc_journeys.rake` | New | `investor_kyc_journeys:rollout` → `JourneySetup.rollout("investor_kyc", …)` |
| ① Setup | `app/packs/core/entities/services/setup_company.rb` | Modified | `step :setup_investor_kyc_journeys` for Investment / Angel Fund |
| ① Setup | `app/packs/core/workflow_templates/policies/workflow_template_policy.rb` | Modified | `setup_journeys?(kind = nil)`: `create?` and entity type in any (or the given) kind's `ENTITY_TYPES` |
| ① Setup | `app/packs/core/workflow_templates/controllers/workflow_templates_controller.rb` | Modified | Plans only permitted kinds; `setup_journeys` authorizes the kind; summary handles no Light |
| ① Setup | `app/packs/core/workflow_templates/views/workflow_templates/_index.html.erb` | Modified | Confirm text per kind: single template, sign-off name from the kind |
| ① Setup | `workflow_templates_controller.rb` `#duplicate`, `workflow_template_policy.rb` `duplicate?`, `config/routes` (`post :duplicate, on: :member`), `views/workflow_templates/show.html.erb` (Duplicate button `#workflow_template_duplicate_btn`) | Modified | Copy a template with steps and actors (design Decision 13) |
| ① Setup | `app/packs/core/workflow_templates/views/workflow_auto_assignment_rules/_form.html.erb`, `controllers/workflow_auto_assignment_rules_controller.rb` | Modified | "KYC form type" select (entity's KYC form types only); controller merges `{attribute: "form_type_id", operator: "eq", value: id}` into `conditions`, replacing any existing `form_type_id` condition; rejects a form type of another entity |
| ③ Actions | `app/packs/core/workflow_templates/models/concerns/workflowable.rb` | Modified | `workflowable_type_name`; base-class `journey_frame_id` and journey path; use it in `apply_workflow_auto_assignment_on_update` |
| ③ Actions | `app/packs/core/workflow_templates/services/workflow_auto_assignment_service.rb`, `models/workflow_template.rb`, `controllers/workflow_instances_controller.rb` (×2), `controllers/concerns/with_journey_panel.rb`, `views/workflow_templates/_workflow_tab.html.erb` (×2), `mailers/workflow_mailer.rb` | Modified | `class.name` → `workflowable_type_name` |
| ③ Actions | `app/packs/core/investor_kycs/models/investor_kyc.rb` | Modified | `has_journey`; `workflow_default_owner` override; `send_kyc_form` hook |
| ③ Actions | `app/packs/core/investor_kycs/services/investor_kyc_action.rb` | Modified | Fund tick → completed; `journey_after_save` step helper |
| ③ Actions | `app/packs/core/investor_kycs/services/investor_kyc_create.rb`, `investor_kyc_update.rb` | Modified | Final `:journey_hook` step |
| ③ Actions | `app/packs/core/investor_kycs/jobs/investor_kycs_bulk_action_job.rb` | Modified | `unverify` → completed; journey hooks once per job |
| ③ Actions | `app/packs/core/investor_kycs/controllers/investor_kycs_controller.rb` | Modified | `include WithJourneyPanel`; `journey`; show evaluation; hooks in `toggle_verified`, `request_updates`, `override_aml_status`, `extract_docs_data` |
| ③ Actions | `config/routes/core.rb` | Modified | `get 'journey', on: :member` under `resources :investor_kycs` |
| ③ Actions | `app/packs/core/investor_kycs/models/concerns/investor_kyc_concern.rb` | Modified | `document_changed` hook (+ deleted variant) |
| ③ Actions | `app/packs/core/documents/jobs/doc_llm_validation_job.rb` | Modified | `journey_progress!` at end when the model responds to it |
| ③ Actions | `app/packs/core/investor_kycs/jobs/aml_report_async_download_job.rb`, `kyc_doc_extractor_job.rb` | Modified | Hooks |
| ④⑤ Checks | `app/packs/core/investor_kycs/workflow_checks/investor_kyc/{support,send_form,submit,upload_documents,validate_documents,run_aml,clear_aml_match,review_kyc,verify,filled_by_fund,no_required_documents,aml_off,no_aml_match}.rb` | New | One class per check |
| ④⑤ Checks | `app/packs/core/investor_kycs/workflow_checks/investor_kyc_warnings.rb` | New | Panel warnings |
| ④⑤ Checks | `config/initializers/workflow_checks.rb` | Modified | Register the 12 checks |
| ⑥ Evaluator | `app/packs/core/workflow_templates/workflow_checks/result.rb` | Modified | `review` field; `confirmed`, `review` factories |
| ⑥ Evaluator | `app/packs/core/workflow_templates/workflow_checks/base.rb` | Modified | `class_attribute :closes_journey, :closing_note` |
| ⑥ Evaluator | `app/packs/core/workflow_templates/services/workflow_evaluator.rb` | Modified | Closing pre-pass; `judge_acknowledge` handles `confirmed` / `requested` |
| ⑥ Evaluator | `app/packs/core/workflow_templates/services/workflow_step_invalidate.rb` | Modified | `only_if_passed:` |
| ⑦ Panel | `app/packs/core/workflow_templates/views/workflow_instances/_journey_panel.html.erb` | Modified | Secondary review button when `review_action_label` present |
| ⑦ Panel | `app/packs/core/investor_kycs/views/investor_kycs/_journey.html.erb` | New | 3-line wrapper |
| ⑦ Panel | `app/packs/core/investor_kycs/views/investor_kycs/show.html.erb` | Modified | Render wrapper + `turbo_stream_from` above `_show` |
| ⑦ Panel | `app/packs/core/investor_kycs/views/investor_kycs/_send_notifications.html.erb` | Unchanged | Default-template ids already exist |
| Docs | `docs/user_guides/investor_kyc_user_guide.md` (or the existing KYC guide) | Modified | Journey section + FAQs |
| Tests | `features/kyc/investor_kyc_journey{,_ui,_rollout}.feature`, `features/kyc/investor_kyc_fixes.feature`, `features/step_definitions/investor_kyc_journey_steps.rb` | New | See [Test Plumbing](#test-plumbing) |

**Reviewer checks**
- [ ] Every class in the design's class diagram has a file here, and nothing here is missing from it
- [ ] `workflow_checks/` under `investor_kycs` is picked up as a namespace by the `config/application.rb:29` rule (it matches any `/workflow_checks/` path)
- [ ] `grep -rn "class\.name" app/packs/core/workflow_templates` after the change shows only log/exception strings

---

## Schema Detail

N/A — no tables or columns change (design [Data model](design.md#data-model-and-schema-changes)).

---

## Method Contracts

**`WorkflowChecks::Result`** (Data)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `.pass` / `.fail` | unchanged | `review: nil` | — | — | Yes |
| `.confirmed(message:, passed_since:, fresh_since: nil)` | strings, Time | `passed: true, review: :confirmed` | — | — | Yes |
| `.review(message:, action_label: nil, action_path: nil, action_target: nil)` | strings | `passed: true, review: :requested` | — | — | Yes |

`Data.define` gains `:review` **last**; grep shows no positional `Result.new` callers outside the factories
(confirm during review).

**`WorkflowChecks::Base`**

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `closes_journey` (class_attribute) | — | `false` default | — | — | — |
| `closing_note` (class_attribute) | — | `"Done without this step"` default; KYC Verify sets `"Verified without this step"` | — | — | — |

**`WorkflowEvaluator`** (private changes)

| Method | Change |
|---|---|
| `closing_position(snapshot, record)` | New. Last step whose check class `closes_journey` and whose `judge_system` result is `passed`; nil otherwise. Called once per evaluation, only when any snapshot step's check `closes_journey` |
| `judge` | If a closing position exists and `step.position < it` and the normal judgement is `current`, return `{status: "na", message: closing_note}`. Human steps: same rule (a resolved vote stays passed) |
| `judge_acknowledge` | `result.review == :confirmed` → passed when `fresh_since > invalidated_at` (or no invalidation), with `result.message` and `passed_since`; else continue. `:requested` → when no valid confirmation, `{status: "current", message: result.message, action_label: "Mark reviewed", review_action_label:, review_action_path:, review_action_target:}`. `nil` → unchanged |

**`WorkflowStepInvalidate`**

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `.call` | + `only_if_passed:` (check key) | ctx | — | Skips the record unless that step's last result is `passed` | Yes |

**`Workflowable`**

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `#workflowable_type_name` | — | `self.class.base_class.name` | — | — | Yes |
| `#journey_frame_id` | — | `"#{workflowable_type_name.underscore}_journey"` | — | — | Yes |
| `#broadcast_journey_change` | — | — | — | src = `polymorphic_path(becomes(self.class.base_class), action: :journey)` | Yes |

**`InvestorKyc`**

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `#workflow_default_owner` | — | creator `User` when `creator.entity_id == entity_id`, else nil | — | — | Yes |
| `#send_kyc_form(reminder: false)` | unchanged | unchanged | — | + `journey_progress!` after the `update_columns` | Yes |

**`WorkflowChecks::InvestorKyc::Support`**

| Method | Returns |
|---|---|
| `required_document_names(kyc)` | Array of strings: entity setting list for `kyc_type` (split `,`, strip, reject blank) ∪ `kyc.form_type&.form_custom_fields.where(field_type: "File", required: true)` labels |
| `missing_document_names(kyc)` | `required - kyc.documents.distinct.pluck(:name)` (order = required order) |
| `ai_answer_counts(kyc)` | `[failed, total]` from `doc_question_answers` using `DocLlmValidator::NO_LIST` (same rule as `validate_all_docs`) |
| `ai_validated_at(kyc)` | newest `audits` row whose `audited_changes` has `all_docs_valid` or `doc_question_answers`, `created_at`; nil if none |
| button id constants | `SEND_FORM_BTN`, `REMINDER_BTN`, `EDIT_BTN`, `VALIDATE_AI_BTN`, `AML_GENERATE_BTN`, `AML_VIEW_BTN`, `VERIFY_BTN`, `DOCS_TAB`, `VALIDATION_TAB` |

**`InvestorKycAction#save`** — new rule, before `save`: `!ctx[:investor_user] && !completed_by_investor_was &&
completed_by_investor && !(submission_completed? || submission_verified?)` → `submission_status = "completed"`,
`submitted_at = Time.current`, and `ctx[:journey_cause] = :progress`. Existing untick rule sets
`ctx[:journey_cause] = :undo, ctx[:journey_note] = "Marked incomplete"`. Both create/update take
`ctx[:journey_started_at] = Time.current` in a first step.

**Reviewer checks**
- [ ] `Result.pass` callers are untouched and still produce today's acknowledge behaviour (calls' `ReviewEmail`, `CheckPreview`; distributions' equivalents)
- [ ] A closing check that raises is reported and treated as "not closing" (normal walk), not as an error on every step
- [ ] `ai_answer_counts` treats a non-hash/blank `doc_question_answers` as "not run" and never raises on bad JSON shape (X6 shows the engine error path only for truly unexpected errors)

---

## Controllers, Params and Responses

| Action | Permitted params | Policy method | Success response | Failure response |
|---|---|---|---|---|
| `InvestorKycsController#journey` (GET) | `id` | `journey?` (= `show?`) | `_journey` partial (frame) | Pundit → access denied |
| `#show` | unchanged | `show?` | + `@journey` unless investor / no `current_user` | unchanged |
| `#toggle_verified` | unchanged | `toggle_verified?` | + hook: verify → `journey_progress!`; unverify → `journey_undo_evaluate(note: "Unverified", started_at:)` | unchanged |
| `#request_updates` | unchanged | `request_updates?` | + `started_at` before `update_columns`; `journey_undo_evaluate(note: "Updates requested")` | unchanged |
| `#override_aml_status` | unchanged | `override_aml_status?` | + progress, or undo `"AML match confirmed"` when overridden to potential_match | unchanged |
| `#extract_docs_data` | unchanged | unchanged | + when `!current_user.curr_role_investor?`: invalidate `review_kyc` only_if_passed, then undo-evaluate | unchanged |
| `WorkflowTemplatesController#duplicate` (POST) | `id` | `duplicate?` (= `create?`) | redirect to the copy's edit page, "Template duplicated" | access denied |
| `WorkflowTemplatesController#setup_journeys` | `kind` (whitelisted) | `setup_journeys?(kind)` | notice per kind | alert "Unknown journey type." / refused |

**Reviewer checks**
- [ ] No action without `authorize` / `policy_scope`
- [ ] `journey` uses `set_investor_kyc` (entity-scoped find) before `authorize`
- [ ] Signed-link (`signed_id`) requests never call `evaluate_journey`

---

## Queries and Indexes

| Where | Query shape | Index used | Rows expected | Preload / batching |
|---|---|---|---|---|
| `UploadDocuments` | `Document.where(owner: kyc).distinct.pluck(:name)` | `documents(owner_type, owner_id)` | ≤ ~30 | — |
| `NoRequiredDocuments` / Support | `form_custom_fields.where(form_type_id:, field_type: "File", required: true).pluck(:label, :name)` | `form_custom_fields(form_type_id)` | ≤ ~20 | — |
| `RunAml` | `kyc.aml_reports.order(created_at: :desc).pick(:created_at)` | `aml_reports(investor_kyc_id)` | 1 | — |
| `ValidateDocuments` | `kyc.doc_questions.exists?`; `kyc.audits.where("audited_changes LIKE ? OR audited_changes LIKE ?", "%all_docs_valid%", "%doc_question_answers%").maximum(:created_at)` | `audits(auditable_type, auditable_id)` | 1 | — |
| `Verify` | latest audit with `submission_status` change to verified | same | 1 | — |
| Warnings | `kyc.investor.approved_users.exists?` (via existing association) | existing | 1 | — |
| `journey_progress_for(ids)` | `InvestorKyc.where(id: ids).where(id: evaluated instances)` | `workflow_instances(workflowable_type, workflowable_id)` | ≤ bulk size | `find_each` |

**Reviewer checks**
- [ ] Every query is scoped to the one KYC (entity-scoped by construction) or by `entity_id`
- [ ] No `present?`/`blank?` on a relation in any check (`IRM/RelationBlankPresent`)
- [ ] Audit lookups are per-KYC and indexed; confirm `audited_changes` includes `doc_question_answers` (else use only `all_docs_valid`, see design risks)

---

## Transactions, Locking and Concurrency

| Operation | Transaction scope | Lock | Race it prevents | Idempotency key |
|---|---|---|---|---|
| Setup apply | one per entity | — | partial seeding | `[entity_id, system_key]` |
| Hooks | after the action's save (outside its transaction) | engine's own | evaluation on uncommitted data | engine writes only when results change |
| Bulk Unverify | per KYC, existing | — | — | status write is idempotent |

**Reviewer checks**
- [ ] No hook runs inside `InvestorKycAction#save`'s transaction (so jobs and the evaluator see committed data)
- [ ] Request Updates takes `started_at` before `update_columns`

---

## Background Jobs

| Job | Queue | Trigger | Retry / backoff | Discard on | Concurrency guard | Timeout |
|---|---|---|---|---|---|---|
| `SendKycFormJob` | existing | send form | existing | existing | — | — |
| `DocLlmValidationJob` | existing | Validate Document Data, bulk | existing | existing | hook at end, outside `Chewy.strategy` block | — |
| `AmlReportAsyncDownloadJob` | existing | AML report | existing (polls) | existing | hook only after the KYC save branch | — |
| `KycDocExtractorJob` | existing | documents-first | existing | existing | hook only for fund-side extraction after review (investor path: no-op) | — |
| `InvestorKycsBulkActionJob` | existing | bulk actions | existing | existing | verify/unverify go through `InvestorKycUpdate`, whose `journey_hook` evaluates each KYC once (a no-op lookup for KYCs without a journey); send link / reminder via `send_kyc_form`; AML / AI via their jobs' hooks | — |
| `WorkflowEvaluateJob` | existing | every 15 min | existing | — | — | — |

**Reviewer checks**
- [ ] A hook that runs twice is harmless (identical results write nothing)
- [ ] `KycReminderJob` / `send_kyc_reminder_to_all` go through `send_kyc_form`, so they get the hook without extra code

---

## External Integrations

N/A — no new external calls. AML (existing provider) and AI validation (existing LLM client) are only
observed through their stored results.

---

## Error Mapping and Logging

| Exception | Raised in | Handled by | User sees | Logged / alerted |
|---|---|---|---|---|
| Any error in a check | check `#call` | `WorkflowEvaluator#judge` rescue | "Could not check this step — support has been notified" | `ExceptionNotifier` with instance + step |
| Any error in a hook | `journey_progress!` / `journey_undo_evaluate` / `journey_invalidate` | `Workflowable` rescue | nothing; action stands | `Rails.logger.error` + `ExceptionNotifier` with `InvestorKyc#id` |
| Unknown `kind` | `setup_journeys` | controller | "Unknown journey type." | — |
| `Pundit::NotAuthorizedError` | `journey`, `setup_journeys` | app handler | access denied | existing |

**Reviewer checks**
- [ ] No bare `rescue => e` added outside the existing Workflowable wrappers
- [ ] Log lines carry `InvestorKyc#id`

---

## Security Review

| Concern | Decision |
|---|---|
| Authorization | `journey?` = `show?`; Mark reviewed uses `WorkflowInstancesController#acknowledge` → `update?`; setup per kind |
| Tenant isolation | KYC found via the controller's entity-scoped finder; checks read only the KYC's own rows |
| Investor exposure | panel never rendered when `curr_role_investor?` or no `current_user` (signed link) |
| Secrets | none |
| Input / output sanitisation | messages built from document names and the AML override reason are rendered escaped by ERB |
| Mass assignment | no new permitted params |

**Reviewer checks**
- [ ] A user from another entity cannot reach any KYC journey through `journey`, `acknowledge` or the frame src
- [ ] The AML override reason in "Overridden by …: <reason>" is escaped

---

## Configuration and Rollout

| Item | Value / location |
|---|---|
| Credentials / env vars | none |
| Feature flag | per-entity: journey exists only after setup (rake / menu / new company) |
| Cron / schedules | none new (`WorkflowEvaluateJob` already scheduled) |
| Deploy order | code → `bin/rails investor_kyc_journeys:rollout` (dry run) → `EXECUTE=1`, run separately on IN and US |
| Rollback | remove the rule (or the template) per entity; KYCs keep working; no data cleanup needed |

**Reviewer checks**
- [ ] Safe to deploy with no entity set up (only the two fixes and the STI fix are live)
- [ ] Release note covers bulk Unverify (BREAKING) and the fund "complete" tick

---

## Test Plumbing

| Feature file | Stubs / fixtures | Factories | New step definitions |
|---|---|---|---|
| `features/kyc/investor_kyc_journey.feature` | stub `DocLlmValidator` / `DocLlmValidationJob` and AML job via `define_singleton_method`; `JourneyActivitySpy`-style spy prepended on `InvestorKyc` | `:investor_kyc` created **as `IndividualKyc`** (as the controller does), `:document`, `:aml_report`, `:doc_question` | `Given the entity is set up for KYC journeys`, `Given the KYC AI validation returned {int} of {int} failing answers`, `Given the KYC AML result is {string}` |
| `…_ui.feature` | live-update DOM marker (reuse call step) | same | reuse call/distribution panel steps |
| `…_rollout.feature` | rake invoke helper (reuse) | Angel Fund entity | reuse |
| `investor_kyc_fixes.feature` | — | same | `When a fund user ticks complete on the KYC` |

Regression: `features/fund/capital_call_journey*.feature`, `features/fund/capital_distribution_journey*.feature`,
`investor_kyc_workflow_auto_assignment.feature`, `kyc_doc_first_wizard.feature`, `kyc_validation.feature`,
`kyc.feature`. Run with `TEST_ENV_NUMBER=$RANDOM` and Redis up.

---

## Project Rules Checklist

| Rule | Applies? | How it is met |
|---|---|---|
| No `blank?`/`present?` on relations; use `exists?`/`none?` | Applies | Checks use `exists?`, `pluck`, `pick`, `maximum` |
| Dedup in SQL (`distinct.pluck`), batch bulk operations (`find_each`/`in_batches`) | Applies | `distinct.pluck(:name)`; `journey_progress_for` uses `find_each` |
| Select only needed columns when loading many `account_entries`; no speculative `includes` of big associations | N/A | No `account_entries`; no `includes` of `documents` |
| Screen dates via `l(...)`; emails render `Mon dd, yyyy` via `EmailDateLocalization`; no human-format `strftime` | Applies | Check messages use `I18n.l(date)` ("form sent on …"); no new emails |
| Date inputs use `f.date_field` / `date_field_tag`; JS dates via `locale_date_format.js` | N/A | No date inputs or JS dates |
| Every query entity-scoped; Pundit `authorize`/`policy_scope` on every action | Applies | See Security Review |
| MCP tool surfaces changed only via the ontology YAML (run the ontology drift feature) | N/A | No ransackable or MCP change |
| Cucumber only (no RSpec); `TEST_ENV_NUMBER=$RANDOM` on every run | Applies | Four features above |
| `bundle exec rubocop` clean, including the `IRM/RelationBlankPresent` cop | Applies | Run on all touched files |

---

## Sign-off

| Reviewer | Date | Decision | Notes |
|---|---|---|---|
| | | | |
