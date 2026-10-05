# NDA Module 3: GP Status Dashboard — Low-Level Design

> **Audience:** The developer who reviews the implementation plan before coding starts.
> **Companion documents:** [Design](design.md) · [Spec](specs/) · [Tasks](tasks.md)

> **Planning phase — no code changes.** This document records the implementation-level decisions
> a reviewing developer must check. It adds to [design.md](design.md): link to its diagrams and
> worked examples rather than repeating them.

> **Reviewable, not descriptive.** Every section states concrete decisions (types, limits,
> indexes, locks, retries, error mappings) and ends with **Reviewer checks** to tick. Short
> snippets (a signature, a query shape, a config line) are fine. Full class bodies and full
> migrations are not.

> **Scale to the change.** **CORE** sections are always present. **CONDITIONAL** sections say when
> they apply. Otherwise keep the heading with `N/A — <reason>`.

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

- **Boolean `exempt_from_nda` on `investor_accesses`** — single `add_column` migration, default false — see [Schema Detail](#schema-detail)
- **NdaStatusResolver batches three read queries** (InvestorAccess → investors + users + exempt_from_nda, NdaAcceptance → latest per investor, NdaSignatory → signatory user_ids) using `pluck` + `where(id: [...])` to avoid N+1 — see [Queries and Indexes](#queries-and-indexes)
- **AG Grid row grouping vs Turbo Stream conflict**: signatory toggle reloads grid JSON via `fetch` + `gridApi.setRowData()` rather than Turbo Stream DOM replacement, because AG Grid manages its own DOM — see [Controllers, Params and Responses](#controllers-params-and-responses)
- **Gate exemption check** is `InvestorAccess.exists?(user_id:, entity_id:, approved: true, exempt_from_nda: true)` inserted before the stakeholder-level check in `DocumentsController#ensure_nda_accepted` — see [Queries and Indexes](#queries-and-indexes)
- **`tagged_by_id` (for signatories) is set server-side** from `current_user.id`, never from params — see [Security Review](#security-review)

---

## File Map

| Boundary | File | New / Modified | Responsibility |
|---|---|---|---|
| **Migration** | `db/migrate/YYYYMMDD_add_exempt_from_nda_to_investor_accesses.rb` | New | Add boolean `exempt_from_nda` column to `investor_accesses` |
| **Migration** | `db/migrate/YYYYMMDD_create_nda_signatories.rb` | New | Create `nda_signatories` table |
| **Model** | `app/packs/core/nda_configs/models/nda_signatory.rb` | New | NdaSignatory AR model, validations, associations |
| **Model** | `app/packs/core/nda_configs/models/nda_config.rb` | Modified | Add `has_many :nda_signatories, dependent: :destroy` |
| **Service** | `app/packs/core/nda_configs/services/nda_status_resolver.rb` | New | Resolves investor/user status data for a given NDA config + folder |
| **Controller** | `app/packs/core/nda_configs/controllers/nda_status_controller.rb` | New | `summary`, `index`, `create_signatory`, `destroy_signatory` |
| **Policy** | `app/packs/core/nda_configs/policies/nda_status_policy.rb` | New | GP-only, same-entity authorization |
| **View** | `app/packs/core/nda_configs/views/nda_status/_summary.html.erb` | New | Modal Status tab partial (Turbo Frame) |
| **View** | `app/packs/core/nda_configs/views/nda_status/index.html.erb` | New | Dedicated dashboard page |
| **View** | `app/packs/core/nda_configs/views/nda_status/index.json.jbuilder` | New | AG Grid JSON data |
| **View** | `app/packs/core/nda_configs/views/nda_status/index.xlsx.axlsx` | New | XLSX export template |
| **View** | `app/packs/core/nda_configs/views/nda_configs/_modal.html.erb` | Modified | Enable Status tab, add Turbo Frame lazy-load |
| **View** | `app/packs/core/documents/views/documents/_index.html.erb` | Modified | Hide NDA Settings on Data Room root (`!@folder.data_room_root?`) |
| **Gate** | `app/packs/core/documents/controllers/documents_controller.rb` | Modified | Add exemption check before stakeholder check in `ensure_nda_accepted` |
| **Controller** | `app/packs/core/investor_accesses/controllers/investor_accesses_controller.rb` | Modified | Add `exempt_from_nda` to permitted params |
| **View** | `app/packs/core/investor_accesses/views/investor_accesses/_form.html.erb` | Modified | Add `exempt_from_nda` checkbox to InvestorAccess form |
| **Routes** | `config/routes/core.rb` | Modified | Add `nda_status` routes |
| **Schema** | `db/schema.rb` | Modified | Auto-updated by migration |
| **Schema** | `db/schema_test.rb` | Modified | Manual sync with schema.rb |
| **Cucumber** | `features/core/nda_status.feature` | New | Feature file for dashboard, signatories, export |
| **Steps** | `features/step_definitions/nda_status_steps.rb` | New | Step definitions for nda_status.feature |

**Reviewer checks**
- [ ] Every class in the design's class diagram has a file here, and nothing here is missing from it
- [ ] Files follow the pack layout (`app/packs/core/nda_configs/...`) and Packwerk boundaries
- [ ] InvestorAccess controller/form changes follow existing `investor_accesses` pack layout

---

## Schema Detail

**`investor_accesses`** (modified — add column)

| Column | Type | Limit | Null | Default | Index / FK | Notes |
|---|---|---|---|---|---|---|
| `exempt_from_nda` | boolean | — | no | false | — | Stakeholder-level NDA exemption |

No new indexes needed — the gate exemption check uses the existing composite index on `[entity_id, user_id]` (or equivalent) already present on `investor_accesses`.

**`nda_signatories`** (new)

| Column | Type | Limit | Null | Default | Index / FK | Notes |
|---|---|---|---|---|---|---|
| `id` | bigint | — | no | auto | PK | — |
| `nda_config_id` | bigint | — | no | — | FK → `nda_configs(id)`, part of unique composite | — |
| `user_id` | bigint | — | no | — | FK → `users(id)`, part of unique composite + standalone idx | The designated signatory |
| `tagged_by_id` | bigint | — | no | — | FK → `users(id)` | GP who designated signatory |
| `created_at` | datetime(6) | — | no | auto | — | — |
| `updated_at` | datetime(6) | — | no | auto | — | — |

**Indexes:**

| Name | Columns | Unique | Purpose |
|---|---|---|---|
| `idx_nda_signatories_config_user` | `[nda_config_id, user_id]` | Yes | Enforces one signatory designation per user per NDA config |
| `idx_nda_signatories_user` | `[user_id]` | No | Lookup: "which NDAs is this user designated signatory for?" |

**Foreign keys:**

| Column | References | On delete |
|---|---|---|
| `nda_config_id` | `nda_configs(id)` | — (default restrict) |
| `user_id` | `users(id)` | — (default restrict) |
| `tagged_by_id` | `users(id)` | — (default restrict) |

**Migration safety:** `add_column` on `investor_accesses` is a metadata-only change in MySQL (boolean with default, NOT NULL) — safe on large tables. `nda_signatories` is a new table with zero rows. Both reversible. Both `schema.rb` and `schema_test.rb` must be updated after migration.

**Reviewer checks**
- [ ] Every foreign key has an index, and every uniqueness rule is enforced by a unique index
- [ ] `add_column :investor_accesses, :exempt_from_nda` uses `default: false, null: false`
- [ ] Migration is reversible and safe on the production table size
- [ ] `tagged_by_id` FK references `users(id)` not `nda_configs(id)`

---

## Method Contracts

**`NdaSignatory`** (Model)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| Standard AR (`create!`, `destroy`) | — | record / true | `ActiveRecord::RecordInvalid`, `RecordNotUnique` | DB write | No (create), Yes (destroy) |

Validations: `belongs_to :nda_config`, `belongs_to :user`, `belongs_to :tagged_by, class_name: "User"`. `validates :user_id, uniqueness: { scope: :nda_config_id }`.

**`NdaStatusResolver`** (Service)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `.resolve(nda_config, folder)` | `NdaConfig`, `Folder` | `StatusData` struct (see below) | None (returns empty data for edge cases) | None (read-only) | Yes |

`StatusData` is an `OpenStruct` or data object with:
- `counters` → `{ accepted: Integer, pending: Integer, declined: Integer, exempt: Integer }`
- `investor_rows` → Array of hashes: `{ investor:, status:, signed_by:, signed_at:, users: [{ user:, status:, nda_tagged:, signer: }] }`

Exempt status is derived at the investor level from `InvestorAccess.exempt_from_nda`, not carried on individual user rows.

**Reviewer checks**
- [ ] Every raised error is handled by a caller or listed in Error Mapping
- [ ] Anything a retry can repeat is idempotent
- [ ] `NdaStatusResolver` returns empty `StatusData` (not nil) when folder has no access rights

---

## Controllers, Params and Responses

| Action | Permitted params | Policy method | Success response | Failure response |
|---|---|---|---|---|
| `NdaStatusController#summary` | `nda_config_id`, `folder_id` (query) | `summary?` on NdaStatusPolicy | Turbo Frame HTML partial | 403 (policy) / 404 (record not found) |
| `NdaStatusController#index` | `nda_config_id`, `folder_id` (query) | `index?` on NdaStatusPolicy | HTML / JSON / XLSX via `respond_to` | 403 / 404 |
| `NdaStatusController#create_signatory` | `nda_config_id`, `user_id` | `create_signatory?` on NdaStatusPolicy | JSON `{ status: "ok", user_id:, signatory: true }` | 422 (validation) / 409 (duplicate — unique constraint) |
| `NdaStatusController#destroy_signatory` | `id` (route), `nda_config_id` | `destroy_signatory?` on NdaStatusPolicy | JSON `{ status: "ok", user_id:, signatory: false }` | 404 (signatory not found) |

**Signatory toggle uses JSON, not Turbo Stream:** Because AG Grid manages its own DOM, Turbo Stream `replace` cannot target rows inside the grid. Instead, the Tag/Untag buttons fire a `fetch` POST/DELETE from a Stimulus controller, receive JSON, and call `gridApi.applyTransaction()` or re-fetch the full JSON + `gridApi.setRowData()` to update the row. This resolves the design's Risk #1 (AG Grid + Turbo Stream conflict).

**`respond_to` in `#index`:**
```ruby
respond_to do |format|
  format.html { render layout: "modernize" }
  format.json { render "index" }  # index.json.jbuilder
  format.xlsx                      # index.xlsx.axlsx
end
```

**`before_action` chain:**
1. `authenticate_user!` (Devise, inherited)
2. `set_nda_config` — `NdaConfig.find(params[:nda_config_id])`
3. `authorize @nda_config, policy_class: NdaStatusPolicy` (per-action)
4. `set_folder` — `Folder.find(params[:folder_id])` (only for `summary`, `index`)

**Reviewer checks**
- [ ] No action without `authorize` / `policy_scope`
- [ ] Permitted params can't set `entity_id` or other ownership fields (`tagged_by_id` set server-side)
- [ ] Signatory create/destroy returns JSON for AG Grid Stimulus controller, not Turbo Stream
- [ ] XLSX format skips pagination

---

## Queries and Indexes

| Where | Query shape | Index used | Rows expected | Preload / batching |
|---|---|---|---|---|
| `NdaStatusResolver` — investor universe | `InvestorAccess.where(entity_id:, approved: true).includes(:user, :investor)` | `idx_investor_accesses_entity` | ≤ 500 (entity-level) | Single query with `includes(:user, :investor)` |
| `NdaStatusResolver` — exempt_from_nda | Read from InvestorAccess records already loaded (`exempt_from_nda` boolean) | — (in-memory) | Subset of above | No separate query |
| `NdaStatusResolver` — NDA tags | From InvestorAccess records above, filter `tag_list.include?("NDA")` | (in-memory filter on loaded records) | Subset of above | No extra query |
| `NdaStatusResolver` — latest acceptance | `NdaAcceptance.where(nda_config_id:, investor_id: investor_ids).select("DISTINCT ON (investor_id) *").order(:investor_id, created_at: :desc)` | `idx_nda_acceptances_config_investor_created` `[nda_config_id, investor_id, created_at]` | ≤ 50 (one per investor) | Single query. MySQL note: use `GROUP BY investor_id` + `MAX(created_at)` subquery instead of `DISTINCT ON` |
| `NdaStatusResolver` — signatory user_ids | `NdaSignatory.where(nda_config_id:).pluck(:user_id)` | `idx_nda_signatories_config_user` (leading column) | ≤ 20 | Single pluck |
| Gate — exemption check | `InvestorAccess.exists?(user_id:, entity_id:, approved: true, exempt_from_nda: true)` | Existing `investor_accesses` entity+user index | 0 or 1 | Single exists? |
| `#create_signatory` | `NdaSignatory.create!(nda_config_id:, user_id:, tagged_by_id:)` | Unique index catches duplicates | 1 INSERT | — |

**MySQL-specific: latest acceptance per investor**

Since MySQL doesn't support `DISTINCT ON`, the query uses a correlated subquery:
```sql
SELECT na.* FROM nda_acceptances na
INNER JOIN (
  SELECT investor_id, MAX(created_at) AS max_created
  FROM nda_acceptances
  WHERE nda_config_id = ?
  AND investor_id IN (?)
  GROUP BY investor_id
) latest ON na.investor_id = latest.investor_id AND na.created_at = latest.max_created
WHERE na.nda_config_id = ?
```
This is served by the existing index `[nda_config_id, investor_id, created_at]` from Module 2.

**Reviewer checks**
- [ ] Every query is scoped by `entity_id` (via NdaConfig → entity_id, AccessRight → folder → entity_id), or explains why not
- [ ] No N+1 on list pages — resolver batches all queries upfront
- [ ] No unbounded loads — investor count capped by access rights per folder (typically < 100)
- [ ] MySQL-compatible query for latest acceptance (no DISTINCT ON)

---

## Transactions, Locking and Concurrency

| Operation | Transaction scope | Lock | Race it prevents | Idempotency key |
|---|---|---|---|---|
| Create signatory | Single INSERT (implicit AR transaction) | None (unique index) | Duplicate signatory | Unique index `[nda_config_id, user_id]` |
| Destroy signatory | Single DELETE | None | Double-delete is no-op (`destroy` returns frozen record) | — |

No multi-row writes. No explicit transactions needed.

**Reviewer checks**
- [ ] No external HTTP call or email inside a transaction
- [ ] Lock order is consistent everywhere two rows are locked (N/A — no locks)

---

## Background Jobs

N/A — no background jobs in this module. Bulk reminders are descoped to a separate notifications module.

**Reviewer checks**
- [ ] N/A

---

## External Integrations

N/A — no third-party API calls. All data comes from internal database queries. No email delivery in this module (reminders descoped).

**Reviewer checks**
- [ ] N/A

---

## Error Mapping and Logging

| Exception | Raised in | Handled by | User sees | Logged / alerted |
|---|---|---|---|---|
| `ActiveRecord::RecordNotFound` | `set_nda_config`, `set_folder` | `ApplicationController` rescue_from | 404 page | Standard Rails 404 log |
| `ActiveRecord::RecordInvalid` | `NdaSignatory.create!` | `create_signatory` rescue block | JSON `{ error: "Validation failed: ..." }` 422 | Warn log with nda_config_id + user_id |
| `ActiveRecord::RecordNotUnique` | `NdaSignatory.create!` (race condition) | `create_signatory` rescue block | JSON `{ error: "User already designated" }` 409 | Info log (expected race) |
| `Pundit::NotAuthorizedError` | `authorize` in any action | `ApplicationController` rescue_from | 403 page | Standard Pundit denial log |

**Reviewer checks**
- [ ] No bare `rescue => e` that swallows errors silently
- [ ] Log lines carry the ids needed to debug (nda_config_id, user_id, entity_id)

---

## Security Review

| Concern | Decision |
|---|---|
| Authorization | `NdaStatusPolicy` on every action: `curr_role_employee? && nda_config.entity_id == user.entity_id`. Same pattern as `NdaConfigPolicy`. |
| Tenant isolation | Every query is scoped through `nda_config` → `entity_id`. The resolver takes `nda_config` and `folder` as args (both entity-scoped). No cross-entity data exposure. |
| Secrets | No secrets involved. No API keys. No file uploads. |
| Input / output sanitisation | XLSX output uses `axlsx` which does not execute formulas. No free-text input fields on the dashboard. |
| Mass assignment | `tagged_by_id` is set server-side from `current_user.id`, never from `params`. Only `user_id` comes from params for signatory actions. `exempt_from_nda` is managed via the InvestorAccess form (standard strong params). |
| XLSX injection | Cell values are plain strings. No formulas. `axlsx` does not auto-execute. |

**Reviewer checks**
- [ ] A user from another entity cannot reach any record through any route or MCP tool
- [ ] `tagged_by_id` is never assignable from params

---

## Configuration and Rollout

| Item | Value / location |
|---|---|
| Credentials / env vars | None required |
| Feature flag | None — the Status tab becomes visible when NDA config exists (already gated by Module 1 rollout) |
| Cron / schedules | None |
| Deploy order | Migration (`add_exempt_from_nda_to_investor_accesses` + `create_nda_signatories`) → code deploy → no post-deploy steps |
| Rollback | Remove `exempt_from_nda` column from `investor_accesses`, drop `nda_signatories` table. Remove routes and controller. Re-disable Status tab in modal. Gate reverts to Module 2 behavior (no exemption check). |

**Reviewer checks**
- [ ] Safe to deploy with the feature unused (yes — Status tab only visible with active NDA config)
- [ ] Safe to roll back (yes — remove column, drop table, revert code)

---

## Test Plumbing

| Feature file | Stubs / fixtures | Factories | New step definitions |
|---|---|---|---|
| `features/core/nda_status.feature` | None (no external services) | Entity, Folder, NdaConfig, Investor, User, InvestorAccess, AccessRight, NdaAcceptance, NdaSignatory | `nda_status_steps.rb` — "I visit the NDA status dashboard", "I click the Status tab", "I tag user {string} as signatory", "I remove signatory tag for user {string}", "I should see {int} accepted investors", "the XLSX should contain {int} rows" |
| (reuses) | — | — | Existing steps from `nda_config_steps.rb` (entity/folder/NDA setup), `nda_acceptance_steps.rb` (acceptance records), `investor_access_steps.rb` (InvestorAccess with NDA tag and exempt_from_nda) |

**Test data setup pattern** (matches design Worked Examples):
- Entity "Alpha Ventures" with GP Admin
- Folder "Fund Alpha Docs" with NDA-A (enabled, click_through, until_revoked)
- 3 investors (Acme Capital, Beta Holdings, Gamma Fund) with AccessRight to folder
- Users per investor with InvestorAccess (approved, NDA-tagged where specified, exempt_from_nda where specified)
- NdaAcceptance records for Acme (accepted) and Gamma (declined)
- NdaSignatory records for designated signatories in signatory test scenarios

---

## Project Rules Checklist

| Rule | Applies? | How it is met |
|---|---|---|
| No `blank?`/`present?` on relations; use `exists?`/`none?` | Applies | Gate uses `InvestorAccess.exists?(...)`; resolver uses `any?` / `none?` on preloaded arrays, not relation checks |
| Dedup in SQL (`distinct.pluck`), batch bulk operations (`find_each`/`in_batches`) | Applies | Latest acceptance uses `GROUP BY` + `MAX`; investor expansion already batched in InvestorAccess query |
| Select only needed columns when loading many records; no speculative `includes` | Applies | `InvestorAccess` query uses `includes(:user, :investor)` — needed for every row; exempt_from_nda read from InvestorAccess records already loaded |
| Screen dates via `l(...)`; emails render `Mon dd, yyyy` via `EmailDateLocalization` | Applies | Signed dates in HTML/JSON formatted via `l(date, format: :short)` |
| Date inputs use `f.date_field` / `date_field_tag` | N/A | No date input fields in this feature |
| Every query entity-scoped; Pundit `authorize`/`policy_scope` on every action | Applies | All queries scoped via `nda_config.entity_id`; `authorize` called in every controller action via `NdaStatusPolicy` |
| MCP tool surfaces changed only via the ontology YAML | N/A | No MCP tools added in this module |
| Cucumber only (no RSpec); `TEST_ENV_NUMBER=$RANDOM` on every run | Applies | Single feature file `nda_status.feature`; no RSpec files |
| `bundle exec rubocop` clean, including `IRM/RelationBlankPresent` cop | Applies | All new files must pass rubocop; `exists?` used instead of `present?` on relations |

---

## Sign-off

| Reviewer | Date | Decision | Notes |
|---|---|---|---|
| | | <!-- Approved / Changes requested --> | |
