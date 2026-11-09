# Encrypt investor PII at rest — Low-Level Design

> **Audience:** The developer who reviews the implementation plan before coding starts.
> **Companion documents:** [Design](design.md) · [Spec](specs/security/investor-pii-encryption/spec.md) · [Business rules](business-rules.md) · [Tasks](tasks.md)

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
- [Pattern Conformance](#pattern-conformance)
- [Security Detail](#security-detail)
- [Project Rules Checklist](#project-rules-checklist)
- [Sign-off](#sign-off)

---

## Review Summary

- **`ApplicationRecord.ransack` wrapper raises instead of ignoring** — every list in the app passes
  through it; a bug here breaks filters everywhere. See [Method Contracts](#method-contracts) and
  [Error Mapping](#error-mapping-and-logging).
- **Declaration order `serialize` → `encrypts` → `normalizes`** on the three models with serialized
  verification replies, and `normalizes` applying inside `where` on an encrypted attribute — proved
  by E1, E27, H12 before anything else in phase 2. See [Method Contracts](#method-contracts).
- **JSON → mediumtext on `kyc_data` / `aml_reports`** with `attribute :x, :json` — the only column
  type change. See [Schema Detail](#schema-detail).
- **Conversion via `record.encrypt` (update_columns)** — no callbacks, no `updated_at`. See
  [Transactions](#transactions-locking-and-concurrency).
- **`scrub_audits` is irreversible** and runs on the 2.3 M-row `audits` table — id-range slicing by
  `auditable_type`. See [Queries and Indexes](#queries-and-indexes).
- **Two deploys** (window open / closed) — [Configuration and Rollout](#configuration-and-rollout).

---

## File Map

| Boundary | File | New / Modified | Responsibility |
|---|---|---|---|
| ① | `db/migrate/<ts>_widen_investor_pii_columns.rb` | New | Widen 13 string columns; 5 JSON → mediumtext |
| ① | `db/schema.rb`, `db/schema_test.rb` | Modified | Mirror the migration (both files, see memory: dev DB lags) |
| ① ② | `config/application.rb` | Modified | Deploy 1: `extend_queries = true`; deploy 2: removed. Fix the "never rotate" comment |
| ② | `app/packs/core/investor_kycs/models/investor_kyc.rb` | Modified | `encrypts`, `normalizes` |
| ② | `app/packs/core/investor_kycs/models/kyc_data.rb` | Modified | `attribute … :json`, `encrypts`, `normalizes` |
| ② | `app/packs/core/investor_kycs/models/aml_report.rb` | Modified | same |
| ② | `app/packs/secondaries/offers/models/offer.rb` | Modified | `encrypts`, `normalizes` |
| ② | `app/packs/secondaries/interests/models/interest.rb` | Modified | same |
| ② | `app/packs/core/fees/models/fee.rb` | Modified | same |
| ③ | `app/packs/core/base/services/pii_encryption/registry.rb` | New | `MODELS = [InvestorKyc, Offer, Interest, Fee, KycData, AmlReport]`, audited types |
| ③ | `app/packs/core/base/services/pii_encryption/preflight.rb` | New | Keys, fingerprint, counts |
| ③ | `app/packs/core/base/services/pii_encryption/conversion.rb` | New | encrypt / verify / decrypt |
| ③ ⑧ | `app/packs/core/base/services/pii_encryption/audit_scrubber.rb` | New | `[FILTERED]` into old audits |
| ③ ⑧ | `app/packs/core/base/services/pii_encryption/dev_copy_scrubber.rb` | New | Fakes into a development copy |
| ③ | `lib/tasks/pii_encryption.rake` | New | Six tasks, region guard, EXECUTE |
| ⑤ | `app/packs/core/base/services/pii_search_fingerprint.rb` | New | HMAC per region |
| ⑤ | `app/packs/core/investor_kycs/models/investor_kyc_index.rb` | Modified | `pan_fp`, `bank_fp`; drop plain fields |
| ⑤ | `app/packs/core/investor_kycs/services/kyc_search.rb` | Modified | `bool.should` with fingerprint `term`s |
| ⑤ | `app/packs/secondaries/offers/models/offer_index.rb` | Modified | `pan_fp` |
| ⑤ | `app/packs/secondaries/offers/services/offer_search_service.rb` | Modified | fingerprint `term` |
| ⑤ | `app/packs/secondaries/offers/controllers/offers_controller.rb` | Modified | `#search` fingerprint `term` |
| ⑤ | `app/packs/core/components/search_component.rb` (+ template) | Modified | Optional ⓘ hint text param |
| ⑥ | `app/packs/core/base/services/encrypted_attribute_search.rb` | New | `vet!`, `Refused`, messages |
| ⑥ | `app/packs/core/base/models/application_record.rb` | Modified | `self.ransack` / `self.ransack!` wrapper |
| ⑥ | `app/packs/core/base/controllers/application_controller.rb` | Modified | `rescue_from EncryptedAttributeSearch::Refused` |
| ⑥ | `app/packs/core/base/helpers/application_helper.rb` | Modified | `ransack_filter_attribute_types` returns `:encrypted_exact` / `:encrypted_presence` |
| ⑥ | `app/javascript/controllers/filter_controller.js` | Modified | Limit predicate options for those types |
| ⑥ | `app/packs/core/base/models/concerns/report_prompt.rb` | Modified | "(exact match only)" hint |
| ⑥ | `app/packs/secondaries/dashboards/offer_dashboard.rb`, `interest_dashboard.rb` | Modified | `searchable: false` on PAN / bank / IFSC |
| ⑦ | `app/packs/core/base/models/report_builder_column_type.rb` | Modified | `encrypted?(key)`; allowed aggregates |
| ⑦ | `app/packs/core/base/models/report_builder_child_aggregator.rb` | Modified | `read_value` deserialize; coerce aggregate |
| ⑦ | `app/packs/core/base/models/report_builder_pivot_aggregator.rb` | Modified | Exclude encrypted group-bys |
| ⑦ | `app/packs/core/base/models/report_builder_query_engine.rb` | Modified | `apply_sort` skips encrypted |
| ⑦ | `app/packs/core/base/views/report_builder/_column_menu.html.erb`, `wizard/aggregates.html.erb` | Modified | Options + tooltip |
| ⑦ | `app/packs/ai/customer_support_agent/services/fm_query_scope.rb` | Modified | Explicit column list minus encrypted |
| ⑦ | `app/packs/ai/customer_support_agent/tools/fm_run_query_tool.rb` | Modified | Refuse SQL naming encrypted columns |
| ⑦ | `app/packs/ai/customer_support_agent/services/fm_cs_chat_provider.rb` | Modified | Prompt line: not available |
| ⑦ | `app/packs/core/base/services/pii_encryption/sqlite_decryptor.rb` | New | Decrypt pass on the dump file |
| ⑦ | `app/packs/core/entities/jobs/entity_db_dump_job.rb` | Modified | Call the decryptor after the script |
| ⑧ | `app/packs/core/components/audit_trail.rb` (+ template) | Modified | `[FILTERED]` pair → "changed (value hidden)" |
| ⑧ | `docs/operations/prod_restore.md` | Modified | Step 4b scrub |
| ⑧ | `docs/operations/dr/dr_guide.md` | Modified | Re-run `pii_encryption:encrypt` after restore |
| tests | `features/security/investor_pii_encryption.feature` | New | F1 |
| tests | `features/core/investor_kyc_pii_lookups.feature` | New | F2 |
| tests | `features/core/report_builder/encrypted_columns.feature` | New | F3 |
| tests | `features/security/investor_pii_raw_readers.feature` | New | F4 |
| tests | `features/step_definitions/investor_pii_encryption_steps.rb` | New | Raw-value, plain-row, rake steps |

**Reviewer checks**
- [ ] Every class in the design's class diagram has a file here, and nothing here is missing from it
- [ ] Files follow the pack layout and Packwerk boundaries (core/base services used by secondaries and ai packs are already dependencies)

---

## Schema Detail

**`investor_kycs`, `offers`, `interests`** (existing): ciphertext exceeds the current limits.

| Column | Change | Type | Limit | Null | Default | Index / FK | Why it's needed |
|---|---|---|---|---|---|---|---|
| `PAN` | Changed from limit 15 | string | 255 | yes | — | none | 15 chars → 90-byte envelope |
| `bank_account_number` | Changed from limit 40 | string | 255 | yes | — | none | 40 chars → 126 bytes |
| `ifsc_code` | Changed from limit 20 | string | 255 | yes | — | none | 20 chars → 98 bytes |

**`fees`** (existing):

| Column | Change | Type | Limit | Null | Default | Index / FK | Why it's needed |
|---|---|---|---|---|---|---|---|
| `bank_account_number` | Changed from limit 40 | string | 255 | yes | — | none | envelope |
| `ifsc_code` | Changed from limit 20 | string | 255 | yes | — | none | envelope |

**`kyc_data`** (existing):

| Column | Change | Type | Limit | Null | Default | Index / FK | Why it's needed |
|---|---|---|---|---|---|---|---|
| `PAN` | Changed from limit 10 | string | 255 | yes | — | none | envelope |
| `response` | Changed from json | text | 16.megabytes (mediumtext) | yes | — | none | ciphertext is not the model's JSON |
| `request_data` | Changed from json | text | mediumtext | yes | — | none | same |
| `response_data` | Changed from json | text | mediumtext | yes | — | none | same |

**`aml_reports`** (existing):

| Column | Change | Type | Limit | Null | Default | Index / FK | Why it's needed |
|---|---|---|---|---|---|---|---|
| `request_data` | Changed from json | text | mediumtext | yes | — | none | max 13,891 bytes today |
| `response_data` | Changed from json | text | mediumtext | yes | — | none | max 35,505 bytes today, grows per run |

**Migration safety:**
- Row counts (India copy): investor_kycs 8,103, offers 342, interests 204, fees 2, kyc_data 4,
  aml_reports 5,873. VARCHAR(15) → VARCHAR(255) in utf8mb4 moves the maximum from 60 to 1,020
  bytes, so the length prefix grows from 1 to 2 bytes and MySQL 8.4 uses `ALGORITHM=COPY`; at these
  sizes that is seconds per table. JSON → MEDIUMTEXT is a `COPY` too; the existing JSON text is kept.
- Reversible: `down` restores the limits / json — only valid **before** the conversion (ciphertext
  would not fit / is not valid model JSON); the down migration refuses if any value is encrypted.
- Order: this migration ships in deploy 1, before any `encrypts` is effective (same deploy is fine:
  migrations run before the new code serves).
- `schema.rb` and `schema_test.rb` both edited by hand after migrating (local migrate drops tables —
  restore and hand-insert, then `db:clean_schema`).

**Reviewer checks**
- [ ] Every changed column has a "why", and none is unjustified
- [ ] Model validations keep the plaintext limits (`investor_kyc.rb:173-175`, `offer.rb:76-78`, `interest.rb:50-52`, `fee.rb:8-9`)
- [ ] `down` refuses once ciphertext exists
- [ ] `schema_test.rb` matches `schema.rb` for these tables

---

## Method Contracts

**Model declarations** (shape, per model; one example)

```ruby
serialize :pan_verification_response, type: Hash          # existing line stays first
encrypts :PAN, :ifsc_code, deterministic: true, support_unencrypted_data: true   # deploy 2 drops the option
encrypts :bank_account_number, :pan_verification_response, :bank_verification_response, support_unencrypted_data: true
normalizes :PAN, :ifsc_code, with: ->(v) { v.to_s.strip.upcase.presence }
normalizes :bank_account_number, with: ->(v) { v.to_s.strip.presence }
```

- `KycData`: `attribute :response, :json` (and `request_data`, `response_data`) declared before
  `encrypts`. `AmlReport`: same for `request_data`, `response_data`.
- `normalizes … apply_to_nil:` stays false (nil already means blank).

**`EncryptedAttributeSearch`** (Service)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `.vet!(search)` | `Ransack::Search` | the same search, sorts on encrypted columns removed | `Refused` (message, field label) | none | Yes |
| `.allowed_predicates(klass, attr)` | model class, attribute name | `%w[eq not_eq in not_in null not_null blank present]` / `%w[null not_null blank present]` / nil | — | — | Yes |
| `.message_for(klass, attr)` | model, attribute | proposal's exact text, label from `human_attribute_name` | — | — | Yes |

**`ApplicationRecord`** (Model)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `.ransack(params = {}, options = {})` | as Ransack | vetted `Ransack::Search` | `EncryptedAttributeSearch::Refused` | none | Yes |
| `.ransack!(params = {}, options = {})` | as Ransack | same | same + Ransack's own | none | Yes |

**`PiiSearchFingerprint`** (Service)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `.for_pan(value)` | String/nil | 64-hex String or nil (blank) | — | — | Yes |
| `.for_bank(value)` | String/nil | 64-hex String or nil | — | — | Yes |

- Tidying reuses the model's normalizer: `InvestorKyc.normalize_value_for(:PAN, value)`.
- Key: `Rails.application.key_generator.generate_key("pii_search_fingerprint", 32)`, memoised.

**`PiiEncryption::Preflight`** (Service)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `.call(region:, other_fp: nil)` | `"production.in"` | Report struct (keys_present, fingerprint, counts) | `RegionMismatch`, `KeysMissing`, `FingerprintClash` | none | Yes |
| `.key_fingerprint` | — | `SHA256(primary + deterministic + salt)[0,8]` | — | — | Yes |

**`PiiEncryption::Conversion`** (Service)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `.encrypt(region:, execute:, batch: 500)` | | per model/column counts, elapsed | `RegionMismatch` | `update_columns` when execute | Yes — skips `encrypted?` values |
| `.verify(region:)` | | plain counts per model/column | `RegionMismatch` | none | Yes |
| `.decrypt(region:, execute:, batch: 500)` | | counts | `RegionMismatch` | `update_columns` (without_encryption) | Yes |

**`PiiEncryption::AuditScrubber`**, **`DevCopyScrubber`**, **`SqliteDecryptor`** (Services)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `AuditScrubber.call(region:, execute:, slice: 1_000)` | | rows updated per type | `RegionMismatch` | `update_column(:audited_changes)` | Yes — `[FILTERED]` already there is skipped |
| `DevCopyScrubber.call(execute:)` | | counts | `NotDevelopment` unless `Rails.env.development?` and DB name `IRM_development` | `update_columns` | Yes |
| `SqliteDecryptor.call(path)` | dump file path | counts | `ActiveRecord::Encryption::Errors::Decryption` | rewrites SQLite rows | Yes — plaintext rows pass through |

**`ReportBuilderColumnType`** additions

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `#encrypted?(clean_key)` | `"investor_kyc.PAN"` | Boolean from target model's `encrypted_attributes` | — | — | Yes |
| `#allowed_aggregates(clean_key)` | | `%w[count latest]` (+ internal `value`) when encrypted, else `AGGREGATES` | — | — | Yes |

**Reviewer checks**
- [ ] `Refused` is rescued in `ApplicationController` and every non-controller caller of `ransack` (jobs, report delivery) is listed in Error Mapping
- [ ] The conversion skips already-encrypted values (a re-run writes 0 rows)
- [ ] Declaration order `serialize`/`attribute` → `encrypts` → `normalizes` on every model

---

## Controllers, Params and Responses

No new actions or params. One `rescue_from`:

| Action | Permitted params | Policy method | Success response | Failure response |
|---|---|---|---|---|
| any action building a Ransack search | unchanged | unchanged | unchanged | `Refused` → HTML: `redirect_to request.path` (q dropped) + `flash[:alert]`; turbo_stream: flash stream; JSON: 422 `{error:}` |
| `InvestorKycsController#generate_all_docs` | unchanged | unchanged | unchanged | redirect to `investor_kycs_url` with the message (no generation) |

**Reviewer checks**
- [ ] No action without `authorize` / `policy_scope` (unchanged)
- [ ] The redirect never loops (it drops `q`)
- [ ] Turbo frame requests get a flash stream, not a full redirect

---

## Queries and Indexes

| Where | Query shape | Index used | Rows expected | Preload / batching |
|---|---|---|---|---|
| `Conversion.encrypt` | `Model.with_deleted.select(:id, *cols).in_batches(of: 500)` | PK | ≤ 8,625 / table | no includes |
| `Conversion.verify` | `pluck(:id, *cols)` per batch, `type.encrypted?` in Ruby | PK | same | — |
| `AuditScrubber` | `Audit.where(auditable_type: T).where(id: lo...hi).where("audited_changes LIKE ?", "%PAN%")`, `select(:id, :audited_changes)` | `auditable_index` (type, id, version) + PK range | ~9,300 of 2.3 M | id slices of 1,000; never `in_batches` + `update_all` on the whole type |
| Exact lookups | `where(PAN: ciphertext)` scoped by `investor_id` / `kyc_datas` | existing FK indexes | 1-2 | unchanged |
| Window lookups | `where(PAN: [ciphertext, plain])` (extend_queries) | as above | 1-2 | — |
| Guard | none | — | — | in memory |
| `FmQueryScope` | `SELECT <cols minus encrypted> FROM …` | unchanged | ≤ 100 | — |
| `SqliteDecryptor` | `SELECT id, col FROM t` / `UPDATE t SET col=? WHERE id=?` (SQLite) | SQLite PK | ≤ 8k | one transaction per table |

**Reviewer checks**
- [ ] Every query is scoped by `entity_id`, or explains why not (ops tasks are region-wide by design)
- [ ] No unbounded loads; `with_deleted` used so soft-deleted rows are converted (E12)
- [ ] Audit scrub never scans the whole `audits` table in one statement
- [ ] Phase features clean under Prosopite

---

## Transactions, Locking and Concurrency

| Operation | Transaction scope | Lock | Race it prevents | Idempotency key |
|---|---|---|---|---|
| Conversion batch | one per 500 ids | `SELECT … FOR UPDATE` on the batch | lost user edit during conversion | `encrypted?` check per value |
| Audit scrub slice | one per 1,000 ids | none | — | `[FILTERED]` present |
| Dump decrypt | one SQLite transaction per table | file is private to the job | — | plaintext passes through |
| User save during window | normal save | none | — | — |

- A user save between the conversion's read and its `update_columns` would be overwritten with the
  value read a moment earlier → each batch is read with `lock` (`SELECT … FOR UPDATE`) inside the
  batch transaction, so a concurrent save waits for at most one batch (500 rows, well under a
  second).

**Reviewer checks**
- [ ] No external HTTP call or email inside a transaction
- [ ] Batches are read `FOR UPDATE` inside their transaction (no lost user edit during conversion)

---

## Background Jobs

| Job | Queue | Trigger | Retry / backoff | Discard on | Concurrency guard | Timeout |
|---|---|---|---|---|---|---|
| `EntityDbDumpJob` (modified) | unchanged | unchanged | unchanged | unchanged | unchanged | + decrypt pass ≤ 1 min for 15k rows |
| No new jobs | — | Conversion runs as rake tasks by hand | — | — | — | — |

**Reviewer checks**
- [ ] A dump job that runs twice decrypts twice harmlessly
- [ ] No cron entries added

---

## External Integrations

N/A — no third-party API is added. Elasticsearch is internal; index mapping changes are applied by
`InvestorKycIndex.reset!` / `OfferIndex.reset!` (existing `ElasticImporterJob`, `lib/dr/search_indexes.rb`).

**Reviewer checks**
- [ ] Mapping for `pan_fp` / `bank_fp` is `keyword` (exact term), not analysed text

---

## Error Mapping and Logging

| Exception | Raised in | Handled by | User sees | Logged / alerted |
|---|---|---|---|---|
| `EncryptedAttributeSearch::Refused` | `ApplicationRecord.ransack` | `ApplicationController` rescue_from | flash / 422 message | `info` log with model + attribute + predicate (no value) |
| `Refused` in report delivery (scheduled report) | report job building the search | report job rescue | delivery skipped, existing failure notice | `warn` |
| `ActiveRecord::Encryption::Errors::Decryption` | model read after window | default 500 | standard error page | exception email (existing) |
| `PiiEncryption::RegionMismatch` / `KeysMissing` / `FingerprintClash` / `NotDevelopment` | rake tasks | task aborts | ops terminal message (exact texts in business-rules X10–X12, E52) | stdout |
| Decryption error in `SqliteDecryptor` | dump job | job's existing failure path | "DB dump failed" notice | exception email |

**Reviewer checks**
- [ ] No bare `rescue => e` that swallows `Decryption`
- [ ] Log lines never contain an in-scope value (only model, column, id)

---

## Security Review

| Concern | Decision |
|---|---|
| Authorization | Unchanged; guard runs on searches already policy-scoped by callers |
| Tenant isolation | ES filter by `entity_id` + `PolicyScopedSearch` unchanged; fingerprint match outside the firm is filtered |
| Secrets | Keys stay in per-region credentials; only an 8-hex fingerprint is printed; fingerprint HMAC key derived from `secret_key_base` |
| Input / output sanitisation | Messages built from `human_attribute_name`, no user input echoed |
| Mass assignment | No new params |

**Reviewer checks**
- [ ] A user from another entity cannot reach any record through any route, job or MCP tool (unchanged; X6)
- [ ] No in-scope value written to ES, logs, audit rows or the chatbot after deploy 1

---

## Configuration and Rollout

| Item | Value / location |
|---|---|
| Credentials | Existing `active_record_encryption` in `config/credentials/{staging.in,production.in,production.us}.yml.enc` — nothing new; IN and US independent |
| Fingerprint HMAC key | Derived from each env's `secret_key_base` — nothing new |
| Feature flag | None; the window is code (deploy 1 / deploy 2) |
| Cron / schedules | None |
| Deploy order | Deploy 1 (migration + `encrypts … support_unencrypted_data: true` + `extend_queries = true`) → `encrypt` → `verify` → `db:purge_binlogs` → reindex → +7 d `scrub_audits` → deploy 2 |
| Rollback (before deploy 2) | `pii_encryption:decrypt[<env>] EXECUTE=1` → `verify` reports 0 encrypted → revert code → reindex. Columns stay wide (harmless) |
| Rollback (after deploy 2) | Revert deploy 2 first (re-opens window), then as above |
| Key rotation (future) | Non-deterministic: `primary_key` becomes `[old, new]`, re-run `encrypt` (re-encrypts with newest because `encrypted?` is true — use `FORCE=1` to rewrite all); deterministic: `previous: [{deterministic_key: old}]` + `extend_queries` during the re-run, then drop `previous` |
| Prod copy on laptops | `prod_restore.md` step 4b: `bundle exec rake pii_encryption:scrub_dev_copy EXECUTE=1` |
| DR restore | `dr_guide.md`: after restore, `pii_encryption:verify` then `encrypt EXECUTE=1` if any plain |

**Reviewer checks**
- [ ] Safe to deploy with nothing converted (window open), and safe to roll back with the reverse task
- [ ] No credential or fingerprint shared between IN and US configs (fingerprint passed by hand as `OTHER_REGION_FP`)

---

## Test Plumbing

| Feature file | Stubs / fixtures | Factories | New step definitions |
|---|---|---|---|
| `features/security/investor_pii_encryption.feature` | `without_encryption` to create plain rows; toggle window via `ActiveRecord::Encryption.config.support_unencrypted_data` stub | `:investor_kyc`, `:offer`, `:interest`, `:fee`, `:kyc_data`, `:aml_report` | `the raw "PAN" of KYC "…" is not "…"`, `I run "pii_encryption:encrypt[test]" with EXECUTE`, `the window is closed` |
| `features/core/investor_kyc_pii_lookups.feature` | Chewy `:urgent` strategy for indexes; import xlsx fixtures | existing | `I filter KYCs with "PAN" "contains" "ABCPM"`, `I search KYCs for "…"` |
| `features/core/report_builder/encrypted_columns.feature` | existing report builder steps | existing | `the report column "…" shows "…"` |
| `features/security/investor_pii_raw_readers.feature` | FM chatbot LLM stub (fm_user_chat), `entity_db_dump_steps.rb`, `Rails.env` stubs for region tests | existing | `the chatbot runs SQL "…"`, `the dump file's "investor_kycs" "PAN" is "…"` |

- Region tests: tasks accept `test` as a region in the test env; wrong-region and staging refusals use stubbed `Rails.env`.

---

## Pattern Conformance

| Class | Pattern | Pack | Public interface | Modelled on |
|---|---|---|---|---|
| `EncryptedAttributeSearch` | service (module functions) | core/base | `vet!`, `allowed_predicates`, `message_for` | `SafeAttributePath` |
| `PiiSearchFingerprint` | service | core/base | `for_pan`, `for_bank` | — |
| `PiiEncryption::Preflight` | service | core/base | `call` | `aws_ebs.rake` audit helpers |
| `PiiEncryption::Conversion` | service | core/base | `encrypt`, `verify`, `decrypt` | — |
| `PiiEncryption::AuditScrubber` | service | core/base | `call` | `ComplianceDescriptionBackfill` |
| `PiiEncryption::DevCopyScrubber` | service | core/base | `call` | `EntitySetting.disable_all` (restore sanitising) |
| `PiiEncryption::SqliteDecryptor` | service | core/base | `call(path)` | — |
| `lib/tasks/pii_encryption.rake` | rake (dry run + EXECUTE + region) | — | 6 tasks | `lib/tasks/aws_ebs.rake` |

## Security Detail

| Action / job / call | Policy method | Loaded through | Permitted params | Tenant checks | Security scenario |
|---|---|---|---|---|---|
| Any list with `q` | unchanged | `policy_scope` (unchanged) | unchanged | unchanged | H18, E31, X4 (F2) |
| KYC / Offer search | unchanged | ES `entity_id` filter + `PolicyScopedSearch` | unchanged | unchanged | X6 (F2) |
| FM chatbot `run_query` | unchanged | `FmQueryScope` CTEs | — | entity CTE | X8, X9, E49 (F4) |
| `EntityDbDumpJob` | unchanged | `entity_id` in script | — | unchanged | H27 (F4) |
| Rake tasks | ops only (server shell) | region guard | `EXECUTE`, `BATCH`, `OTHER_REGION_FP` | n/a | X10–X12 (F4) |

## Project Rules Checklist

| Rule | Applies? | How it is met |
|---|---|---|
| No `blank?`/`present?` on relations; use `exists?`/`none?` | Applies | Tasks use `exists?`; value checks are on strings |
| Dedup in SQL (`distinct.pluck`), batch bulk operations (`find_each`/`in_batches`) | Applies | `in_batches(of: 500)`; audits by id slices |
| Select only needed columns when loading many `account_entries`; no speculative `includes` of big associations | Applies (pattern) | `select(:id, *cols)`; audits `select(:id, :audited_changes)` |
| Screen dates via `l(...)`; emails render `Mon dd, yyyy`; no human-format `strftime` | N/A | No dates added |
| Date inputs use `f.date_field` / `date_field_tag`; JS dates via `locale_date_format.js` | N/A | None |
| Every query entity-scoped; Pundit `authorize`/`policy_scope` on every action | Applies | Unchanged; ops tasks region-wide by design |
| MCP tool surfaces changed only via the ontology YAML | N/A | No ontology entity exposes these models |
| Cucumber only (no RSpec); `TEST_ENV_NUMBER=$RANDOM` on every run | Applies | Four features |
| `bundle exec rubocop` clean, including `IRM/RelationBlankPresent` | Applies | — |
| No query inside a row loop; `PROSOPITE=1` clean | Applies | Decrypt is in Ruby; no per-row queries added |
| Screens copy the reference screen; no new CSS | Applies | Only tooltips/flash on existing screens |

---

## Sign-off

| Reviewer | Date | Decision | Notes |
|---|---|---|---|
| | | | |
