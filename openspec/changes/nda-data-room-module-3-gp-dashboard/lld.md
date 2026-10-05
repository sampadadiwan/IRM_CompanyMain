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

- **Unique index `[nda_config_id, user_id]` on `nda_exemptions`** enforces one-exemption-per-user at the DB level; model validation mirrors it — see [Schema Detail](#schema-detail)
- **NdaStatusResolver batches four read queries** (AccessRight → investors, InvestorAccess → users, NdaAcceptance → latest per investor, NdaExemption → exempt set) using `pluck` + `where(id: [...])` to avoid N+1 — see [Queries and Indexes](#queries-and-indexes)
- **AG Grid row grouping vs Turbo Stream conflict**: exemption toggle reloads grid JSON via `fetch` + `gridApi.setRowData()` rather than Turbo Stream DOM replacement, because AG Grid manages its own DOM — see [Controllers, Params and Responses](#controllers-params-and-responses)
- **NdaReminderJob fires one `NdaReminderNotifier.deliver_later` per user** (not a batch mailer) to match the BaseNotifier pattern — see [Background Jobs](#background-jobs)
- **Gate exemption check** is a single `NdaExemption.exists?` call inserted before the stakeholder-level check in `DocumentsController#ensure_nda_accepted` — see [Queries and Indexes](#queries-and-indexes)
- **`exempted_by_id` is set server-side** from `current_user.id`, never from params — see [Security Review](#security-review)

---

## File Map

| Boundary | File | New / Modified | Responsibility |
|---|---|---|---|
| **Migration** | `db/migrate/YYYYMMDD_create_nda_exemptions.rb` | New | Create `nda_exemptions` table |
| **Model** | `app/packs/core/nda_configs/models/nda_exemption.rb` | New | NdaExemption AR model, validations, associations |
| **Model** | `app/packs/core/nda_configs/models/nda_config.rb` | Modified | Add `has_many :nda_exemptions, dependent: :destroy` |
| **Service** | `app/packs/core/nda_configs/services/nda_status_resolver.rb` | New | Resolves investor/user status data for a given NDA config + folder |
| **Controller** | `app/packs/core/nda_configs/controllers/nda_status_controller.rb` | New | `summary`, `index`, `create_exemption`, `destroy_exemption`, `send_reminders` |
| **Policy** | `app/packs/core/nda_configs/policies/nda_status_policy.rb` | New | GP-only, same-entity authorization |
| **Job** | `app/packs/core/nda_configs/jobs/nda_reminder_job.rb` | New | Dispatches NdaReminderNotifier per user |
| **Notifier** | `app/packs/core/nda_configs/mailers/nda_reminder_notifier.rb` | New | BaseNotifier subclass for NDA reminders |
| **Mailer** | `app/packs/core/nda_configs/mailers/nda_reminder_mailer.rb` | New | `send_reminder` email method |
| **Mailer view** | `app/packs/core/nda_configs/views/nda_reminder_mailer/send_reminder.html.erb` | New | Reminder email template |
| **View** | `app/packs/core/nda_configs/views/nda_status/_summary.html.erb` | New | Modal Status tab partial (Turbo Frame) |
| **View** | `app/packs/core/nda_configs/views/nda_status/index.html.erb` | New | Dedicated dashboard page |
| **View** | `app/packs/core/nda_configs/views/nda_status/index.json.jbuilder` | New | AG Grid JSON data |
| **View** | `app/packs/core/nda_configs/views/nda_status/index.xlsx.axlsx` | New | XLSX export template |
| **View** | `app/packs/core/nda_configs/views/nda_configs/_modal.html.erb` | Modified | Enable Status tab, add Turbo Frame lazy-load |
| **Gate** | `app/packs/core/documents/controllers/documents_controller.rb` | Modified | Add exemption check before stakeholder check in `ensure_nda_accepted` |
| **Routes** | `config/routes/core.rb` | Modified | Add `nda_status` routes |
| **Schema** | `db/schema.rb` | Modified | Auto-updated by migration |
| **Schema** | `db/schema_test.rb` | Modified | Manual sync with schema.rb |
| **Cucumber** | `features/core/nda_status.feature` | New | Feature file for dashboard, exemptions, reminders, export |
| **Steps** | `features/step_definitions/nda_status_steps.rb` | New | Step definitions for nda_status.feature |

**Reviewer checks**
- [ ] Every class in the design's class diagram has a file here, and nothing here is missing from it
- [ ] Files follow the pack layout (`app/packs/core/nda_configs/...`) and Packwerk boundaries
- [ ] Mailer views placed alongside mailer class under `views/nda_reminder_mailer/`

---

## Schema Detail

**`nda_exemptions`** (new)

| Column | Type | Limit | Null | Default | Index / FK | Notes |
|---|---|---|---|---|---|---|
| `id` | bigint | — | no | auto | PK | — |
| `nda_config_id` | bigint | — | no | — | FK → `nda_configs(id)`, part of unique composite | — |
| `user_id` | bigint | — | no | — | FK → `users(id)`, part of unique composite + standalone idx | The exempted user |
| `exempted_by_id` | bigint | — | no | — | FK → `users(id)` | GP who granted exemption |
| `reason` | string | 500 | yes | nil | — | Free-text justification |
| `created_at` | datetime(6) | — | no | auto | — | — |
| `updated_at` | datetime(6) | — | no | auto | — | — |

**Indexes:**

| Name | Columns | Unique | Purpose |
|---|---|---|---|
| `idx_nda_exemptions_config_user` | `[nda_config_id, user_id]` | Yes | Enforces one exemption per user per NDA config; also serves the gate query `exists?(nda_config_id:, user_id:)` |
| `idx_nda_exemptions_user` | `[user_id]` | No | Audit: "which NDAs is this user exempt from?" |

**Foreign keys:**

| Column | References | On delete |
|---|---|---|
| `nda_config_id` | `nda_configs(id)` | — (default restrict) |
| `user_id` | `users(id)` | — (default restrict) |
| `exempted_by_id` | `users(id)` | — (default restrict) |

**Migration safety:** New table with zero rows. No lock concerns. Reversible via `drop_table`. Both `schema.rb` and `schema_test.rb` must be updated after migration.

**Reviewer checks**
- [ ] Every foreign key has an index, and every uniqueness rule is enforced by a unique index
- [ ] Column limits match validation limits (`reason` limit 500 matches model `length: { maximum: 500 }`)
- [ ] Migration is reversible and safe on the production table size
- [ ] `exempted_by_id` FK references `users(id)` not `nda_configs(id)`

---

## Method Contracts

**`NdaExemption`** (Model)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| Standard AR (`create!`, `destroy`) | — | record / true | `ActiveRecord::RecordInvalid`, `RecordNotUnique` | DB write | No (create), Yes (destroy) |

Validations: `belongs_to :nda_config`, `belongs_to :user`, `belongs_to :exempted_by, class_name: "User"`. `validates :user_id, uniqueness: { scope: :nda_config_id }`. `validates :reason, length: { maximum: 500 }`.

**`NdaStatusResolver`** (Service)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `.resolve(nda_config, folder)` | `NdaConfig`, `Folder` | `StatusData` struct (see below) | None (returns empty data for edge cases) | None (read-only) | Yes |

`StatusData` is an `OpenStruct` or data object with:
- `counters` → `{ accepted: Integer, pending: Integer, declined: Integer, exempt: Integer }`
- `investor_rows` → Array of hashes: `{ investor:, status:, signed_by:, signed_at:, users: [{ user:, status:, nda_tagged:, exempt:, signer: }] }`

**`NdaReminderJob`** (Job)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `#perform(nda_config_id, user_ids)` | Integer, Array[Integer] | nil | `ActiveRecord::RecordNotFound` (if nda_config deleted) | Enqueues N notifier deliveries | Yes — delivering the same reminder twice is harmless (email, not state change) |

**`NdaReminderNotifier`** (Notifier)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `#mailer_name` | — | `NdaReminderMailer` | — | — | — |
| `#email_method` | — | `:send_reminder` | — | — | — |
| `#email_data(notification)` | `Noticed::Notification` | Hash with `notification_id`, `user_id`, `entity_id`, `nda_config_id`, `folder_name` | — | — | — |

Follows `BaseNotifier` pattern: `deliver_by :email` with `config.mailer`, `config.method`, `config.params`. `required_param :entity_id`.

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
| `NdaStatusController#create_exemption` | `nda_config_id`, `user_id`, `reason` | `create_exemption?` on NdaStatusPolicy | JSON `{ status: "ok", user_id:, exempt: true }` | 422 (validation) / 409 (duplicate — unique constraint) |
| `NdaStatusController#destroy_exemption` | `id` (route) | `destroy_exemption?` on NdaStatusPolicy | JSON `{ status: "ok", user_id:, exempt: false }` | 404 (exemption not found) |
| `NdaStatusController#send_reminders` | `nda_config_id`, `folder_id` | `send_reminders?` on NdaStatusPolicy | JSON `{ status: "ok", count: N }` | 403 / 422 (no pending investors) |

**Exemption toggle uses JSON, not Turbo Stream:** Because AG Grid manages its own DOM, Turbo Stream `replace` cannot target rows inside the grid. Instead, the Exempt/Revoke buttons fire a `fetch` POST/DELETE from a Stimulus controller, receive JSON, and call `gridApi.applyTransaction()` or re-fetch the full JSON + `gridApi.setRowData()` to update the row. This resolves the design's Risk #1 (AG Grid + Turbo Stream conflict).

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
4. `set_folder` — `Folder.find(params[:folder_id])` (only for `summary`, `index`, `send_reminders`)

**Reviewer checks**
- [ ] No action without `authorize` / `policy_scope`
- [ ] Permitted params can't set `entity_id`, `user_id` or other ownership fields (exempted_by_id set server-side)
- [ ] Exemption create/destroy returns JSON for AG Grid Stimulus controller, not Turbo Stream
- [ ] XLSX format skips pagination

---

## Queries and Indexes

| Where | Query shape | Index used | Rows expected | Preload / batching |
|---|---|---|---|---|
| `NdaStatusResolver` — investor universe | `AccessRight.where(owner: folder).flat_map(&:investors)` | `idx_access_rights_owner` (polymorphic) | ≤ 50 per folder | `investors` method on AccessRight handles expansion |
| `NdaStatusResolver` — users per investor | `InvestorAccess.where(entity_id:, investor_id: investor_ids, approved: true).includes(:user)` | `idx_investor_accesses_entity_investor` | ≤ 500 (all users across all investors) | Single query with `includes(:user)` |
| `NdaStatusResolver` — NDA tags | From InvestorAccess records above, filter `tag_list.include?("NDA")` | (in-memory filter on loaded records) | Subset of above | No extra query |
| `NdaStatusResolver` — latest acceptance | `NdaAcceptance.where(nda_config_id:, investor_id: investor_ids).select("DISTINCT ON (investor_id) *").order(:investor_id, created_at: :desc)` | `idx_nda_acceptances_config_investor_created` `[nda_config_id, investor_id, created_at]` | ≤ 50 (one per investor) | Single query. MySQL note: use `GROUP BY investor_id` + `MAX(created_at)` subquery instead of `DISTINCT ON` |
| `NdaStatusResolver` — exempt users | `NdaExemption.where(nda_config_id:).pluck(:user_id)` | `idx_nda_exemptions_config_user` (leading column) | ≤ 20 | Single pluck |
| Gate — exemption check | `NdaExemption.exists?(nda_config_id:, user_id:)` | `idx_nda_exemptions_config_user` (exact match on unique composite) | 0 or 1 | Single exists? |
| `#create_exemption` | `NdaExemption.create!(nda_config_id:, user_id:, exempted_by_id:, reason:)` | Unique index catches duplicates | 1 INSERT | — |
| `#send_reminders` — pending investors | Reuses resolver data (in-memory filter for `status == "pending"`) | — | — | — |
| `#send_reminders` — NDA-tagged users | From resolver user data, filter `nda_tagged && !exempt` | — | — | — |

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
| Create exemption | Single INSERT (implicit AR transaction) | None (unique index) | Duplicate exemption | Unique index `[nda_config_id, user_id]` |
| Destroy exemption | Single DELETE | None | Double-delete is no-op (`destroy` returns frozen record) | — |
| Send reminders | Controller resolves users, enqueues one job | None | Double-click → two jobs; mitigated by button disable in Stimulus | — |

No multi-row writes. No explicit transactions needed.

**Reviewer checks**
- [ ] No external HTTP call or email inside a transaction
- [ ] Lock order is consistent everywhere two rows are locked (N/A — no locks)

---

## Background Jobs

| Job | Queue | Trigger | Retry / backoff | Discard on | Concurrency guard | Timeout |
|---|---|---|---|---|---|---|
| `NdaReminderJob` | `:default` | `NdaStatusController#send_reminders` | 3, polynomial | `ActiveRecord::RecordNotFound` (NDA config deleted between enqueue and execution) | None (duplicate reminders are harmless emails) | Default (no custom timeout) |

**Job contract:**
- Receives `nda_config_id` (Integer) and `user_ids` (Array[Integer])
- Loads `NdaConfig.find(nda_config_id)` → raises `RecordNotFound` if deleted (discarded)
- Loops through `user_ids`, for each: `User.find(uid)` → `NdaReminderNotifier.with(record: nda_config, entity_id: nda_config.entity_id).deliver_later(user)`
- Each `deliver_later` enqueues a separate Noticed delivery job (standard Noticed pattern)

**Reviewer checks**
- [ ] A job that runs twice, or out of order, is harmless (yes — sends duplicate email, no state mutation)
- [ ] Cron entries are registered where they actually run (N/A — not a cron job, triggered by GP action)

---

## External Integrations

N/A — no third-party API calls. All data comes from internal database queries. Email delivery uses the existing Rails mailer infrastructure (ActionMailer + Sidekiq).

**Reviewer checks**
- [ ] N/A

---

## Error Mapping and Logging

| Exception | Raised in | Handled by | User sees | Logged / alerted |
|---|---|---|---|---|
| `ActiveRecord::RecordNotFound` | `set_nda_config`, `set_folder` | `ApplicationController` rescue_from | 404 page | Standard Rails 404 log |
| `ActiveRecord::RecordInvalid` | `NdaExemption.create!` | `create_exemption` rescue block | JSON `{ error: "Validation failed: ..." }` 422 | Warn log with nda_config_id + user_id |
| `ActiveRecord::RecordNotUnique` | `NdaExemption.create!` (race condition) | `create_exemption` rescue block | JSON `{ error: "User already exempt" }` 409 | Info log (expected race) |
| `Pundit::NotAuthorizedError` | `authorize` in any action | `ApplicationController` rescue_from | 403 page | Standard Pundit denial log |
| `ActiveRecord::RecordNotFound` | `NdaReminderJob#perform` | `discard_on` | N/A (background) | Sidekiq discarded job log |

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
| Input / output sanitisation | `reason` field is a plain string rendered in HTML via ERB `<%= %>` (auto-escaped). XLSX output uses `axlsx` which does not execute formulas. |
| Mass assignment | `exempted_by_id` set to `current_user.id` server-side in controller, never from `params`. Only `user_id` and `reason` come from params. |
| XLSX injection | Cell values are plain strings. No formulas. `axlsx` does not auto-execute. |

**Reviewer checks**
- [ ] A user from another entity cannot reach any record through any route, job or MCP tool
- [ ] `exempted_by_id` is never assignable from params

---

## Configuration and Rollout

| Item | Value / location |
|---|---|
| Credentials / env vars | None required |
| Feature flag | None — the Status tab becomes visible when NDA config exists (already gated by Module 1 rollout) |
| Cron / schedules | None |
| Deploy order | Migration (`create_nda_exemptions`) → code deploy → no post-deploy steps |
| Rollback | Drop `nda_exemptions` table (no data loss concern — starts empty). Remove routes and controller. Re-disable Status tab in modal. Gate reverts to Module 2 behavior (no exemption check). |

**Reviewer checks**
- [ ] Safe to deploy with the feature unused (yes — Status tab only visible with active NDA config)
- [ ] Safe to roll back (yes — drop table, revert code)

---

## Test Plumbing

| Feature file | Stubs / fixtures | Factories | New step definitions |
|---|---|---|---|
| `features/core/nda_status.feature` | None (no external services) | Entity, Folder, NdaConfig, Investor, User, InvestorAccess, AccessRight, NdaAcceptance, NdaExemption | `nda_status_steps.rb` — "I visit the NDA status dashboard", "I click the Status tab", "I exempt user {string}", "I revoke exemption for user {string}", "I send NDA reminders", "I should see {int} accepted investors", "the XLSX should contain {int} rows", "user {string} should receive a reminder email" |
| (reuses) | — | — | Existing steps from `nda_config_steps.rb` (entity/folder/NDA setup), `nda_acceptance_steps.rb` (acceptance records), `investor_access_steps.rb` (InvestorAccess with NDA tag) |

**Test data setup pattern** (matches design Worked Examples):
- Entity "Alpha Ventures" with GP Admin
- Folder "Fund Alpha Docs" with NDA-A (enabled, click_through, until_revoked)
- 3 investors (Acme Capital, Beta Holdings, Gamma Fund) with AccessRight to folder
- Users per investor with InvestorAccess (approved, NDA-tagged where specified)
- NdaAcceptance records for Acme (accepted) and Gamma (declined)
- NdaExemption for Eve (Acme) in exemption test scenarios

---

## Project Rules Checklist

| Rule | Applies? | How it is met |
|---|---|---|
| No `blank?`/`present?` on relations; use `exists?`/`none?` | Applies | Gate uses `NdaExemption.exists?(...)`; resolver uses `any?` / `none?` on preloaded arrays, not relation checks |
| Dedup in SQL (`distinct.pluck`), batch bulk operations (`find_each`/`in_batches`) | Applies | Latest acceptance uses `GROUP BY` + `MAX`; investor expansion already batched in `AccessRight#investors`; reminder job loops a bounded array (not find_each — user_ids already resolved) |
| Select only needed columns when loading many records; no speculative `includes` | Applies | `InvestorAccess` query uses `includes(:user)` — needed for every row; `NdaExemption.pluck(:user_id)` selects only the needed column |
| Screen dates via `l(...)`; emails render `Mon dd, yyyy` via `EmailDateLocalization` | Applies | Signed dates in HTML/JSON formatted via `l(date, format: :short)`; email template uses `EmailDateLocalization` for reminder date |
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
