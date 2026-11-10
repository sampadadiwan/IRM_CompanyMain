# Security Event Trail — Low-Level Design

> **Audience:** The developer who reviews the implementation plan before coding starts.
> **Companion documents:** [Design](design.md) · [Business rules](business-rules.md) · [Spec](specs/identity/security-event-trail/spec.md) · [Tasks](tasks.md)

> **Planning phase — no code changes.** Adds to [design.md](design.md); links rather than repeats.

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
- [Pattern Conformance](#pattern-conformance)
- [Security Detail](#security-detail)
- [Project Rules Checklist](#project-rules-checklist)
- [Sign-off](#sign-off)

---

## Review Summary

- **rolify callbacks are the role hook** (design D2) — verify `remove_role` fires `after_remove` before
  building on it; see [Method Contracts](#method-contracts) `User#security_role_added/removed`.
- **Enqueue after the outer transaction commits** via `ActiveRecord.after_all_transactions_commit` —
  check this is available on the app's Rails version; see [Transactions](#transactions-locking-and-concurrency).
- **Never-raise recorder** with three tiers (queue → inline insert → log) — see [Error Mapping](#error-mapping-and-logging).
- **Request context from `Audited.store[:current_controller]`** (design D6) — API controllers that don't
  run the sweeper pass `request:` explicitly; see [Method Contracts](#method-contracts).
- **Warden `before_failure` filter** on `POST /users/sign_in` — see [Controllers](#controllers-params-and-responses).
- **`entity_id` is not ransackable** — the tenant filter is the policy only; see [Security Review](#security-review).

**Reviewer checks**
- [ ] Each bullet above has been checked against the code before approval

---

## File Map

| Boundary | File | New / Modified | Responsibility |
|---|---|---|---|
| ③ | `app/packs/core/security_events/services/security_events.rb` | New | `SecurityEvents.record` |
| ③ | `app/packs/core/security_events/services/security_events/catalogue.rb` | New | frozen kind table |
| ③ | `app/packs/core/security_events/services/security_events/context.rb` | New | IP/UA/actor/impersonator/digest |
| ④ | `app/packs/core/security_events/jobs/security_event_write_job.rb` | New | insert by uid, alert |
| ⑤ | `app/packs/core/security_events/models/security_event.rb` | New | read-only model, scopes, ransack allowlist, `STANDARD_COLUMNS` |
| ⑤ | `db/migrate/2026111xxxxxxx_create_security_events.rb` | New | table + 6 indexes |
| ⑤ | `db/schema.rb`, `db/schema_test.rb` | Modified | regenerated (restore per local-migrate note) |
| ⑥ | `app/packs/core/security_events/controllers/security_events_controller.rb` | New | `index` (html, xlsx) |
| ⑥ | `app/packs/core/security_events/policies/security_event_policy.rb` | New | `index?`, `Scope` |
| ⑥ | `app/packs/core/security_events/jobs/security_event_download_job.rb` | New | xlsx by email |
| ⑥ | `app/packs/core/security_events/views/security_events/index.html.erb`, `_index.html.erb`, `_grid_stats.html.erb`, `index.xlsx.axlsx` | New | screen, cards, spreadsheet |
| ⑥ | `config/routes.rb` | Modified | `resources :security_events, only: :index` |
| ⑥ | `app/packs/core/base/views/layouts/modernize/_company_menus.html.erb:138` | Modified | menu entry |
| ⑦ | `app/packs/core/security_events/services/security_event_alert.rb` | New | alert kinds + recipients |
| ⑦ | `app/packs/core/security_events/mailers/security_event_notifier.rb` | New | `< BaseNotifier` |
| ⑦ | `app/packs/core/security_events/mailers/security_events_mailer.rb` + views | New | `admin_alert`, `download`, `weekly_pack` |
| ⑧ | `app/packs/core/security_events/jobs/security_event_weekly_pack_job.rb` | New | Monday xlsx |
| ⑧ | `app/packs/core/security_events/jobs/security_event_purge_job.rb` | New | retention |
| ⑧ | `config/initializers/sidekiq.rb` | Modified | 2 cron entries |
| ② | `app/packs/core/users/models/user.rb` (`:173`, `:284`, `:986`) | Modified | K1–K3 |
| ② | `app/packs/core/support_client_mappings/models/support_client_mapping.rb` (`:77`, `:109`) | Modified | K4 |
| ② | `config/initializers/security_event_warden.rb` | New | `before_failure` |
| ② | `config/initializers/devise_api.rb` | Modified | `after_successful_sign_in` |
| ② | `config/initializers/doorkeeper.rb:500` | Modified | `after_successful_authorization` |
| ② | `app/packs/core/base/controllers/application_controller.rb:27` | Modified | xlsx `after_action` |
| ② | `users/sessions_controller.rb:41,51`; `users/two_factor_controller.rb:144,189,232,349,362`; `users_controller.rb:186,216,233,264,267,301,462`; `users/passwords_controller.rb` (new `create`/`update` wrappers); `users/tokens_controller.rb:15`; `users/mobile_handoffs_controller.rb:29,34`; `users/api_tokens_controller.rb:16,29`; `users/mobile_devices_controller.rb:12`; `api/mobile/v1/sessions_controller.rb:51,63`; `outlook_addin_controller.rb:58`; `gmail_addin_controller.rb:87`; `api/v1/mail/base_controller.rb:72,80,81`; `mcp_controller.rb:97`; `entities_controller.rb:127,153`; `folders_controller.rb:31`; `documents_controller.rb:375`; `report_builder_controller.rb:182`; `secondary_sales_controller.rb:130` | Modified | one `SecurityEvents.record` line each (K5) |
| Tests | `features/security/security_events_{sign_in,access,screen,tenant_isolation}.feature`, `features/step_definitions/security_events_steps.rb` | New | business-rules rows |

**Reviewer checks**
- [ ] Every class in the design's class diagram has a file here, and nothing here is missing from it
- [ ] New files live under `app/packs/core/security_events/` (core package; no new `package.yml` needed)

---

## Schema Detail

**`security_events`** (new): the append-only trail (design D1).

| Column | Change | Type | Limit | Null | Default | Index / FK | Why it's needed |
|---|---|---|---|---|---|---|---|
| `id` | Added | bigint | — | no | auto | PK | keyset paging, purge batches |
| `uid` | Added | string | 36 | no | — | unique | idempotent write; UUID string length |
| `entity_id` | Added | bigint | — | yes | — | `[entity_id, occurred_at]`; no FK | NULL for unknown accounts; no FK so a deleted firm keeps evidence |
| `kind` | Added | string | 40 | no | — | `[kind, occurred_at]` | longest kind `connected_app.authorised` = 24 |
| `category` | Added | string | 20 | no | — | — | 7 values; card counts |
| `outcome` | Added | string | 10 | no | `"success"` | — | `success`/`failure` |
| `door` | Added | string | 20 | no | — | — | longest `mobile_handoff` = 14 |
| `user_id` | Added | bigint | — | yes | — | `[user_id, occurred_at]` | account |
| `actor_id` | Added | bigint | — | yes | — | — | filter by actor is rare; no index |
| `impersonator_id` | Added | bigint | — | yes | — | — | rare filter |
| `identifier_digest` | Added | string | 64 | yes | — | — | hex SHA-256 |
| `ip_address` | Added | string | 45 | yes | — | `[ip_address, occurred_at]` | IPv6 max text length; nil in jobs |
| `user_agent` | Added | string | 255 | yes | — | — | truncated in Context |
| `request_id` | Added | string | 36 | yes | — | — | `request.request_id` UUID |
| `region` | Added | string | 5 | no | — | — | `ENV["CURRENT_SITE"]` upcased |
| `details` | Added | json | — | yes | — | — | allowlisted keys only, < 1 KB |
| `occurred_at` | Added | datetime(6) | — | no | — | `[occurred_at]` | set on request thread |
| `created_at` | Added | datetime(6) | — | no | — | — | write lag; no `updated_at` (append-only) |

**Migration safety:** new empty table; no backfill; reversible (`create_table`/`drop_table`). Update both
`db/schema.rb` and `db/schema_test.rb`. Do **not** run against the shared dev DB from a side branch.

**Reviewer checks**
- [ ] Every new column and index has a "why", and none is unjustified
- [ ] `uid` unique index exists; no FK on any id (evidence survives deletes)
- [ ] Column limits match `Catalogue` values and Context truncation
- [ ] Migration is reversible; no `updated_at`

---

## Method Contracts

**`SecurityEvents`** (Service)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `.record(kind, user: nil, door: nil, outcome: :success, details: {}, entity_id: nil, email: nil, actor: :current, request: nil)` | kind String in Catalogue; user User/nil; email only for failures | `nil` | never | enqueue (after commit) or inline insert or warn log; `ActiveSupport::Notifications.instrument("recorded.security_event", kind:, outcome:, door:)` | No — each call is one event (uid minted per call) |

**`SecurityEvents::Context`** (Service)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `.current(request: nil)` | explicit request or `Audited.store[:current_controller]&.request` | `{ip_address:, user_agent:, request_id:, actor_id:, impersonator_id:}` | never | none; no query | Yes |
| `.identifier_digest(email)` | String | 64-char hex or nil | never | none | Yes |

- Actor: `controller.current_user&.id` if the controller responds; else `Current.user&.id`; else nil (= System).
- Impersonator: `controller.session[:support_user_id]` (web) — nil for bearer controllers.
- Door default: `web_password` for `ActionController::Base` requests, `system` when no request.
- Digest: `OpenSSL::HMAC.hexdigest("SHA256", Rails.application.secret_key_base[0,32] + "security_event", email.strip.downcase)` — per-region secret, so a digest can't be matched across regions.

**`SecurityEvent`** (Model)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `.write!(attrs)` | attrs Hash | record or nil when uid exists | DB errors | insert on writing role | Yes (uid) |
| `#readonly?` | — | `persisted?` | — | — | — |
| `.for_period(range)` | Range | Relation | — | — | — |

**`User`** (Model, existing — K1–K3)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `#security_role_added(role)` / `#security_role_removed(role)` | Role | nil | never | `record("role.granted"/"role.revoked", user: self, details: {role: role.name, resource_type:, resource_id:})` | n/a |
| `#record_security_changes` (`after_update_commit`) | — | nil | never | one record per changed watched column | n/a |
| `.disable_support_for_all` | — | as today | as today | + one `support_access.disabled` door `system` | n/a |

**`SecurityEventAlert`** (Service)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `.deliver(event)` | SecurityEvent | nil | delivery errors bubble to job | `SecurityEventNotifier.with(record: event, entity_id:).deliver(recipients)` | Called once per uid by the job |
| `.alert?(event)` | SecurityEvent | bool | — | — | Yes |
| `.recipients(event)` | SecurityEvent | Relation | — | — | Yes |

**Reviewer checks**
- [ ] `record` has a top-level `rescue StandardError` and returns nil on every path
- [ ] `details` passes through `Catalogue.fetch(kind)[:detail_keys]` slice before leaving the request
- [ ] Anything a retry can repeat (`write!`, alert) is guarded by `uid`

---

## Controllers, Params and Responses

| Action | Permitted params | Policy method | Success response | Failure response |
|---|---|---|---|---|
| `SecurityEventsController#index` (html) | `q:` ransack on allowlist; `page` | `index?` + `policy_scope` | 200, frame `security_events_frame` | Pundit → "You are not authorized to perform this action." |
| `SecurityEventsController#index` (xlsx) | same | same | enqueue `SecurityEventDownloadJob(params.to_unsafe_h.slice("q"), user_id:)`; redirect back + flash | same |
| Warden `before_failure` | — | — | n/a | n/a; records only when `env["REQUEST_METHOD"] == "POST" && env["PATH_INFO"] == "/users/sign_in"` |
| `Users::PasswordsController#create`/`#update` | unchanged (call `super`) | — | unchanged | unchanged |

- Ransack allowlist: `kind category outcome door ip_address occurred_at user_id actor_id region` — **no**
  `entity_id`, `details`, `identifier_digest` (the digest is searched through a dedicated `email` filter
  that digests the input).
- Breadcrumbs: `{ "Settings" => nil, "Security Events" => nil }`.
- `verify_authorized` / `verify_policy_scoped` stay on (no exclusion).

**Reviewer checks**
- [ ] No action without `authorize` / `policy_scope`
- [ ] Permitted params can't set `entity_id`
- [ ] No row actions → no turbo-stream needed; filter/page replace the frame
- [ ] Breadcrumbs set; frame requests render only the frame

---

## Queries and Indexes

| Where | Query shape | Index used | Rows expected | Preload / batching |
|---|---|---|---|---|
| List | `policy_scope.where(occurred_at: range).ransack(q).result.order(occurred_at: :desc)` paged 25 | `[entity_id, occurred_at]` | ≤ 2,500/month/firm | `includes(:user, :actor, :impersonator)` |
| Cards | same scope `.group(:category, :outcome).count` | same | 1 query | — |
| Download | same scope `find_each(batch_size: 1000)` | same | ≤ 30k | users preloaded per batch |
| Weekly pack | `SecurityEvent.where(occurred_at: week).find_each`; sheets via `group(:user_id, "DATE(occurred_at)").where(kind: "sign_in.failed").count` | `[occurred_at]`, `[kind, occurred_at]` | ~600/week | — |
| Purge | `where(occurred_at: ...cutoff).in_batches(of: 5_000).delete_all` | `[occurred_at]` | 0 until month 14 | batches |
| Alert recipients | `User.company_admins.active.where(entity_id:)` | users indexes | ≤ 10 | — |
| Web failure user lookup (job) | `User.find_for_authentication(email:)` | `users.email` unique | 1 | — |

**Reviewer checks**
- [ ] Every query scoped by `entity_id` via the policy (super excepted)
- [ ] No N+1 on the list (user links decided from a memoised set of visible entity ids)
- [ ] `PROSOPITE=1` clean for `security_events_screen.feature`

---

## Transactions, Locking and Concurrency

| Operation | Transaction scope | Lock | Race it prevents | Idempotency key |
|---|---|---|---|---|
| Enqueue from a callback | outer caller's | none | recording a rolled-back grant | `ActiveRecord.after_all_transactions_commit { enqueue }` |
| Write | none | none | double insert on retry | `uid` unique |
| Alert | after insert | none | double email on retry | only on fresh insert |
| Purge | per batch | none | — | — |

**Reviewer checks**
- [ ] No email or enqueue inside an open transaction
- [ ] `after_all_transactions_commit` exists on this Rails version (else `after_commit` on a transaction callback object)

---

## Background Jobs

| Job | Queue | Trigger | Retry / backoff | Discard on | Concurrency guard | Timeout |
|---|---|---|---|---|---|---|
| `SecurityEventWriteJob` | `:default` | `record` | ActiveJob/Sidekiq default (25) | `ActiveJob::DeserializationError` (inherited) | `uid` unique | — |
| `SecurityEventDownloadJob` | `:low` | Download click | 3 | `RecordNotFound` (user gone) | — | — |
| `SecurityEventWeeklyPackJob` | `:low` | cron Mon in `30 1 * * 1` / us `0 12 * * 1` | 3 | — | sidekiq-cron single schedule | — |
| `SecurityEventPurgeJob` | `:low` | cron daily in `15 21 * * *` / us `15 7 * * *` | 3 | — | idempotent by nature | — |

- All four: `self.log_arguments = false` (attrs carry IP/UA; download params carry filters).
- Cron entries go in the non-local block of `config/initializers/sidekiq.rb` next to `ReportDraftCleanupJob`.

**Reviewer checks**
- [ ] A job that runs twice, or out of order, is harmless
- [ ] Cron entries registered where they actually run; times follow the per-region LOCAL anchors

---

## External Integrations

N/A — no third-party API. Gem hooks used: Warden `before_failure`, rolify association callbacks,
devise-api `after_successful_sign_in`, Doorkeeper `after_successful_authorization`.

**Reviewer checks**
- [ ] Gem hook signatures checked against the installed versions (devise 5.0.4, devise-api bd49310, doorkeeper)

---

## Error Mapping and Logging

| Exception | Raised in | Handled by | User sees | Logged / alerted |
|---|---|---|---|---|
| `Redis::BaseError`, `RedisClient::Error` | enqueue | `record` rescue → inline `write!` | nothing | warn `[security_event] enqueue_failed kind=… ` |
| any `StandardError` in inline write | `write!` | `record` rescue | nothing | warn JSON line with kind, user_id, entity_id, ip, occurred_at; `ExceptionNotifier.notify_exception` once per 10 min (Rails.cache key) |
| `KeyError` unknown kind | `Catalogue.fetch` | `record` rescue | nothing | warn `[security_event] unknown_kind` |
| `ActiveRecord::RecordNotUnique` | job insert | job | — | none (retry) |
| `ActiveRecord::ReadOnlyRecord` | any update | caller | — | test X4 |
| Notifier/mail errors | alert | Sidekiq retry | — | ExceptionNotifier on dead |

**Reviewer checks**
- [ ] The one deliberate swallow (`record`) logs every swallowed error
- [ ] Log lines carry kind, user id, entity id; never email, token or code

---

## Security Review

| Concern | Decision |
|---|---|
| Authorization | `SecurityEventPolicy#index?` = super \|\| support \|\| company_admin; `Scope` per design ⑥ |
| Tenant isolation | `entity_id` filter in Scope only; not ransackable; download job re-applies Scope with a reloaded user |
| Secrets | no tokens/codes/links stored; details allowlist; digest is HMAC with a per-region key; jobs don't log args |
| Input / output sanitisation | ERB escaping; details rendered via `h`; xlsx cells starting `= + - @` prefixed `'` |
| Mass assignment | no write actions |

**Reviewer checks**
- [ ] A user from another entity cannot reach any event through the list, the xlsx, a job or MCP (no MCP tool)

---

## Configuration and Rollout

| Item | Value / location |
|---|---|
| Credentials / env vars | none new; `CURRENT_SITE` (exists) for `region` |
| Feature flag | none — a security control for all firms (design pattern 13) |
| Cron / schedules | `config/initializers/sidekiq.rb` (weekly pack, purge) |
| Deploy order | migration → Phase 1 code (recording) → Phase 2 hooks → Phase 3 screen, alerts, cron |
| Rollback | revert code; table can stay (no readers); `drop_table` on full rollback loses evidence — avoid |

**Reviewer checks**
- [ ] Safe to deploy with the table empty and no screen; safe to roll back code with the table present

---

## Test Plumbing

| Feature file | Stubs / fixtures | Factories | New step definitions |
|---|---|---|---|
| `security_events_sign_in.feature` | ActiveJob inline; Twilio Verify stub (existing 2FA steps); a step that makes `perform_later` raise | `:user`, `:entity` (existing) | `Then a security event "<kind>" is recorded for "<name>"` · `Then no security event "<kind>" is recorded` · `Given the security event queue is down` |
| `security_events_access.feature` | same | `:support_client_mapping`, `:api_token` | `When "<admin>" grants "<role>" to "<user>"` (reuse user-edit steps where they exist) |
| `security_events_screen.feature` | `ActionMailer` deliveries; travel_to 09 Nov 2026 | `:security_event` (new factory) | `Given security events:` table step |
| `security_events_tenant_isolation.feature` | — | as above | reuse `tenant_isolation_batch1` request steps |

- Grep step text before adding (dry-run hides ambiguous steps).

---

## Pattern Conformance

| Class | Pattern | Pack | Public interface | Modelled on |
|---|---|---|---|---|
| `SecurityEvents` | service (module fn) | core/security_events | `.record` | `CrossSiteMetrics` (never-fail) |
| `SecurityEvents::Catalogue` | constant table | same | `.fetch`, `.alert?` | `User::NOTIFICATION_TAGS` style constants |
| `SecurityEvents::Context` | service | same | `.current`, `.identifier_digest` | `ErrorReportContext` |
| `SecurityEvent` | model | same | scopes, `.write!` | `Audit` |
| `SecurityEventWriteJob` | job | same | `perform(attrs)` | `ApplicationJob` subclasses |
| `SecurityEventsController` | controller | same | `index` | `AuditsController` |
| `SecurityEventPolicy` | policy | same | `index?`, `Scope` | `AuditPolicy`, `BaseScope#resolve_admin` |
| `SecurityEventDownloadJob` | job | same | `perform(params, user_id:)` | `AuditDownloadJob` |
| `SecurityEventAlert` | service | same | `.deliver` | `FinancialStatementUnlockGuard` |
| `SecurityEventNotifier` | notifier | same | Noticed | `FinancialStatementNotifier` |
| `SecurityEventsMailer` | mailer | same | 3 methods | `FinancialStatementsMailer` |
| `SecurityEventWeeklyPackJob`, `SecurityEventPurgeJob` | jobs | same | `perform` | `ReportDraftCleanupJob` |

## Security Detail

| Action / job / call | Policy method | Loaded through | Permitted params | Tenant checks | Security scenario |
|---|---|---|---|---|---|
| `SecurityEventsController#index` html | `index?` | `policy_scope(SecurityEvent)` | `q` (allowlist), `page` | Scope by entity | X6, X7, X8, E45 |
| `SecurityEventsController#index` xlsx | `index?` | job re-scopes | `q` | Scope re-applied with reloaded user | X9 |
| `SecurityEventWriteJob` | n/a (system write) | attrs | — | `entity_id` from the account's/actor's firm on the request thread | E33, X5 |
| `SecurityEventWeeklyPackJob` | n/a | all rows of region | — | recipient = region's `SECURITY_EVENTS_WEEKLY_TO` (support@caphive.com); region's events only | H34 |
| Write routes | none exist | — | — | — | X11 |

## Project Rules Checklist

| Rule | Applies? | How it is met |
|---|---|---|
| No `blank?`/`present?` on relations; use `exists?`/`none?` | Applies | recipients use `.any?` only after load for delivery; no `present?` on scopes |
| Dedup in SQL, batch bulk operations | Applies | purge `in_batches`; downloads `find_each` |
| Select only needed columns for `account_entries`; no speculative `includes` | N/A | no `account_entries` |
| Screen dates via `l(...)`; emails `Mon dd, yyyy`; no human `strftime` | Applies | `l(event.occurred_at)` on screen; mailer views `l(...)` |
| Date inputs `f.date_field` / `date_field_tag` | Applies | filter dates via `date_field_tag` |
| Every query entity-scoped; Pundit on every action | Applies | Scope; one action |
| MCP via ontology YAML | N/A | no MCP surface |
| Cucumber only; `TEST_ENV_NUMBER=$RANDOM` | Applies | four features |
| rubocop clean incl. `IRM/RelationBlankPresent` | Applies | |
| No query in a row loop; PROSOPITE clean | Applies | preload + entity-id memo |
| Screens copy the reference screen | Applies | `capital_calls/_index`; mock in `mocks/` |

---

## Sign-off

| Reviewer | Date | Decision | Notes |
|---|---|---|---|
| | | | |
