# NDA Settings Enhancements — Low-Level Design

> **Audience:** The developer who reviews the implementation plan before coding starts.
> **Companion documents:** [Design](design.md) · [Spec](specs/nda/settings-enhancements/spec.md) · [Tasks](tasks.md)

> **Note:** This change is already implemented on branch `fix/nda-resign-on-override-inheritance`.

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

- Acceptance migration uses `find_each` with individual creates + rescue, not a bulk insert — see [Transactions](#transactions-locking-and-concurrency)
- Date min clamping uses Ruby `max` not JS — see [Method Contracts](#method-contracts)
- `entity_id` must be passed to `NdaAcceptance.create!` — see [Error Mapping](#error-mapping-and-logging)
- Debug logging (`[NDA_DEBUG]`) must be removed before merge — see [Error Mapping](#error-mapping-and-logging)
- Inline `overflow: visible` scoped to NDA Status table only — see [File Map](#file-map)

---

## File Map

| Boundary | File | New / Modified | Responsibility |
|---|---|---|---|
| ① Detector | `app/packs/core/nda_configs/controllers/nda_configs_controller.rb` | Modified | `new` action: detect inherited acceptances, set `@inherited_accepted_count` |
| ②③ Resign + Migrate | `app/packs/core/nda_configs/controllers/nda_configs_controller.rb` | Modified | `create` action: capture effective NDA, read resign param, call `migrate_inherited_acceptances` |
| ③ Migrator | `app/packs/core/nda_configs/controllers/nda_configs_controller.rb` | New method | `migrate_inherited_acceptances`: private method copying acceptance records |
| ④⑤⑥ Form | `app/packs/core/nda_configs/views/nda_configs/_form.html.erb` | Modified | Resign checkbox, locked radios, expiry summary, date min clamping |
| ⑤ Expiry | `app/packs/core/nda_configs/controllers/nda_configs_controller.rb` | Modified | `edit` action: compute `@earliest_expiry`, `@latest_expiry` |
| ⑦ Overflow | `app/packs/core/nda_configs/views/nda_status/index.html.erb` | Modified | Inline overflow:visible, data-bs-display="static" |

**Reviewer checks**
- [x] Every class in the design's class diagram has a file here, and nothing here is missing from it
- [x] Files follow the pack layout (`app/packs/core/nda_configs/...`)

---

## Schema Detail

N/A — no database schema changes. All changes use existing tables and columns (NdaConfig, NdaAcceptance, NdaConfigVersion).

---

## Method Contracts

**`NdaConfigsController`** (Controller)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `#new` | `params[:override]` (optional) | renders form | Pundit::NotAuthorizedError | Sets `@inherited_accepted_count` | Yes — read-only |
| `#create` | `nda_config_params`, `params[:nda_config][:resign_required]` | turbo_stream / redirect | Pundit::NotAuthorizedError, ActiveRecord::RecordInvalid | Creates NdaConfig, updates folder mode, creates version, optionally migrates acceptances | No — creates records |
| `#edit` | — | renders form | Pundit::NotAuthorizedError | Sets `@accepted_count`, `@earliest_expiry`, `@latest_expiry` | Yes — read-only |
| `#migrate_inherited_acceptances` (private) | `source_nda: NdaConfig, target_nda: NdaConfig` | void | — (all rescued) | Creates NdaAcceptance records | Yes — rescue RecordNotUnique |

**Form view computations** (ERB)

| Computation | Input | Output | Logic |
|---|---|---|---|
| `validity_locked` | `nda_config.persisted?`, `@accepted_count` | boolean | `persisted? && accepted_count > 0` |
| `date_min` | `validity_locked`, `nda_config.validity_date` | string | Locked: `[validity_date, Date.tomorrow].max.to_s`; else: `Date.tomorrow.to_s` |
| `period_options` | `validity_locked`, `nda_config.validity_days` | array | Locked: filter `>= current_days`; else: all options |

**Reviewer checks**
- [x] Every raised error is handled by a caller or listed in Error Mapping
- [x] `migrate_inherited_acceptances` is idempotent via RecordNotUnique rescue

---

## Controllers, Params and Responses

| Action | Permitted params | Policy method | Success response | Failure response |
|---|---|---|---|---|
| `NdaConfigsController#new` | — (GET) | `new?` via `authorize @nda_config` | Renders form in modal | 403 redirect |
| `NdaConfigsController#create` | `nda_config: [:enabled, :nda_document, :validity_type, :validity_days, :validity_date, :acceptance_method, :contact_email, :notification_emails]` + `nda_config[:resign_required]` (read separately, not permitted) | `create?` via `authorize @nda_config` | turbo_stream / redirect to nda_status | 422 turbo_stream with form errors |
| `NdaConfigsController#edit` | — (GET) | `edit?` via `authorize @nda_config` | Renders form in modal | 403 redirect |

Note: `resign_required` is read via `params.dig(:nda_config, :resign_required)` — not in `permit()` because it's not a model attribute. Cast to boolean via `ActiveModel::Type::Boolean.new.cast()`.

**Reviewer checks**
- [x] No action without `authorize`
- [x] Permitted params cannot set `entity_id`, `user_id` or ownership fields
- [x] `resign_required` is not in `permit()` — read separately and cast

---

## Queries and Indexes

| Where | Query shape | Index used | Rows expected | Preload / batching |
|---|---|---|---|---|
| `new` — count inherited acceptances | `nda_acceptances.where(investor_id: [...], status: "accepted").select(:investor_id).distinct.count` | `index_nda_acceptances_on_nda_config_id` + filter | ≤ 50 | Single count query |
| `new` — folder investor IDs | `Investor.owner_access_rights(@folder, nil).pluck(:id)` | AccessRight indexes | ≤ 100 | Single pluck |
| `create` — migration source | `source_nda.nda_acceptances.where(investor_id: [...], status: "accepted")` | Same as above | ≤ 50 | `find_each` (batched) |
| `edit` — accepted count | `nda_acceptances.where(status: "accepted").select(:investor_id).distinct.count` | `index_nda_acceptances_on_nda_config_id` | ≤ 50 | Single count query |
| `edit` — expiry dates | `nda_acceptances.where(status: "accepted").pluck(:accepted_at)` | Same | ≤ 50 | Single pluck, min/max in Ruby |

**Reviewer checks**
- [x] Every query scoped by entity (through `@folder` which is verified in `set_owner`)
- [x] No N+1 — all queries are single-shot (count, pluck, find_each)

---

## Transactions, Locking and Concurrency

| Operation | Transaction scope | Lock | Race it prevents | Idempotency key |
|---|---|---|---|---|
| Acceptance migration | No explicit transaction — individual creates | None | Duplicate creates rescued by unique index | `RecordNotUnique` rescue per row |
| NdaConfig create + folder mode update | Separate saves (not wrapped) | None | — | — |

Decision: No transaction wrapping the migration because partial migration is acceptable — GP can verify on the NDA Status dashboard and manually tag missing investors.

**Reviewer checks**
- [x] No external HTTP call or email inside a transaction
- [x] Partial migration failure is safe (dashboard shows actual state)

---

## Background Jobs

N/A — all changes are synchronous, within the request cycle.

---

## External Integrations

N/A — no external API calls added.

---

## Error Mapping and Logging

| Exception | Raised in | Handled by | User sees | Logged / alerted |
|---|---|---|---|---|
| `ActiveRecord::RecordNotUnique` | `migrate_inherited_acceptances` | `rescue` block, `next` | Nothing (silent skip) | Not logged |
| `ActiveRecord::RecordInvalid` | `migrate_inherited_acceptances` | `rescue` block, `next` | Nothing (silent skip) | Not logged |

**Cleanup required:** Remove 4 `Rails.logger.info("[NDA_DEBUG]...")` lines from the `create` action before merge. These are temporary debug lines added during development.

**Reviewer checks**
- [ ] All `[NDA_DEBUG]` lines removed before merge
- [x] No bare `rescue => e` that swallows errors silently (rescue is scoped to specific exceptions)

---

## Security Review

| Concern | Decision |
|---|---|
| Authorization | `authorize @nda_config` via Pundit on every action (`new`, `create`, `edit`, `update`) |
| Tenant isolation | `set_owner` verifies `@owner.entity_id == current_user.entity_id`; all investor queries scoped through `@folder` |
| Secrets | N/A — no secrets handled |
| Input / output sanitisation | ERB auto-escapes all output; no raw HTML |
| Mass assignment | `resign_required` read via `params.dig` not `permit` — cannot set other attributes |

**Reviewer checks**
- [x] A user from another entity cannot reach any record through any route

---

## Configuration and Rollout

| Item | Value / location |
|---|---|
| Credentials / env vars | None new |
| Feature flag | None — changes are always active |
| Cron / schedules | None |
| Deploy order | Code only — no migrations needed |
| Rollback | Revert the 4 commits on the branch. Migrated acceptances remain in DB (harmless — they're valid records). |

**Reviewer checks**
- [x] Safe to deploy with the feature unused, and safe to roll back

---

## Test Plumbing

| Feature file | Stubs / fixtures | Factories | New step definitions |
|---|---|---|---|
| `features/core/nda_settings_enhancements.feature` (future) | None — uses test DB | Existing NDA setup steps from `nda_config_steps.rb`, `nda_acceptance_steps.rb`, `nda_status_steps.rb` | Resign checkbox interaction, validity locking assertion, expiry summary text assertion |

---

## Project Rules Checklist

| Rule | Applies? | How it is met |
|---|---|---|
| No `blank?`/`present?` on relations; use `exists?`/`none?` | N/A | No relation blank/present checks added |
| Dedup in SQL (`distinct.pluck`), batch bulk operations (`find_each`/`in_batches`) | Applies | `select(:investor_id).distinct.count` for counting; `find_each` for migration |
| Select only needed columns when loading many records | Applies | `pluck(:id)` for investor IDs; `pluck(:accepted_at)` for expiry dates |
| Screen dates via `l(...)`; emails render `Mon dd, yyyy` | Applies | Expiry dates formatted via `strftime("%b %d, %Y")` — matches existing NDA date formatting pattern |
| Date inputs use `f.date_field` / `date_field_tag` | Applies | `form.date_field :validity_date` with min attribute |
| Every query entity-scoped; Pundit `authorize`/`policy_scope` on every action | Applies | `set_owner` checks entity_id; `authorize @nda_config` on all actions |
| MCP tool surfaces changed only via the ontology YAML | N/A | No MCP tools changed |
| Cucumber only (no RSpec) | Applies | No RSpec tests added; Cucumber is the test target |
| `bundle exec rubocop` clean | Applies | Must verify before merge |

---

## Sign-off

| Reviewer | Date | Decision | Notes |
|---|---|---|---|
| | | | |
