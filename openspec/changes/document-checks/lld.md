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

- **Reply keyed by `c<check_id>`, and the field is picked from the registry allowlist.** This is
  the core safety decision. See [Security Review](#security-review) and
  [design ⑤](design.md#⑤-reader).
- **The `current` flag on `doc_check_runs` is flipped inside the finish transaction**, with the
  previous current run locked first. See
  [Transactions, Locking and Concurrency](#transactions-locking-and-concurrency).
- **A provider error mid-run fails the whole run** (no partial results). A per-document
  conversion/parse failure becomes error rows. See [Error Mapping](#error-mapping-and-logging).
- **"Out of date" is derived, not stored.** The entity list filters it in Ruby on the paginated
  page. See [Queries and Indexes](#queries-and-indexes).
- **The KYC field allowlist is hard-coded in `DocChecks::Kyc::COLUMNS`.** Contested: should
  `esign_emails` and `residency` be AI-writable? See [Method Contracts](#method-contracts).
- **`RunJob` uses `retry: 0`**, and stuck `running` runs are expired after 30 min. See
  [Background Jobs](#background-jobs).

---

## File Map

| Boundary | File | New / Modified | Responsibility |
|---|---|---|---|
| ① Setup | `db/migrate/<ts>_create_doc_checks.rb` | New | Four tables + indexes |
| ① Setup | `app/packs/core/documents/models/doc_check_set.rb` | New | Set, `set_for`, nested checks, validations |
| ① Setup | `app/packs/core/documents/models/doc_check.rb` | New | Check, kind enum, `reply_key`, validations against registry |
| ① Setup | `app/packs/core/documents/services/doc_checks/presets.rb` | New | Load YAML, `apply` |
| ① Setup | `config/doc_check_presets.yml` | New | CML, PAN card, Aadhaar, Passport entries |
| ① Setup | `app/packs/core/documents/controllers/doc_check_sets_controller.rb` | New | index/new/create/edit/update/destroy/apply_preset/test_run |
| ① Setup | `app/packs/core/documents/policies/doc_check_set_policy.rb` | New | Permission + entity |
| ① Setup | `app/packs/core/documents/views/doc_check_sets/{index,new,edit,_form,_document_group,_check_row}.html.erb` | New | Setup UI |
| ① Setup | `app/javascript/controllers/doc_check_row_controller.js` | New | Show/hide Field/Fill/Expect by kind |
| ② Registry | `app/packs/core/documents/services/doc_checks/registry.rb` | New | Type → entry map |
| ② Registry | `app/packs/core/investor_kycs/services/doc_checks/kyc.rb` | New | KYC entry |
| ② Registry | `app/packs/core/investor_kycs/models/concerns/investor_kyc_concern.rb` | Modified | Extract `required_document_names` + matcher to share with `Support` and the registry |
| ③ Triggers | `app/packs/core/documents/controllers/doc_check_runs_controller.rb` | New | create/show |
| ③ Triggers | `app/packs/core/documents/policies/doc_check_run_policy.rb` | New | Via registry `can_view?`/`can_update?` |
| ③ Triggers | `app/packs/core/investor_kycs/jobs/investor_kycs_bulk_action_job.rb` | Modified | `validate_docs_with_ai` → `StartRun` + `RunJob.perform_now` |
| ③ Triggers | `app/packs/core/investor_kycs/controllers/investor_kycs_controller.rb` | Modified | Remove `validate_docs_with_ai` |
| ③ Triggers | `app/packs/core/investor_kycs/views/investor_kycs/show.html.erb`, `_bulk_actions.html.erb` | Modified | Button label/route; same DOM id |
| ③ Triggers | `config/routes/core.rb` | Modified | New resources; remove `doc_questions` and `validate_docs_with_ai` |
| ④ Run | `app/packs/core/documents/models/doc_check_run.rb` | New | Status enum, `active`, scopes |
| ④ Run | `app/packs/core/documents/services/doc_checks/start_run.rb` | New | Guard + enqueue |
| ④ Run | `app/packs/core/documents/jobs/doc_checks/run_job.rb` | New | Orchestrates read/judge/finish |
| ⑤ Reader | `app/packs/core/documents/services/doc_checks/document_reader.rb` | New | `< DocLlmBase` |
| ⑤ Reader | `app/packs/core/documents/services/doc_llm_base.rb` | Reused | Unchanged |
| ⑥ Judge | `app/packs/core/documents/services/doc_checks/judge.rb` | New | Outcome rules, normalise |
| ⑦ Results | `app/packs/core/documents/models/doc_check_result.rb` | New | Statuses, `accept!` |
| ⑦ Results | `app/packs/core/documents/services/doc_checks/assessment.rb` | New | Read-model |
| ⑧ Screens | `app/packs/core/documents/views/doc_check_runs/{_panel,_group,_result,show}.html.erb` | New | Panel |
| ⑧ Screens | `app/packs/core/documents/controllers/doc_check_results_controller.rb` | New | index/accept/rerun |
| ⑧ Screens | `app/packs/core/documents/policies/doc_check_result_policy.rb` | New | Scope + accept |
| ⑧ Screens | `app/packs/core/documents/views/doc_check_results/index.html.erb` | New | Entity list |
| ⑧ Screens | `app/packs/core/investor_kycs/views/investor_kycs/_details.html.erb` | Modified | Tab → panel + Earlier AI answers |
| ⑧ Journey | `app/packs/core/investor_kycs/workflow_checks/investor_kyc/validate_documents.rb` | Modified | Uses `Assessment` |
| ⑧ Journey | `app/packs/core/investor_kycs/workflow_checks/investor_kyc/support.rb` | Modified | Drop `ai_answer_counts`, `ai_validated_at`; `required_document_names` delegates to the concern |
| Legacy | `app/packs/core/investor_kycs/models/investor_kyc.rb`, `investors/models/investor.rb`, `funds/portfolios/models/aggregate_portfolio_investment.rb` | Modified | Drop `WithDocQuestions`; KYC keeps `attribute :doc_question_answers, :json` |
| Legacy | `app/packs/core/entities/models/entity.rb` | Modified | `has_many :doc_check_sets` |
| Legacy | `app/packs/core/documents/services/doc_checks/legacy_converter.rb`, `lib/tasks/doc_checks.rake` | New | Conversion |
| Legacy | DocQuestions controller/views/policy, `doc_llm_validation_job.rb`, `doc_llm_validator.rb`, `doc_llm_qna_job.rb`, `variable_interpolation.rb`, `import_doc_question*.rb`, `with_doc_questions.rb` | Deleted | Retired |
| Legacy | `import_upload.rb`, `import_uploads/show.html.erb`, `user_guide_helper.rb`, `ai_data_manager.rb` | Modified | Remove DocQuestion references |
| Docs | `docs/user_guides/document_checks_user_guide.md` | New | User guide + FAQ |
| Tests | `features/core/doc_check_setup.feature`, `doc_check_runs.feature`, `doc_check_results.feature`, `features/core/kyc_doc_checks_journey.feature`, `features/core/doc_checks_conversion.feature` | New | See [Test Plumbing](#test-plumbing) |
| Tests | `features/ai/kyc_validation.feature`, `features/core/doc_question_import.feature`, `features/step_definitions/kyc_validation.rb`, `doc_question_import_steps.rb` | Deleted | Legacy |

**Reviewer checks**
- [ ] Every class in the design's class diagram has a file here, and nothing here is missing from it
- [ ] Files follow the pack layout (`app/packs/<domain>/<sub_domain>/...`). The KYC registry entry lives in the KYC pack, and the engine in documents

---

## Schema Detail

**`doc_check_sets`** (new): one per entity, record type and variant.

| Column | Change | Type | Limit | Null | Default | Index / FK | Why it's needed |
|---|---|---|---|---|---|---|---|
| `entity_id` | Added | bigint | — | no | — | FK entities, part of UK | Tenant |
| `record_type` | Added | string | 40 | no | — | UK | Registry key; class names are short |
| `variant` | Added | string | 20 | no | "all" | UK | Not null so the UK works on MySQL |
| `name` | Added | string | 100 | no | — | — | Display |
| `[entity_id, record_type, variant]` | New index | — | — | — | — | UNIQUE | One set per variant |

**`doc_checks`** (new)

| Column | Change | Type | Limit | Null | Default | Index / FK | Why it's needed |
|---|---|---|---|---|---|---|---|
| `entity_id` | Added | bigint | — | no | — | FK entities | Scoping |
| `doc_check_set_id` | Added | bigint | — | no | — | FK, part of UK | Parent |
| `document_name` | Added | string | 100 | no | — | part of UK | Document names in settings are short |
| `kind` | Added | string | 10 | no | "extract" | — | extract/match/rule |
| `label` | Added | string | 100 | no | — | part of UK | Matches validation limit |
| `hint` | Added | string | 255 | yes | — | — | Matches validation limit |
| `field_name` | Added | string | 100 | yes | — | — | Null for rule |
| `fill_mode` | Added | string | 12 | no | "blank_only" | — | blank_only / always |
| `expected_answer` | Added | string | 3 | no | "yes" | — | yes / no |
| `position` | Added | integer | — | no | 0 | — | Order |
| `legacy_doc_question_id` | Added | bigint | — | yes | — | UNIQUE | Conversion idempotency (nulls allowed repeatedly) |
| `[doc_check_set_id, document_name, label]` | New index | — | — | — | — | UNIQUE | Label unique per document |

**`doc_check_runs`** (new)

| Column | Change | Type | Limit | Null | Default | Index / FK | Why it's needed |
|---|---|---|---|---|---|---|---|
| `entity_id` | Added | bigint | — | no | — | FK; idx with current | Scoping, list |
| `record_type` | Added | string | 40 | no | — | idx | Polymorphic |
| `record_id` | Added | bigint | — | no | — | idx | Polymorphic |
| `doc_check_set_id` | Added | bigint | — | yes | — | FK `on_delete: :nullify` | Set may be deleted later |
| `user_id` | Added | bigint | — | yes | — | FK `on_delete: :nullify` | Notifications |
| `trigger` | Added | string | 10 | no | "manual" | — | manual/bulk/rerun/test |
| `test_run` | Added | boolean | — | no | false | — | Exclusion |
| `current` | Added | boolean | — | no | false | idx | Current results |
| `status` | Added | string | 20 | no | "queued" | idx | `done_with_errors` is 16 chars |
| `started_at` / `finished_at` | Added | datetime | — | yes | — | idx (finished_at) | Header, freshness, expiry |
| `error_message` | Added | string | 255 | yes | — | — | Run-level reason |
| `counts` | Added | json | — | yes | — | — | `{pass:, fail:, review:, error:, skipped:}` |
| `[record_type, record_id, current]` | New index | | | | | | Panel lookup |
| `[record_type, record_id, status]` | New index | | | | | | Active guard |
| `[entity_id, current, finished_at]` | New index | | | | | | Entity list |

**`doc_check_results`** (new)

| Column | Change | Type | Limit | Null | Default | Index / FK | Why it's needed |
|---|---|---|---|---|---|---|---|
| `entity_id` | Added | bigint | — | no | — | idx with status | List |
| `doc_check_run_id` | Added | bigint | — | no | — | FK `on_delete: :cascade`, idx | Parent |
| `doc_check_id` | Added | bigint | — | yes | — | FK `on_delete: :nullify`, idx | Carry-over of acceptance |
| `document_name` | Added | string | 100 | no | — | — | Snapshot |
| `check_label` | Added | string | 100 | no | — | — | Snapshot |
| `kind` | Added | string | 10 | no | — | — | Snapshot |
| `document_id` | Added | bigint | — | yes | — | no FK (documents soft-delete) | Read document |
| `document_file_id` | Added | string | 100 | yes | — | — | Shrine `file.id` (uuid + ext) |
| `status` | Added | string | 10 | no | — | idx | pass/fail/review/error/skipped |
| `doc_value` / `record_value` | Added | text | — | yes | — | — | Addresses can exceed 255 |
| `explanation` | Added | text | — | yes | — | — | AI reason |
| `outcome_note` | Added | string | 255 | yes | — | — | "Filled DP ID", error text |
| `accepted_by_id` | Added | bigint | — | yes | — | FK users `on_delete: :nullify` | Accept stamp |
| `accepted_at` | Added | datetime | — | yes | — | — | Accept stamp; journey freshness |
| `accept_reason` | Added | string | 255 | yes | — | — | Matches validation |

**Migration safety:** all four tables are new and empty. There is no change to existing tables, so
there's no lock risk and no backfill. It's reversible (`create_table` in `change`). Update both
`db/schema.rb` and `db/schema_test.rb` (sqlite), and run `db:clean_schema` per the local-migrate
note. The dev DB lags schema, so restore and hand-insert rather than trusting the dump.

**Reviewer checks**
- [ ] Every new or changed column and index has a "why", and none is unjustified
- [ ] Every foreign key has an index, and every uniqueness rule is enforced by a unique index
- [ ] Column limits match validation limits (label 100, hint 255, accept_reason 255)
- [ ] Migration is reversible; `schema.rb` and `schema_test.rb` both carry the tables

---

## Method Contracts

**`DocCheckSet`** (Model)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `.set_for(record)` | registered record | `DocCheckSet` or nil | `DocChecks::UnknownRecordType` | none | Yes |
| `#checks_for(document_name)` | String | relation ordered by `position` | — | none | Yes |
| `#document_names` | — | `[String]` distinct, in first-position order (`distinct.pluck` then sort) | — | none | Yes |

**`DocCheck`** (Model)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `#reply_key` | — | `"c#{id}"` | — | — | Yes |
| `#field_missing?` | — | true when `field_name` is not in `registry.fields_for` | — | — | Yes |
| validations | — | — | — | errors: "Choose a field from the list" (`field_name`), document not on list, label presence/uniqueness/length | — |

**`DocChecks::Registry`** (Service)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `.for(record_or_type)` | record or `"InvestorKyc"` | entry class | `DocChecks::UnknownRecordType` | — | Yes |
| `.record_types` | — | `["InvestorKyc"]` | — | — | Yes |

**`DocChecks::Kyc`** (Service, registry entry)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `.variant_for(kyc)` | InvestorKyc | `"individual"`/`"non_individual"` | — | — | Yes |
| `.documents_for(entity, variant)` | Entity, String | `[String]` | — | — | Yes |
| `.fields_for(entity, variant)` | Entity, String | `[Field]` (Struct: `name`, `label`, `storage` `:column`/`:json`, `compare` `:exact`/`:loose`, `type` `:string`/`:date`) | — | memoised per call site | Yes |
| `.read(kyc, field)` | InvestorKyc, Field | String/Date/nil | — | — | Yes |
| `.write(kyc, field, value)` | InvestorKyc, Field, String | value assigned | `DocChecks::BadValue` (unparseable date) | assigns, no save | Yes |
| `.record_documents(kyc)` | InvestorKyc | `kyc.documents.not_generated.select(:id, :name, :owner_tag, :file_data, :updated_at)` | — | — | Yes |
| `.find_document(documents, name)` | loaded docs, String | newest matching Document or nil | — | — | Yes |
| `.on_assessed(kyc, settled)` | InvestorKyc, Boolean | — | — | `save(validate: false)` only if `all_docs_valid` changes | Yes |
| `.can_view?(user, kyc)` / `.can_update?(user, kyc)` | User, InvestorKyc | Boolean | — | — | Yes |
| `COLUMNS` | — | `full_name`(loose) `PAN` `address`(loose) `corr_address`(loose) `birth_date`(date) `expiry_date`(date) `bank_name` `bank_branch` `bank_account_number` `bank_account_type` `ifsc_code` `esign_emails` `residency` | — | — | — |

**`DocChecks::StartRun`** (Service)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `.call(record:, user:, trigger:, test_run: false, set: nil, enqueue: true)` | — | `DocCheckRun` (queued) | `DocChecks::AlreadyRunning` (non-test only) | Locks record row; expires stuck runs; inserts run; `RunJob.perform_later` if `enqueue` | No (creates a run); the guard prevents doubles |

**`DocChecks::RunJob`** (Job)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `#perform(run_id)` | Integer | `[error_msgs]` (for bulk aggregation) | re-raises unexpected errors after marking the run failed | AI calls, results insert, record writes, `current` flip, `on_assessed`, `journey_progress!`, alert, broadcast | Returns early unless the run is `queued`, so a duplicate enqueue is harmless |

**`DocChecks::DocumentReader`** (Service, `< DocLlmBase`)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `.call(document:, checks:)` | Document, `[DocCheck]` | Trailblazer result; `ctx[:readings]` Hash or `ctx[:failure]` Symbol | provider errors (Faraday/OpenAI/Anthropic/Gemini) propagate | temp image under `tmp/`, removed in `cleanup` | Yes (read-only) |

**`DocChecks::Judge`** (Service)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `.call(check:, reading:, record:, entry:, fields:)` | DocCheck, Hash or nil, record, registry entry, `{name => Field}` | `{status:, doc_value:, record_value:, outcome_note:, explanation:, write: [Field, value] or nil}` | — | none | Yes |
| `.normalise(value, compare)` | String, Symbol | String | — | — | Yes |

**`DocChecks::Assessment`** (Service)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `.new(record)` | record | — | — | loads current run, results, documents (3 queries) | — |
| `#groups` / `#counts` / `#problems` / `#settled?` / `#stale?(name)` / `#last_failed_attempt` / `#fresh_at` | — | as design ⑦ | — | none | Yes |

**`DocCheckResult`** (Model)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `#accept!(user:, reason:)` | User, String | true | `ActiveRecord::RecordInvalid` ("Give a reason for accepting"; status must be fail/review; run must be current) | stamps | No (re-accept overwrites stamp) |

**`DocChecks::LegacyConverter`** (Service)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `.call(entity:, execute: false)` | Entity, Boolean | `{converted: [[label, field_name, question_id]], unconverted: [[question, reason]]}` | — | with `execute`: creates the All set and checks (`find_or_create_by` on `legacy_doc_question_id`) | Yes |

**Reviewer checks**
- [ ] Every raised error is handled by a caller or listed in Error Mapping
- [ ] `RunJob` is safe to enqueue twice (status guard)
- [ ] `COLUMNS` contains no control column (`verified`, `submission_status`, `entity_id`, `investor_id`, `form_type_id`, `kyc_type`, `all_docs_valid`, `*_verified`, `*_status`)

---

## Controllers, Params and Responses

| Action | Permitted params | Policy method | Success response | Failure response |
|---|---|---|---|---|
| `DocCheckSetsController#index` | — | `index?` + `policy_scope` | HTML | 403 |
| `#create` | `doc_check_set: [:record_type, :variant, :name]` | `create?` | redirect edit | 422 form |
| `#update` | `doc_check_set: [:name, doc_checks_attributes: [:id, :document_name, :kind, :label, :hint, :field_name, :fill_mode, :expected_answer, :position, :_destroy]]` | `update?` | redirect edit, notice "Document Checks saved" | 422 form with row errors |
| `#destroy` | — | `destroy?` | redirect index | — |
| `#apply_preset` | `document_name`, `preset` | `update?` | turbo_stream replace document group | turbo_stream flash "Unknown preset" |
| `#test_run` | `record_id` | `test_run?` (+ registry `can_view?` on the record) | turbo_stream: frame `doc_check_run_<id>` with "Running…" | flash "Record not found" |
| `DocCheckRunsController#create` | `record_type`, `record_id` | `create?` (registry `can_update?` + permission) | turbo_stream panel / redirect back, notice "Document Checks started for X" | `AlreadyRunning` → flash "Document Checks are already running for X" |
| `#show` | — | `show?` | HTML (frame) | 403 |
| `DocCheckResultsController#index` | `q: [status_in, document_name_eq, doc_check_run_doc_check_set_id_eq, doc_check_run_finished_at_gteq, _lteq]`, `out_of_date`, `page` | `index?` + `policy_scope` | HTML | 403 |
| `#accept` | `doc_check_result: [:accept_reason]` | `accept?` (registry `can_update?` on run.record) | turbo_stream panel | 422 turbo_stream row with "Give a reason for accepting" |
| `#rerun` | `record_type`, `record_ids: []` | `rerun?` + per-record `can_update?` (skips unauthorised) | redirect, notice "Document Checks queued for N KYCs" | — |

`record_type` is checked against `DocChecks::Registry.record_types` before `constantize`.

**Reviewer checks**
- [ ] No action without `authorize` / `policy_scope`
- [ ] Permitted params can't set `entity_id`, `user_id`, `status`, `current`, `accepted_by_id`; `record_type` is allowlisted before `constantize`

---

## Queries and Indexes

| Where | Query shape | Index used | Rows expected | Preload / batching |
|---|---|---|---|---|
| `DocCheckSet.set_for` | `where(entity_id:, record_type:, variant: [v, "all"])` then pick | UK | ≤ 2 | — |
| `StartRun` guard | `DocCheckRun.where(record_type:, record_id:, test_run: false, status: %w[queued running]).exists?` | `[record_type, record_id, status]` | ≤ 1 | — |
| `Assessment` current run | `DocCheckRun.find_by(record_type:, record_id:, current: true)` | `[record_type, record_id, current]` | 1 | — |
| `Assessment` results | `run.doc_check_results.order(:id)` | `[doc_check_run_id]` | ~10 | — |
| `Assessment` documents | `entry.record_documents(record)` (selected columns) | documents owner idx | ≤ 20 | loaded once |
| `Assessment` last failed | `DocCheckRun.where(record…, test_run: false, status: "failed").where("id > ?", current.id).order(id: :desc).first` | `[record_type, record_id, status]` | ≤ 1 | — |
| Results list | `DocCheckResult.joins(:doc_check_run).where(entity_id:, doc_check_runs: { current: true })` + ransack, `order(doc_check_runs.finished_at desc)` | `[entity_id, status]`, `[entity_id, current, finished_at]` | paged 50 | `includes(doc_check_run: :record)` for the KYC name |
| Out of date filter | After paging: group page rows by record and compute `Assessment#stale?` per record (one documents query per record on the page) | — | ≤ 50 records | Bounded by page size |
| Journey `ValidateDocuments` | `Assessment.new(kyc)` (3 queries) + `DocCheckSet.set_for` | as above | — | — |
| Conversion | `DocQuestion.where(entity_id:, for_class: "InvestorKyc").find_each` | entity idx | ≤ 20 per entity | `find_each` |

Out of date is filtered per page, so with "Out of date" selected a page may show fewer than 50 rows.
This is accepted for phase 1, because the volume is small. Phase 2's upload trigger removes most
stale rows by re-running.

**Reviewer checks**
- [ ] Every query is scoped by `entity_id` or by an already-authorised record
- [ ] No N+1 on the list (KYC name via `includes`), no unbounded loads; `distinct.pluck`, never `pluck.uniq`
- [ ] No `blank?`/`present?` on relations (use `exists?`/`none?`)

---

## Transactions, Locking and Concurrency

| Operation | Transaction scope | Lock | Race it prevents | Idempotency key |
|---|---|---|---|---|
| Start run | guard + insert | `record.lock!` (`SELECT … FOR UPDATE` on the KYC row) | Two clicks creating two runs | Status guard |
| Finish run | results `insert_all` + record writes/save + old `current` → false + new `current` → true + status/counts | `record.lock!` again, then reload the previous current run | Two finishing runs (bulk + manual) both ending current; writes interleaving with a user edit | `RunJob` status guard (`queued` only) |
| Accept | single update on the result | `result.lock!` | Double accept | — (overwrite) |
| Conversion | per entity: set + checks | none | — | UK `legacy_doc_question_id` |

The AI calls happen before the finish transaction, never inside it. Notifications and broadcasts
go in `after_commit`-equivalent code, after the transaction block returns.

**Reviewer checks**
- [ ] No external HTTP call, alert or broadcast inside a transaction
- [ ] Only the record row is locked (one lock), so there is no lock-order issue

---

## Background Jobs

| Job | Queue | Trigger | Retry / backoff | Discard on | Concurrency guard | Timeout |
|---|---|---|---|---|---|---|
| `DocChecks::RunJob` | `:default` | `StartRun` (`perform_later`); bulk job (`perform_now`) | `sidekiq_options retry: 0` | `ActiveRecord::RecordNotFound` (run or record deleted) → nothing | Run must be `queued` to start; one active run per record (`StartRun`) | Runs `running` > 30 min are expired to `failed` "Timed out" by `StartRun`/`Assessment` |

No cron is needed in phase 1.

**Reviewer checks**
- [ ] A job that runs twice, or out of order, is harmless (status guard; `current` flip compares `finished_at`)
- [ ] The bulk job still sleeps 2 s between KYCs, and collects `RunJob` error messages into `@error_msg`

---

## External Integrations

| Call | Method + path | Auth | Timeouts | Rate limit handling | Error → exception |
|---|---|---|---|---|---|
| LLM vision call (OpenAI / Anthropic / Gemini via `Langchain::LLM`, chosen by `DOCUMENT_VALIDATION_PROVIDER`) | client `chat` | `Rails.application.credentials` keys, as today in `DocLlmBase#initialize_llm` | client default plus a 120 s `Timeout.timeout` around the call | 429 → treated as provider error (run failed "The AI service is busy — try again later"); bulk pacing unchanged | connection/timeout/5xx/429/auth → `DocChecks::ProviderError` (wrapped), run failed |

The OpenAI request adds `response_format: { type: "json_object" }`. Gemini keeps
`generation_config: { response_mime_type: "application/json" }`.

**Reviewer checks**
- [ ] Prompts and images are never logged at info level; only the run id, document id and timing are logged
- [ ] Every provider failure maps to `DocChecks::ProviderError` with a user-safe message

---

## Error Mapping and Logging

| Exception / failure | Raised in | Handled by | User sees | Logged / alerted |
|---|---|---|---|---|
| no set for the record | `RunJob` | run failed | "No Document Checks are set up for this KYC" | info log |
| `ctx[:failure] == :no_llm` | `DocumentReader#init` | run failed | "The AI service is not configured" | error log |
| `DocChecks::ProviderError` | `DocumentReader` | run failed, no writes | "Document Checks could not run for X: the AI service is unavailable. Try again later." | error log (run id, provider, class) + danger alert |
| `:unsupported_file` | convert step | error rows for that document | "Can't read this file type — upload a PDF or image" | warn log (document id, mime) |
| `:unreadable_reply` / `JSON::ParserError` | parse step | error rows for that document | "The AI's reply couldn't be read — try again" | warn log (run id, document id, first 200 chars of reply at debug) |
| field missing | `Judge` | error row | "Field no longer exists" | — |
| `DocChecks::BadValue` | `Kyc.write` (date) | result becomes review "Couldn't read a date from 'X'" | as note | — |
| `DocChecks::AlreadyRunning` | `StartRun` | controller / bulk | "Document Checks are already running for X" | — |
| any other `StandardError` | `RunJob` | `rescue` → mark run failed "Something went wrong" → re-raise | danger alert | error log + error tracker |

**Reviewer checks**
- [ ] No bare `rescue => e` that swallows: the only broad rescue marks the run failed and re-raises
- [ ] Log lines carry entity id, run id, record type/id and document id

---

## Security Review

| Concern | Decision |
|---|---|
| Authorization | `DocCheckSetPolicy`: `user.entity.enable_doc_llm_validation && belongs_to_entity?(user, record)`. `DocCheckRunPolicy` / `DocCheckResultPolicy`: same permission plus registry `can_view?`/`can_update?` on the run's record (which delegate to `InvestorKycPolicy` and require `user.entity_id == kyc.entity_id`, excluding investor users) |
| Tenant isolation | Every table has `entity_id`. `policy_scope` = `where(entity_id: user.entity_id)`. `StartRun` asserts `set.entity_id == record.entity_id` |
| Code execution from config | None. Labels and hints are prompt text only. There is no `send`/`public_send` with user or AI strings. `Field` objects come only from `fields_for` |
| AI-controlled writes | Reply keys are filtered to `c<id>` of the document's checks. The written field is the check's `field_name` re-validated against `fields_for` at run time |
| Input / output sanitisation | Values, explanations and notes are rendered with ERB escaping, never `html_safe`. The legacy Json2table output keeps its existing escaping, unchanged |
| Mass assignment | Permitted params per the table above |
| Secrets | Reuses existing credentials; nothing new is stored or logged |

**Reviewer checks**
- [ ] A user from another entity cannot reach any set, run or result through any route or job
- [ ] An investor user gets 403 on `/doc_check_runs/:id` and `/doc_check_results`, and the KYC tab is not rendered for them

---

## Configuration and Rollout

| Item | Value / location |
|---|---|
| Credentials / env vars | Existing `DOCUMENT_VALIDATION_PROVIDER`, `DOCUMENT_VALIDATION_MODEL` and provider keys; IN and US set independently |
| Feature flag | Existing entity permission `enable_doc_llm_validation` |
| Cron / schedules | None |
| Deploy order | 1) migration + new code with legacy still present, behind the permission (phases 1–6). 2) Support runs `doc_checks:convert_doc_questions` dry run per entity, reviews, then `EXECUTE=1`. 3) Deploy the legacy removal (phase 7) |
| Rollback | Revert the code. The new tables can stay (unused). `doc_question_answers` and `doc_questions` are untouched throughout, so the old feature works again after a revert of the removal |

**Reviewer checks**
- [ ] Safe to deploy with the feature unused (no set → button says "No Document Checks are set up"), and safe to roll back

---

## Test Plumbing

| Feature file | Stubs / fixtures | Factories | New step definitions |
|---|---|---|---|
| `features/core/doc_check_setup.feature` (H1, H10, E11, E12, X4, X10) | — | existing entity/KYC/form type/custom field steps | `Given a Document Checks set "…" with:` (table), `When I apply the preset "CML" to "CML"` |
| `features/core/doc_check_runs.feature` (H2, E1–E8, E10, E13, E17, E18, X1, X2, X3, X5) | `@doc_checks_fake_ai` → `DocChecks::FakeReader` (`features/support/doc_checks_fake_reader.rb`): readings per document name, call counter, `raise_provider_error!`, `garbage_for(name)` | `doc_check_set`, `doc_check` | `Given the AI reads from "CML": DP ID=…;…`, `When Document Checks run for the kyc`, `Then the "PAN" check is "fail" with "…"`, `Then the AI was called 3 times` |
| `features/core/doc_check_results.feature` (H3, H4, H6, H7, X6, X7, X8) | same tag | same | `When I accept the "First holder" result with "…"`, `Then I should see the Document Checks panel with …` |
| `features/core/kyc_doc_checks_journey.feature` (H5, E9, E14, E15, E19) | same tag; journey steps from `investor_kyc_journey_steps.rb` | same | reuses journey assertions |
| `features/core/doc_checks_conversion.feature` (H8, H9, X9) | — | `doc_question` rows via table | `When the Doc Questions conversion runs for "…"( with execute)`, `Then the conversion report lists …` |

Run with `TEST_ENV_NUMBER=$RANDOM` and Redis up. `FakeReader` is installed by overriding
`DocChecks::DocumentReader.llm_call` in a `Before('@doc_checks_fake_ai')` hook, and restored in
`After`.

---

## Project Rules Checklist

| Rule | Applies? | How it is met |
|---|---|---|
| No `blank?`/`present?` on relations; use `exists?`/`none?` | Applies | Guard uses `exists?`; panels use the loaded arrays from `Assessment` |
| Dedup in SQL (`distinct.pluck`), batch bulk operations (`find_each`/`in_batches`) | Applies | `document_names` via `distinct.pluck`; conversion `find_each`; bulk via the existing job |
| Select only needed columns when loading many `account_entries`; no speculative `includes` of big associations | Applies (documents) | `record_documents` selects 5 columns; no `includes(:documents)` |
| Screen dates via `l(...)`; emails render `Mon dd, yyyy`; no human-format `strftime` | Applies | "Last run" uses `l(run.finished_at, format: :abbr_date_time)`; list dates `l(date)`; no emails |
| Date inputs use `f.date_field` / `date_field_tag`; JS dates via `locale_date_format.js` | Applies (list filter) | Date range filter uses `date_field_tag` |
| Every query entity-scoped; Pundit `authorize`/`policy_scope` on every action | Applies | See Security Review |
| MCP tool surfaces changed only via the ontology YAML | N/A | No MCP tool exposes these tables in phase 1 |
| Cucumber only (no RSpec); `TEST_ENV_NUMBER=$RANDOM` on every run | Applies | Five features above |
| `bundle exec rubocop` clean, including `IRM/RelationBlankPresent` | Applies | Final task per phase |
| Inline comments in method bodies, citing worked-example IDs | Applies | Per user convention; link `design.md#worked-examples` |

---

## Sign-off

| Reviewer | Date | Decision | Notes |
|---|---|---|---|
| | | | |
