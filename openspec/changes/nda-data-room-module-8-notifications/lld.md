# NDA Module 8 — Notifications & Reminders — Low-Level Design

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

- **NdaExpiryReminder unique index** `[nda_config_id, investor_id, expiry_date, kind]` — ensures at-most-once semantics for expiry alerts; scanner relies on existence check, not upsert. See [Schema Detail](#schema-detail).
- **GP notification_emails bypass Noticed entirely** — external emails are sent by calling `NdaMailer.method(params).deliver_later` directly, not through a Notifier. Only LP system Users go through NdaEventNotifier → deliver_later. See [Method Contracts](#method-contracts).
- **NdaExpiryCheckJob cron slot at 20:15 UTC (IN) / 06:15 UTC (US)** — placed after FaqVerificationJob (the last current daily slot). See [Background Jobs](#background-jobs).
- **`reason` column on nda_acceptances** — `text, nullable, no limit`. Only populated for status=revoked. No backfill needed (new column, null default). See [Schema Detail](#schema-detail).
- **Two new routes on NdaStatusController** (revoke, send_reminders) — both gated by `NdaStatusPolicy#gp_same_entity?`. See [Controllers, Params and Responses](#controllers-params-and-responses).
- **Expiry scanner iterates entities, not all acceptances globally** — scoped query per entity avoids unbounded loads. See [Queries and Indexes](#queries-and-indexes).

---

## File Map

| Boundary | File | New / Modified | Responsibility |
|---|---|---|---|
| ① Trigger | `app/packs/core/nda_configs/controllers/nda_acceptances_controller.rb` | Modified | Add notification calls after accept/decline save |
| ① Trigger | `app/packs/core/nda_configs/controllers/nda_configs_controller.rb` | Modified | Add version change notification after update when version increments |
| ① Trigger | `app/packs/core/nda_configs/controllers/nda_status_controller.rb` | Modified | Add `revoke` and `send_reminders` actions |
| ② Recipients | `app/packs/core/nda_configs/services/nda_notification_recipients.rb` | New | Resolves GP emails + LP users per event type |
| ③ Notifier | `app/packs/core/nda_configs/models/nda_event_notifier.rb` | New | Noticed notifier for LP event emails (confirm, revoke, version, expiry) |
| ③ Notifier | `app/packs/core/nda_configs/models/nda_reminder_notifier.rb` | New | Noticed notifier for LP reminder emails |
| ④ Mailer | `app/packs/core/nda_configs/mailers/nda_mailer.rb` | New | 8 email methods, handles both direct GP + Noticed LP delivery |
| ④ Mailer | `app/packs/core/nda_configs/views/nda_mailer/nda_accepted.html.erb` | New | GP accept notification template |
| ④ Mailer | `app/packs/core/nda_configs/views/nda_mailer/nda_acceptance_confirm.html.erb` | New | LP confirmation template |
| ④ Mailer | `app/packs/core/nda_configs/views/nda_mailer/nda_declined.html.erb` | New | GP decline notification template |
| ④ Mailer | `app/packs/core/nda_configs/views/nda_mailer/nda_revoked.html.erb` | New | LP revocation notification template |
| ④ Mailer | `app/packs/core/nda_configs/views/nda_mailer/nda_new_version.html.erb` | New | LP version change template |
| ④ Mailer | `app/packs/core/nda_configs/views/nda_mailer/nda_expiry_approaching.html.erb` | New | GP+LP approaching expiry template |
| ④ Mailer | `app/packs/core/nda_configs/views/nda_mailer/nda_expired.html.erb` | New | GP+LP expired template |
| ④ Mailer | `app/packs/core/nda_configs/views/nda_mailer/nda_reminder.html.erb` | New | LP reminder template |
| ⑤ Scanner | `app/packs/core/nda_configs/jobs/nda_expiry_check_job.rb` | New | Daily cron job scanning for expiring acceptances |
| ⑤ Scanner (trigger) | `app/packs/core/nda_configs/jobs/nda_reminder_job.rb` | New | Background job for GP-triggered bulk reminders |
| ⑥ Guard | `app/packs/core/nda_configs/models/nda_expiry_reminder.rb` | New | Idempotency model for expiry alerts |
| ⑦ Revocation | `app/packs/core/nda_configs/models/nda_acceptance.rb` | Modified | Add "revoked" to STATUSES, add `reason` attr, add `revoked?` method |
| ⑦ Revocation | `app/packs/core/nda_configs/services/nda_status_resolver.rb` | Modified | Add "Revoked" status derivation and counter |
| ⑦ Revocation | `app/packs/core/nda_configs/policies/nda_status_policy.rb` | Modified | Add `revoke?` and `send_reminders?` policy methods |
| ⑦ Revocation (UI) | `app/packs/core/nda_configs/views/nda_status/index.html.erb` | Modified | Add Revoke button, Send Reminders button, Revoked status, reason column |
| ⑦ Revocation (UI) | `app/packs/core/nda_configs/views/nda_status/_revoke_dialog.html.erb` | New | Turbo Frame confirmation dialog for revoke |
| ⑦ Revocation (UI) | `app/packs/core/nda_configs/views/nda_status/_remind_dialog.html.erb` | New | Turbo Frame confirmation dialog for send reminders |
| Routes | `config/routes/core.rb` | Modified | Add `revoke` and `send_reminders` routes under nda_status |
| Migration | `db/migrate/YYYYMMDD_add_reason_to_nda_acceptances.rb` | New | Add `reason` text column |
| Migration | `db/migrate/YYYYMMDD_create_nda_expiry_reminders.rb` | New | Create nda_expiry_reminders table |
| Cron | `config/initializers/sidekiq.rb` | Modified | Register NdaExpiryCheckJob cron slot |
| Export | `app/packs/core/nda_configs/views/nda_status/index.xlsx.axlsx` | Modified | Add reason column to XLSX export |

**Reviewer checks**
- [ ] Every class in the [design's class diagram](design.md#class-diagram) has a file here, and nothing here is missing from it
- [ ] Files follow the pack layout (`app/packs/core/nda_configs/...`) and Packwerk boundaries
- [ ] Mailer views live under `views/nda_mailer/`, not `views/nda_configs/`

---

## Schema Detail

**`nda_acceptances`** (existing, ~100s of rows per entity): Adding reason column for revocation audit trail.

| Column | Change | Type | Limit | Null | Default | Index / FK | Why it's needed |
|---|---|---|---|---|---|---|---|
| `reason` | Added | text | none | yes | NULL | none | Free text for GP's optional revocation reason. Text (not string) because reason may be multi-sentence. Nullable — only populated for status=revoked; accepted/declined rows have NULL. No index needed — never queried by reason. |

**Migration safety:** nda_acceptances has <10k rows across all entities. `ADD COLUMN text NULL` is an instant metadata-only operation in MySQL 8+ (no table rebuild, no lock). No backfill needed. Reversible via `remove_column`.

**Model change:** Add "revoked" to `STATUSES = %w[accepted declined revoked].freeze`. Add `reason` to model (no attr restriction needed — ApplicationRecord does not use `attr_accessible`). Add `revoked?` convenience method.

---

**`nda_expiry_reminders`** (new): Idempotency guard for expiry alerts. Following ObligationReminder pattern.

| Column | Change | Type | Limit | Null | Default | Index / FK | Why it's needed |
|---|---|---|---|---|---|---|---|
| `id` | Added | bigint | — | no | auto | PK | Standard primary key |
| `nda_config_id` | Added | bigint | — | no | — | FK → nda_configs, part of unique composite | Scopes to a specific NDA configuration |
| `investor_id` | Added | bigint | — | no | — | FK → investors, part of unique composite | Tracks which investor this alert was sent for |
| `expiry_date` | Added | date | — | no | — | part of unique composite | The computed expiry date. Enables dedup: same investor but different expiry (after re-accept) = separate alert series |
| `kind` | Added | string | 20 | no | — | part of unique composite | "approaching" or "expired" — two distinct alerts per expiry event |
| `sent_at` | Added | datetime | — | no | — | none | When the alert was actually sent. Audit trail. |
| `created_at` | Added | datetime | — | no | — | none | Rails timestamp |
| `updated_at` | Added | datetime | — | no | — | none | Rails timestamp |

| Index | Columns | Unique | Why |
|---|---|---|---|
| `idx_nda_expiry_reminders_dedup` | `[nda_config_id, investor_id, expiry_date, kind]` | yes | The idempotency guard. Scanner checks `exists?` on this before sending. RecordNotUnique on race = safe skip. |
| `idx_nda_expiry_reminders_config` | `[nda_config_id]` | no | FK index for has_many from NdaConfig. Also used by scanner when clearing stale reminders for a re-accepted investor. |
| `fk_nda_expiry_reminders_investor` | `[investor_id]` | no | FK index |

**Migration safety:** New table. No lock on existing tables. `create_table` is a DDL statement — fast. Reversible via `drop_table`.

**Reviewer checks**
- [ ] Every new or changed column and index has a "why", and none is unjustified
- [ ] Every foreign key has an index, and every uniqueness rule is enforced by a unique index
- [ ] Column limits match validation limits (`kind` string limit 20 matches KINDS constant)
- [ ] Migration is reversible and safe on the production table size
- [ ] `nda_expiry_reminders` unique index column order matches the query pattern (nda_config_id first, then investor_id — matches the scanner's entity-scoped iteration)

---

## Method Contracts

**`NdaNotificationRecipients`** (Service)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `.resolve(event_type, nda_config, investor, options = {})` | `event_type`: Symbol (`:accepted`, `:declined`, `:revoked`, `:new_version`, `:expiry_approaching`, `:expired`, `:reminder`). `nda_config`: NdaConfig. `investor`: Investor (nil for `:reminder`/`:new_version`). `options`: `{ exclude_user_id: }` | `{ gp_emails: Array<String>, lp_users: Array<User> }` | None | None (read-only) | Yes |
| `#parsed_notification_emails` | none | `Array<String>` | None | None | Yes |

**`NdaEventNotifier`** (Notifier < BaseNotifier)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `#mailer_name` | none | `NdaMailer` | None | None | Yes |
| `#email_method` | none | Symbol from `params[:email_method]` | None | None | Yes |
| `#email_data(notification)` | Noticed notification | Hash with keys per email method | None | None | Yes |

Required params: `entity_id`, `email_method`, `record` (NdaAcceptance or NdaConfig). Optional: `investor_name`, `folder_name`, `folder_link`, `contact_email`, `expiry_date`, `days_until_expiry`, `old_version`, `new_version`, `reason`.

**`NdaReminderNotifier`** (Notifier < BaseNotifier)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `#mailer_name` | none | `NdaMailer` | None | None | Yes |
| `#email_method` | none | `:nda_reminder` | None | None | Yes |
| `#email_data(notification)` | Noticed notification | Hash with folder_name, folder_link, contact_email | None | None | Yes |

Required params: `entity_id`, `record` (NdaConfig), `folder_name`, `folder_link`, `contact_email`.

**`NdaMailer`** (Mailer < ApplicationMailer)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `#nda_accepted(params)` | Hash from email_data or direct call | Mail::Message | None | Sends email | Yes (same content if called twice) |
| `#nda_acceptance_confirm(params)` | Hash from email_data | Mail::Message | None | Sends email | Yes |
| `#nda_declined(params)` | Hash from email_data or direct call | Mail::Message | None | Sends email | Yes |
| `#nda_revoked(params)` | Hash from email_data | Mail::Message | None | Sends email | Yes |
| `#nda_new_version(params)` | Hash from email_data | Mail::Message | None | Sends email | Yes |
| `#nda_expiry_approaching(params)` | Hash from email_data or direct call | Mail::Message | None | Sends email | Yes |
| `#nda_expired(params)` | Hash from email_data or direct call | Mail::Message | None | Sends email | Yes |
| `#nda_reminder(params)` | Hash from email_data | Mail::Message | None | Sends email | Yes |

GP-facing methods (nda_accepted, nda_declined, nda_expiry_approaching, nda_expired) have a dual code path: when called through Noticed (LP user), they use `setup_defaults`; when called directly for GP emails, they set `to:` from the passed email address and skip `setup_defaults`.

**`NdaExpiryCheckJob`** (Job)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `#perform` | none | void | StandardError (rescued per-entity) | Creates NdaExpiryReminder records, enqueues notifications | Yes (idempotency guard) |

**`NdaReminderJob`** (Job)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `#perform(nda_config_id)` | nda_config_id: Integer | void | ActiveRecord::RecordNotFound | Enqueues notifications | No (sends each time — manual trigger, intentional) |

**`NdaExpiryReminder`** (Model)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `.already_sent?(nda_config_id, investor_id, expiry_date, kind)` | column values | Boolean | None | None (read-only) | Yes |

**Reviewer checks**
- [ ] Every raised error is handled by a caller or listed in Error Mapping
- [ ] Anything a retry can repeat is idempotent
- [ ] NdaMailer GP-direct code path does not call `setup_defaults` (which expects a User record)

---

## Controllers, Params and Responses

| Action | Permitted params | Policy method | Success response | Failure response |
|---|---|---|---|---|
| `NdaStatusController#revoke` | `investor_id`, `reason` (text, optional) | `NdaStatusPolicy#revoke?` → `gp_same_entity?` | Turbo Stream: update investor row status to "Revoked" + flash | 422 + flash alert if investor not in Accepted status |
| `NdaStatusController#send_reminders` | none (nda_config_id from existing before_action) | `NdaStatusPolicy#send_reminders?` → `gp_same_entity?` | Turbo Stream: flash "Reminders sent to X users" | 422 + flash if no pending investors |

**Route additions** in `config/routes/core.rb`:

```
post "nda_status/revoke", controller: "nda_status", action: :revoke, as: :nda_status_revoke
post "nda_status/send_reminders", controller: "nda_status", action: :send_reminders, as: :nda_status_send_reminders
```

**Existing trigger points** (modified, no new params):

| Action | Change | Notification triggered |
|---|---|---|
| `NdaAcceptancesController#create` | After successful save, call notification service | GP accept + LP confirm |
| `NdaAcceptancesController#decline` | After successful save, call notification service | GP decline |
| `NdaConfigsController#update` | After successful save when `saved_change_to_version?`, call notification service | LP new version |

**Reviewer checks**
- [ ] No action without `authorize` / `policy_scope`
- [ ] Permitted params can't set `entity_id`, `user_id` or other ownership fields
- [ ] `revoke` action sets `user_id` from `current_user`, not from params
- [ ] `investor_id` on revoke is validated against the NdaConfig's entity (cannot revoke investor from another entity)

---

## Queries and Indexes

| Where | Query shape | Index used | Rows expected | Preload / batching |
|---|---|---|---|---|
| `NdaNotificationRecipients#resolve` (LP users) | `InvestorAccess.where(entity_id:, investor_id:, approved: true).includes(:user)` | `idx_investor_accesses_entity` (existing) | ≤ 10 per investor | `.includes(:user)` |
| `NdaNotificationRecipients#resolve` (exempt check) | `InvestorAccess.where(entity_id:, investor_id:, exempt_from_nda: true).exists?` | `idx_investor_accesses_entity` (existing) | 0 or 1 | none needed (exists?) |
| `NdaNotificationRecipients#resolve` (signatories) | `NdaSignatory.where(nda_config_id:).includes(:user)` | `idx_nda_signatories_config_user` (existing) | ≤ 20 | `.includes(:user)` |
| `NdaNotificationRecipients#resolve` (stale acceptances for version change) | `NdaAcceptance.where(nda_config_id:, status: "accepted").where.not(nda_version: nda_config.version).select(:investor_id).distinct` | `idx_nda_acceptances_gate_lookup` (existing) | ≤ 50 | `.distinct.pluck(:investor_id)` |
| `NdaExpiryCheckJob#perform` (find entities with time-based NDAs) | `NdaConfig.where(enabled: true).where.not(validity_type: "until_revoked").select(:entity_id).distinct` | `idx_nda_configs_deleted_at` + sequential scan on `enabled` | ≤ 100 total | `.distinct.pluck(:entity_id)` then iterate |
| `NdaExpiryCheckJob#perform` (accepted acceptances per config) | `NdaAcceptance.where(nda_config_id:, status: "accepted")` | `idx_nda_acceptances_gate_lookup` | ≤ 50 per config | loaded into memory (small set) |
| `NdaExpiryCheckJob#perform` (idempotency check) | `NdaExpiryReminder.exists?(nda_config_id:, investor_id:, expiry_date:, kind:)` | `idx_nda_expiry_reminders_dedup` (unique) | 0 or 1 | none needed (exists?) |
| `NdaStatusController#revoke` (find latest accepted) | `NdaAcceptance.where(nda_config_id:, investor_id:, status: "accepted").order(created_at: :desc).first` | `idx_nda_acceptances_gate_lookup` | 1 | none |
| `NdaStatusResolver` (counters — modified) | Same existing queries, now also returns "Revoked" | existing indexes | unchanged | unchanged |

**Reviewer checks**
- [ ] Every query is scoped by `entity_id`, or explains why not (NdaExpiryCheckJob iterates by entity_id from NdaConfig)
- [ ] No N+1 on list pages. No unbounded loads (expiry scanner uses entity-scoped iteration)
- [ ] Stale acceptance query for version change uses `distinct.pluck(:investor_id)` to avoid loading full records

---

## Transactions, Locking and Concurrency

| Operation | Transaction scope | Lock | Race it prevents | Idempotency key |
|---|---|---|---|---|
| Revoke acceptance | Single INSERT (NdaAcceptance with status "revoked") | None (append-only) | Double-revoke: second revoke finds no "Accepted" investor → 422. No data corruption. | None needed — append-only, duplicates visible in audit trail |
| NdaExpiryReminder creation | Single INSERT | None | Duplicate alert: unique index on `[nda_config_id, investor_id, expiry_date, kind]` → RecordNotUnique rescued silently | Unique composite index |
| Send reminders | Enqueue multiple NdaReminderNotifier deliveries | None | Double-send if GP clicks twice: confirmation dialog prevents double-click; if it does happen, duplicate email is harmless (same content) | None — intentional one-shot |

**Reviewer checks**
- [ ] No external HTTP call or email inside a transaction
- [ ] Lock order is consistent everywhere two rows are locked (N/A — no locks used)
- [ ] NdaExpiryReminder INSERT + RecordNotUnique rescue is safe without transaction

---

## Background Jobs

| Job | Queue | Trigger | Retry / backoff | Discard on | Concurrency guard | Timeout |
|---|---|---|---|---|---|---|
| `NdaExpiryCheckJob` | `default` | Sidekiq-cron daily at `15 20 * * *` (IN) / `15 6 * * *` (US) | Sidekiq default (25 retries, exponential) | None | Single cron instance (Sidekiq-cron built-in) | None (fast — iterates small entity set) |
| `NdaReminderJob` | `default` | GP clicks "Send Reminders" → controller enqueues | Sidekiq default | `ActiveRecord::RecordNotFound` (NdaConfig deleted mid-flight) | None needed (manual trigger, fire-and-forget) | None |
| Noticed delivery jobs (NdaEventNotifier, NdaReminderNotifier) | `default` (Noticed default) | Enqueued by Noticed `deliver_later` | Sidekiq default (25) | None | Noticed built-in | None |
| Direct GP mailer calls | `mailers` (ActionMailer default) | Enqueued by `.deliver_later` from trigger code | Sidekiq default | None | None | None |

**Cron registration** in `config/initializers/sidekiq.rb`:

```ruby
nda_expiry_check_cron = in_region ? '15 20 * * *' : '15 6 * * *'
Sidekiq::Cron::Job.create(name: 'NdaExpiryCheckJob', cron: nda_expiry_check_cron, class: 'NdaExpiryCheckJob')
```

Slot is 15 minutes after FaqVerificationJob (the last current daily job). Comment block at top of cron section updated to include `01:45 NdaExpiryCheckJob`.

**Reviewer checks**
- [ ] A job that runs twice, or out of order, is harmless (NdaExpiryCheckJob: idempotency guard; NdaReminderJob: manual trigger, harmless duplicate)
- [ ] Cron entry registered in the same block as other daily jobs, with region-aware expression
- [ ] NdaExpiryCheckJob rescues per-entity errors to avoid one entity's failure blocking others

---

## External Integrations

N/A — No external API calls. Email delivery goes through the existing SES/SMTP setup configured in ActionMailer. No new external service integration.

**Reviewer checks**
- [ ] N/A

---

## Error Mapping and Logging

| Exception | Raised in | Handled by | User sees | Logged / alerted |
|---|---|---|---|---|
| `ActiveRecord::RecordNotUnique` | NdaExpiryReminder creation (duplicate alert) | `rescue` in NdaExpiryCheckJob — silently skips | Nothing | Debug log: "Expiry alert already sent for investor #{id}" |
| `ActiveRecord::RecordNotFound` | NdaReminderJob (NdaConfig deleted) | Sidekiq discard | Nothing (job was enqueued, config gone) | Warn log |
| `ActiveRecord::RecordInvalid` | NdaAcceptance save on revoke (validation fail) | Controller rescue → 422 | Flash: "Unable to revoke" | Error log with validation messages |
| `Net::SMTPError` (or SES equivalent) | Mailer delivery job | Sidekiq retry (up to 25) | Nothing (background) | Standard Sidekiq error logging |
| `StandardError` | NdaExpiryCheckJob per-entity iteration | Per-entity rescue → continue to next entity | Nothing | Error log with entity_id + backtrace. Sidekiq dead set if entire job fails. |

**Reviewer checks**
- [ ] No bare `rescue => e` that swallows errors silently (NdaExpiryCheckJob rescues per-entity with logging)
- [ ] Log lines carry the ids needed to debug (entity_id, nda_config_id, investor_id)

---

## Security Review

| Concern | Decision |
|---|---|
| Authorization | `NdaStatusPolicy#revoke?` and `#send_reminders?` both delegate to `gp_same_entity?` — same pattern as existing `index?`, `create_signatory?`. Every controller action calls `authorize`. |
| Tenant isolation | Every query scoped by `entity_id` (from NdaConfig or explicit param). NdaExpiryCheckJob iterates entities independently. Investor scoping: revoke validates investor has InvestorAccess for the NdaConfig's entity before allowing revocation. |
| Secrets | No new secrets. Emails sent through existing SES credentials. No API keys introduced. |
| Input / output sanitisation | `reason` field: free text stored as-is, rendered in ERB with `<%= %>` (auto-escaped by Rails). notification_emails: already validated on NdaConfig save with `EMAIL_FORMAT`. No user-generated HTML in email templates. |
| Mass assignment | `revoke` action: `investor_id` from params (validated), `reason` from params (text). `user_id` set from `current_user`, `entity_id` from `@nda_config.entity_id` — never from params. |

**Reviewer checks**
- [ ] A user from another entity cannot reach any record through any route, job, or mailer
- [ ] LP users cannot access `revoke` or `send_reminders` actions (gp_same_entity? returns false for LP)
- [ ] `reason` text is escaped in all display contexts (dashboard HTML, XLSX export, email template)

---

## Configuration and Rollout

| Item | Value / location |
|---|---|
| Credentials / env vars | None new. Uses existing SES/SMTP config in `config/environments/`. |
| Feature flag | None. Module 8 is additive — notifications appear silently. Revoke button visible immediately but only for GPs with existing dashboard access. |
| Cron / schedules | `NdaExpiryCheckJob` added to `config/initializers/sidekiq.rb` daily cron block |
| Deploy order | 1. Run migrations (add reason column + create nda_expiry_reminders). 2. Deploy code (new files + modified files). 3. Sidekiq restart picks up new cron. All three happen in standard Capistrano deploy. |
| Rollback | Remove cron entry → Sidekiq restart stops expiry checks. Notification code is controller-level — removing the calls silences notifications. `reason` column is nullable — no harm leaving it. `nda_expiry_reminders` table can be dropped. "revoked" status: any existing revoked records stay valid in the append-only trail. |

**Reviewer checks**
- [ ] Safe to deploy with the feature unused (notifications fire only when NDA events happen), and safe to roll back (remove cron + notification calls)
- [ ] No feature flag needed — notifications are additive and the revoke button only appears for Accepted investors on the GP dashboard

---

## Test Plumbing

| Feature file | Stubs / fixtures | Factories | New step definitions |
|---|---|---|---|
| `features/core/nda_notifications.feature` | `ActionMailer::Base.deliveries` for email assertions | Reuse existing: entity, folder, nda_config, investor, investor_access, user. New: nda_acceptance (accepted/declined/revoked) | `Then {string} should receive an NDA email with subject {string}`, `Then no NDA email should be sent`, `When the NDA expiry check job runs` |
| `features/core/nda_reminders.feature` | `ActionMailer::Base.deliveries` | Same as above + nda_signatory | `When the GP sends NDA reminders`, `Then {int} reminder emails should be sent` |
| `features/core/nda_expiry.feature` | `ActionMailer::Base.deliveries`, `travel_to` for date simulation | Same as above + nda_expiry_reminder (for idempotency test) | `Given an NDA acceptance created {int} days ago`, `When the daily expiry check runs`, `Then no duplicate expiry alert should be sent` |
| `features/core/nda_revocation.feature` | None | Same as above | `When the GP revokes the NDA for {string}`, `Then the investor status should be {string}`, `Given the GP enters reason {string}` |

**Shared NDA steps:** Reuse existing step definitions from `features/step_definitions/nda_acceptance_steps.rb` and `features/step_definitions/nda_status_steps.rb` for setup (creating entities, folders, NDA configs, investor access, signatories).

**Email assertion pattern:** Follow the existing `side_letter_obligation_steps.rb` pattern: clear `ActionMailer::Base.deliveries` before the trigger step, then assert on `deliveries.select { |m| m.subject.include?(expected_text) }`.

---

## Project Rules Checklist

| Rule | Applies? | How it is met |
|---|---|---|
| No `blank?`/`present?` on relations; use `exists?`/`none?` | Applies | NdaExpiryReminder check uses `.exists?`. InvestorAccess exempt check uses `.exists?`. No `.blank?` or `.present?` on relation queries. |
| Dedup in SQL (`distinct.pluck`), batch bulk operations (`find_each`/`in_batches`) | Applies | Stale acceptance investor_ids: `distinct.pluck(:investor_id)`. Entity iteration in expiry scanner: `distinct.pluck(:entity_id)`. Per-entity acceptance sets are small enough for in-memory (≤50 rows). |
| Select only needed columns when loading many records; no speculative `includes` | Applies | Recipient resolution uses `.includes(:user)` only when accessing user attributes. Stale acceptance query uses `.select(:investor_id).distinct`. |
| Screen dates via `l(...)`; emails render `Mon dd, yyyy` via `EmailDateLocalization`; no human-format `strftime` | Applies | All date rendering in email templates uses `l(date, format: :long)` or `EmailDateLocalization` helper. No raw `strftime`. Dashboard reason column is text, not date. |
| Date inputs use `f.date_field` / `date_field_tag`; JS dates via `locale_date_format.js` | N/A | No new date input fields. Reason is a text field. Expiry dates are computed, not user-entered. |
| Every query entity-scoped; Pundit `authorize`/`policy_scope` on every action | Applies | All queries scoped by entity_id (from NdaConfig). `authorize @nda_config, policy_class: NdaStatusPolicy` on revoke and send_reminders. NdaAcceptancesController already authorizes on create/decline. |
| MCP tool surfaces changed only via the ontology YAML | N/A | No MCP tools added or changed. |
| Cucumber only (no RSpec); `TEST_ENV_NUMBER=$RANDOM` on every run | Applies | All tests are Cucumber features. Test commands use `TEST_ENV_NUMBER=$RANDOM`. |
| `bundle exec rubocop` clean, including the `IRM/RelationBlankPresent` cop | Applies | No `blank?`/`present?` on relations. All new files include `# frozen_string_literal: true` and YARD comments. |

---

## Sign-off

| Reviewer | Date | Decision | Notes |
|---|---|---|---|
| | | <!-- Approved / Changes requested --> | |
