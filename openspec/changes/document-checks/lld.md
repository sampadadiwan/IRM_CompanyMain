# Document Checks — Low-Level Design

> **Audience:** The developer who reviews the implementation plan before coding starts.
> **Companion documents:** [Design](design.md) · [Spec](specs/documents/document-checks/spec.md) · [Tasks](tasks.md)

> **Planning phase — no code changes.** This document records the implementation-level decisions
> a reviewing developer must check. It adds to [design.md](design.md): link to its diagrams and
> worked examples rather than repeating them.

> **Reviewable, not descriptive.** Every section states concrete decisions and ends with
> **Reviewer checks** to tick.

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

- **Reply keyed by `c<check_id>`, and the field is picked from the registry allowlist and re-checked at
  write time.** The core safety decision. See [Security Review](#security-review).
- **The `current` flag is flipped inside the finish transaction under a record-row lock.** See
  [Transactions](#transactions-locking-and-concurrency).
- **A provider error mid-run means `could_not_run`, with no partial results.** Document-level failures
  become `unreadable_*` results. See [Error Mapping](#error-mapping-and-logging).
- **Use document value and Fill-in writes call `InvestorKyc#journey_details_changed!`**, extracted
  from `InvestorKycAction#journey_hook`'s "details changed" branch with no behaviour change. See
  [Method Contracts](#method-contracts).
- **Retirement drop migration is guarded:** it aborts unless every `doc_questions` row is converted
  or logged as not converted. `documents.qna` is dropped `INSTANT` (MySQL 8.4.11 in the prod dump). See
  [Schema Detail](#schema-detail).
- **The KYC field allowlist is hard-coded in `DocChecks::Kyc::COLUMNS`.** Contested: should
  `esign_emails` and `residency` be writable?

---

## File Map

Boundaries follow the design's boxes. **D1** = deploy 1 (feature live), **D2** = deploy 2 (retirement).

| Boundary | File | New / Modified / Deleted | Deploy | Responsibility |
|---|---|---|---|---|
| ① | `db/migrate/<ts>_create_doc_checks.rb` | New | D1 | `doc_checks`, `doc_check_runs`, `doc_check_results`, `doc_check_conversion_logs` |
| ① | `app/packs/core/documents/models/doc_check.rb` | New | D1 | Model, `for_record`, `reply_key`, validations |
| ① | `app/packs/core/documents/services/doc_checks/card_form.rb` | New | D1 | One card's rows: validate, upsert, delete missing |
| ① | `app/packs/core/documents/services/doc_checks/presets.rb`, `config/doc_check_presets.yml` | New | D1 | Preset entries and mapping |
| ① | `app/packs/core/documents/controllers/doc_checks_controller.rb`, `policies/doc_check_policy.rb` | New | D1 | index / card / update_card / preset / try |
| ① | `app/packs/core/documents/views/doc_checks/{index,_card,_row,_not_added}.html.erb` | New | D1 | Setup UI |
| ① | `app/javascript/controllers/doc_check_row_controller.js` | New | D1 | Row swap, look-for autofill, dirty state |
| ② | `app/packs/core/documents/services/doc_checks/registry.rb`, `field.rb`, `errors.rb` | New | D1 | Map, `Field` struct, error classes |
| ② | `app/packs/core/investor_kycs/services/doc_checks/kyc.rb` | New | D1 | KYC entry |
| ② | `app/packs/core/investor_kycs/models/concerns/investor_kyc_concern.rb` | Modified | D1 | `required_document_names` (moved from `Support`), `find_document_by_name` |
| ② | `app/packs/core/investor_kycs/services/investor_kyc_action.rb`, `models/investor_kyc.rb` | Modified | D1 | `journey_details_changed!(actor:, started_at:)` extracted and called from `journey_hook` |
| ③ | `app/packs/core/documents/controllers/doc_check_runs_controller.rb`, `policies/doc_check_run_policy.rb` | New | D1 | create / show |
| ③ | `app/packs/core/investor_kycs/jobs/investor_kycs_bulk_action_job.rb` | Modified | D1 | `validate_docs_with_ai` → `StartRun` + `RunJob.perform_now` |
| ③ | `app/packs/core/investor_kycs/views/investor_kycs/{show,_show,_bulk_actions}.html.erb` | Modified | D1 | "Check documents", posting to `doc_check_runs` |
| ④ | `app/packs/core/documents/models/doc_check_run.rb` | New | D1 | Statuses, scopes, progress |
| ④ | `app/packs/core/documents/services/doc_checks/start_run.rb`, `jobs/doc_checks/run_job.rb` | New | D1 | Guard + orchestration |
| ⑤ | `app/packs/core/documents/services/doc_checks/document_reader.rb` | New | D1 | `< DocLlmBase` |
| ⑤ | `app/packs/ai/ai_rules/services/ai_data_manager.rb` | Modified | D1 | `validate_document` → `DocumentReader`; drop dead `DocQuestion.new` |
| ⑥ | `app/packs/core/documents/services/doc_checks/judge.rb` | New | D1 | Outcome codes |
| ⑦ | `app/packs/core/documents/models/doc_check_result.rb`, `services/doc_checks/assessment.rb` | New | D1 | Results, resolutions, read-model |
| ⑧ | `app/packs/core/documents/controllers/doc_check_results_controller.rb`, `policies/doc_check_result_policy.rb` | New | D1 | index / use_document_value / mark_ok / undo / check_again |
| ⑧ | `app/packs/core/documents/views/doc_check_runs/{_panel,_header,_group,_result,show}.html.erb`, `views/doc_check_results/index.html.erb` | New | D1 | Tab and attention list |
| ⑧ | `config/locales/doc_checks.en.yml` | New | D1 | Every user-facing sentence |
| ⑧ | `app/packs/core/investor_kycs/views/investor_kycs/_details.html.erb` | Modified | D1 | Tab → panel + Earlier AI answers |
| ⑧ | `app/packs/core/investor_kycs/workflow_checks/investor_kyc/{validate_documents,support}.rb` | Modified | D1 | Assessment-based; drop `ai_answer_counts` / `ai_validated_at` |
| ⑧ | Settings/KYC menu partial(s) linking `doc_questions_path` | Modified | D1 | Link to `doc_checks_path` and `doc_check_results_path` |
| Conv | `app/packs/core/documents/services/doc_checks/legacy_converter.rb`, `lib/tasks/doc_checks.rake`, `models/doc_check_conversion_log.rb` | New | D1 | Conversion and log |
| Retire | `investor_kycs_controller.rb` (`validate_docs_with_ai`), `config/routes/core.rb` (member route) | Modified | D1 | Removed together with the button change |
| Retire | `documents/_document_details.html.erb` (QnA tab), `models/document.rb` (`ignored_columns`) | Modified | D1 | QnA tab gone; column ignored |
| Retire | `user_guide_helper.rb` | Modified | D1 | `doc_questions` key → `doc_checks` |
| Retire | `doc_questions_controller.rb`, `views/doc_questions/*` (11), `doc_question_policy.rb`, `doc_question.rb`, `with_doc_questions.rb`, `doc_llm_validator.rb`, `doc_llm_validation_job.rb`, `doc_llm_qna_job.rb`, `variable_interpolation.rb`, `import_doc_question.rb`, `import_doc_question_service.rb` | Deleted | D2 | Legacy code |
| Retire | `investor_kyc.rb`, `investor.rb`, `aggregate_portfolio_investment.rb`, `entity.rb`, `import_upload.rb`, `import_uploads/show.html.erb`, `config/routes/core.rb` | Modified | D2 | Remove includes, associations, import type, `resources :doc_questions` |
| Retire | `public/sample_uploads/doc_questions.xlsx`, `public/sample_uploads/kyc_validation_rules.xlsx` | Deleted | D2 | Samples / fixtures |
| Retire | `db/migrate/<ts>_retire_doc_questions.rb` | New | D2 | Guarded `drop_table :doc_questions`, `:doc_check_conversion_logs`; `remove_column :documents, :qna` INSTANT |
| Tests | `features/core/doc_check_setup.feature`, `doc_check_runs.feature`, `doc_check_results.feature`, `kyc_doc_checks_journey.feature`, `doc_checks_conversion.feature`, `doc_checks_retirement.feature` | New | D1/D2 | See [Test Plumbing](#test-plumbing) |
| Tests | `features/support/doc_checks_fake_reader.rb`, `features/step_definitions/doc_checks_steps.rb`, factories | New | D1 | Plumbing |
| Tests | `features/step_definitions/investor_kyc_journey_steps.rb`, `features/core/investor_kyc_journey*.feature` | Modified | D1 | DocQuestion steps → DocCheck steps |
| Tests | `features/ai/kyc_validation.feature`, `features/core/doc_question_import.feature`, `step_definitions/kyc_validation.rb`, `doc_question_import_steps.rb` | Deleted | D2 | Legacy |
| Docs | `docs/user_guides/document_checks_user_guide.md` (new); `document_management_user_guide.md`, `ai_features_user_guide.md`, `investor_kyc_user_guide.md`, `app/packs/core/documents/documents_module_prd.md` | New / Modified | D1 | Guide and references |

**Reviewer checks**
- [ ] Every class in the design's class diagram has a file here, and every row in the design's Retirement tables has a row here
- [ ] D2 rows contain no file that D1 code still needs

---

## Schema Detail

**`doc_checks`** (new)

| Column | Change | Type | Limit | Null | Default | Index / FK | Why it's needed |
|---|---|---|---|---|---|---|---|
| `entity_id` | Added | bigint | — | no | — | FK entities, UKs | Tenant |
| `record_type` | Added | string | 40 | no | "InvestorKyc" | UKs | Registry key |
| `document_name` | Added | string | 100 | no | — | UKs | Card |
| `action` | Added | string | 12 | no | "fill_in" | — | fill_in / compare / question |
| `field_name` | Added | string | 100 | yes | — | UK | Null for question |
| `look_for` | Added | string | 100 | no | — | UK | Matches validation |
| `tip` | Added | string | 255 | yes | — | — | Matches validation |
| `replace_existing` | Added | boolean | — | no | false | — | Fill in |
| `expected_answer` | Added | string | 3 | no | "yes" | — | Question |
| `position` | Added | integer | — | no | 0 | — | Order |
| `legacy_doc_question_id` | Added | bigint | — | yes | — | UNIQUE, no FK | Idempotent conversion; survives the D2 drop |
| `[entity_id, record_type, document_name, field_name]` | New index | | | | | UNIQUE | Field once per card |
| `[entity_id, record_type, document_name, look_for]` | New index | | | | | UNIQUE | No duplicate items |

**`doc_check_runs`** (new)

| Column | Change | Type | Limit | Null | Default | Index / FK | Why it's needed |
|---|---|---|---|---|---|---|---|
| `entity_id` | Added | bigint | — | no | — | FK; idx | Scoping |
| `record_type` / `record_id` | Added | string(40) / bigint | — | no | — | idx | Polymorphic |
| `user_id` | Added | bigint | — | yes | — | FK nullify | Toasts |
| `trigger` | Added | string | 10 | no | "manual" | — | manual / bulk / again / trial |
| `trial` | Added | boolean | — | no | false | — | Exclusion |
| `current` | Added | boolean | — | no | false | idx | Current results |
| `status` | Added | string | 15 | no | "queued" | idx | `could_not_run` is 13 chars |
| `documents_total` / `documents_done` | Added | integer | — | no | 0 | — | Progress |
| `current_document` | Added | string | 100 | yes | — | — | Progress |
| `started_at` / `finished_at` | Added | datetime | — | yes | — | idx (finished_at) | Header, freshness, expiry |
| `error_message` | Added | string | 255 | yes | — | — | Couldn't-run reason |
| `counts` | Added | json | — | yes | — | — | `{ok:, attention:}` |
| `[record_type, record_id, current]`, `[record_type, record_id, status]`, `[entity_id, current, finished_at]` | New indexes | | | | | | Tab, guard, list |

**`doc_check_results`** (new)

| Column | Change | Type | Limit | Null | Default | Index / FK | Why it's needed |
|---|---|---|---|---|---|---|---|
| `entity_id` | Added | bigint | — | no | — | idx with outcome | List |
| `doc_check_run_id` | Added | bigint | — | no | — | FK cascade, idx | Parent |
| `doc_check_id` | Added | bigint | — | yes | — | FK nullify, idx | Carry-over |
| `document_name` / `look_for` | Added | string | 100 | no | — | — | Snapshot |
| `action` | Added | string | 12 | no | — | — | Snapshot |
| `field_name` | Added | string | 100 | yes | — | — | Snapshot; Use document value |
| `document_id` | Added | bigint | — | yes | — | — (no FK: documents soft-delete) | Read document |
| `document_file_id` | Added | string | 100 | yes | — | — | Shrine `file.id` |
| `outcome` | Added | string | 20 | no | — | idx | `unexpected_answer` is 17 |
| `note` | Added | string | 255 | yes | — | — | OK kind / detail |
| `doc_value` / `record_value` / `explanation` | Added | text | — | yes | — | — | Long values |
| `resolution` | Added | string | 20 | yes | — | — | `used_document_value` is 19 |
| `resolved_by_id` | Added | bigint | — | yes | — | FK users nullify | Stamp |
| `resolved_at` | Added | datetime | — | yes | — | — | Stamp, freshness |
| `resolve_reason` | Added | string | 255 | yes | — | — | Matches validation |

**`doc_check_conversion_logs`** (new in D1, dropped in D2): lets the drop guard tell "reviewed and
skipped" from "never looked at".

| Column | Change | Type | Limit | Null | Default | Index / FK | Why it's needed |
|---|---|---|---|---|---|---|---|
| `entity_id` | Added | bigint | — | no | — | idx | Scope |
| `doc_question_id` | Added | bigint | — | no | — | UNIQUE | One entry per question |
| `reason` | Added | string | 255 | no | — | — | Why not converted |

**D2 retirement migration** (`retire_doc_questions`):

| Step | Detail |
|---|---|
| Guard | `unconverted = DocQuestion ids − doc_checks.legacy_doc_question_id − doc_check_conversion_logs.doc_question_id` (raw SQL, no model). If any → `raise "N Doc Questions are not converted — run doc_checks:convert_doc_questions first"`. Exposed as `RetireDocQuestions.unconverted_count` for the R5 step |
| Drops | `drop_table :doc_questions`, `drop_table :doc_check_conversion_logs` |
| Column | `remove_column :documents, :qna, :text` via `ALTER TABLE documents DROP COLUMN qna, ALGORITHM=INSTANT` on MySQL; plain `remove_column` on sqlite (test) |
| Down | Re-creates both tables and the column, empty (data from backup) |

**Migration safety:** all D1 tables are new, with no locks. In D2, `doc_questions` is tiny. The
`documents` table is large, which is why the column is ignored from D1 and dropped `INSTANT` (8.4.11
supports it). Update `db/schema.rb` and `db/schema_test.rb`, then `db:clean_schema`.

**Reviewer checks**
- [ ] Every column has a "why"; every FK an index; every uniqueness rule a unique index
- [ ] Column limits match validation limits (look_for 100, tip 255, resolve_reason 255)
- [ ] The D2 migration cannot drop data on an environment where the conversion wasn't run

---

## Method Contracts

**`DocCheck`** (Model)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `.for_record(record)` | record | relation ordered by `document_name` setup order, `position` | `DocChecks::UnknownRecordType` | — | Yes |
| `#reply_key` | — | `"c#{id}"` (unsaved: `"c#{object_id}"`) | — | — | Yes |
| `#field` | — | `Field` or nil (missing) | — | — | Yes |

**`DocChecks::CardForm`**: `new(entity:, record_type:, document_name:, rows:)`. `#save` returns
Boolean and fills `#rows` with row errors. Side effects: in one transaction, it upserts and deletes
that card's checks. It is idempotent.

**`DocChecks::Presets`**: `.key_for(name)` returns `"cml" | "pan" | "aadhaar" | "passport" | nil`.
`.rows_for(entity:, document_name:, key:, existing_fields:, existing_look_fors:)` returns
`{rows: [DocCheck(unsaved)], not_added: [label]}`.

**`DocChecks::Kyc`** (registry entry)

| Method | Returns | Notes |
|---|---|---|
| `.document_names(entity)` | `[String]` | Union of both lists plus required file labels; de-duplicated case-insensitively, first spelling kept |
| `.document_names_for(kyc)` | `[String]` | `kyc.required_document_names` |
| `.fields_for(entity)` | `[Field]` | `COLUMNS` (13) + `FormCustomField.where(form_type: entity KYC form types).where.not(field_type: %w[File Calculation])`, with labels; memoised per request |
| `.find_document(kyc, name)` | Document or nil | Newest match among `kyc.documents.not_generated.select(:id, :name, :owner_tag, :file_data, :updated_at)` |
| `.read(kyc, field)` / `.write(kyc, field, value)` | value | Raises `DocChecks::BadValue` for unparseable dates |
| `.details_changed!(kyc, user:)` | — | `kyc.save!(validate: false)` with `audit_comment: "Document checks"`, then `kyc.journey_details_changed!(actor: user)` |
| `.on_assessed(kyc, settled)` | — | `update_column`-free save only if `all_docs_valid != settled` |
| `.can_view?(user, kyc)` / `.can_edit?(user, kyc)` | Boolean | Policy + same entity |

**`InvestorKyc#journey_details_changed!(actor:, started_at: Time.current)`**: the existing
"details changed" branch of `InvestorKycAction#journey_hook`, extracted verbatim:
`journey_invalidate(check_keys: "investor_kyc.review_kyc", reason: "KYC details changed after
review", only_if_passed: …)` + `journey_undo_evaluate`. `journey_hook` calls it. It never raises.

**`DocChecks::StartRun.call(record:, user:, trigger:, trial: false, enqueue: true)`** returns a
`DocCheckRun` or raises `DocChecks::AlreadyRunning`. It locks the record row, expires stale runs (>
30 min) and inserts a run. It is not idempotent; the guard prevents doubles.

**`DocChecks::RunJob#perform(run_id)`** returns `[error_msgs]` for bulk. It is a no-op unless the
run is `queued`, so it is idempotent on re-delivery.

**`DocChecks::DocumentReader.call(document:, checks:)`** returns a Trailblazer result, with
`ctx[:readings]` or `ctx[:failure]`. It raises `DocChecks::ProviderError`. It is read-only.

**`DocChecks::Judge.call(check:, reading:, record:, entry:)`** returns the result attrs Hash. It is
pure.

**`DocChecks::Assessment.new(record)`** exposes `#groups`, `#attention_count`, `#changed?(name)`,
`#settled?`, `#could_not_run`, `#fresh_at`, using 3 queries.

**`DocCheckResult`**

| Method | Raises | Side effects |
|---|---|---|
| `#use_document_value!(user:)` | `ActiveRecord::RecordInvalid` (wrong outcome / not current / not allowed) | Registry write + `details_changed!` + stamp, in one transaction |
| `#mark_ok!(user:, reason:)` | `RecordInvalid` "Say why this is OK" | Stamp |
| `#undo!` | `RecordInvalid` unless `marked_ok` | Clear stamp |

**`DocChecks::LegacyConverter.call(entity:, execute: false)`** returns `{converted:, not_converted:}`.
With `execute`, it does `find_or_create_by(legacy_doc_question_id:)` and upserts the log. It is
idempotent.

**`AiDataManager#validate_document(question:)`** builds an unsaved
`DocCheck(action: "question", look_for: question)` and returns `DocumentReader` readings, or "Error
in validation". The signature is unchanged.

**Reviewer checks**
- [ ] `COLUMNS` contains no control column (`verified`, `submission_status`, `entity_id`, `investor_id`, `form_type_id`, `kyc_type`, `all_docs_valid`, `*_verified`, `*_status`)
- [ ] `journey_details_changed!` extraction leaves `InvestorKycAction#journey_hook` behaviour identical (existing journey features green)

---

## Controllers, Params and Responses

| Action | Permitted params | Policy method | Success | Failure |
|---|---|---|---|---|
| `DocChecksController#index` | `record_type` (allowlisted) | `DocCheckPolicy#index?` | HTML | 403 |
| `#card` | `document_name` | `index?` | frame | — |
| `#update_card` | `document_name`, `rows: [[:id, :action, :field_name, :look_for, :tip, :replace_existing, :expected_answer, :position]]` | `update?` | turbo_stream card, flash "Saved" | 422 turbo_stream card with row errors |
| `#preset` | `document_name`, `preset` | `update?` | turbo_stream card (unsaved rows + note) | flash "No preset for this document" |
| `#try` | `record_id` | `update?` + registry `can_view?` | turbo_stream trial frame | flash "KYC not found" |
| `DocCheckRunsController#create` | `record_type`, `record_id` | `DocCheckRunPolicy#create?` | turbo_stream tab / redirect back | `AlreadyRunning` → flash text |
| `#show` | — | `show?` | frame | 403 |
| `DocCheckResultsController#index` | `reason`, `document_name`, `checked_from`, `checked_to`, `page` | `index?` + `policy_scope` | HTML | 403 |
| `#use_document_value` / `#mark_ok` (`reason`) / `#undo` | — | `resolve?` (registry `can_edit?`) | turbo_stream tab | 422 row error |
| `#check_again` | `record_type`, `record_ids: []` | `check_again?` + per-record `can_edit?` | redirect, flash count | — |

`entity_id` is always `current_user.entity_id`, never a param. `record_type` is checked against
`DocChecks::Registry.record_types` before `constantize`.

**Reviewer checks**
- [ ] Every action calls `authorize` / `policy_scope`
- [ ] No param sets `entity_id`, `status`, `current`, `outcome`, `resolution` or `resolved_by_id`

---

## Queries and Indexes

| Where | Query shape | Index | Rows |
|---|---|---|---|
| Setup page | `DocCheck.where(entity_id:, record_type:)` | UK prefix | ≤ 100 |
| `for_record` | `+ where(document_name: names)` | UK prefix | ≤ 20 |
| Guard | `DocCheckRun.where(record_type:, record_id:, trial: false, status: %w[queued running]).exists?` | `[record_type, record_id, status]` | ≤ 1 |
| Tab | `find_by(record…, current: true)` + `results.order(:id)` + `find_document` (selected columns, one query per record) | `[record_type, record_id, current]`, `[doc_check_run_id]` | ~10 |
| Attention list | `DocCheckResult.joins(:doc_check_run).where(entity_id:, resolution: nil, doc_check_runs: {current: true}).where.not(outcome: "ok")` + filters, `order(doc_check_runs.finished_at desc)`, Pagy 50, `includes(doc_check_run: :record)` | `[entity_id, outcome]`, `[entity_id, current, finished_at]` | paged |
| "Document changed" filter | all current results of the entity, `Assessment#changed?` per record, then paginated in Ruby (`Pagy.new`) so pages are never sparse — only when this filter is chosen | `[entity_id, current, finished_at]` | ~10 × records with a current run |
| Conversion | `find_each` on legacy rows per entity | entity idx | ≤ 20 |

**Reviewer checks**
- [ ] Every query is entity-scoped or goes through an authorised record
- [ ] No `blank?`/`present?` on relations; `distinct.pluck` not `pluck.uniq`; no N+1 on the list

---

## Transactions, Locking and Concurrency

| Operation | Scope | Lock | Race prevented |
|---|---|---|---|
| Start | guard + insert | `record.lock!` | Double click |
| Finish | results insert + writes + `details_changed!` save + current flip + status | `record.lock!`, reload previous current | Two finishers both current; write vs user edit |
| Use document value | write + save + stamp | `result.lock!` then `record.lock!` (same order everywhere) | Double click; concurrent run finish |
| Mark OK / Undo | single update | `result.lock!` | Double click |
| Card save | that card's upserts/deletes | none (UKs catch races → row error "Already used on this card") | Two tabs saving |

No HTTP, toast or broadcast happens inside a transaction.

**Reviewer checks**
- [ ] Lock order is result → record everywhere both are locked

---

## Background Jobs

| Job | Queue | Trigger | Retry | Discard on | Guard | Timeout |
|---|---|---|---|---|---|---|
| `DocChecks::RunJob` | `:default` | `StartRun` / bulk `perform_now` | `retry: 0` | `RecordNotFound` | status must be `queued` | expired after 30 min by `StartRun` / `Assessment` |

**Reviewer checks**
- [ ] Bulk keeps `sleep(2)` between KYCs and aggregates `RunJob` messages

---

## External Integrations

| Call | Auth | Timeout | Rate limit | Error mapping |
|---|---|---|---|---|
| `Langchain::LLM` vision chat (provider from `DOCUMENT_VALIDATION_PROVIDER`) | Existing credentials via `DocLlmBase#initialize_llm` | 120 s `Timeout.timeout` per call | 429 → `ProviderError` "the AI service is busy" | Faraday / provider / timeout / auth → `DocChecks::ProviderError` with a user-safe message |

**Reviewer checks**
- [ ] Prompts and images are never logged above debug

---

## Error Mapping and Logging

| Failure | Raised in | Handled by | User sees | Logged |
|---|---|---|---|---|
| No checks for the record's docs | `RunJob` | run `could_not_run` | "No document checks are set up for this KYC's documents" | info |
| `:no_llm` | reader init | run `could_not_run` | "the AI service is not configured" | error |
| `ProviderError` | reader | run `could_not_run`, no writes | "the AI service is unavailable" | error + danger toast |
| `:unreadable_file` | convert | results `unreadable_file` | "Couldn't read this file — upload it as a PDF or image" | warn (doc id, mime) |
| `:unreadable_reply` | parse | results `unreadable_reply` | "Couldn't read the AI's answer for this document" | warn (first 200 chars at debug) |
| Missing field | judge | result `field_missing` | "this check's KYC field no longer exists" | — |
| `BadValue` | registry write | result `bad_date` | "couldn't read a date from 'V'" | — |
| `AlreadyRunning` | `StartRun` | controller / bulk | "Documents are already being checked for X" | — |
| Other `StandardError` | `RunJob` | mark `could_not_run` "Something went wrong", re-raise | danger toast | error + tracker |
| D2 guard | migration | aborts deploy step | — | migration output |

**Reviewer checks**
- [ ] The only broad rescue marks the run and re-raises
- [ ] Logs carry entity id, run id, record type/id, document id

---

## Security Review

| Concern | Decision |
|---|---|
| Authorization | `DocCheckPolicy`: permission `enable_doc_llm_validation` + `belongs_to_entity?`. Run/result policies: permission + registry `can_view?` / `can_edit?` |
| Tenant isolation | `entity_id` on every table; `policy_scope` by `user.entity_id`; `for_record` uses `record.entity_id` |
| Code execution from config | None. `VariableInterpolation` is deleted; no `send` with user/AI strings; fields only from `fields_for` |
| AI-controlled writes | Reply keys filtered to the document's `c<id>`; the written field is re-validated at write time |
| Output | ERB escaping; no `html_safe` on values or explanations |
| Mass assignment | Per-action permitted params above |

**Reviewer checks**
- [ ] Another entity's user gets 403/404 on every new route; investors get no tab and 403 on routes

---

## Configuration and Rollout

| Item | Value |
|---|---|
| Env | Existing `DOCUMENT_VALIDATION_PROVIDER` / `_MODEL`; IN and US set independently |
| Flag | Existing `enable_doc_llm_validation` (label "Document checks (AI)") |
| Deploy order | **D1**: migration + feature + D1 retirements → Support runs `doc_checks:convert_doc_questions` dry run per entity, reviews, `EXECUTE=1`, on IN then US → **D2**: deletions + guarded drop migration |
| Rollback D1 | Revert code; the new tables stay unused; Doc Questions is untouched in D1 |
| Rollback D2 | Revert code; the down-migration re-creates empty tables. Restore `doc_questions` rows from backup only if needed |

**Reviewer checks**
- [ ] D1 is safe with the feature unused; D2 can't run before conversion (guard)

---

## Test Plumbing

| Feature file | Covers | Stubs | New steps |
|---|---|---|---|
| `features/core/doc_check_runs.feature` | H3, H13, E6–E12, E14, E15, E17, E18, X1, X2, X3, X5 | `@doc_checks_fake_ai` → `DocChecks::FakeReader` (readings per document, call count, provider error, garbage, delay) | `Given the AI reads from "CML": …`, `When documents are checked for the kyc`, `Then the "PAN" item needs attention "…"` |
| `features/core/doc_check_setup.feature` | H1, H2, E1–E5, E16, X4 | same tag for E16's run | `When I use the "CML" preset on "CML"`, `When I add a check …` |
| `features/core/doc_check_results.feature` | H4, H5, H6, H8, H9, H12, E19, X6, X7, X8, X10 | same | `When I mark "Full name" OK with "…"` |
| `features/core/kyc_doc_checks_journey.feature` | H7, E13, E20, E21, E22, E23 | same + journey steps | reuses journey assertions |
| `features/core/doc_checks_conversion.feature` | H10, H11, X9 | — | `Given Doc Questions:` table, `When the conversion runs for "…"` |
| `features/core/doc_checks_retirement.feature` | R1–R5 | — | `Then "/doc_questions" is not found`, `Then the database has no table "doc_questions"` |

Run every feature with `TEST_ENV_NUMBER=$RANDOM`, with Redis up. `FakeReader` overrides
`DocChecks::DocumentReader.llm_call` in a `Before('@doc_checks_fake_ai')` hook, restored in `After`.

---

## Project Rules Checklist

| Rule | Applies? | How it is met |
|---|---|---|
| No `blank?`/`present?` on relations | Applies | `exists?` / loaded arrays |
| Dedup in SQL, batch bulk ops | Applies | `distinct.pluck`; conversion `find_each` |
| Select needed columns on big tables; no speculative includes | Applies (documents) | `find_document` selects 5 columns |
| Screen dates via `l(...)` | Applies | "Checked …" `l(time, format: :abbr_date_time)`; list `l(date)` |
| Date inputs via `date_field_tag` | Applies | Attention list date filter |
| Entity scoping + Pundit everywhere | Applies | Security Review |
| MCP ontology | N/A | No MCP tool touches these tables |
| Cucumber only, `TEST_ENV_NUMBER=$RANDOM` | Applies | Six features |
| Rubocop clean incl. `IRM/RelationBlankPresent` | Applies | Per phase |
| Inline comments citing worked-example IDs | Applies | User convention |

---

## Sign-off

| Reviewer | Date | Decision | Notes |
|---|---|---|---|
| | | | |
