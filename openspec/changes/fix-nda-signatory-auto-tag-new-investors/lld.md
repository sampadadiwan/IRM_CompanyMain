# Fix NDA Signatory Auto-Tag — Low-Level Design

> **Audience:** The developer who reviews the implementation plan before coding starts.
> **Companion documents:** [Design](design.md) · [Spec](specs/) · [Tasks](tasks.md)

> **Planning phase — no code changes.**

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

- Callback fires on every approved InvestorAccess save — confirm the query cost is acceptable for bulk imports — see [Queries and Indexes](#queries-and-indexes)
- Controller auto-tag changes from entity-wide to folder-scoped — verify `Investor.owner_access_rights` returns the right set — see [Method Contracts](#method-contracts)
- Race condition handled by rescue on unique constraint — see [Transactions, Locking and Concurrency](#transactions-locking-and-concurrency)
- No schema changes — see [Schema Detail](#schema-detail)

---

## File Map

| Boundary | File | New / Modified | Responsibility |
|---|---|---|---|
| ① Trigger | `app/packs/core/investor_accesses/models/investor_access.rb` | Modified | Add `after_commit` callback and `auto_tag_nda_signatory_if_needed` method |
| ① Trigger | `app/packs/core/nda_configs/controllers/nda_configs_controller.rb` | Modified | Fix `auto_tag_default_signatories` to use folder-scoped investor query |
| Tests | `features/core/nda_signatory_auto_tag.feature` | New | Cucumber scenarios for auto-tag on access approval and folder-scoped creation |
| Tests | `features/step_definitions/nda_signatory_auto_tag_steps.rb` | New | Step definitions for auto-tag scenarios |

**Reviewer checks**
- [x] Every class in the design's class diagram has a file here, and nothing here is missing from it
- [x] Files follow the pack layout (`app/packs/<domain>/<sub_domain>/...`) and Packwerk boundaries

---

## Schema Detail

N/A — no schema changes. All tables (`nda_configs`, `nda_signatories`, `investor_accesses`, `access_rights`) already exist with the required columns and indexes.

---

## Method Contracts

**`InvestorAccess`** (Model)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `auto_tag_nda_signatory_if_needed` (private) | none (uses `self`) | void | none (rescues RecordNotUnique, RecordInvalid) | Creates NdaSignatory records | Yes — checks existence before creating, rescues duplicates |

**`NdaConfigsController`** (Controller — existing private method, modified)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `auto_tag_default_signatories(nda_config)` | `nda_config: NdaConfig` | void | none (rescues RecordNotUnique, RecordInvalid) | Creates NdaSignatory records | Yes — rescues duplicates |

**Changes to `auto_tag_default_signatories`:**
- Before: `InvestorAccess.where(entity_id: nda_config.entity_id, approved: true)`
- After: `Investor.owner_access_rights(@folder, nil)` to get folder-scoped investors, then `InvestorAccess.where(entity_id:, investor_id: investor_ids, approved: true)` to get users

**Reviewer checks**
- [x] Every raised error is handled by a caller or listed in Error Mapping
- [x] Anything a retry can repeat is idempotent

---

## Controllers, Params and Responses

N/A — no new controller actions. The only controller change is to the private `auto_tag_default_signatories` method (internal logic, not a routable action).

---

## Queries and Indexes

| Where | Query shape | Index used | Rows expected | Preload / batching |
|---|---|---|---|---|
| `auto_tag_nda_signatory_if_needed` | `NdaConfig.where(entity_id:, enabled: true, owner_type: 'Folder')` | `entity_id` | 1-3 | None needed |
| `auto_tag_nda_signatory_if_needed` | `AccessRight.exists?(owner_type: 'Folder', owner_id:, entity_id:, access_to_investor_id:)` OR category match | `[owner_type, owner_id]` | 0-1 | Existence check |
| `auto_tag_nda_signatory_if_needed` | `NdaSignatory.where(nda_config_id:).where(user_id: InvestorAccess.where(investor_id:, entity_id:, approved: true).select(:user_id)).exists?` | `[nda_config_id, user_id]` unique index | 0-1 | Existence check |
| `auto_tag_nda_signatory_if_needed` | `NdaSignatory.create(...)` | unique index on `[nda_config_id, user_id]` | 1 insert | — |
| `auto_tag_default_signatories` (controller) | `Investor.owner_access_rights(@folder, nil)` | `[owner_type, owner_id]` on access_rights | 1-50 | `.pluck(:id)` |
| `auto_tag_default_signatories` (controller) | `InvestorAccess.where(entity_id:, investor_id: ids, approved: true).order(:created_at).group_by(&:investor_id)` | `[entity_id, investor_id]` | 1-100 | Group in Ruby |

**Reviewer checks**
- [x] Every query is scoped by `entity_id`, or explains why not
- [x] No N+1 on list pages. No unbounded loads

---

## Transactions, Locking and Concurrency

| Operation | Transaction scope | Lock | Race it prevents | Idempotency key |
|---|---|---|---|---|
| NdaSignatory create (callback) | Single insert, outside InvestorAccess transaction (after_commit) | None | Duplicate signatory | Unique index on `[nda_config_id, user_id]` |
| NdaSignatory create (controller) | Single insert per investor | None | Duplicate signatory | Unique index on `[nda_config_id, user_id]`, rescue RecordNotUnique |

**Reviewer checks**
- [x] No external HTTP call or email inside a transaction
- [x] Lock order is consistent everywhere two rows are locked

---

## Background Jobs

N/A — no new jobs. All logic runs inline in the `after_commit` callback.

---

## External Integrations

N/A — no external API calls.

---

## Error Mapping and Logging

| Exception | Raised in | Handled by | User sees | Logged / alerted |
|---|---|---|---|---|
| `ActiveRecord::RecordNotUnique` | `NdaSignatory.create` | `rescue` in callback/controller — silently skip | Nothing — transparent | Not logged (expected race condition) |
| `ActiveRecord::RecordInvalid` | `NdaSignatory.create` | `rescue` in callback/controller — silently skip | Nothing — transparent | Not logged (validation failure = already exists) |

**Reviewer checks**
- [x] No bare `rescue => e` that swallows errors silently — only specific exceptions rescued
- [x] Log lines carry the ids needed to debug — N/A, rescued errors are expected

---

## Security Review

| Concern | Decision |
|---|---|
| Authorization | No new routes or actions. Callback runs in model context, no user-facing endpoint |
| Tenant isolation | All queries scoped by `entity_id`. InvestorAccess model already validates entity scoping |
| Secrets | N/A |
| Input / output sanitisation | N/A — no user input processed |
| Mass assignment | N/A — no new permitted params |

**Reviewer checks**
- [x] A user from another entity cannot reach any record through any route, job or MCP tool

---

## Configuration and Rollout

| Item | Value / location |
|---|---|
| Credentials / env vars | None |
| Feature flag | None — this is a bugfix, always active |
| Cron / schedules | None |
| Deploy order | Code only, no migrations |
| Rollback | Revert the commit. Existing NdaSignatory records created by the callback are harmless and don't need cleanup |

**Reviewer checks**
- [x] Safe to deploy with the feature unused, and safe to roll back

---

## Test Plumbing

| Feature file | Stubs / fixtures | Factories | New step definitions |
|---|---|---|---|
| `features/core/nda_signatory_auto_tag.feature` | None | Entity, folder, NDA config, investor, access right, investor access, user | `nda_signatory_auto_tag_steps.rb` — Given/When/Then for auto-tag scenarios |

Reuses existing steps from `nda_acceptance_steps.rb` and `nda_config_steps.rb` for entity/folder/NDA setup.

---

## Project Rules Checklist

| Rule | Applies? | How it is met |
|---|---|---|
| No `blank?`/`present?` on relations; use `exists?`/`none?` | Applies | Uses `.exists?` for signatory check, not `.blank?` |
| Dedup in SQL (`distinct.pluck`), batch bulk operations | N/A | Small result sets (1-3 NDA configs), no batching needed |
| Select only needed columns | N/A | Uses existence checks, not loading full records |
| Every query entity-scoped; Pundit `authorize`/`policy_scope` on every action | Applies | All queries include `entity_id:` scope. No new controller actions |
| Cucumber only (no RSpec) | Applies | Cucumber feature file for all scenarios |
| `bundle exec rubocop` clean | Applies | Will run rubocop before commit |

---

## Sign-off

| Reviewer | Date | Decision | Notes |
|---|---|---|---|
| | | | |
