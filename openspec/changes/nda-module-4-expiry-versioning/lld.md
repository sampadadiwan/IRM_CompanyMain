# NDA Module 4: Expiry & Version Management — Low-Level Design

> **Audience:** The developer who reviews the implementation plan before coding starts.
> **Companion documents:** [Design](design.md) · [Spec](specs/) · [Tasks](tasks.md)

> **Planning phase — no code changes.** This document records the implementation-level decisions
> a reviewing developer must check. It adds to [design.md](design.md): link to its diagrams and
> worked examples rather than repeating them.

> **Reviewable, not descriptive.** Every section states concrete decisions (types, limits,
> indexes, locks, retries, error mappings) and ends with **Reviewer checks** to tick. Short
> snippets (a signature, a query shape, a config line) are fine. Full class bodies and full
> migrations are not.

---

## Contents

- [Review Summary](#review-summary)
- [File Map](#file-map)
- [Schema Detail](#schema-detail)
- [Method Contracts](#method-contracts)
  - [NdaConfig](#ndaconfig)
  - [DocumentsController (gate)](#documentscontroller-gate)
  - [NdaAcceptancesController](#ndaacceptancescontroller)
  - [NdaStatusResolver](#ndastatusresolver)
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

- **Version bump relies on Shrine's dirty tracking** (`nda_document_data_changed?`) — must confirm Shrine promotion doesn't trigger the callback. See [Method Contracts → NdaConfig](#ndaconfig).
- **Gate adds zero new queries** — version and time checks are in-memory comparisons on already-loaded `NdaAcceptance` and `NdaConfig` records. See [Queries and Indexes](#queries-and-indexes).
- **`reason` query param is whitelisted** — any value outside `VALID_REASONS` is treated as nil (first-time acceptance). See [Security Review](#security-review).
- **Lapsed NDA uses a new `GET /nda_acceptances/lapsed` route** — requires a collection-level route addition and a new view file. See [Controllers, Params and Responses](#controllers-params-and-responses).
- **`validity_date_must_be_future` validation relaxed** — currently prevents saving if `validity_date <= Date.current`, which blocks GP from editing other fields after the date passes. Must be conditional on new records or date changes. See [Method Contracts → NdaConfig](#ndaconfig).
- **Accepted count query for the version warning** counts distinct investors at the current version, not total acceptance records. See [Queries and Indexes](#queries-and-indexes).

---

## File Map

| Boundary | File | New / Modified | Responsibility |
|---|---|---|---|
| ① NDA Config | `app/packs/core/nda_configs/models/nda_config.rb` | Modified | Add `before_save :increment_version_if_document_changed` callback |
| ② Version Bump | `app/packs/core/nda_configs/controllers/nda_configs_controller.rb` | Modified | Load accepted investor count for version warning data attribute |
| ② Version Bump | `app/packs/core/nda_configs/views/nda_configs/_form.html.erb` | Modified | Add version display, version warning banner, accepted count data attribute |
| ② Version Bump | `app/javascript/controllers/nda_settings_controller.js` | Modified | Add Stimulus action for new-PDF-selected → show/hide warning banner |
| ③ NDA Gate | `app/packs/core/documents/controllers/documents_controller.rb` | Modified | Add version match + time expiry checks after `latest&.accepted?`, pass `reason` param |
| ④ Acceptance Screen | `app/packs/core/nda_configs/controllers/nda_acceptances_controller.rb` | Modified | Read `reason` param in `index`, add `lapsed` action |
| ④ Acceptance Screen | `app/packs/core/nda_configs/views/nda_acceptances/index.html.erb` | Modified | Add contextual re-acceptance note banner above NDA PDF |
| ④ Acceptance Screen | `app/packs/core/nda_configs/views/nda_acceptances/lapsed.html.erb` | New | Dead-end page for specific-date expired NDAs (no form, no buttons) |
| ④ Acceptance Screen | `config/routes/core.rb` | Modified | Add `get :lapsed, on: :collection` to `nda_acceptances` resource |
| ⑤ Status Resolver | `app/packs/core/nda_configs/services/nda_status_resolver.rb` | Modified | Add Expired status derivation with reason, update counters |
| ⑤ Status Resolver | `app/packs/core/nda_configs/views/nda_status/index.html.erb` | Modified | Add Expired badge/filter to dashboard table and counters |
| ⑤ Status Resolver | `app/packs/core/nda_configs/views/nda_status/_summary.html.erb` | Modified | Add Expired counter to modal summary |

**Reviewer checks**
- [ ] Every class in the [design's class diagram](design.md#class-diagram) has a file here, and nothing here is missing from it
- [ ] Files follow the pack layout (`app/packs/core/nda_configs/...`) and Packwerk boundaries
- [ ] No files from other packs are modified (all changes stay within `core/nda_configs` and `core/documents`)

---

## Schema Detail

N/A — No new tables, columns, indexes, or migrations. All required columns exist from Modules 1–2:

| Column | Table | Type | Default | Index |
|---|---|---|---|---|
| `version` | `nda_configs` | integer | 1 | — |
| `validity_type` | `nda_configs` | varchar(20) | `"until_revoked"` | — |
| `validity_days` | `nda_configs` | integer | nil | — |
| `validity_date` | `nda_configs` | date | nil | — |
| `nda_version` | `nda_acceptances` | integer | 1 | — |
| `accepted_at` | `nda_acceptances` | datetime | nil | — |

Existing gate-lookup index: `idx_nda_acceptances_gate_lookup [nda_config_id, investor_id, created_at]`.

**Reviewer checks**
- [ ] Confirmed: no migration file needed for this module
- [ ] The gate-lookup index covers the new version/expiry check queries (yes — same query, just in-memory comparisons on the loaded record)

---

## Method Contracts

### NdaConfig

**`NdaConfig`** (Model)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `increment_version_if_document_changed` (private, before_save) | — | void | — | Increments `self.version` by 1 | Yes — same save = same increment |

**Implementation decisions:**

- **Dirty tracking:** Uses `nda_document_data_changed?` — Shrine stores the document as JSON in `nda_document_data` (text column). Any new upload changes this column's value. `ActiveRecord::Dirty` tracks it.
- **Promotion safety:** Shrine's `promote` (background processing to S3) happens asynchronously via `PromoteJob`. It uses `Attacher#atomic_promote` which saves the record, but the document data change during promotion is a metadata update (storage key change), not a user-initiated upload. However, `nda_document_data_changed?` WILL fire on promotion. **Decision:** Guard the callback with `nda_document_data_previously_changed?` is wrong — use `will_save_change_to_nda_document_data?` only when the change originates from a controller context. Safer approach: check `nda_document_data_change` and verify the old value was a different document (different `id` key in the Shrine JSON), not just a metadata/storage update.
  - **Concrete check:** Compare `nda_document_data_was` parsed JSON `"id"` vs current parsed JSON `"id"`. If the file id changed, it's a new upload. Shrine generates a unique id per upload, so same-filename re-uploads get different ids.
- **Disabled config guard:** Only increment when `enabled?` — uploading a PDF on a disabled config shouldn't trigger version semantics (see design card ①).
- **`validity_date_must_be_future` relaxation:** Currently `errors.add(:validity_date, "must be in the future") if validity_date <= Date.current`. This prevents a GP from editing ANY field on the config after the validity_date passes. **Decision:** Change the validation to run only on new records or when `validity_date` itself changed: `if: -> { validity_type == "specific_date" && validity_date.present? && (new_record? || will_save_change_to_validity_date?) }`.

**Reviewer checks**
- [ ] `nda_document_data_changed?` does not false-positive on Shrine promotion (file id comparison guards it)
- [ ] Version only increments when `enabled?` is true
- [ ] `validity_date_must_be_future` validation won't block GP from editing other fields after date passes

### DocumentsController (gate)

**`DocumentsController`** (Controller — `#ensure_nda_accepted` private method)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `acceptance_version_current?(acceptance, nda_config)` (private) | NdaAcceptance, NdaConfig | Boolean | — | — | Yes |
| `acceptance_time_valid?(acceptance, nda_config)` (private) | NdaAcceptance, NdaConfig | Boolean | — | — | Yes |

**Implementation decisions:**

- **Check order in `ensure_nda_accepted`:** After the existing `return if latest&.accepted?` line is replaced with the expanded checks:
  1. `return if latest&.accepted?` removed — replaced by explicit version + time checks below
  2. If `latest.nil?` or not `accepted?` → redirect with `reason` absent (first-time/decline behavior unchanged)
  3. If `latest.nda_version != nda_config.version` → redirect with `reason=version_mismatch`
  4. If `nda_config.validity_type == "specific_date"` and `nda_config.validity_date < Date.current` → redirect with `reason=lapsed`
  5. If `nda_config.validity_type == "fixed_period"` and `latest.accepted_at + nda_config.validity_days.days < Time.current` → redirect with `reason=expired`
  6. `return` (acceptance is valid)

- **Lapsed redirect target:** `reason=lapsed` redirects to `lapsed_nda_acceptances_path(...)` instead of `nda_acceptances_path(...)`. All other reasons redirect to `nda_acceptances_path(...)` with the reason param.

- **`reason` param on redirect URL:** Appended as a query param alongside existing `nda_config_id`, `folder_id`, `return_to`.

- **No new queries:** `nda_config` and `latest` are already loaded. Version comparison and date arithmetic are in-memory.

**Reviewer checks**
- [ ] The `return if latest&.accepted?` line is replaced, not duplicated
- [ ] Lapsed check uses `Date.current` (not `Time.current`) for date-only comparison
- [ ] Fixed-period check uses `Time.current` (not `Date.current`) for datetime comparison with `accepted_at`
- [ ] Exempt investor check remains BEFORE all version/time checks (existing order preserved)

### NdaAcceptancesController

**`NdaAcceptancesController`** (Controller)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `index` (existing, modified) | — | renders view | — | Reads `reason` param, sets `@reason` | Yes |
| `lapsed` (new) | — | renders `lapsed.html.erb` | — | Sets `@nda_config`, `@folder` | Yes |

**Implementation decisions:**

- **`VALID_REASONS` constant:** `%w[version_mismatch expired].freeze` — defined on the controller. `lapsed` is NOT in this list because the lapsed page has its own action/route.
- **`@reason` assignment in `index`:** `@reason = VALID_REASONS.include?(params[:reason]) ? params[:reason] : nil`. Any invalid/missing value → nil → no note shown.
- **`lapsed` action:** Uses existing `before_action :set_nda_config` and `before_action :set_folder`. Authorizes via `authorize NdaAcceptance.new(nda_config: @nda_config), :show?` (same as `index`).
- **`lapsed` view:** Modeled on `declined.html.erb` — same `turbo_frame_tag "documents_frame"`, same layout, same logo/back-button pattern. Shows: folder name, `@nda_config.validity_date` formatted via `l(...)`, contact email (if present), "Back to Data Rooms" link. No form, no checkbox, no buttons.

**Reviewer checks**
- [ ] `reason` param is validated against a whitelist, not passed raw to the view
- [ ] `lapsed` action has `authorize` call
- [ ] `lapsed.html.erb` has no Accept/Decline form — dead-end page only

### NdaStatusResolver

**`NdaStatusResolver`** (Service)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `acceptance_expired?(acceptance, nda_config)` (private) | NdaAcceptance, NdaConfig | Boolean | — | — | Yes |

**Implementation decisions:**

- **Status derivation order change in `build_investor_rows`:** Between `accepted?` check and returning `"Accepted"`, insert version and time checks:
  ```
  Exempt → (no acceptance) Pending → Declined → (accepted but version stale) Expired → (accepted but time expired) Expired → Accepted
  ```
- **Expiry reason:** Each investor row gains `:expiry_reason` key — `nil`, `"version"`, or `"period"`. Used by dashboard view for reason indicator tooltip.
- **Counter update:** `compute_counters` adds `:expired` key (integer, default 0). `empty_result` also adds `:expired`.
- **`acceptance_expired?` logic:** Same as gate — checks `nda_version` vs `@nda_config.version`, then `validity_type`-specific time check. Extracted as a shared private method since both version and time checks are needed.
- **No new queries:** The resolver already loads all acceptances in batch. Version and validity settings are on `@nda_config`, already in memory.

**Reviewer checks**
- [ ] `compute_counters` includes `:expired` key
- [ ] `empty_result` includes `:expired` key
- [ ] Expiry reason is per-investor-row, not per-acceptance
- [ ] The resolver uses the same expiry logic as the gate (version check, then time check)

---

## Controllers, Params and Responses

| Action | Permitted params | Policy method | Success response | Failure response |
|---|---|---|---|---|
| `NdaAcceptancesController#index` (modified) | `reason` (query, whitelisted) | `show?` | 200 + acceptance screen (with note if reason present) | — |
| `NdaAcceptancesController#lapsed` (new) | `nda_config_id`, `folder_id` (query) | `show?` on new NdaAcceptance | 200 + lapsed page (422 for Turbo frame) | — |
| `NdaConfigsController#edit` (modified) | — | `edit?` | 200 + form with version display + accepted count data attr | — |
| `NdaConfigsController#update` (unchanged) | existing `nda_config_params` | `update?` | turbo_stream | 422 + form errors |

**Route addition:**

```ruby
resources :nda_acceptances, controller: "nda_acceptances", only: %i[index create] do
  post :decline, on: :collection
  get :lapsed, on: :collection  # NEW — Module 4
end
```

**Lapsed action response status:** Must return `422` (like `decline`) so Turbo processes the response inside `documents_frame`. A 200 to a GET navigated via Turbo Frame works fine, but explicitly using `render :lapsed` without status is a 200 which is correct for a GET — **no 422 needed for GET requests** (only POST responses need non-redirect status for Turbo).

**Reviewer checks**
- [ ] No action without `authorize` / `policy_scope`
- [ ] Permitted params can't set `entity_id`, `user_id` or other ownership fields
- [ ] `lapsed` is a GET route (collection-level), not POST
- [ ] `lapsed` renders inside `documents_frame` turbo-frame tag (consistent with index and declined views)

---

## Queries and Indexes

| Where | Query shape | Index used | Rows expected | Preload / batching |
|---|---|---|---|---|
| Gate — existing (unchanged) | `NdaAcceptance.where(nda_config_id:, investor_id:).order(created_at: :desc).limit(1)` | `idx_nda_acceptances_gate_lookup` | 1 | — |
| Gate — version/time check | In-memory: `latest.nda_version != nda_config.version`, `latest.accepted_at + days < Time.current` | N/A (in-memory) | 0 (no query) | — |
| Version warning count | `NdaAcceptance.where(nda_config_id:).where(status: "accepted").select(:investor_id).distinct.count` | `idx_nda_acceptances_gate_lookup` (nda_config_id prefix) | 1 result (count) | — |
| Status resolver — existing (unchanged) | Subquery with `MAX(created_at)` per investor | `idx_nda_acceptances_gate_lookup` | All investors (batched) | `includes(:user)` |
| Status resolver — expiry check | In-memory on loaded acceptance records | N/A (in-memory) | 0 (no query) | — |

**Note on accepted count query for version warning:** The count query runs once when the GP opens the NDA Settings modal `edit` action. It counts distinct investors whose latest accepted acceptance is at the current version. Simpler approach: count ALL accepted investors regardless of version — they'll all need to re-accept if the version bumps. This avoids a complex subquery:

```
NdaAcceptance.where(nda_config_id: @nda_config.id, status: "accepted")
             .select(:investor_id).distinct.count
```

This slightly overcounts (includes investors who already re-accepted at the current version and also have old accepted records), but the count is directional guidance, not a legal commitment. The warning says "up to X" or "X investors have accepted" — either framing is acceptable.

**Reviewer checks**
- [ ] Every query is scoped by `entity_id` or `nda_config_id` (which is entity-scoped)
- [ ] No N+1 on list pages. No unbounded loads
- [ ] The accepted count query uses `distinct` on `investor_id` to avoid counting multiple acceptances per investor

---

## Transactions, Locking and Concurrency

| Operation | Transaction scope | Lock | Race it prevents | Idempotency key |
|---|---|---|---|---|
| Version increment (before_save) | Single NdaConfig save | Row-level (implicit ActiveRecord) | Concurrent PDF uploads by same GP | — (last write wins, monotonic increment) |
| Acceptance creation | Single NdaAcceptance insert | — | Duplicate re-acceptance | Append-only — no duplicate prevention needed; latest record wins |

**Concurrent version bump:** If two GP users upload PDFs simultaneously, both saves trigger `before_save`. Each reads the current `version` and increments by 1. With row-level locking, the second save reads the updated version and increments from there. **No explicit locking needed** — MySQL's default isolation level (REPEATABLE READ) handles this via implicit row locks on UPDATE.

**Concurrent re-acceptance:** If the same LP submits Accept twice rapidly, two NdaAcceptance records are created. Both are valid (same version, same accepted_at ≈ now). The gate always reads the latest by `created_at`, so the second record supersedes the first. No harm.

**Reviewer checks**
- [ ] No external HTTP call or email inside a transaction
- [ ] Lock order is consistent everywhere two rows are locked
- [ ] Concurrent version bumps result in monotonically increasing versions (no skip or duplicate)

---

## Background Jobs

N/A — No background jobs added. Version increment is synchronous (before_save). Expiry checks are read-time. Module 8 (Notifications) will add jobs for notifying affected investors; that is out of scope for Module 4.

**Reviewer checks**
- [ ] Confirmed: no jobs or cron entries in this module

---

## External Integrations

N/A — No external API calls. NDA document is stored in S3 via Shrine (existing infrastructure). No new S3 interactions.

**Reviewer checks**
- [ ] Confirmed: no external API integrations in this module

---

## Error Mapping and Logging

| Exception | Raised in | Handled by | User sees | Logged / alerted |
|---|---|---|---|---|
| `ActiveRecord::RecordNotFound` | `NdaAcceptancesController#lapsed` (`set_nda_config`) | ApplicationController rescue | 404 page | Standard Rails 404 log |
| `Pundit::NotAuthorizedError` | `NdaAcceptancesController#lapsed` (`authorize`) | ApplicationController rescue | 403 / redirect to sign in | Standard Pundit error log |

No new exceptions introduced. All error paths follow existing patterns.

**Reviewer checks**
- [ ] No bare `rescue => e` that swallows errors silently
- [ ] Log lines carry the ids needed to debug (entity, record, external id)

---

## Security Review

| Concern | Decision |
|---|---|
| Authorization | `lapsed` action uses `authorize NdaAcceptance.new(nda_config: @nda_config), :show?` — same policy as `index`. Version warning count scoped by `nda_config_id` which is entity-scoped via `NdaConfigPolicy`. |
| Tenant isolation | Gate: `nda_config` resolved via `@folder.effective_nda_config` which is entity-scoped. Acceptance queries scoped by `nda_config_id`. Warning count scoped by `nda_config_id`. No cross-entity data exposure. |
| Secrets | No new secrets. No new credential storage. |
| Input / output sanitisation | `reason` param whitelisted against `VALID_REASONS` constant. Any unrecognized value treated as nil. Displayed `validity_date` uses `l(...)` helper (Rails I18n localization). No raw user input rendered. |
| Mass assignment | No change to `nda_config_params`. Version is auto-incremented via callback, not settable via params. `reason` is a read-only query param, not a model attribute. |

**Reviewer checks**
- [ ] A user from another entity cannot reach any record through any route, job or MCP tool
- [ ] `reason` param cannot inject HTML/JS (whitelisted to fixed string values, not rendered as raw HTML)
- [ ] `version` field cannot be set via params (auto-incremented only)

---

## Configuration and Rollout

| Item | Value / location |
|---|---|
| Credentials / env vars | None added |
| Feature flag | None — NDA feature is already gated by `enable_data_rooms` on Entity. Module 4 activates only when `validity_type != "until_revoked"` or when a version bump occurs. |
| Cron / schedules | None |
| Deploy order | Code only (no migrations). Standard deploy via `bundle exec cap staging deploy`. |
| Rollback | Revert commit. Version counter is monotonically increasing, so rolling back code won't reset versions. Existing acceptances remain valid. Rolling back simply removes the expiry and version checks — all accepted investors regain access. No data cleanup needed. |

**Reviewer checks**
- [ ] Safe to deploy with the feature unused (until_revoked configs behave exactly as before), and safe to roll back (removing checks is permissive, not restrictive)

---

## Test Plumbing

| Feature file | Stubs / fixtures | Factories | New step definitions |
|---|---|---|---|
| `features/core/nda_expiry.feature` | Time travel via `travel_to` for fixed-period expiry testing | Reuse existing `NdaConfig`, `NdaAcceptance`, `InvestorAccess` factories | Steps for: version bump via PDF upload, time-based expiry, re-acceptance note verification, lapsed page verification, dashboard Expired status |

**Step definition location:** Add to existing `features/step_definitions/nda_acceptance_steps.rb` — no new step file.

**New steps needed:**

| Step pattern | What it does |
|---|---|
| `Given the NDA config has version {int}` | Sets `nda_config.update!(version: n)` |
| `Given the NDA acceptance was created {int} days ago` | Sets `acceptance.update!(accepted_at: n.days.ago)` |
| `When the GP uploads a new NDA PDF` | Simulates PDF replacement via form submission |
| `Then I should see the re-acceptance note {string}` | Asserts note banner text on acceptance screen |
| `Then I should see the lapsed NDA page` | Asserts lapsed page elements (no Accept/Decline, expiry date, contact info) |
| `Then the NDA config version should be {int}` | Asserts `nda_config.reload.version == n` |
| `Then the investor status should be "Expired"` | Asserts dashboard shows Expired status for investor |

**Time travel:** Use `travel_to(91.days.from_now)` for fixed-period expiry scenarios. Reset with `travel_back` in `After` hook.

**Reviewer checks**
- [ ] `travel_to` is reset in After hooks (no leaking frozen time between scenarios)
- [ ] Feature file tagged `@nda` for selective test runs

---

## Project Rules Checklist

| Rule | Applies? | How it is met |
|---|---|---|
| No `blank?`/`present?` on relations; use `exists?`/`none?` | N/A | No new relation blank/present checks. Exempt check uses existing `InvestorAccess.exists?`. |
| Dedup in SQL (`distinct.pluck`), batch bulk operations (`find_each`/`in_batches`) | Applies | Warning count uses `.select(:investor_id).distinct.count`. Status resolver batches all queries. |
| Select only needed columns when loading many `account_entries`; no speculative `includes` of big associations | N/A | No account_entries involved. No new includes added. |
| Screen dates via `l(...)`; emails render `Mon dd, yyyy` via `EmailDateLocalization`; no human-format `strftime` | Applies | Lapsed page uses `l(@nda_config.validity_date)` for date display. Dashboard expiry dates use `l(...)`. |
| Date inputs use `f.date_field` / `date_field_tag`; JS dates via `locale_date_format.js` | N/A | No new date inputs in Module 4. |
| Every query entity-scoped; Pundit `authorize`/`policy_scope` on every action | Applies | All queries scoped via `nda_config_id` (entity-scoped). New `lapsed` action has `authorize` call. |
| MCP tool surfaces changed only via the ontology YAML (run the ontology drift feature) | N/A | No MCP tools changed. |
| Cucumber only (no RSpec); `TEST_ENV_NUMBER=$RANDOM` on every run | Applies | New scenarios go into Cucumber feature file. No RSpec. |
| `bundle exec rubocop` clean, including the `IRM/RelationBlankPresent` cop | Applies | Will run Rubocop after implementation. |

---

## Sign-off

| Reviewer | Date | Decision | Notes |
|---|---|---|---|
| | | | |
