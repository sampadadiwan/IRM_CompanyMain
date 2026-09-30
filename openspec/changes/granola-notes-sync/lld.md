# Granola Meeting Notes Sync — Low-Level Design

> **Audience:** The developer who reviews the implementation plan before coding starts.
> **Companion documents:** [Design](design.md) · [Spec](specs/granola-notes-sync/spec.md) · [Tasks](tasks.md)

> **Planning phase — no code changes.** This document records the implementation-level decisions
> a reviewing developer must check. It adds to [design.md](design.md): the boundaries, class
> diagram, sequences and worked examples live there and are not repeated here.

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
- [Project Rules Checklist](#project-rules-checklist)
- [Sign-off](#sign-off)

---

## Review Summary

The decisions most likely to be wrong or contested:

- **Group Company users.** `ApplicationPolicy#belongs_to_entity?` lets a Group Company user reach
  child-entity records, but the design's inbox scope only filters on `entity_id = user.entity_id`.
  The LLD keeps the narrower scope for v1, so group users see only their own entity's meetings.
  **Decide.** See [Security Review](#security-review).
- **First `encrypts` in the app.** It relies on the existing AR encryption config (built for 2FA)
  and on per-environment `active_record_encryption` credentials. See
  [Configuration and Rollout](#configuration-and-rollout).
- **`scope_key` instead of a partial unique index**, because MySQL has none. See
  [Schema Detail](#schema-detail).
- **Single-flight claim via a conditional `update_all`** on `sync_started_at`, not a Redis lock.
  See [Transactions, Locking and Concurrency](#transactions-locking-and-concurrency).
- **The edit-detection digest** is computed from `details.body.to_html` after save. It is only
  stable if ActionText serialisation is. See [Method Contracts](#method-contracts).
- **Domain-fallback `LIKE '%@domain'`** is a leading-wildcard scan of the entity's contacts. See
  [Queries and Indexes](#queries-and-indexes).

---

## File Map

| Boundary | File | New / Modified | Responsibility |
|---|---|---|---|
| Sync | `app/packs/core/granola/models/granola_connection.rb` | New | Key storage (encrypted), status, cursor, sync claim |
| Sync | `app/packs/core/granola/models/granola_meeting.rb` | New | Meeting snapshot, routing status, candidates, filed ids |
| Integration | `app/packs/core/granola/services/granola_client.rb` | New | All HTTP to Granola, error classes |
| Sync | `app/packs/core/granola/services/granola_sync_service.rb` | New | One incremental pass per connection |
| Sync | `app/packs/core/granola/services/granola_meeting_processor.rb` | New | Route a meeting by status and match |
| Sync | `app/packs/core/granola/services/granola_attendee_matcher.rb` | New | Emails → `MatchResult` (read-only) |
| Sync | `app/packs/core/granola/services/granola_note_filer.rb` | New | Create / refresh notes (only writer of notes) |
| Scheduling | `app/packs/core/granola/jobs/granola_sync_all_job.rb` | New | Cron fan-out |
| Scheduling | `app/packs/core/granola/jobs/granola_sync_job.rb` | New | One pass, retries |
| Scheduling | `app/packs/core/granola/jobs/granola_rematch_job.rb` | New | Bulk re-match |
| UI | `app/packs/core/granola/controllers/granola_connections_controller.rb` | New | Connect / reconnect / disconnect / sync now |
| UI | `app/packs/core/granola/controllers/granola_meetings_controller.rb` | New | Inbox, file, discard, re-match |
| UI | `app/packs/core/granola/policies/granola_connection_policy.rb` | New | Who may manage which connection |
| UI | `app/packs/core/granola/policies/granola_meeting_policy.rb` | New | Inbox scope and actions |
| UI | `app/packs/core/granola/views/granola_connections/_granola_connection.html.erb` | New | Connection panel (3 states) |
| UI | `app/packs/core/granola/views/granola_meetings/index.html.erb`, `_granola_meeting.html.erb`, `*.turbo_stream.erb` | New | Inbox and row updates |
| Notification | `app/packs/core/granola/mailers/granola_mailer.rb`, `granola_connection_failed_notifier.rb`, view | New | Needs-attention alert (pattern: `KpiReportImportFailedNotifier`) |
| CRM | `app/packs/core/notes/models/note.rb` | Modified | `belongs_to :granola_meeting`, `granola_detached?`, `update_investor` branch |
| CRM | `app/packs/core/notes/views/notes/_note.html.erb` | Modified | Granola link, "Edited in CapHive" line |
| CRM | `app/packs/core/notes/controllers/notes_controller.rb` | Modified | Add `:granola_meeting` to `preloads` |
| UI | `app/packs/core/users/views/users/show.html.erb` | Modified | Render the panel on your own profile |
| UI | `app/packs/core/entities/views/entities/_form_fields.html.erb` | Modified | Render the workspace panel for admins |
| UI | Investors menu partial (**path to confirm in task 3.4**) | Modified | Inbox link and badge |
| Config | `config/routes/core.rb` | Modified | Routes |
| Config | `config/initializers/sidekiq.rb` | Modified | Cron registration inside `unless Rails.env.local?` |
| Data | `db/migrate/*` ×3, `db/schema.rb`, `db/schema_test.rb` | New / Modified | See Schema Detail |

**Reviewer checks**
- [ ] Every class in the design's class diagram has a row here
- [ ] `core/granola` depends on `core/notes` and never the reverse, apart from the one `belongs_to` on `Note`

---

## Schema Detail

**`granola_connections`** (new)

| Column | Type | Limit | Null | Default | Index / FK | Notes |
|---|---|---|---|---|---|---|
| `entity_id` | bigint | — | no | — | FK entities; part of unique | |
| `kind` | string | 10 | no | — | — | `user` / `workspace` |
| `user_id` | bigint | — | yes | — | FK users | NULL for workspace |
| `connected_by_id` | bigint | — | no | — | FK users | alert recipient, fallback author |
| `scope_key` | string | 40 | no | — | unique `[entity_id, scope_key]` | `user:<id>` / `workspace`, set in `before_validation` |
| `api_key` | text | — | no | — | — | `encrypts` (ciphertext is longer than plaintext, hence text) |
| `api_key_last4` | string | 4 | no | — | — | display only |
| `status` | string | 20 | no | `connected` | — | `connected` / `needs_attention` |
| `cursor_at` | datetime | — | yes | — | — | next `updated_after` |
| `sync_started_at` | datetime | — | yes | — | — | claim, stale after 30 min |
| `last_synced_at`, `last_success_at`, `failure_notified_at` | datetime | — | yes | — | — | |
| `last_error` | string | 500 | yes | — | — | truncated message |
| `last_sync_stats` | json | — | yes | — | — | `{filed:, review:, ignored:}` |

**`granola_meetings`** (new)

| Column | Type | Limit | Null | Default | Index / FK | Notes |
|---|---|---|---|---|---|---|
| `entity_id` | bigint | — | no | — | FK; unique `[entity_id, granola_note_id]`; `[entity_id, status, meeting_at]` | |
| `granola_connection_id` | bigint | — | yes | — | FK `on_delete: :nullify` | disconnect keeps meetings |
| `granola_note_id` | string | 30 | no | — | unique (above) | `not_` + 14 chars |
| `title`, `owner_email`, `owner_name`, `web_url` | string | 255 | yes | — | — | |
| `meeting_at` | datetime | — | yes | — | in composite index | calendar start, else `created_at` |
| `attendees` | json | — | yes | — | — | `[{name, email}]` |
| `summary_markdown`, `private_notes_markdown` | text | — | yes | — | — | NULL while ignored |
| `granola_updated_at` | datetime | — | yes | — | — | skip-if-unchanged check |
| `status` | string | 20 | no | — | in composite index | 4 values |
| `match_tier` | string | 10 | yes | — | — | 4 values |
| `candidate_investor_ids`, `filed_investor_ids` | json | — | yes | — | — | arrays of ids |
| `user_id` | bigint | — | yes | — | FK users | resolved author |
| `resolved_by_id` | bigint | — | yes | — | FK users | |
| `resolved_at` | datetime | — | yes | — | — | |

**`notes`** (existing, add 2 columns)

| Column | Type | Limit | Null | Default | Index / FK | Notes |
|---|---|---|---|---|---|---|
| `granola_meeting_id` | bigint | — | yes | — | FK `on_delete: :nullify` + index | |
| `granola_digest` | string | 64 | yes | — | — | SHA256 hex |

**Migration safety:** both new tables start empty. `notes` gets two nullable columns with no
default, which is an instant/online ALTER on MySQL 8 and needs no backfill. All three migrations
are reversible. Per the repo's local-migrate caveat, restore `schema.rb` / `schema_test.rb` and
hand-insert only these additions.

**Reviewer checks**
- [ ] Validation limits match column limits (`kind` 10, `status` 20, `last_error` truncated to 500)
- [ ] `on_delete: :nullify` on both meeting FKs matches "disconnect keeps notes"
- [ ] The `notes` ALTER is instant in production (check the MySQL version and the table size)

---

## Method Contracts

**`GranolaClient`**

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `#initialize(api_key)` | String | client | — | — | — |
| `#list_notes(updated_after:, cursor: nil, page_size: 30)` | Time, String | `{notes: [Hash], has_more:, cursor:}` | `AuthError`, `RetryableError`, `Error` | 1 HTTP GET, then sleep 0.2s | Yes (read) |
| `#get_note(id)` | String | Hash (full note, no transcript) | same | 1 HTTP GET | Yes |
| `#verify!` | — | `true` | same | `list_notes(page_size: 1)` | Yes |

**`GranolaConnection`**

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `#claim_sync!` | — | Boolean (claimed?) | — | conditional `update_all(sync_started_at: now)` where nil or < 30 min ago | Yes |
| `#record_success!(max_updated_at)` | Time or nil | self | — | cursor, `last_success_at`, clears error / claim / `failure_notified_at` | Yes |
| `#record_failure!(error)` | Exception | self | — | Auth: `needs_attention` + notify. Transient: notify once if `last_success_at` < 24h ago. Always releases the claim | Notifies at most once per episode |

**`GranolaMeeting`**

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `.upsert_from_api!(connection, payload)` | connection, Hash | meeting | `RecordInvalid` | find-or-init by `[entity_id, granola_note_id]`; resolves author; never blanks private notes from a workspace pass; rescues `RecordNotUnique` once and reloads | Yes |
| `#mark_needs_review!(ids, tier)` / `#mark_ignored!(tier)` | Array, String | self | — | `mark_ignored!` nils both markdown columns | Yes |
| `#resolve!(user:, resolution:)` | User, `filed`/`discarded` | self | `ArgumentError` on another value | `resolved_by`, `resolved_at` | Yes |

**`GranolaAttendeeMatcher.call(meeting)`** returns `MatchResult(tier:, investor_ids:, touch_points: {investor_id => InvestorAccess})`.
It raises nothing and writes nothing.

**`GranolaNoteFiler`**

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `.call(meeting, investor_ids:, filed_by: nil)` | meeting, Array, User or nil | Array of created notes | `RecordNotFound` (investor outside the entity), `RecordInvalid` | notes, investor `last_interaction_date`, meeting status / filed ids / resolve | Yes: skips ids already in `filed_investor_ids` |
| `.refresh(meeting)` | meeting | Array of updated notes | `RecordInvalid` | rewrites non-detached notes, re-digests | Yes |

**`Note`** (modified)

| Method | Returns | Notes |
|---|---|---|
| `#granola_detached?` | Boolean | `granola_digest != SHA256(details.body.to_html)`. False when either side is blank |
| `#update_investor` | — | Granola notes on an `Investor`: `last_interaction_date = [current, on].compact.max`. Every other case is unchanged |

**Reviewer checks**
- [ ] `record_failure!` always releases the claim, so a failed pass can't block the next one for 30 minutes
- [ ] The digest is set from the **reloaded** body after save, not from the string passed in
- [ ] `upsert_from_api!` never overwrites `private_notes_markdown` with nil from a workspace payload

---

## Controllers, Params and Responses

| Action | Permitted params | Policy method | Success response | Failure response |
|---|---|---|---|---|
| `GranolaConnectionsController#create` | `granola_connection: [:kind, :api_key]` (the controller sets entity / user / connected_by) | `create?` | redirect back, "Connected" | `AuthError` → re-render panel, 422, inline message. Duplicate `scope_key` → flash "already connected" |
| `#update` | `granola_connection: [:api_key]` | `update?` | redirect back; status → connected, cursor kept | as create |
| `#destroy` | — | `destroy?` | redirect back, "Disconnected" | — |
| `#sync` | — | `sync?` | redirect back, "Sync started" | — |
| `GranolaMeetingsController#index` | `status` (`needs_review`/`ignored`, default `needs_review`), `page` | `index?` + `policy_scope` | HTML | — |
| `#file` | `investor_ids: []` | `file?` | turbo_stream remove row + badge replace | `RecordNotFound` → flash "Investor not found", 422 |
| `#discard` | — | `discard?` | turbo_stream remove + badge | — |
| `#rematch` | — | `rematch?` | turbo_stream replace/remove | connection gone → flash, 422 |
| `#rematch_all` | — | `index?` | flash "Re-match started" | — |

**Reviewer checks**
- [ ] `create` never accepts `user_id`, `entity_id` or `connected_by_id` from params
- [ ] An empty `investor_ids` array on `#file` is rejected server-side, not just by the disabled button

---

## Queries and Indexes

| Where | Query shape | Index used | Rows expected | Preload / batching |
|---|---|---|---|---|
| `GranolaSyncAllJob` | `GranolaConnection.syncable.find_each` | PK scan (tiny table) | tens | `find_each` |
| Sync, per page | `GranolaMeeting.where(entity_id:, granola_note_id: page_ids).index_by(&:granola_note_id)` | unique `[entity_id, granola_note_id]` | ≤ 30 | one query per page |
| Matcher | `User.where(entity_id:, email: emails).pluck(:email)` | `users.email` | ≤ attendees | — |
| Matcher | `InvestorAccess.where(entity_id:, email: externals).pluck(:investor_id, :id, :email)` | `investor_accesses.email` | ≤ attendees | — |
| Matcher, fallback | `InvestorAccess.where(entity_id:).where("email LIKE ?", "%@#{domain}").distinct.pluck(:investor_id)` | `entity_id` then scan | the entity's contacts (thousands) | only when there's no exact match |
| Filer | `Investor.where(entity_id:, id: ids)` | PK | ≤ ids | — |
| Inbox | `policy_scope(GranolaMeeting).where(status:).order(meeting_at: :desc)` | `[entity_id, status, meeting_at]` | page of 25 | candidate names: one `Investor.where(id: all_ids).pluck(:id, :investor_name).to_h` |
| Badge | `policy_scope(GranolaMeeting).needs_review.count` | same composite | count | — |
| Notes list | existing query + `includes(:granola_meeting)` | FK index | page | `with_all_rich_text` already loads details |

**Reviewer checks**
- [ ] The LIKE fallback is bounded by `entity_id` and runs only on the no-exact-match path
- [ ] No `pluck(...).uniq` (use `distinct.pluck`), and no `blank?`/`present?` on relations

---

## Transactions, Locking and Concurrency

| Operation | Transaction scope | Lock | Race it prevents | Idempotency key |
|---|---|---|---|---|
| `GranolaNoteFiler.call` | notes + investor callback + meeting | `meeting.lock!` (SELECT … FOR UPDATE) first | two connections filing the same meeting; double-click on File | `filed_investor_ids` re-read under the lock |
| `GranolaNoteFiler.refresh` | the meeting's notes | `meeting.lock!` | refresh racing a manual File | digest compare |
| `upsert_from_api!` | none (single row) | unique index | two connections inserting the same meeting | `[entity_id, granola_note_id]` |
| `claim_sync!` | none | conditional UPDATE, checked for `== 1` rows | cron and Sync now running the same connection | `sync_started_at` |

**Reviewer checks**
- [ ] No Granola HTTP call happens while `meeting.lock!` is held (fetch first, then lock and write)
- [ ] Only one row is ever locked per transaction, so there's no lock-ordering risk

---

## Background Jobs

| Job | Queue | Trigger | Retry / backoff | Discard on | Concurrency guard | Timeout |
|---|---|---|---|---|---|---|
| `GranolaSyncAllJob` | `:low` | sidekiq-cron `every 15 minutes` | default | — | — | fast |
| `GranolaSyncJob(connection_id)` | `:low` | fan-out, Sync now, Connect | `retry_on GranolaClient::RetryableError, wait: :polynomially_longer, attempts: 5` | `ActiveRecord::RecordNotFound` | `claim_sync!` | 30s HTTP read; the claim goes stale after 30 min |
| `GranolaRematchJob(meeting_ids, user_id)` | `:low` | Re-match all | none (each row is best-effort) | `RecordNotFound` | — | ≤ 500 ids |

The whole `GranolaSyncJob` pass runs inside `Chewy.strategy(:atomic)`.

**Reviewer checks**
- [ ] A retry after `retry_on` exhaustion leaves the cursor unchanged and `last_error` set
- [ ] The cron is registered only inside `unless Rails.env.local?`, like its neighbours

---

## External Integrations

| Call | Method + path | Auth | Timeouts | Rate limit handling | Error → exception |
|---|---|---|---|---|---|
| List notes | `GET https://public-api.granola.ai/v1/notes?updated_after=&cursor=&page_size=30` | `Authorization: Bearer grn_…` | 10s open / 30s read | 0.2s spacing; 429 → `RetryableError` honouring `Retry-After` | 401/403 → `AuthError`; 429/5xx/timeout → `RetryableError`; other → `Error` |
| Get note | `GET /v1/notes/{not_…}` (no `include=transcript`) | same | same | same | same, plus 404 → `Error` (skip that meeting) |

**Reviewer checks**
- [ ] The API key never appears in logs or exception messages (Faraday logger off or filtered)
- [ ] A 404 on `get_note` (deleted in Granola) skips the meeting without failing the pass

---

## Error Mapping and Logging

| Exception | Raised in | Handled by | User sees | Logged / alerted |
|---|---|---|---|---|
| `GranolaClient::AuthError` on Connect | client `verify!` | connections controller | inline "Granola rejected this API key…" | none |
| `GranolaClient::AuthError` in a sync | client | `record_failure!` | panel: Needs attention | warn log; `GranolaConnectionFailedNotifier` |
| `GranolaClient::RetryableError` | client | `retry_on`, then `record_failure!` | panel shows `last_error` | info log; notifier after 24h |
| Any error on one meeting | processor / filer | per-meeting rescue in `GranolaSyncService` | — | error log with `entity_id`, `granola_note_id`; error tracker; cursor held |
| `ActiveRecord::RecordNotFound` on file | filer | meetings controller | "Investor not found" | none |

**Reviewer checks**
- [ ] The per-meeting rescue re-raises nothing, but it does prevent the cursor advancing
- [ ] Log lines carry `entity_id`, `granola_connection_id` and `granola_note_id`

---

## Security Review

| Concern | Decision |
|---|---|
| Authorization | `GranolaConnectionPolicy`: `kind=user` only when `record.user_id == user.id`; `workspace` uses the `EntityPolicy#update?` admin test. `GranolaMeetingPolicy`: admin/support see everything in the entity, others only `user_id == user.id` |
| Tenant isolation | Every query filters `entity_id`. The filer loads investors by `entity_id`. **Group Company:** `belongs_to_entity?` admits child-entity records, but the v1 scope uses `entity_id = user.entity_id` only, so group users won't see child funds' meetings. Confirm this is acceptable |
| Secrets | `encrypts :api_key`; only `api_key_last4` rendered; `_key` is already in `filter_parameters` |
| Sanitisation | Redcarpet with `escape_html: true`, then ActionText sanitising |
| Mass assignment | Ownership fields are set in the controller and never permitted |
| Data minimisation | Ignored meetings keep no summary; transcripts are never fetched |

**Reviewer checks**
- [ ] A user from another entity cannot reach any meeting or connection through any route, job or MCP tool (none of these are exposed over MCP in v1)
- [ ] The Group Company scope decision is agreed

---

## Configuration and Rollout

| Item | Value / location |
|---|---|
| Credentials | `active_record_encryption` keys must exist in the credentials of **every** environment (production.in, production.us, staging.*). IN and US are independent. No Granola credentials are needed, because keys are per customer |
| Feature flag | None. The feature is invisible until someone connects a key, and the Inbox link only shows once a connection exists |
| Cron | `GranolaSyncAllJob` every 15 minutes in `config/initializers/sidekiq.rb` |
| Deploy order | migrations → code (cron registers on Sidekiq boot) |
| Rollback | Remove the cron entry and disconnect connections. The tables can stay. Imported notes are ordinary notes and stay |

**Reviewer checks**
- [ ] `active_record_encryption` credentials confirmed present in production.in and production.us before deploy
- [ ] Deploying with zero connections does no work, apart from a no-op cron tick

---

## Test Plumbing

| Feature file | Stubs / fixtures | Factories | New step definitions |
|---|---|---|---|
| `features/core/granola/granola_connections.feature` | `features/support/granola_api_stub.rb` (WebMock, `@sync-http`) | `granola_connection` | connect / disconnect, panel state |
| `features/core/granola/granola_sync.feature` | per-scenario note fixtures (attendees, summary, private notes) | `granola_connection`, `investor_access` (existing) | "Granola returns meeting …", "the sync runs" (`perform_now`) |
| `features/core/granola/granola_inbox.feature` | same | `granola_meeting` | inbox file / discard / re-match |
| `features/core/granola/granola_updates.feature` | fixtures with a changed `updated_at`; 401 / 503 stubs | same | edit a note, time travel for the 24h rule |

---

## Project Rules Checklist

| Rule | Applies? | How it is met |
|---|---|---|
| No `blank?`/`present?` on relations | Applies | `exists?` / `none?` in the policy and badge code |
| Dedup in SQL, batch bulk operations | Applies | `distinct.pluck` in the domain fallback; `find_each` in the cron fan-out |
| `account_entries` column selection / no big `includes` | N/A | Feature doesn't touch `account_entries` |
| Dates: `l(...)` on screens, email format in mailers, no human `strftime` | Applies | Panel and inbox use `l(meeting_at)`; the alert email uses a bare `l()` under `EmailDateLocalization` |
| Date inputs via `f.date_field` / `date_field_tag` | N/A | No date inputs |
| Entity scoping + Pundit on every action | Applies | See Security Review |
| MCP ontology | N/A | No MCP tools in v1 |
| Cucumber only, `TEST_ENV_NUMBER=$RANDOM` | Applies | 4 feature files; `@sync-http` |
| rubocop incl. `IRM/RelationBlankPresent` | Applies | Run on the whole `core/granola` pack |

---

## Sign-off

| Reviewer | Date | Decision | Notes |
|---|---|---|---|
| | | | |
