# NDA Module 2: LP Acceptance Flow (Stakeholder-Level) — Low-Level Design

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

- **Append-only `nda_acceptances` table** — no unique constraint, gate queries latest by `[nda_config_id, investor_id, created_at DESC]` composite index for stakeholder-level lookup — see [Schema Detail](#schema-detail)
- **Stakeholder-level gate** — resolves `investor_id` via `InvestorAccess` for current_user + nda_config.entity, then checks latest acceptance for that investor — see [Method Contracts](#method-contracts)
- **Gate short-circuits for GP employees** before any NDA query — `@folder.entity_id == current_user.entity_id` — see [Method Contracts](#method-contracts)
- **`return_to` open redirect protection** — only relative paths starting with `/` and not `//` accepted — see [Security Review](#security-review)
- **Minimal layout `nda_minimal.html.erb`** excludes all heavy JS (AG Grid, DataTables, PDFTron, Select2) — see [File Map](#file-map)
- **No `dependent: :destroy` cascade risk** — `NdaConfig` already uses `acts_as_paranoid`; NdaAcceptance records survive soft-delete of their config — see [Schema Detail](#schema-detail)

---

## File Map

| Boundary | File | New / Modified | Responsibility |
|---|---|---|---|
| Domain | `db/migrate/YYYYMMDDHHMMSS_create_nda_acceptances.rb` | New | Creates `nda_acceptances` table |
| Domain | `app/packs/core/nda_configs/models/nda_acceptance.rb` | New | NdaAcceptance model — belongs_to nda_config/investor/user/entity, status validation, `accepted?` predicate |
| Domain | `app/packs/core/nda_configs/models/nda_config.rb` | Modified | Add `has_many :nda_acceptances, dependent: :destroy` |
| Domain | `app/packs/core/nda_configs/controllers/nda_acceptances_controller.rb` | New | show/create/decline actions, minimal layout, set_nda_config/set_folder/resolve_investor (InvestorAccess lookup) |
| Domain | `app/packs/core/nda_configs/policies/nda_acceptance_policy.rb` | New | LP can view/submit; GP denied; entity-scoped via investor relationship |
| Domain | `app/packs/core/nda_configs/views/nda_acceptances/show.html.erb` | New | NDA acceptance screen — PDF iframe, checkbox, accept/decline buttons |
| Domain | `app/packs/core/nda_configs/views/nda_acceptances/declined.html.erb` | New | Decline confirmation — message, contact email, retry/back links |
| Gate | `app/packs/core/documents/controllers/documents_controller.rb` | Modified | Add `before_action :ensure_nda_accepted, only: [:folder]` + private methods (investor resolution via InvestorAccess, stakeholder-level gate check) |
| UI | `app/packs/core/base/views/layouts/nda_minimal.html.erb` | New | Minimal layout — head, CSRF, core CSS, importmap, yield, no sidebar/topbar |
| UI | `app/javascript/controllers/nda_acceptance_controller.js` | New | Stimulus: toggleAccept enables/disables Accept button on checkbox change |
| Routes | `config/routes/core.rb` | Modified | Add `resources :nda_acceptances, only: [:index, :create]` with `decline` collection route |
| Schema | `db/schema.rb` | Modified | Auto-regenerated |
| Schema | `db/schema_test.rb` | Modified | Synced with schema.rb |
| Test | `features/core/nda_acceptance.feature` | New | Cucumber scenarios for all H/E/X rows |
| Test | `features/step_definitions/nda_acceptance_steps.rb` | New | Step definitions for acceptance-specific actions |

**Reviewer checks**
- [ ] Every class in the design's class diagram has a file here, and nothing here is missing from it
- [ ] Files follow the pack layout (`app/packs/<domain>/<sub_domain>/...`) and Packwerk boundaries
- [ ] View path for `nda_acceptances/` registered in `config/application.rb` (same pattern as `nda_configs/`)

---

## Schema Detail

**`nda_acceptances`** (new)

| Column | Type | Limit | Null | Default | Index / FK | Notes |
|---|---|---|---|---|---|---|
| `id` | bigint | — | no | auto | PK | |
| `nda_config_id` | bigint | — | no | — | FK → nda_configs, composite idx | |
| `investor_id` | bigint | — | no | — | FK → investors, composite idx | Stakeholder on whose behalf the NDA is accepted |
| `user_id` | bigint | — | no | — | FK → users, idx | Who physically signed |
| `entity_id` | bigint | — | no | — | FK → entities, idx | Denormalized from nda_config for dashboard queries |
| `status` | string | 20 | no | — | — | `accepted` or `declined` |
| `nda_version` | integer | — | no | 1 | — | Copied from `nda_config.version` at time of action |
| `ip_address` | string | 45 | yes | nil | — | IPv4 or IPv6 |
| `user_agent` | string | 500 | yes | nil | — | Truncated to 500 chars |
| `accepted_at` | datetime | — | yes | nil | — | Set when status=accepted |
| `declined_at` | datetime | — | yes | nil | — | Set when status=declined |
| `created_at` | datetime | — | no | — | composite idx | Part of gate lookup index |

**Indexes:**
- `idx_nda_acceptances_gate_lookup [nda_config_id, investor_id, created_at]` — primary gate query (stakeholder-level)
- `idx_nda_acceptances_entity [entity_id]` — Module 3 dashboard queries
- `idx_nda_acceptances_user [user_id]` — audit queries (who signed)
- `idx_nda_acceptances_investor [investor_id]` — stakeholder-scoped queries

**Migration safety:** New table, no lock risk. No backfill needed. Reversible via `drop_table`. `schema.rb` and `schema_test.rb` both updated after migration.

**`has_many :nda_acceptances, dependent: :destroy` on NdaConfig:** When NdaConfig is hard-deleted (via `acts_as_paranoid#really_destroy!`), acceptance records are cascaded. On soft-delete (`destroy` via Trackable), `dependent: :destroy` fires but NdaAcceptance does not include Trackable, so records are actually deleted. This is acceptable — if a GP fully removes an NDA config, its acceptance records have no purpose. For the normal soft-delete path, acceptance records remain because `acts_as_paranoid` overrides `destroy` to set `deleted_at` without triggering `dependent`.

**Reviewer checks**
- [ ] Every foreign key has an index, and every uniqueness rule is enforced by a unique index
- [ ] Column limits match validation limits (`status` limit 20 matches model validation; `ip_address` limit 45 covers IPv6; `user_agent` limit 500 is practical)
- [ ] Migration is reversible and safe on the production table size
- [ ] No unique index on `[nda_config_id, investor_id]` — intentional (append-only, multiple records per pair)

---

## Method Contracts

**`NdaAcceptance`** (Model)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `accepted?` | none | Boolean | — | none | Yes |

**`DocumentsController`** (Controller — private gate methods)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `ensure_nda_accepted` | none (uses `@folder`, `current_user`) | nil (pass) or redirect | — | Sets `@folder` if not set. Resolves investor via InvestorAccess. Checks latest NdaAcceptance by investor_id. Redirects to NDA screen if stakeholder not accepted. | Yes — read-only check |
| `safe_return_to(path)` | String or nil | Sanitized path or fallback | — | none | Yes |

**`NdaAcceptancesController`** (Controller)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `show` | params: `nda_config_id`, `folder_id`, `return_to` | Renders acceptance screen | `ActiveRecord::RecordNotFound` if config missing | none | Yes |
| `create` | params: `nda_config_id`, `folder_id`, `return_to` | Redirect to return_to | — | Resolves investor from InvestorAccess. Creates NdaAcceptance (accepted) with investor_id and user_id | No — creates record each call |
| `decline` | params: `nda_config_id`, `folder_id`, `return_to` | Renders decline page | — | Resolves investor from InvestorAccess. Creates NdaAcceptance (declined) with investor_id and user_id | No — creates record each call |

**Reviewer checks**
- [ ] Every raised error is handled by a caller or listed in Error Mapping
- [ ] `create` and `decline` are not idempotent — double-click creates two records. Acceptable for append-only audit trail; no financial or state impact.

---

## Controllers, Params and Responses

| Action | Permitted params | Policy method | Success response | Failure response |
|---|---|---|---|---|
| `NdaAcceptancesController#show` | `nda_config_id`, `folder_id`, `return_to` (query params, not strong params) | `show?` | HTML (minimal layout) | 404 (config not found) |
| `NdaAcceptancesController#create` | `nda_config_id`, `folder_id`, `return_to` (query params) | `create?` | Redirect to `safe_return_to(params[:return_to])` | Re-render show with flash error (unlikely) |
| `NdaAcceptancesController#decline` | `nda_config_id`, `folder_id`, `return_to` (query params) | `decline?` | HTML decline page (minimal layout) | Re-render show with flash error (unlikely) |

**Note:** No strong params needed — the controller sets all NdaAcceptance attributes directly (status, nda_version from config, ip/user_agent from request). No user-supplied attributes are mass-assigned.

**Reviewer checks**
- [ ] No action without `authorize` / `policy_scope`
- [ ] Permitted params can't set `entity_id`, `user_id` or other ownership fields — confirmed, these are set server-side
- [ ] `nda_config_id` from params is validated via `NdaConfig.find` (raises RecordNotFound if tampered)

---

## Queries and Indexes

| Where | Query shape | Index used | Rows expected | Preload / batching |
|---|---|---|---|---|
| `ensure_nda_accepted` | `InvestorAccess.where(user_id: Y, entity_id: E, approved: true).pluck(:investor_id)` | Existing InvestorAccess indexes | 1-3 | None needed — small set |
| `ensure_nda_accepted` | `NdaAcceptance.where(nda_config_id: X, investor_id: investor_ids).order(created_at: :desc).limit(1)` | `idx_nda_acceptances_gate_lookup` | 0 or 1 | None needed — single row |
| `ensure_nda_accepted` | `@folder.effective_nda_config` | Ancestry gem index on `folders` | 1-3 rows (ancestor walk) | Memoized on Folder instance |
| `NdaAcceptancesController#create` | `InvestorAccess.where(user_id: Y, entity_id: E, approved: true).first` | Existing InvestorAccess indexes | 1 | None |
| `NdaAcceptancesController#show` | `NdaConfig.find(params[:nda_config_id])` | PK | 1 | None |
| `NdaAcceptancesController#show` | `Folder.find(params[:folder_id])` | PK | 1 | None |

**Reviewer checks**
- [ ] Every query is scoped by `entity_id`, or explains why not — gate resolves investor via InvestorAccess (entity-scoped), then queries NdaAcceptance by investor_id + nda_config_id which is entity-specific
- [ ] No N+1 on list pages — no list pages in this feature
- [ ] No unbounded loads

---

## Transactions, Locking and Concurrency

N/A — Single-row inserts only. No multi-table writes. No concurrent update risk on append-only records. Double-submit creates two records with identical content — harmless for audit trail.

**Reviewer checks**
- [ ] No external HTTP call or email inside a transaction — confirmed, no transactions
- [ ] Double-click on Accept/Decline is harmless — two identical records, latest still determines access correctly

---

## Background Jobs

N/A — No background jobs in Module 2. Module 8 (Notifications) will add jobs for accept/decline email notifications.

---

## External Integrations

N/A — No external API calls. E-sign (Zoho) integration is Module 6.

---

## Error Mapping and Logging

| Exception | Raised in | Handled by | User sees | Logged / alerted |
|---|---|---|---|---|
| `ActiveRecord::RecordNotFound` | `NdaConfig.find`, `Folder.find` | Rails default handler | 404 page | Standard Rails log |
| `ActiveRecord::RecordInvalid` | `NdaAcceptance` save (unlikely — minimal validations) | Controller rescue | Flash error, re-render show | Rails log |
| `Pundit::NotAuthorizedError` | `NdaAcceptancePolicy` | `ApplicationController` Pundit handler | 403 / redirect | Standard Pundit handling |

**Reviewer checks**
- [ ] No bare `rescue => e` that swallows errors silently
- [ ] Log lines carry the ids needed to debug — standard Rails logging includes controller/action/params

---

## Security Review

| Concern | Decision |
|---|---|
| Authorization | `NdaAcceptancePolicy` on every action. GP employees never reach controller (gate skips). LP must have investor relationship with NDA config's entity. |
| Tenant isolation | `entity_id` set from `nda_config.entity_id` server-side. Policy validates LP's entity relationship. |
| Secrets | No secrets involved. NDA PDF served via existing Shrine URL (already access-controlled). |
| Input / output sanitisation | `return_to` validated: must start with `/`, must not start with `//`, must not contain `://`. Reject external URLs. Entity/folder names in views escaped by default ERB. |
| Mass assignment | No mass assignment — all NdaAcceptance fields set server-side in controller. |

**`safe_return_to` validation rules:**
- Accept: relative path starting with `/` (e.g. `/documents/folder?folder_id=123&entity_id=456`)
- Reject: `nil`, empty, starts with `//`, contains `://`, starts with anything other than `/`
- Fallback: `data_rooms_folders_path`

**Reviewer checks**
- [ ] A user from another entity cannot reach any record through any route, job or MCP tool
- [ ] `return_to` cannot redirect to an external domain — validated before use

---

## Configuration and Rollout

| Item | Value / location |
|---|---|
| Credentials / env vars | None — no new credentials |
| Feature flag | Uses existing `enable_data_rooms` on Entity — NDA gate only applies within Data Room folders |
| Cron / schedules | None |
| Deploy order | 1. Migration (`rake db:migrate`) 2. Code deploy 3. No cron changes |
| Rollback | Remove `before_action :ensure_nda_accepted` from DocumentsController. Acceptance records remain harmless in DB. Migration is reversible (`drop_table`). |

**Reviewer checks**
- [ ] Safe to deploy with the feature unused — the gate only activates when a folder has an enabled NdaConfig
- [ ] Safe to roll back — removing the gate restores pre-Module-2 behavior; acceptance records are inert

---

## Test Plumbing

| Feature file | Stubs / fixtures | Factories | New step definitions |
|---|---|---|---|
| `features/core/nda_acceptance.feature` | None — no external services | NdaConfig records created in step definitions (reuse `nda_config_steps.rb` setup). NdaAcceptance records created via model. InvestorAccess records needed for investor resolution. Two LP users under same Investor for stakeholder tests. | `nda_acceptance_steps.rb`: LP navigation steps, acceptance screen assertions, accept/decline actions, redirect verification, audit field checks, stakeholder-level access checks (User B access after User A accepted, decline isolation, no-InvestorAccess denial) |

Reused step files: `nda_config_steps.rb` (entity, folder, NDA config setup), `nda_inheritance_steps.rb` (inheritance mode setup), `investor_access_steps.rb` (InvestorAccess setup with NDA tag).

Tag: `@nda`

---

## Project Rules Checklist

| Rule | Applies? | How it is met |
|---|---|---|
| No `blank?`/`present?` on relations; use `exists?`/`none?` | N/A | No relation-level blank/present checks |
| Dedup in SQL (`distinct.pluck`), batch bulk operations (`find_each`/`in_batches`) | N/A | No list pages, no bulk operations |
| Select only needed columns when loading many records | N/A | Gate loads single records only |
| Screen dates via `l(...)`; emails render `Mon dd, yyyy` | N/A | No dates displayed on acceptance screens; `accepted_at`/`declined_at` are for audit, not shown to LP |
| Date inputs use `f.date_field` / `date_field_tag` | N/A | No date inputs in this feature |
| Every query entity-scoped; Pundit `authorize`/`policy_scope` on every action | Applies | Policy enforces entity relationship; gate checks entity_id match for GP bypass |
| MCP tool surfaces changed only via the ontology YAML | N/A | No MCP tools added |
| Cucumber only (no RSpec); `TEST_ENV_NUMBER=$RANDOM` on every run | Applies | Single Cucumber feature file, tagged `@nda` |
| `bundle exec rubocop` clean, including the `IRM/RelationBlankPresent` cop | Applies | Run after implementation |
| `# frozen_string_literal: true` on every new Ruby file | Applies | All new .rb files include it |
| YARD-style class-level comments on all new classes | Applies | All new models, controllers, policies include `@description` |

---

## Sign-off

| Reviewer | Date | Decision | Notes |
|---|---|---|---|
| | | | |
