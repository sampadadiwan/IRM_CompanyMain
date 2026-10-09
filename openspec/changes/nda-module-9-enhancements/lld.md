# NDA Module 9 — Signatory Gating & Enhancements — Low-Level Design

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

- **Signatory check uses `NdaSignatory.exists?` on the existing unique index `[nda_config_id, user_id]`** — single indexed lookup, no new index needed. See [Queries and Indexes](#queries-and-indexes).
- **`ensure_signatory` before_action on `NdaAcceptancesController` runs before `resolve_investor`** — it only needs `@nda_config`, not `@investor`. The before_action order is: `set_nda_config`, `set_folder`, `ensure_signatory`, then `resolve_investor` (on create/decline only). See [Controllers, Params and Responses](#controllers-params-and-responses).
- **`NdaConfigsController#create` switches from turbo_stream to redirect** — the turbo_stream response that updated the modal is replaced with a `redirect_to` for the first-creation flow. The `update` action keeps turbo_stream. See [Controllers, Params and Responses](#controllers-params-and-responses).
- **No DB migration** — the `nda_signatories` table already exists with the needed schema and indexes. See [Schema Detail](#schema-detail).
- **New route: `GET /nda_acceptances/blocked`** — collection route on `nda_acceptances`. Must be defined before the existing `resources :nda_acceptances` to avoid routing conflicts. See [Controllers, Params and Responses](#controllers-params-and-responses).

---

## File Map

| Boundary | File | New / Modified | Responsibility |
|---|---|---|---|
| ① Folder gate | `app/packs/core/documents/controllers/documents_controller.rb` | Modified | Add signatory check branch inside `ensure_nda_accepted` |
| ② Signatory check | _(inline query in ① and ④)_ | N/A | `NdaSignatory.exists?` called at two sites |
| ③ Blocked page | `app/packs/core/nda_configs/views/nda_acceptances/blocked.html.erb` | New | Dead-end page for non-signatories |
| ④ Accept/Decline guard | `app/packs/core/nda_configs/controllers/nda_acceptances_controller.rb` | Modified | Add `ensure_signatory` before_action and `blocked` action |
| ⑤ First-creation redirect | `app/packs/core/nda_configs/controllers/nda_configs_controller.rb` | Modified | Change `create` response from turbo_stream to redirect |
| ⑤ First-creation redirect | `app/packs/core/nda_configs/views/nda_configs/create.turbo_stream.erb` | Modified | No longer used for first creation (kept for any future non-first create path) |
| ⑥ Dashboard warnings | `app/packs/core/nda_configs/views/nda_status/index.html.erb` | Modified | Add ⚠ zero-signatory icon and first-creation banner |
| ⑥ Dashboard warnings | `app/javascript/controllers/nda_status_controller.js` | Modified | Add first-creation auto-expand and banner logic |
| Routes | `config/routes/core.rb` | Modified | Add `GET /nda_acceptances/blocked` collection route |
| Tests | `features/nda_signatory_gating.feature` | New | Cucumber scenarios for all H/E/X cases |

**Reviewer checks**
- [ ] Every class in the design's class diagram has a file here, and nothing here is missing from it
- [ ] Files follow the pack layout (`app/packs/<domain>/<sub_domain>/...`) and Packwerk boundaries

---

## Schema Detail

N/A — no DB migration. The `nda_signatories` table already exists (created in Module 3) with columns `nda_config_id`, `user_id`, `tagged_by_id` and unique index on `[nda_config_id, user_id]`.

**Reviewer checks**
- [x] No migration needed — confirmed existing table has the required schema and index

---

## Method Contracts

**`NdaAcceptancesController`** (Controller)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `#ensure_signatory` (private before_action) | None (reads `@nda_config`, `current_user`) | `nil` (pass-through) or redirect | None | Redirects to blocked page if not signatory | Yes — read-only check |
| `#blocked` (action) | Params: `nda_config_id`, `folder_id` | Rendered HTML | `ActiveRecord::RecordNotFound` if nda_config missing | None | Yes — read-only |

**Reviewer checks**
- [ ] Every raised error is handled by a caller or listed in Error Mapping
- [ ] Anything a retry can repeat is idempotent

---

## Controllers, Params and Responses

| Action | Permitted params | Policy method | Success response | Failure response |
|---|---|---|---|---|
| `NdaAcceptancesController#blocked` | `nda_config_id`, `folder_id` (query params, not permitted — read via `params[]`) | `show?` on `NdaAcceptancePolicy` | Render `blocked.html.erb` (200) | `RecordNotFound` → 404 |
| `NdaConfigsController#create` (modified) | Unchanged: `nda_config: [:enabled, :nda_document, ...]` | `create?` on `NdaConfigPolicy` | `redirect_to nda_status_path(...)` (302) | 422 + form errors (unchanged) |

**before_action order on `NdaAcceptancesController`:**

| Order | Before action | Runs on | Purpose |
|---|---|---|---|
| 1 | `set_nda_config` | All actions | Loads `@nda_config` from params |
| 2 | `set_folder` | All actions | Loads `@folder` from params |
| 3 | `ensure_signatory` | `index`, `create`, `decline`, `blocked` excluded | Checks signatory status, redirects to blocked if not |
| 4 | `resolve_investor` | `create`, `decline` only | Resolves `@investor` from InvestorAccess |

**`ensure_signatory` must NOT run on `blocked` action** — that would cause an infinite redirect loop (non-signatory → blocked → ensure_signatory → blocked → ...). Use `before_action :ensure_signatory, only: %i[index create decline]`.

**Route definition for `blocked`:**

The `blocked` route must be defined as a collection route on `nda_acceptances`:

```
resources :nda_acceptances, only: %i[index create] do
  collection do
    post :decline
    get :lapsed
    get :blocked    # ← new
  end
end
```

**Reviewer checks**
- [ ] No action without `authorize` / `policy_scope`
- [ ] Permitted params can't set `entity_id`, `user_id` or other ownership fields
- [ ] `ensure_signatory` excluded from `blocked` action to prevent redirect loop
- [ ] `blocked` route defined inside collection block (not as a member route)

---

## Queries and Indexes

| Where | Query shape | Index used | Rows expected | Preload / batching |
|---|---|---|---|---|
| `DocumentsController#ensure_nda_accepted` (signatory check) | `NdaSignatory.exists?(nda_config_id: X, user_id: Y)` | Unique index `[nda_config_id, user_id]` | 0 or 1 | None — single EXISTS |
| `NdaAcceptancesController#ensure_signatory` | `NdaSignatory.exists?(nda_config_id: X, user_id: Y)` | Same unique index | 0 or 1 | None — single EXISTS |
| `nda_status/index.html.erb` (zero-signatory check) | View-level: `row[:users].any? { |u| u[:nda_tagged] }` | N/A — in-memory on already-loaded data from `NdaStatusResolver` | N/A | N/A |

**Reviewer checks**
- [ ] Every query is scoped by `entity_id`, or explains why not — the signatory check is scoped by `nda_config_id` which is entity-scoped (NdaConfig belongs to an entity)
- [ ] No N+1 on list pages. No unbounded loads

---

## Transactions, Locking and Concurrency

N/A — no new multi-row writes. The signatory check is a read-only EXISTS query. The `create` redirect and view changes are single-request operations.

**Reviewer checks**
- [x] No multi-table writes or concurrent mutation patterns introduced

---

## Background Jobs

N/A — no new jobs. Existing Module 8 notification jobs are unchanged.

**Reviewer checks**
- [x] No new background jobs

---

## External Integrations

N/A — no external API calls.

**Reviewer checks**
- [x] No external integrations

---

## Error Mapping and Logging

| Exception | Raised in | Handled by | User sees | Logged / alerted |
|---|---|---|---|---|
| `ActiveRecord::RecordNotFound` | `NdaAcceptancesController#blocked` (`set_nda_config` / `set_folder`) | Rails default handler | 404 page | Standard Rails 404 log |

No new error paths — the signatory check produces a boolean, never raises. The blocked page is a static render.

**Reviewer checks**
- [ ] No bare `rescue => e` that swallows errors silently
- [ ] Log lines carry the ids needed to debug

---

## Security Review

| Concern | Decision |
|---|---|
| Authorization | `blocked` action uses `authorize @nda_acceptance, :show?` (same as `index`). `ensure_signatory` is an additional check on top of existing Pundit authorization — it never relaxes auth. |
| Tenant isolation | Signatory check uses `nda_config_id` which is entity-scoped via `NdaConfig.entity_id`. The existing gate already confirms `InvestorAccess` for the user's entity. No cross-tenant path. |
| Secrets | N/A — no new secrets or credentials. |
| Input / output sanitisation | `first_creation` query param is only read as a boolean flag (`params[:first_creation].present?`). No user-supplied text rendered unescaped. |
| Mass assignment | No new permitted params. `blocked` action reads query params directly (not `require`/`permit`). |

**Reviewer checks**
- [ ] A user from another entity cannot reach any record through any route, job or MCP tool

---

## Configuration and Rollout

| Item | Value / location |
|---|---|
| Credentials / env vars | None — no new credentials |
| Feature flag | None — ships directly (the feature is additive and backwards-compatible) |
| Cron / schedules | None |
| Deploy order | Code-only deploy (no migration) |
| Rollback | Revert the commit. Existing behavior (any LP can sign) is restored. No data cleanup needed — `nda_signatories` table is unaffected. |

**Reviewer checks**
- [ ] Safe to deploy with the feature unused, and safe to roll back

---

## Test Plumbing

| Feature file | Stubs / fixtures | Factories | New step definitions |
|---|---|---|---|
| `features/nda_signatory_gating.feature` | None — uses real DB (MySQL test instance) | `:entity`, `:folder`, `:nda_config`, `:investor`, `:user`, `:investor_access`, `:nda_signatory` | `Given user "{name}" is a signatory for the NDA`, `Then I should see the blocked page`, `Then the dashboard shows a zero-signatory warning for "{investor}"`, `Then the dashboard shows the first-creation banner` |

Reuses existing step definitions from `features/step_definitions/nda_steps.rb` for: folder access, NDA config creation, NDA acceptance, signatory tagging/untagging.

---

## Project Rules Checklist

| Rule | Applies? | How it is met |
|---|---|---|
| No `blank?`/`present?` on relations; use `exists?`/`none?` | Applies | Signatory check uses `NdaSignatory.exists?`. `first_creation` param uses `.present?` on a string param, not a relation |
| Dedup in SQL (`distinct.pluck`), batch bulk operations (`find_each`/`in_batches`) | N/A | No new list queries or bulk operations |
| Select only needed columns when loading many records; no speculative `includes` | N/A | No new list loads — signatory check is EXISTS |
| Screen dates via `l(...)`; emails render `Mon dd, yyyy` via `EmailDateLocalization`; no human-format `strftime` | N/A | No new dates displayed |
| Date inputs use `f.date_field` / `date_field_tag`; JS dates via `locale_date_format.js` | N/A | No new date inputs |
| Every query entity-scoped; Pundit `authorize`/`policy_scope` on every action | Applies | `blocked` action calls `authorize`. Signatory query is scoped by `nda_config_id` (entity-scoped). |
| MCP tool surfaces changed only via the ontology YAML (run the ontology drift feature) | N/A | No MCP tool changes |
| Cucumber only (no RSpec); `TEST_ENV_NUMBER=$RANDOM` on every run | Applies | New feature file is Cucumber. Test commands use `TEST_ENV_NUMBER`. |
| `bundle exec rubocop` clean, including the `IRM/RelationBlankPresent` cop | Applies | Will run rubocop after implementation |

---

## Sign-off

| Reviewer | Date | Decision | Notes |
|---|---|---|---|
| | | | |
