# NDA Inheritance — Low-Level Design

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

- `nda_inheritance_mode` column type is `string(10)` with `NOT NULL DEFAULT 'inherit'` — validates inclusion against `%w[inherit own opt_out]`. See [Schema Detail](#schema-detail).
- Backfill data migration sets `nda_inheritance_mode = 'own'` for all folders that have an associated `NdaConfig` (polymorphic, `owner_type = 'Folder'`). See [Schema Detail](#schema-detail).
- `NdaInheritanceResolver` is a stateless PORO in `core/nda_configs/services/` — receives preloaded folder tree, resolves in O(N) with top-down memoization. See [Method Contracts](#method-contracts).
- `NdaConfigsController` state transitions wrap `NdaConfig` create/destroy + `Folder#nda_inheritance_mode` update in a single `ActiveRecord::Base.transaction`. See [Transactions](#transactions-locking-and-concurrency).
- `inheritance_choice` param added to `nda_config_params` — values: `use_parent`, `set_own`, `opt_out`. See [Controllers](#controllers-params-and-responses).

---

## File Map

| Boundary | File | New / Modified | Responsibility |
|---|---|---|---|
| Domain | `db/migrate/YYYYMMDD_add_nda_inheritance_mode_to_folders.rb` | New | Adds `nda_inheritance_mode` column |
| Domain | `db/migrate/YYYYMMDD_backfill_nda_inheritance_mode_for_existing_configs.rb` | New | Backfills `own` for folders with existing NdaConfig |
| Domain | `app/packs/core/folders/models/folder.rb` | Modified | Adds `NDA_INHERITANCE_MODES`, validation, `effective_nda_config`, `nda_source_folder`, convenience predicates |
| Domain | `app/packs/core/nda_configs/services/nda_inheritance_resolver.rb` | New | Batch resolver for tree rendering |
| Controller | `app/packs/core/nda_configs/controllers/nda_configs_controller.rb` | Modified | Adds `detect_inheritance_state`, `inheritance_choice` handling, descendant caret updates |
| Controller | `app/packs/core/folders/controllers/folders_controller.rb` | Modified | Adds `nda_inheritance_mode` to permitted params |
| UI | `app/packs/core/nda_configs/views/nda_configs/_settings_inherited.html.erb` | New | Inherited variant: source folder, read-only details, three radios |
| UI | `app/packs/core/nda_configs/views/nda_configs/_settings_opted_out.html.erb` | New | Opted-out variant: parent info, three radios |
| UI | `app/packs/core/nda_configs/views/nda_configs/_form.html.erb` | Modified | Adds "Remove this NDA and use parent's" revert option |
| UI | `app/packs/core/nda_configs/views/nda_configs/_modal.html.erb` | Modified | Conditional partial rendering based on `@inheritance_state` |
| UI | `app/packs/core/nda_configs/views/nda_configs/create.turbo_stream.erb` | Modified | Adds descendant caret replacements |
| UI | `app/packs/core/nda_configs/views/nda_configs/update.turbo_stream.erb` | Modified | Adds descendant caret replacements |
| UI | `app/packs/core/folders/views/folders/_tree_view.html.erb` | Modified | Uses `@nda_resolver` for inheritance icons and "(Inherited)" label |
| UI | `app/packs/core/folders/views/folders/_tree_caret.html.erb` | Modified | Adds `(Inherited)` label and tooltip for inherited folders |
| UI | `app/javascript/controllers/nda_settings_controller.js` | Modified | Adds inheritance radio button toggle for inline form expand/collapse |
| Helper | `app/packs/core/documents/helpers/document_helper.rb` | Modified | Builds `@nda_resolver` from preloaded folder tree |
| Test | `features/core/nda_inheritance.feature` | New | Cucumber feature (11+ scenarios) |
| Test | `features/step_definitions/nda_inheritance_steps.rb` | New | Step definitions for inheritance-specific assertions |
| Schema | `db/schema.rb` | Modified | Reflects new column |
| Schema | `db/schema_test.rb` | Modified | Reflects new column |

**Reviewer checks**
- [ ] Every class in the design's class diagram has a file here, and nothing here is missing from it
- [ ] Files follow the pack layout (`app/packs/<domain>/<sub_domain>/...`) and Packwerk boundaries
- [ ] `NdaInheritanceResolver` is in `core/nda_configs/services/`, not `core/folders/services/`

---

## Schema Detail

**`folders`** (existing — 1 column added)

| Column | Type | Limit | Null | Default | Index / FK | Notes |
|---|---|---|---|---|---|---|
| `nda_inheritance_mode` | string | 10 | no | `"inherit"` | `idx_folders_nda_inheritance_mode` | enum: `inherit`, `own`, `opt_out` |

**Migration safety:**
- `folders` table size: ~5,000 rows typical, ~50,000 max. Adding a `NOT NULL` column with a default is a metadata-only operation on MySQL 8+ (instant DDL). No lock concern.
- Backfill migration: `UPDATE folders SET nda_inheritance_mode = 'own' WHERE id IN (SELECT owner_id FROM nda_configs WHERE owner_type = 'Folder' AND deleted_at IS NULL)`. Hits ~10-50 rows. Safe.
- Both migrations are reversible (`remove_column`, `UPDATE ... SET nda_inheritance_mode = 'inherit'`).
- `db/schema.rb` and `db/schema_test.rb` both updated.

**Reviewer checks**
- [ ] Column default `'inherit'` matches `Folder::NDA_INHERITANCE_MODES` constant
- [ ] Index exists for `nda_inheritance_mode` column
- [ ] Backfill targets only `owner_type = 'Folder'` and `deleted_at IS NULL`
- [ ] Migration is reversible and safe on production table size
- [ ] Both `schema.rb` and `schema_test.rb` updated

---

## Method Contracts

**`Folder`** (Model — existing, inheritance methods added)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `effective_nda_config` | none | `NdaConfig` or `nil` | — | none (memoized `@_effective_nda_config`) | Yes |
| `nda_source_folder` | none | `Folder` or `nil` | — | none (memoized `@_nda_source_folder`) | Yes |
| `nda_inheriting?` | none | `Boolean` | — | none | Yes |
| `nda_opted_out?` | none | `Boolean` | — | none | Yes |
| `nda_has_own?` | none | `Boolean` | — | none | Yes |
| `resolve_effective_nda` | none | `[NdaConfig, Folder]` or `[nil, nil]` | — | none (private, recursive) | Yes |

**`NdaInheritanceResolver`** (Service — new)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `initialize` | `folders` (Array), `config_map` (Hash) | self | — | builds `@resolved` memoization hash | Yes |
| `resolve_tree` | none | Hash `{ folder_id => { config:, source_folder: } }` | — | populates `@resolved` | Yes |
| `effective_config_for` | `folder` (Folder) | `NdaConfig` or `nil` | — | none | Yes |
| `source_folder_for` | `folder` (Folder) | `Folder` or `nil` | — | none | Yes |

**Reviewer checks**
- [ ] `effective_nda_config` checks opt-out FIRST, then own config, then recurses on parent
- [ ] `resolve_tree` is top-down (parent before children) so memoization works
- [ ] Both `effective_nda_config` and `nda_source_folder` are memoized per request (`@_` prefix)
- [ ] `NdaInheritanceResolver` never issues DB queries — works from preloaded data only

---

## Controllers, Params and Responses

| Action | Permitted params | Policy method | Success response | Failure response |
|---|---|---|---|---|
| `NdaConfigsController#new` | — | `new?` | Turbo Frame: modal with correct variant based on `@inheritance_state` | — |
| `NdaConfigsController#create` | `nda_config: [...]`, `inheritance_choice` | `create?` | turbo_stream: replace modal + replace target + descendant carets | 422 + form errors via `form_update.turbo_stream.erb` |
| `NdaConfigsController#edit` | — | `edit?` | Turbo Frame: modal with form + optional revert | — |
| `NdaConfigsController#update` | `nda_config: [...]`, `inheritance_choice` | `update?` | turbo_stream: replace modal + replace target + descendant carets | 422 + form errors |

`inheritance_choice` values: `use_parent`, `set_own`, `opt_out`. Added to `nda_config_params` or as a separate permitted param.

**Reviewer checks**
- [ ] `inheritance_choice` is NOT in the `nda_config` nested params — it's a top-level param
- [ ] Every action calls `authorize`
- [ ] `detect_inheritance_state` runs before rendering to determine which partial to show
- [ ] `set_owner` still enforces `entity_id` check (no regression from Module 1)

---

## Queries and Indexes

| Query | When | Shape | Index used |
|---|---|---|---|
| `Folder.find(params[:folder_id])` | Every controller action | PK lookup | Primary key |
| `@owner.nda_config` | `new`, `edit` | `nda_configs WHERE owner_type = 'Folder' AND owner_id = ? AND deleted_at IS NULL` | `idx_nda_configs_owner_type_owner_id` (unique composite) |
| `@folder.descendants.where(nda_inheritance_mode: 'inherit')` | After mode change (Turbo Stream carets) | `folders WHERE ancestry LIKE ? AND nda_inheritance_mode = 'inherit'` | `idx_folders_nda_inheritance_mode` + ancestry index |
| `Folder.where(entity_id: ...).includes(:nda_config)` | Tree rendering (DocumentHelper) | Batch preload for resolver | `idx_nda_configs_entity_id` |
| `folder.ancestors` (ancestry gem) | `effective_nda_config` per-folder walk | `folders WHERE id IN (ancestry ids)` — max 3 hops | Primary key |

**Reviewer checks**
- [ ] `descendants.where(nda_inheritance_mode: 'inherit')` uses the new index
- [ ] `includes(:nda_config)` in tree query prevents N+1 for resolver
- [ ] Ancestry walk is max 3 levels — no unbounded recursion

---

## Transactions, Locking and Concurrency

| Operation | Transaction boundary | Lock scope | Notes |
|---|---|---|---|
| Override (set_own): create NdaConfig + set mode=own | `ActiveRecord::Base.transaction` wrapping both writes | Row-level on `folders` + insert on `nda_configs` | Both must succeed |
| Revert (use_parent): soft-delete NdaConfig + set mode=inherit | `ActiveRecord::Base.transaction` wrapping both writes | Row-level on both tables | Avoids orphaned config |
| Opt-out: set mode=opt_out + optional soft-delete | `ActiveRecord::Base.transaction` wrapping both writes | Row-level | Consistent state |

No optimistic locking needed — single user (GP admin) configures NDA. Concurrent updates to the same folder are extremely unlikely.

**Reviewer checks**
- [ ] All three state transitions are wrapped in a transaction
- [ ] Soft-delete uses `destroy` (which triggers `acts_as_paranoid`), not `delete`
- [ ] No transaction wraps the Turbo Stream rendering (rendering is outside the transaction)

---

## Background Jobs

N/A — no background jobs in Module 5. All operations are synchronous controller actions.

**Reviewer checks**
- [ ] No new Sidekiq jobs introduced

---

## External Integrations

N/A — no external API calls. All operations are local database writes and folder tree updates.

**Reviewer checks**
- [ ] No new external dependencies

---

## Error Mapping and Logging

| Error | Source | User sees | Logged? | Alert? |
|---|---|---|---|---|
| Validation error on override NDA | `NdaConfig` model validation | Form re-renders with field errors | No (expected user error) | No |
| `Pundit::NotAuthorizedError` | LP or unauthorized GP | Redirect with flash "Not authorized" | Yes (standard Pundit handler) | No |
| `ActiveRecord::RecordNotFound` | Invalid folder_id | 404 | Yes (standard Rails handler) | No |

**Reviewer checks**
- [ ] No new error types introduced beyond standard Rails/Pundit
- [ ] Validation errors re-render the correct modal variant (not always the standard form)

---

## Security Review

- **Authorization**: `NdaConfigPolicy#manageable?` guards all actions via `authorize`. Type-dispatch `case record.owner when Folder` checks `in_data_room?` and delegates to `FolderPolicy#update?`. LP users are denied.
- **Tenant isolation**: `set_owner` verifies `@owner.entity_id == current_user.entity_id`. Cross-tenant requests denied before reaching the policy.
- **Input validation**: `nda_inheritance_mode` validates inclusion in `%w[inherit own opt_out]`. `inheritance_choice` is checked against known values in controller logic.
- **Mass assignment**: `inheritance_choice` is a top-level param, not nested under `nda_config`. `nda_inheritance_mode` is set by controller logic, not from params — no mass assignment vector.

**Reviewer checks**
- [ ] `nda_inheritance_mode` cannot be set directly from params (only through controller logic)
- [ ] `inheritance_choice` values are validated (unknown values are rejected or ignored)
- [ ] `set_owner` entity check is not bypassed by inheritance logic

---

## Configuration and Rollout

- No feature flag needed — inheritance is the default behavior (all existing folders get `nda_inheritance_mode = 'inherit'`).
- Backfill migration sets `own` on folders with existing NdaConfigs — no behavior change for existing setups.
- No new environment variables, secrets, or external configuration.

**Reviewer checks**
- [ ] Backfill migration is idempotent (can be re-run safely)
- [ ] Existing Module 1 functionality is unaffected when `nda_inheritance_mode` defaults to `inherit`

---

## Test Plumbing

- **Feature file**: `features/core/nda_inheritance.feature`, tag `@nda`
- **Step definitions**: `features/step_definitions/nda_inheritance_steps.rb` — new file
- **Shared steps**: Deduplicate "there is a child folder" step from `nda_config_steps.rb` — extract to shared step or use distinct phrasing
- **Factory/setup**: Reuse existing `folder` factory. New trait: `trait :with_inheritance_mode` for setting `nda_inheritance_mode`. Use `fake_shrine_nda_document` helper from Module 1 steps.
- **No RSpec**: Cucumber only, consistent with Module 1

**Reviewer checks**
- [ ] No duplicate step definitions between `nda_config_steps.rb` and `nda_inheritance_steps.rb`
- [ ] Every worked example (H1-H9, E1-E10, X1-X2) has a matching Cucumber scenario
- [ ] Tag `@nda` is used consistently

---

## Project Rules Checklist

| Rule | Applies | Notes |
|---|---|---|
| `# frozen_string_literal: true` on all new Ruby files | Applies | Resolver, migration, step definitions |
| YARD-style class/method comments | Applies | All new/modified Ruby files |
| Pack layout (`app/packs/<domain>/<sub>/`) | Applies | Resolver in `core/nda_configs/services/` |
| Entity scoping (multi-tenancy) | Applies | `set_owner` entity check unchanged from Module 1 |
| No real names in docs | Applies | All design docs use neutral roles |
| Cucumber feature files in `features/core/` | Applies | `nda_inheritance.feature` |
| `db/schema.rb` and `db/schema_test.rb` both updated | Applies | After migration |

**Reviewer checks**
- [ ] All items marked "Applies" are verified in the implementation
- [ ] No CLAUDE.md rules violated

---

## Sign-off

| Reviewer | Date | Decision |
|---|---|---|
| — | — | — |
