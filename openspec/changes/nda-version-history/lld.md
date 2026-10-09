# NDA Version History & Resign Control — Low-Level Design

> **Audience:** The developer who reviews the implementation plan before coding starts.
> **Companion documents:** [Design](design.md) · [Spec](specs/nda/version-history/spec.md) · [Tasks](tasks.md)

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

- `resign_required` is a virtual attribute on `NdaConfig`, not a DB column — ensure it's in `attr_accessor` and excluded from mass assignment to the model. See [Controllers, Params and Responses](#controllers-params-and-responses).
- Gate query uses a version range with `resign_required: true` — must fall back to strict equality when no `NdaConfigVersion` records exist. See [Queries and Indexes](#queries-and-indexes).
- Backfill migration creates one record per existing config at its current version — does not reconstruct historical versions. See [Schema Detail](#schema-detail).
- Shrine `nda_document_data` is copied as-is (JSON text) to version records — the S3 objects are shared, not duplicated. See [Method Contracts](#method-contracts).

---

## File Map

| Boundary | File | New / Modified | Responsibility |
|---|---|---|---|
| ① Schema | `db/migrate/XXXX_create_nda_config_versions.rb` | New | Table creation + indexes |
| ① Schema | `db/migrate/XXXX_backfill_nda_config_versions.rb` | New | Data migration for existing configs |
| ① Model | `app/packs/core/nda_configs/models/nda_config_version.rb` | New | `NdaConfigVersion` AR model |
| ① Model | `app/packs/core/nda_configs/models/nda_config.rb` | Modified | Add `has_many :nda_config_versions` |
| ② Form | `app/packs/core/nda_configs/views/nda_configs/_form.html.erb` | Modified | Resign checkbox in version warning |
| ③ Controller | `app/packs/core/nda_configs/controllers/nda_configs_controller.rb` | Modified | `create_version_record`, conditional notify |
| ④ Gate | `app/packs/core/documents/controllers/documents_controller.rb` | Modified | `acceptance_version_current?` update |
| ⑥ Dashboard | `app/packs/core/nda_configs/views/nda_status/index.html.erb` | Modified | Version history collapsible section |
| ⑥ Dashboard | `app/packs/core/nda_configs/controllers/nda_status_controller.rb` | Modified | Load `nda_config_versions` |

**Reviewer checks**
- [ ] Every file follows pack layout (`app/packs/core/nda_configs/...`)
- [ ] No file outside `core/nda_configs` except the documents_controller gate change
- [ ] Migration timestamps are sequential (schema before backfill)

---

## Schema Detail

**`nda_config_versions`** (new table — stores one row per NDA PDF version for audit trail)

| Column | Type | Null | Default | Why this type / limit |
|---|---|---|---|---|
| `id` | `bigint` | no | auto | Standard PK |
| `nda_config_id` | `bigint` | no | — | FK to `nda_configs.id`, `ON DELETE CASCADE` |
| `version` | `integer` | no | — | Matches `nda_configs.version` integer type |
| `nda_document_data` | `text` | no | — | Shrine JSON; `text` matches `nda_configs.nda_document_data` type |
| `resign_required` | `boolean` | no | `true` | Default true preserves existing behavior for safety |
| `uploaded_by_id` | `bigint` | no | — | FK to `users.id` |
| `created_at` | `datetime(6)` | no | auto | Precision 6 matches Rails default |
| `updated_at` | `datetime(6)` | no | auto | Rails convention |

**Indexes:**

| Name | Columns | Unique | Why |
|---|---|---|---|
| `idx_nda_config_versions_config_version` | `[nda_config_id, version]` | yes | Primary lookup + prevents duplicate versions per config |
| `idx_nda_config_versions_resign_lookup` | `[nda_config_id, resign_required, version]` | no | Covers the gate query: find resign-required versions in a range for a config |

**Foreign keys:**
- `nda_config_id` → `nda_configs.id` with `ON DELETE CASCADE` (config deletion removes all version records)
- `uploaded_by_id` → `users.id` with `ON DELETE SET NULL` would lose audit data, so no cascade — use `ON DELETE RESTRICT` or no FK action (user deletion is rare and should not silently delete version records)

**Reviewer checks**
- [ ] `nda_document_data` is `text`, not `json` — matches the parent table
- [ ] Unique index on `[nda_config_id, version]` prevents duplicate version records
- [ ] `resign_required` default is `true` (safe default)
- [ ] `ON DELETE CASCADE` on `nda_config_id` FK
- [ ] No `ON DELETE CASCADE` on `uploaded_by_id`

---

## Method Contracts

### `NdaConfigVersion` model

| Method / validation | Contract |
|---|---|
| `belongs_to :nda_config` | Required |
| `belongs_to :uploaded_by, class_name: "User"` | Required |
| `validates :version, uniqueness: { scope: :nda_config_id }` | Mirrors DB unique index |
| `validates :nda_document_data, presence: true` | Every version must have a PDF reference |
| `include FileUploader::Attachment(:nda_document)` | **Do NOT include.** The version record stores raw `nda_document_data` JSON — Shrine attachment on the parent handles URL generation. For historical URL generation, reconstruct: `FileUploader::UploadedFile.new(JSON.parse(record.nda_document_data))` |

### `NdaConfig` model

| Change | Contract |
|---|---|
| `has_many :nda_config_versions, dependent: :destroy` | Cascade delete on config removal |
| `attr_accessor :resign_required` | Virtual attribute — **not** in `nda_config_params` permitted list. Read separately in controller. |

### `NdaConfigsController` private method: `create_version_record`

| Input | Type | Notes |
|---|---|---|
| `nda_config` | `NdaConfig` | Must be persisted (after save) |
| `resign_required:` | `Boolean` | Defaults to `true` |

| Output | Notes |
|---|---|
| `NdaConfigVersion` or `nil` | Returns created record, or nil if rescue fires |

Rescue: `StandardError` — log error, do not re-raise. Version history creation is non-blocking.

### `DocumentsController#acceptance_version_current?`

| Input | Current | New |
|---|---|---|
| `acceptance` | `NdaAcceptance` | Same |
| `nda_config` | `NdaConfig` | Same |
| Return | `acceptance.nda_version == nda_config.version` | See [Queries and Indexes](#queries-and-indexes) |

**Reviewer checks**
- [ ] `NdaConfigVersion` does NOT include `FileUploader::Attachment` (no Shrine attachment — raw JSON storage)
- [ ] `resign_required` virtual attribute is NOT in `nda_config_params`
- [ ] `create_version_record` rescues and logs, never raises
- [ ] `acceptance_version_current?` falls back to strict equality when no version records exist

---

## Controllers, Params and Responses

### `NdaConfigsController#update`

**Params change:** `resign_required` is read from `params[:nda_config][:resign_required]` **after** the model save, not through `nda_config_params`. It is a checkbox value (`"1"` / `"0"` or `nil`).

**Parsing:** `ActiveModel::Type::Boolean.new.cast(params.dig(:nda_config, :resign_required))` — defaults to `true` when param is missing (checkbox unchecked sends no param, but we default to true).

**Sequence after successful `@nda_config.update`:**
1. Check `@nda_config.saved_change_to_version?`
2. If true: parse `resign_required` from params (default `true`)
3. Call `create_version_record(@nda_config, resign_required: resign_required)`
4. Call `notify_version_change` only if `resign_required` is true

### `NdaConfigsController#create`

**After successful `@nda_config.save`:**
1. Existing: `auto_tag_default_signatories(@nda_config)`
2. New: `create_version_record(@nda_config, resign_required: false)` — version 1, no resign applicable

### `NdaConfigsController#nda_config_params`

**No change.** `resign_required` is NOT added to permitted params — it's a virtual attribute read separately.

**Reviewer checks**
- [ ] `resign_required` is NOT in `nda_config_params` permitted list
- [ ] Default for missing `resign_required` param is `true` (preserves existing behavior)
- [ ] `notify_version_change` is now conditional on `resign_required`
- [ ] Version 1 record created in `create` action with `resign_required: false`

---

## Queries and Indexes

### Gate query: `acceptance_version_current?`

**New logic:**

```
IF acceptance.nda_version == nda_config.version → true (exact match)

versions_with_resign = NdaConfigVersion
  .where(nda_config_id: nda_config.id)
  .where(version: (acceptance.nda_version + 1)..nda_config.version)

IF versions_with_resign.none? → true (fallback: no records = pre-feature data, use strict equality → false)

IF versions_with_resign.where(resign_required: true).exists? → false (stale)

ELSE → true (all non-resign)
```

**Fallback clarification:** When `versions_with_resign.none?` is true (no version records in range), it means either:
- Pre-feature configs with no backfill, OR
- A data inconsistency

In both cases, fall back to the original strict check: `acceptance.nda_version == nda_config.version` (which is already `false` since we're past the exact-match check). So the fallback is implicit — the method returns `false`.

**Revised simplified logic:**

```
IF acceptance.nda_version == nda_config.version → true

resign_exists = NdaConfigVersion
  .where(nda_config_id: nda_config.id)
  .where(version: (acceptance.nda_version + 1)..nda_config.version)
  .where(resign_required: true)
  .exists?

IF resign_exists → false
ELSE IF NdaConfigVersion.where(nda_config_id: nda_config.id).exists? → true (has records, none required resign)
ELSE → false (no records at all — fallback to strict, which is already false)
```

**Index used:** `idx_nda_config_versions_resign_lookup` on `[nda_config_id, resign_required, version]`

**Reviewer checks**
- [ ] Gate falls back safely when no `NdaConfigVersion` records exist (returns `false` = stale)
- [ ] Range query excludes acceptance version, includes current version
- [ ] `.exists?` used, not `.count` or `.any?` (single SQL, no loading)

---

## Transactions, Locking and Concurrency

N/A — Version record creation is append-only with a unique index. Duplicate inserts (race condition on double-submit) raise `RecordNotUnique` and are rescued. No cross-table transaction needed — the NDA config save and version record creation are independent (version record failure is non-blocking).

**Reviewer checks**
- [ ] No explicit transaction wrapping needed
- [ ] `RecordNotUnique` is rescued in `create_version_record`

---

## Background Jobs

N/A — No new background jobs. Existing `notify_version_change` already enqueues mailer jobs via `deliver_later`. The only change is the conditional trigger.

**Reviewer checks**
- [ ] No new Sidekiq jobs introduced

---

## External Integrations

N/A — No external service calls. Shrine S3 uploads happen through the existing upload flow, not through version record creation.

**Reviewer checks**
- [ ] No new API calls or webhooks

---

## Error Mapping and Logging

| Error source | Handling | Log tag |
|---|---|---|
| `create_version_record` failure | Rescue `StandardError`, log error, return nil | `[NdaVersionHistory]` |
| Duplicate version record | Rescue `ActiveRecord::RecordNotUnique`, log warn, return nil | `[NdaVersionHistory]` |

**Reviewer checks**
- [ ] All rescues log with `[NdaVersionHistory]` tag
- [ ] No error in version history creation blocks the NDA config save

---

## Security Review

| Check | Status |
|---|---|
| `resign_required` param injection | Safe — not in `nda_config_params`, read separately as boolean cast. Cannot affect model attributes. |
| Historical PDF access | PDFs served via Shrine S3 presigned URLs — same auth as current PDF. No new endpoint. |
| Version history visibility | GP-only — dashboard is already behind GP entity auth. No LP access to version history. |

**Reviewer checks**
- [ ] `resign_required` is not mass-assignable
- [ ] No new public-facing endpoint for historical PDF download (uses existing Shrine URL generation)
- [ ] Version history section is only rendered for GP users (same entity check)

---

## Configuration and Rollout

N/A — No feature flag needed. The feature is additive (checkbox defaults to checked = existing behavior). Backfill migration is safe to run in production — append-only, no data mutation.

**Reviewer checks**
- [ ] No feature flag required
- [ ] Backfill migration is idempotent (skips existing records)

---

## Test Plumbing

| Test type | Scope | Framework |
|---|---|---|
| Model spec | `NdaConfigVersion` validations, associations | RSpec |
| Controller spec | `NdaConfigsController#update` with resign param | RSpec request spec |
| Gate spec | `acceptance_version_current?` with version records | RSpec |
| Cucumber | Full flow: upload with/without resign, LP access check | Cucumber + Capybara |

**Factory:** `nda_config_version` factory in `spec/factories/nda_config_versions.rb`

| Trait | Values |
|---|---|
| default | `version: 1, resign_required: true` |
| `:no_resign` | `resign_required: false` |

**Reviewer checks**
- [ ] Factory exists before specs are written
- [ ] Gate spec covers: exact match, resign-required gap, all-non-resign gap, no-records fallback, mixed history

---

## Project Rules Checklist

| Rule | Applies | Notes |
|---|---|---|
| `# frozen_string_literal: true` on all new Ruby files | Applies | `nda_config_version.rb`, both migrations |
| YARD-style class comment on new classes | Applies | `NdaConfigVersion` model |
| No N+1 on dashboard | Applies | `.includes(:uploaded_by)` on version history query |
| ERB header comment on modified views | Applies | `_form.html.erb`, `index.html.erb` |
| Comments explaining what changed and why | Applies | All modified files |
| No `db:schema:load` — use `db:migrate:up` | Applies | Two migrations run individually |
| No names in docs | Applies | Use "GP", "LP", "the user" |

---

## Sign-off

| Reviewer | Date | Decision |
|---|---|---|
| | | |
