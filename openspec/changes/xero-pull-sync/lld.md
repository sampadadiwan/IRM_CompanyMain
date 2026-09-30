# Xero Pull Sync (Phase I) — Low-Level Design

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

- `account_entries.external_sync_id` is added to a very large, partitioned table. The column
  is added with `ALGORITHM=INSTANT` and the index is built online, and both are MySQL-only
  guarded because tests run on SQLite. See [Schema Detail](#schema-detail).
- The fund pass diffs against **synced rows only** (`external_sync_id IS NOT NULL`) and
  writes one transaction per account, not one per period. A partial failure is therefore
  safe and fixes itself on the next pass. See
  [Transactions, Locking and Concurrency](#transactions-locking-and-concurrency).
- Xero rotates the refresh token on every refresh, so refresh runs under `with_lock` on the
  connection row. See [External Integrations](#external-integrations).
- Dismissing a held change is remembered per Xero figure through the unique key
  `(connection, mapping, reporting_date, xero_amount_cents)`. See
  [Schema Detail](#schema-detail).
- `KpiWorkbookReader#save_kpi_entry` becomes a thin call to `KpiValueStager#stage`, and the
  workbook import must behave exactly as before. See [Method Contracts](#method-contracts).
- `enable_xero` is appended as the **last** `permissions` flag, because flag_shih_tzu bits
  are positional. See [Configuration and Rollout](#configuration-and-rollout).

---

## File Map

| Boundary | File | New / Modified | Responsibility |
|---|---|---|---|
| Xero pack | `app/packs/core/xero/models/xero_connection.rb` | New | Polymorphic owner, encrypted tokens, status, claim, `periods_to_sync` |
| Xero pack | `app/packs/core/xero/models/xero_account_mapping.rb` | New | Per-connection account → entry type/name/negate |
| Xero pack | `app/packs/core/xero/models/xero_held_change.rb` | New | Pending/applied/dismissed; `apply!`, `dismiss!` |
| Xero pack | `app/packs/core/xero/services/xero_client.rb` | New | OAuth + Accounting API calls, error classification |
| Xero pack | `app/packs/core/xero/services/xero_report_parser.rb` | New | Report JSON → account rows / labelled rows |
| Xero pack | `app/packs/core/xero/services/xero_fund_ledger_sync.rb` | New | One fund period pass |
| Xero pack | `app/packs/core/xero/services/xero_portco_kpi_sync.rb` | New | One portco period pass |
| Scheduling | `app/packs/core/xero/jobs/xero_sync_job.rb` | New | Claim, run, classify failures, transitions |
| Scheduling | `app/packs/core/xero/jobs/xero_sync_all_job.rb` | New | Nightly fan-out |
| UI | `app/packs/core/xero/controllers/xero_oauth_controller.rb` | New | connect / callback / choose_tenant |
| UI | `app/packs/core/xero/controllers/xero_connections_controller.rb` | New | show / update / destroy / sync / send_connect_link |
| UI | `app/packs/core/xero/controllers/xero_account_mappings_controller.rb` | New | update |
| UI | `app/packs/core/xero/controllers/xero_held_changes_controller.rb` | New | apply / dismiss |
| UI | `app/packs/core/xero/policies/xero_connection_policy.rb` (+ mapping, held-change policies delegating to it) | New | Access rules from design Policy |
| UI | `app/packs/core/xero/views/xero_connections/*`, `xero_oauth/choose_tenant.html.erb`, `xero_account_mappings/_row`, `xero_held_changes/_row` | New | Tab/panel, tenant picker, rows |
| Notifications | `app/packs/core/xero/notifiers/xero_connection_notifier.rb`, `xero_review_needed_notifier.rb` (+ mailer views) | New | `BaseNotifier` subclasses |
| Notifications | `app/packs/core/xero/mailers/xero_connect_link_mailer.rb` | New | "Connect your Xero" email to portco users |
| Pack | `app/packs/core/xero/package.yml` | New | Depends on core, funds, startups/kpis |
| Existing | `app/packs/funds/capital_commitments/models/account_entry.rb` | Modified | `xero_synced` scope, `external_sync_id` uniqueness |
| Existing | `app/packs/funds/funds/models/allocation_run.rb` | Modified | `scope :covering` |
| Existing | `app/packs/funds/funds/models/fund.rb`, `app/packs/core/investors/models/investor.rb` | Modified | `has_one :xero_connection, as: :owner` |
| Existing | `app/packs/core/entities/models/concerns/entity_enabled.rb` | Modified | append `enable_xero` |
| Existing | `app/packs/startups/kpis/services/kpi_value_stager.rb` | New | Extracted staging |
| Existing | `app/packs/startups/kpis/services/kpi_workbook_reader.rb` | Modified | `save_kpi_entry` delegates; `normalize_kpi_name` → `KpiValueStager.normalize_name` |
| Existing | `app/packs/startups/kpis/jobs/generate_periodic_kpi_reports_job.rb` | Modified | Skip reminder for Xero-filled reports |
| Existing | `app/packs/funds/funds/views/funds/_show.html.erb` | Modified | Xero tab (gated) |
| Existing | Portco KPIs tab partial and portco pending-report view (under `app/packs/startups/kpis/views/kpi_reports/`) | Modified | Xero panel / "Connect Xero instead of uploading" |
| Config | `config/routes.rb` (or pack routes) | Modified | Routes in design |
| Config | `config/initializers/sidekiq.rb` | Modified | `XeroSyncAllJob` cron |
| Config | `config/initializers/filter_parameter_logging.rb` | Modified | filter `code`, `access_token`, `refresh_token` |
| DB | `db/migrate/*_create_xero_tables.rb`, `db/migrate/*_add_external_sync_id_to_account_entries.rb` | New | Schema |
| DB | `db/schema.rb`, `db/schema_test.rb` | Modified | Both updated |

**Reviewer checks**
- [ ] Every class in the design's class diagram has a file here, and nothing here is missing from it
- [ ] Files follow the pack layout (`app/packs/<domain>/<sub_domain>/...`) and Packwerk boundaries
- [ ] `core/xero` depending on `funds` and `startups/kpis` doesn't create a Packwerk cycle; if it does, declare the dependency the way other core packs that touch funds do

---

## Schema Detail

**`xero_connections`** (new)

| Column | Type | Limit | Null | Default | Index / FK | Notes |
|---|---|---|---|---|---|---|
| `entity_id` | bigint | | no | | FK, idx | owner's entity |
| `owner_type` | string | 20 | no | | unique `[owner_type, owner_id, deleted_at]` | `Fund` / `Investor` |
| `owner_id` | bigint | | no | | ↑ | |
| `xero_tenant_id` | string | 36 | no | | idx `[entity_id, xero_tenant_id, owner_type, deleted_at]` | unique for Fund only, enforced in the model (portcos may repeat across entities) |
| `xero_tenant_name` | string | 255 | no | | | |
| `base_currency` | string | 3 | no | | | from Organisation |
| `access_token` | text | | yes | | | `encrypts` |
| `refresh_token` | text | | yes | | | `encrypts` |
| `token_expires_at` | datetime | | yes | | | |
| `status` | string | 20 | no | `"connected"` | idx `[status]` | connected / needs_reconnect / sync_failing / disconnected |
| `period_frequency` | string | 10 | yes | `"Quarterly"` | | fund only; Monthly / Quarterly |
| `last_synced_at` | datetime | | yes | | | |
| `first_failed_at` | datetime | | yes | | | cleared on success |
| `last_error` | text | | yes | | | truncated 1,000 chars, no tokens |
| `sync_started_at` | datetime | | yes | | | claim; stale after 30 min |
| `unmatched_labels` | json | | yes | | | portco only, array of strings |
| `connected_by_user_id` | bigint | | yes | | FK users | |
| `deleted_at` | datetime | | yes | | | soft delete (`acts_as_paranoid` as elsewhere) |

**`xero_account_mappings`** (new)

| Column | Type | Limit | Null | Default | Index / FK | Notes |
|---|---|---|---|---|---|---|
| `entity_id` | bigint | | no | | FK | |
| `xero_connection_id` | bigint | | no | | FK; unique `[xero_connection_id, xero_account_id]` | |
| `xero_account_id` | string | 36 | no | | ↑ | GUID |
| `xero_account_code` | string | 20 | yes | | | Xero `Code` can be blank |
| `xero_account_name` | string | 150 | no | | | refreshed each pass |
| `report_section` | string | 20 | no | | | profit_and_loss / balance_sheet, from Account `Class` (REVENUE/EXPENSE → P&L; ASSET/LIABILITY/EQUITY → BS) |
| `status` | string | 10 | no | `"unmapped"` | | |
| `entry_type` | string | 60 | yes | | | required when mapped; matches `AccountEntry` limit |
| `entry_name` | string | 125 | yes | | | required when mapped; matches `AccountEntry#name` limit |
| `negate` | boolean | | no | false | | |

**`xero_held_changes`** (new)

| Column | Type | Limit | Null | Default | Index / FK | Notes |
|---|---|---|---|---|---|---|
| `entity_id` | bigint | | no | | FK | |
| `xero_connection_id` | bigint | | no | | FK | |
| `xero_account_mapping_id` | bigint | | no | | FK; unique `[xero_connection_id, xero_account_mapping_id, reporting_date, xero_amount_cents]` | |
| `account_entry_id` | bigint | | yes | | idx, **no FK** | composite PK and partitioned target |
| `allocation_run_id` | bigint | | no | | FK | the run that caused the hold (first covering) |
| `reporting_date` | date | | no | | | |
| `current_amount_cents` | decimal(30,8) | | yes | | | NULL = no entry today |
| `xero_amount_cents` | decimal(30,8) | | no | | | after negate; 0 = remove |
| `status` | string | 10 | no | `"pending"` | idx `[xero_connection_id, status]` | |
| `resolved_by_user_id` | bigint | | yes | | FK users | |
| `resolved_at` | datetime | | yes | | | |

**`account_entries`** (existing)

| Column | Type | Limit | Null | Default | Index / FK | Notes |
|---|---|---|---|---|---|---|
| `external_sync_id` | string | 36 | yes | | idx `idx_ae_fund_date_extsync [fund_id, reporting_date, external_sync_id]` | Xero AccountID |

**Migration safety:**
- `account_entries` is the largest table and is partitioned by `reporting_date`
  (`partitions:ensure_account_entries`). Add the column with `ALGORITHM=INSTANT` (a nullable
  column at the end is instant on MySQL 8.0.29+, partitioned tables included). Build the
  index in a **separate** migration with `ALGORITHM=INPLACE, LOCK=NONE`, run off-hours. Both
  statements are behind an `adapter_name =~ /mysql/i` guard, with a plain
  `add_column`/`add_index` for SQLite.
- Not a unique index: the uniqueness is enforced by the model validation plus the sync's
  lookup. A unique index on a partitioned table must include the partition key, which this
  one does, but a unique constraint would also collide with soft-deleted rows. The model
  validation scopes `deleted_at`.
- New tables are small; there's no backfill; every migration is reversible.
- Update `db/schema.rb` and `db/schema_test.rb` by hand, following the local-migrate
  drift routine, then run `db:clean_schema`.

**Reviewer checks**
- [ ] Every foreign key has an index, and every uniqueness rule is enforced by a unique index (except the two model-enforced ones stated above)
- [ ] Column limits match validation limits (`entry_type` 60, `entry_name` 125)
- [ ] Migration is reversible and safe on the production table size; the index migration is separate from the column migration
- [ ] `EXPLAIN` of the fund-pass lookup on a prod-size copy (port 33066) shows `idx_ae_fund_date_extsync` and a single partition

---

## Method Contracts

**`XeroClient`** (Service)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `.authorize_url(state:)` | String | URL | — | — | Yes |
| `.exchange_code(code)` | String | `{access_token:, refresh_token:, expires_at:}` | `AuthError` | — | No (codes are single-use) |
| `.new(connection)` | `XeroConnection` or unsaved token hash | client | — | — | — |
| `#tenants` | — | `[{tenant_id:, name:}]` (type ORGANISATION only) | `AuthError`, `TransientError` | may refresh | Yes |
| `#organisation` | — | `{name:, base_currency:}` | as above | may refresh | Yes |
| `#accounts` | — | `[{account_id:, code:, name:, klass:, status:}]` (ARCHIVED included) | as above | may refresh | Yes |
| `#profit_and_loss(from:, to:)` | Date, Date | report JSON | as above + `RateLimited` | may refresh | Yes |
| `#balance_sheet(date:)` | Date | report JSON | as above + `RateLimited` | may refresh | Yes |
| `#revoke!` | — | true | swallows errors (logged) | revokes refresh token at Xero | Yes |

**`XeroReportParser`** (Service, pure)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `.account_rows(report, section:)` | Hash, Symbol | `{account_id => BigDecimal}` from rows whose first cell's `Attributes` has `account` | `ParseError` on unexpected shape | — | Yes |
| `.labelled_rows(report)` | Hash | `{label => BigDecimal}` for `Row` and `SummaryRow` first-cell labels; first occurrence wins | `ParseError` | — | Yes |

**`XeroFundLedgerSync`** (Service)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `.call(connection, period_end)` | `XeroConnection` (Fund owner), Date | `Result(created:, updated:, removed:, held:, new_unmapped:)` | client errors propagate | upserts mappings, writes `account_entries`, creates held changes | Yes: a second run with unchanged Xero data writes nothing |

**`XeroPortcoKpiSync`** (Service)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `.call(connection, period_end)` | `XeroConnection` (Investor owner), Date | `Result(staged:, unchanged:, unmatched:)` | client errors propagate | may create KpiReport shell, stage KPIs, mark report submitted, set `unmatched_labels` | Yes |

**`KpiValueStager`** (Service)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `#initialize(portfolio_company)` | Investor | | | builds `KpiFxConverter` | — |
| `#stage(kpi_report:, mapping:, value:, source:, notes:)` | KpiReport, InvestorKpiMapping, BigDecimal, String, String | `:staged` / `:unchanged` / `:staged_without_fx` | — | upsert unapproved `Kpi` (scoped by `investor_kpi_mapping_id`) | Yes |
| `.normalize_name(str)` | String | String | | | Yes |

**`XeroConnection`** (Model)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `#claim!` | — | Boolean | — | atomic `UPDATE … SET sync_started_at = now WHERE id = ? AND (sync_started_at IS NULL OR sync_started_at < now - 30 min)` | Yes |
| `#release!` | — | — | — | `sync_started_at = NULL` | Yes |
| `#record_success!` | — | — | — | `last_synced_at`, clear `first_failed_at`/`last_error`, `sync_failing → connected` | Yes |
| `#record_failure!(error)` | Exception | `:became_failing` or nil | — | `first_failed_at ||= now`, `last_error`; flips to `sync_failing` once 24 h have passed | Yes |
| `#mark_needs_reconnect!(error)` | Exception | Boolean (true on transition) | — | status | Yes |
| `#periods_to_sync(today)` | Date | `[Date, Date]` | — | — | Yes |
| `#fund_ledger?` | — | Boolean | | | |

**`XeroHeldChange`** (Model)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `#apply!(user)` | User | self | `StaleEntry` if the entry's amount ≠ `current_amount_cents` (or the entry exists or is missing unexpectedly) | writes `account_entries`, status applied | No (second call raises `InvalidTransition`) |
| `#dismiss!(user)` | User | self | `InvalidTransition` unless pending | status dismissed | No |

**`AllocationRun.covering(fund, date)`**: `where(fund_id: fund.id).where("start_date <= ? AND end_date >= ?", date, date)`.

**Reviewer checks**
- [ ] Every raised error is handled by a caller or listed in Error Mapping
- [ ] Anything a retry can repeat is idempotent (both sync services, `claim!`, `record_*`)
- [ ] The existing KPI features pass unchanged after the `KpiValueStager` extraction (the notes string for workbook imports is unchanged)

---

## Controllers, Params and Responses

| Action | Permitted params | Policy method | Success response | Failure response |
|---|---|---|---|---|
| `XeroOauthController#connect` | `owner` (signed GlobalID) | `XeroConnectionPolicy#connect?` on owner | 302 to Xero | 403 / redirect with flash |
| `#callback` | `code`, `state`, `error` | re-verified from state | tenant picker, or 302 to owner | `error=access_denied` → 302 + "Xero connection was cancelled."; bad state → 403 |
| `#choose_tenant` | `tenant_id` (in the signed session payload's list) | as connect | 302 owner page, "Connected" | 302 + acceptance error flash |
| `XeroConnectionsController#show` | `id` | `show?` | turbo frame | 403 |
| `#update` | `xero_connection: [:period_frequency]` | `update?` (fund only) | turbo_stream | 422 |
| `#sync` | `period_end` (ISO) | `sync?` | turbo_stream "Sync queued" | 422 "Pick a past quarter-end / month-end date" |
| `#destroy` | `id` | `destroy?` | 302 | 403 |
| `#send_connect_link` | `investor_id` | `connect?` on portco | turbo_stream flash "Link sent to …" | 422 "Acme Robotics has no users to send to" |
| `XeroAccountMappingsController#update` | `xero_account_mapping: [:status, :entry_type, :entry_name, :negate]` | `update?` → connection `update?` | turbo_stream row | 422 row with errors |
| `XeroHeldChangesController#apply` / `#dismiss` | `id` | connection `update?` | turbo_stream remove + flash | `StaleEntry` → flash (see Error Mapping) |

Between `callback` and `choose_tenant`, tokens are held in the **encrypted Rails session**
under `xero_pending` (tokens, tenant list, owner sgid, 10-minute expiry). They are never put
in a hidden form field.

**Reviewer checks**
- [ ] No action without `authorize` / `policy_scope`
- [ ] Permitted params can't set `entity_id`, `owner_*`, `xero_tenant_id`, tokens or status
- [ ] `tenant_id` in `choose_tenant` is checked against the session's tenant list

---

## Queries and Indexes

| Where | Query shape | Index used | Rows expected | Preload / batching |
|---|---|---|---|---|
| `XeroFundLedgerSync` | `AccountEntry.xero_synced.where(fund_id:, reporting_date:).select(:id, :reporting_date, :external_sync_id, :amount_cents, :cumulative, :entity_id, :fund_id)` | `idx_ae_fund_date_extsync` | ≤ ~60 | indexed by `external_sync_id` in Ruby |
| `XeroFundLedgerSync` | `connection.xero_account_mappings` | `[xero_connection_id, xero_account_id]` | ≤ ~300 | `index_by(&:xero_account_id)` |
| `XeroFundLedgerSync` | `AllocationRun.covering(fund, date).order(:id).first` | `allocation_runs[fund_id]` | tiny | — |
| `XeroFundLedgerSync` | `connection.xero_held_changes.where(reporting_date:)` | `[xero_connection_id, …]` | tiny | loaded once |
| `XeroPortcoKpiSync` | KpiReport by `(entity_id, portfolio_company_id, as_of, period, tag_list "Actual")` | existing | 1 | — |
| `XeroPortcoKpiSync` | `InvestorKpiMapping.where(entity_id:, investor_id:)` | existing | ≤ ~100 | grouped by normalized name |
| `KpiValueStager#stage` | unapproved + approved Kpi lookups per mapping | existing | ≤ 2 per call | as today |
| `XeroSyncAllJob` | `XeroConnection.where(status: %w[connected sync_failing]).joins(:entity).merge(Entity.where_permissions(:enable_xero)).select(:id)` then `find_each` | `[status]` | ≤ hundreds | `find_each` |
| Tab: held changes | `connection.xero_held_changes.where(status: "pending").order(:reporting_date)` | `[xero_connection_id, status]` | small | `includes(:xero_account_mapping)` |

**Reviewer checks**
- [ ] Every query is scoped by `entity_id`, or reached through an entity-scoped connection
- [ ] No N+1 on list pages. No unbounded loads (use `find_each` / `in_batches`)
- [ ] No `account_entries` read without `fund_id + reporting_date` and a narrow `select`

---

## Transactions, Locking and Concurrency

| Operation | Transaction scope | Lock | Race it prevents | Idempotency key |
|---|---|---|---|---|
| Pass per connection | none (claim only) | `claim!` atomic UPDATE | cron + Sync now running together | `sync_started_at` |
| One account write | `AccountEntry` create/update/destroy | none (the claim already serialises) | — | `(fund_id, reporting_date, external_sync_id)` |
| Hold | supersede older pending (→ dismissed) + insert pending | none | duplicate holds | unique `(connection, mapping, date, xero_amount_cents)`; `RecordNotUnique` → no-op |
| `XeroHeldChange#apply!` | entry write + status | `lock!` on the held change | double click / two admins | status must be pending |
| Token refresh | update tokens | `connection.with_lock` then re-check `token_expires_at` | two refreshes rotating the refresh token | — |
| Connect/reconnect | create/update connection | none | two tabs connecting the same owner | unique `[owner_type, owner_id, deleted_at]` → "Already connected" flash |

A pass that runs while an admin applies a held change: `apply!` runs outside the claim.
If the pass has already updated the same entry, `apply!` finds `current_amount_cents` stale
and raises `StaleEntry`. That is safe.

**Reviewer checks**
- [ ] No external HTTP call or email inside a transaction (the Xero fetch happens before any writes; notifications fire after the loop)
- [ ] Lock order is consistent: connection before held change, never the reverse

---

## Background Jobs

| Job | Queue | Trigger | Retry / backoff | Discard on | Concurrency guard | Timeout |
|---|---|---|---|---|---|---|
| `XeroSyncAllJob` | `:low` | sidekiq-cron `0 2 * * *` (env TZ) | 0 | — | — | — |
| `XeroSyncJob(connection_id, period_end = nil)` | `:low` | fan-out (`set(wait: (id % 60).minutes)`), Sync now, post-connect | `retry_on RateLimited, wait: retry_after`, `retry_on TransientError, wait: :polynomially_longer, attempts: 5` | `ActiveRecord::RecordNotFound`, `AuthError` (handled, not retried), connection not syncable | `claim!`; exit if not claimed | HTTP 30 s per call |

`period_end = nil` → `periods_to_sync(Date.current)`. After retries run out,
`record_failure!` has already run on every attempt, so the 24-hour rule still applies across
nights.

**Reviewer checks**
- [ ] A job that runs twice, or out of order, is harmless (claim + idempotent passes)
- [ ] The cron entry is registered in `config/initializers/sidekiq.rb` next to the existing `Sidekiq::Cron::Job.create` calls, not in `schedule.rb`
- [ ] The claim is released in `ensure`, and a stale claim (> 30 min) is reclaimable

---

## External Integrations

| Call | Method + path | Auth | Timeouts | Rate limit handling | Error → exception |
|---|---|---|---|---|---|
| Authorize | `GET https://login.xero.com/identity/connect/authorize` | client id, `state`, scopes | — | — | `error=access_denied` → cancelled |
| Token | `POST https://identity.xero.com/connect/token` | Basic client id:secret | 5 s / 15 s | — | 400 `invalid_grant` → `AuthError` |
| Revoke | `POST https://identity.xero.com/connect/revocation` | Basic | 5 s / 15 s | — | logged only |
| Tenants | `GET https://api.xero.com/connections` | Bearer | 5 s / 30 s | 429 → `RateLimited` | 401 → `AuthError` |
| Organisation | `GET /api.xro/2.0/Organisation` | Bearer + `xero-tenant-id` | 5 s / 30 s | 429 `Retry-After` | 401/403 → `AuthError`; 5xx/timeout → `TransientError` |
| Accounts | `GET /api.xro/2.0/Accounts` | as above | | | |
| P&L | `GET /api.xro/2.0/Reports/ProfitAndLoss?fromDate=&toDate=` | as above | | | |
| Balance sheet | `GET /api.xro/2.0/Reports/BalanceSheet?date=` | as above | | | |

- HTTP via the Faraday setup the app already uses (or `Net::HTTP` if none), JSON
  `Accept: application/json`.
- Access tokens last 30 minutes. Refresh when fewer than 120 s remain. Store the new refresh
  token in the same locked update.
- Scopes: `offline_access` plus read-only report and settings scopes. The exact names are
  confirmed at app registration (design open question 1).
- Amounts: parse `Value` strings as `BigDecimal`, multiply by 100 for `_cents`, and treat
  blank as 0.

**Reviewer checks**
- [ ] Secrets never logged; `Authorization` header and token bodies excluded from request logging
- [ ] Every non-2xx status maps to a named exception (`AuthError`, `RateLimited`, `TransientError`, `ParseError`)

---

## Error Mapping and Logging

| Exception | Raised in | Handled by | User sees | Logged / alerted |
|---|---|---|---|---|
| `XeroClient::AuthError` | client | `XeroSyncJob` → `mark_needs_reconnect!` | "Needs reconnecting" + notification | warn `xero.auth_failed connection_id entity_id tenant_id` |
| `XeroClient::RateLimited` | client | Sidekiq `retry_on` | nothing | info |
| `XeroClient::TransientError` | client | `record_failure!` + `retry_on` | "Sync failing" after 24 h + notification | warn per attempt |
| `XeroReportParser::ParseError` | parser | `XeroSyncJob` treats it as transient | as transient | error + exception notifier (Xero format drift) |
| `XeroHeldChange::StaleEntry` | `apply!` | controller | flash "This entry changed since the review item was raised. Run Sync now for this period." | info |
| `ActiveRecord::RecordInvalid` on account entry | ledger sync | ledger sync: skip that account, count in the result, continue | nothing directly | error with mapping id + reporting_date; exception notifier |
| Anything else | job | Sidekiq default | nothing | exception notifier; claim released |

**Reviewer checks**
- [ ] No bare `rescue => e` that swallows errors silently
- [ ] Log lines carry `entity_id`, `connection_id`, `xero_tenant_id`, `period_end`

---

## Security Review

| Concern | Decision |
|---|---|
| Authorization | `XeroConnectionPolicy` (`connect? show? update? sync? destroy?`) per design Policy flowchart; mapping and held-change policies delegate to the connection |
| Tenant isolation | `entity_id` on every Xero table; `Scope` filters by `user.entity_id`; the portco founder path checks `owner.investor_entity_id == user.entity_id` and never exposes other entities' connections |
| Secrets | `encrypts :access_token, :refresh_token`; never rendered; filtered from logs; client secret from credentials |
| OAuth CSRF | `state` = `MessageVerifier` payload (owner sgid, user id, nonce, 10-minute expiry) plus a nonce stored in the session |
| Input / output sanitisation | Xero names and labels rendered escaped; `last_error` never includes response bodies with tokens |
| Mass assignment | See Controllers table; no ownership fields permitted |

**Reviewer checks**
- [ ] A user from another entity cannot reach any record through any route, job or MCP tool (no MCP surface is added)
- [ ] A founder of Acme cannot connect, or see, any other portfolio company or fund

---

## Configuration and Rollout

| Item | Value / location |
|---|---|
| Credentials | `Rails.application.credentials.xero: { client_id, client_secret, redirect_uri }` per environment; **separate Xero apps for production.in and production.us** |
| Feature flag | `Entity#permissions.enable_xero`, appended last in `EntityEnabled` |
| Cron | `XeroSyncAllJob`, `0 2 * * *`, in `config/initializers/sidekiq.rb` (non-local envs only, matching existing entries) |
| Deploy order | 1) column migration (instant) → 2) index migration (off-hours) → 3) code → 4) credentials → 5) enable flag for pilot entities |
| Rollback | Turn off `enable_xero` (hides the UI, and the cron skips the entity). Synced entries stay as ordinary fund-level entries. Dropping the tables and column is safe; there are no dependent rows elsewhere |
| App certification | Uncertified cap is 25 orgs per app, so pilot rollout only until Xero certification completes |

**Reviewer checks**
- [ ] Safe to deploy with the feature unused (flag off, cron runs no passes), and safe to roll back

---

## Test Plumbing

| Feature file | Stubs / fixtures | Factories | New step definitions |
|---|---|---|---|
| `features/core/xero/connections.feature` | `features/support/xero_stubs.rb` (WebMock; `@sync-http`): token, connections, Organisation (AUD / USD variants), revocation; 401 and 503 variants | `:xero_connection` (fund / portco traits) | `Given the Xero org "…" in "AUD"`, `When I complete Xero consent choosing "…"`, `Then the Xero status is "…"`, `Given Xero rejects the token` |
| `features/core/xero/fund_ledger_sync.feature` | Accounts, P&L, BalanceSheet JSON under `features/fixtures/xero/` built from a table step | `:xero_account_mapping`, `:xero_held_change`; existing `:allocation_run`, `:account_entry` | `Given Xero reports for "30/09/2026":` (table), `When the Xero sync runs for "…"`, `Then the fund has a synced entry …` |
| `features/core/xero/portco_kpi_sync.feature` | P&L / BalanceSheet with labelled rows | existing `:investor_kpi_mapping`, `:kpi_report` | `Given Xero report labels for "Acme Robotics" …`, reuses KPI approval steps |
| Existing KPI features | — | — | none (regression for the stager extraction) |

Jobs run inline, as other features do (`active_job_inline_patch.rb`). The OAuth callback is
driven directly with a signed state produced by a helper, so no real browser redirect to
Xero is needed.

---

## Project Rules Checklist

| Rule | Applies? | How it is met |
|---|---|---|
| No `blank?`/`present?` on relations; use `exists?`/`none?` | Applies | Synced-entry and held-change checks use `exists?`, or index loaded arrays |
| Dedup in SQL (`distinct.pluck`), batch bulk operations (`find_each`/`in_batches`) | Applies | `find_each` in the cron fan-out; no bulk destroy (≤ 60 rows, one at a time for callbacks) |
| Select only needed columns when loading many `account_entries`; no speculative `includes` of big associations | Applies | Narrow `select` in the fund pass; no `includes(:account_entries)` |
| Screen dates via `l(...)`; emails render `Mon dd, yyyy` via `EmailDateLocalization`; no human-format `strftime` | Applies | Tab/review rows use `l(date)`; notifier mail views use bare `l(date)`; Xero API dates use ISO `%Y-%m-%d` (machine format) |
| Date inputs use `f.date_field` / `date_field_tag`; JS dates via `locale_date_format.js` | Applies | Sync now period picker uses `date_field_tag` |
| Every query entity-scoped; Pundit `authorize`/`policy_scope` on every action | Applies | See Security Review |
| MCP tool surfaces changed only via the ontology YAML (run the ontology drift feature) | N/A | No MCP tool or ransackable-attribute change; `external_sync_id` is not added to `ransackable_attributes` |
| Cucumber only (no RSpec); `TEST_ENV_NUMBER=$RANDOM` on every run | Applies | Three new features plus the KPI regression |
| `bundle exec rubocop` clean, including the `IRM/RelationBlankPresent` cop | Applies | Run on all new and changed files |

---

## Sign-off

| Reviewer | Date | Decision | Notes |
|---|---|---|---|
| | | | |
