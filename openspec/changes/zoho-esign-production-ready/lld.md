# Zoho eSign, production ready — Low-Level Design

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

- **Access token in `Rails.cache`, keyed by a credentials fingerprint, no row lock** — departs from the
  Xero design's locked DB columns because Zoho doesn't rotate refresh tokens. See
  [Transactions, Locking and Concurrency](#transactions-locking-and-concurrency).
- **New index on `documents.provider_doc_id`** (large table) — every webhook looks documents up by it
  and today it is unindexed. Built online. See [Schema Detail](#schema-detail).
- **Shared webhook refuses unsigned Zoho updates outside development/test** — needs
  `ZOHO_WEBHOOK_SECRET` deployed in the same release. See [Configuration and Rollout](#configuration-and-rollout).
- **Flat constants `ZohoSignClient` / `ZohoSignAccount` / `ZohoSignConnectionSetup`** in
  `core/investor_kycs/services/zoho/` (every pack folder is a Zeitwerk root). See [File Map](#file-map).
- **No `has_one` on `Entity`** — `ZohoSignConnection.find_by(entity_id:)` keeps PR 2 under 20 files.
  See [Method Contracts](#method-contracts).
- **PR file budget** — PR 1: 15, PR 2: 20, PR 3: 19 files. See [File Map](#file-map).

---

## File Map

Boxes refer to [design Part 2](design.md#picture). **PR** = which pull request carries the file.

| PR | Box | File | New / Modified | Responsibility |
|---|---|---|---|---|
| 1 | ④ | `app/packs/core/investor_kycs/services/zoho/zoho_sign_client.rb` | New | Region table, HTTP, token cache, error classes |
| 1 | ②③ | `app/packs/core/investor_kycs/services/zoho/zoho_sign_account.rb` | New | Account value object; `.platform`; `.for_document` / `.for_entity` (platform only in PR 1) |
| 1 | ⑤ | `app/packs/core/investor_kycs/services/zoho/zoho_esigning.rb` | Modified | `validate_signer_count`, failure rescue |
| 1 | ⑤ | `app/packs/core/investor_kycs/models/concerns/zoho_esign_helper.rb` | Modified | Uses client/account; status table; events; extend validation; draft cleanup; `ErrorReport` |
| 1 | ⑤ | `app/packs/core/investor_kycs/models/helper/esign_helper.rb` | Modified | Drop Zoho branch from `update_signature_progress`; pass `ZohoResult` from `extend_expiry` |
| 1 | ⑥ | `app/packs/core/documents/controllers/documents_controller.rb` | Modified | `signature_progress` Zoho branch (verify → enqueue); extend refusal message |
| 1 | ⑥ | `app/packs/core/documents/jobs/zoho_webhook_job.rb` | New | Applies a verified update (platform scope in PR 1) |
| 1 | ⑤ | `app/packs/core/documents/jobs/esign_update_job.rb` | Modified | `retry_on` / `discard_on` Zoho errors |
| 1 | ⑦ | `app/packs/core/documents/models/document.rb` | Modified | Range validations |
| 1 | ⑦ | `app/packs/core/entities/models/entity_setting.rb` | Modified | `ESIGN_CAPABILITIES`, `esign_supports?` |
| 1 | ⑦ | `app/packs/core/documents/policies/document_policy.rb` | Modified | Capability instead of `"Zoho"` |
| 1 | ⑦ | `app/packs/core/documents/views/documents/_form.html.erb` | Modified | Capability check |
| 1 | ⑦ | `app/packs/core/documents/views/documents/show.html.erb` | Modified | Capability check; `l(...)` for the expiry date |
| 1 | ⑦ | `app/packs/core/documents/views/e_signatures/_index.html.erb` | Modified | Allowed-window text with `l(...)` |
| 1 | — | `features/step_definitions/zoho_esign_steps.rb` | Modified | Keep the 8 existing scenarios green against the new client |
| 2 | ① | `db/migrate/20261029120000_create_zoho_sign_connections.rb` | New | Table + `e_signatures.provider_signer_id` + `documents.provider_doc_id` index |
| 2 | ① | `db/schema.rb` | Modified | Dump |
| 2 | ① | `db/schema_test.rb` | Modified | Via `ruby bin/sync_schema_test.rb` |
| 2 | ① | `app/packs/core/documents/models/zoho_sign_connection.rb` | New | Model, `encrypts`, `audited`, status transitions |
| 2 | ① | `app/packs/core/documents/policies/zoho_sign_connection_policy.rb` | New | Delegates to `EntityPolicy#update?` |
| 2 | ① | `app/packs/core/documents/controllers/zoho_sign_connections_controller.rb` | New | Panel actions |
| 2 | ⑥ | `app/packs/core/documents/controllers/zoho_sign_webhooks_controller.rb` | New | Per-company webhook address |
| 2 | ①⑥ | `config/routes/core.rb` | Modified | Nested singular resource under `entities`; webhook route |
| 2 | ① | `app/packs/core/investor_kycs/services/zoho/zoho_sign_connection_setup.rb` | New | connect / reconnect / verify / disconnect |
| 2 | ③ | `app/packs/core/investor_kycs/services/zoho/zoho_sign_account.rb` | Modified | Cutover rule; `ZohoSignConnection#account` |
| 2 | ⑤ | `app/packs/core/investor_kycs/services/zoho/zoho_esigning.rb` | Modified | `check_account` (needs_reauth) |
| 2 | ⑤ | `app/packs/core/investor_kycs/models/concerns/zoho_esign_helper.rb` | Modified | Store/match `provider_signer_id`; forwarded |
| 2 | ⑥ | `app/packs/core/documents/jobs/zoho_webhook_job.rb` | Modified | Company scoping |
| 2 | ⑦ | `app/packs/core/documents/views/zoho_sign_connections/_panel.html.erb` | New | Panel + connect/reconnect form |
| 2 | ⑦ | `app/packs/core/entities/views/entities/show.html.erb` | Modified | Render panel |
| 2 | ⑦ | `app/packs/core/documents/mailers/zoho_sign_connection_notifier.rb` | New | `BaseNotifier` subclass |
| 2 | ⑦ | `app/packs/core/entities/mailers/entity_mailer.rb` | Modified | `zoho_sign_needs_reconnect` |
| 2 | ⑦ | `app/packs/core/entities/views/entity_mailer/zoho_sign_needs_reconnect.html.erb` | New | Email body |
| 2 | ① | `config/initializers/filter_parameter_logging.rb` | Modified | `grant_code` |
| 3 | — | `features/core/zoho_sign_connections.feature` | New | CN rows |
| 3 | — | `features/core/zoho_esign.feature` | Modified | ES rows |
| 3 | — | `features/core/zoho_esign_webhook.feature` | Modified | WH rows |
| 3 | — | `features/step_definitions/zoho_sign_connection_steps.rb` | New | Panel steps |
| 3 | — | `features/step_definitions/zoho_esign_steps.rb` | Modified | WebMock-based steps, no `sleep` |
| 3 | — | `features/support/zoho_sign_stub.rb` | New | WebMock stubs per region |
| 3 | — | `features/support/webmock_toggle.rb` | Modified | `@sync-http or @zoho-http` |
| 3 | — | `spec/factories/zoho_sign_connections.rb` | New | Factory |
| 3 | — | `docs/operations/zoho_sign.md` | New | Runbook (Option A, Option B note, rollout, troubleshooting) |
| 3 | — | `.env.development`, `.env.staging.in` | Modified (2) | Remove `ZOHO_SIGN_URL` / `ZOHO_ACCOUNTS_URL` |
| 3 | — | `openspec/changes/zoho-esign-production-ready/*` (8 files incl. specs and `.openspec.yaml`) | New | Planning artifacts |

Counts: **PR 1 = 15**, **PR 2 = 20**, **PR 3 = 19** (9 test/doc files + 2 env + 8 OpenSpec).

**Reviewer checks**
- [ ] Every class in the [design class diagram](design.md#class-diagram) has a file here, and nothing here is missing from it
- [ ] Files follow the pack layout and the root `package.yml` (`enforce_dependencies: true`) — no new pack
- [ ] No PR exceeds 20 files (recount before opening each PR)

---

## Schema Detail

**`zoho_sign_connections`** (new): one company's own Zoho Sign account.

| Column | Change | Type | Limit | Null | Default | Index / FK | Why it's needed |
|---|---|---|---|---|---|---|---|
| `id` | Added | bigint | — | no | — | PK | — |
| `entity_id` | Added | bigint | — | no | — | unique index, FK `entities` | One connection per company; unique index enforces it and decides double-click races |
| `region` | Added | string | 10 | no | — | — | Key into `ZohoSignClient::REGIONS` (`com.au` is the longest, 6) |
| `client_id` | Added | string | 100 | no | — | — | Zoho client ids are `1000.` + ~30 chars |
| `client_secret` | Added | text | — | no | — | — | `encrypts` ciphertext is longer than the plaintext; text avoids a limit |
| `refresh_token` | Added | text | — | no | — | — | Same (encrypted) |
| `status` | Added | string | 20 | no | `"connected"` | — | `connected` / `needs_reauth`; enumerize |
| `connected_at` | Added | datetime | — | no | — | — | Cutover; set once on create |
| `last_verified_at` | Added | datetime | — | yes | — | — | Panel |
| `last_webhook_at` | Added | datetime | — | yes | — | — | Panel; written with `update_column` (no audit noise) |
| `last_error` | Added | string | 255 | yes | — | — | Truncated Zoho error for the panel |
| `webhook_token` | Added | string | 40 | no | — | unique index | `has_secure_token :webhook_token, length: 32` |
| `webhook_secret` | Added | text | — | no | — | — | Encrypted; `SecureRandom.base58(40)` |
| `webhook_secret_revealed_at` | Added | datetime | — | yes | — | — | Show-once |
| `connected_by_id` | Added | bigint | — | yes | — | index, FK `users` | Who connected; nullable so user deletion doesn't block |
| `created_at`, `updated_at` | Added | datetime | — | no | — | — | Standard |

**`e_signatures`** (existing): stores Zoho's per-signer id.

| Column | Change | Type | Limit | Null | Default | Index / FK | Why it's needed |
|---|---|---|---|---|---|---|---|
| `provider_signer_id` | Added | string | 40 | yes | — | none | Zoho `action_id` (numeric string); looked up within one document's signers (≤ 25 rows), so no index |

**`documents`** (existing, large): webhook lookup.

| Column | Change | Type | Limit | Null | Default | Index / FK | Why it's needed |
|---|---|---|---|---|---|---|---|
| `provider_doc_id` | New index | — | — | — | — | `index_documents_on_provider_doc_id` | `ZohoWebhookJob` (and the existing Digio/Docusign webhook) look documents up by it; currently a full scan |

**Migration safety:** one migration. `create_table` and the `e_signatures` column are cheap. The
`documents` index is built online (MySQL InnoDB `ALGORITHM=INPLACE, LOCK=NONE`); confirm the adapter
emits it (`algorithm: :inplace`) or use the explicit DDL. Reversible (`change`). No backfill:
`provider_signer_id` stays NULL for old signers (email fallback). `schema.rb` dumped, `schema_test.rb`
synced with `ruby bin/sync_schema_test.rb` then `RAILS_ENV=test bin/rails db:test:load_schema`.

**Reviewer checks**
- [ ] Every new or changed column and index has a "why", and none is unjustified
- [ ] `entity_id` and `webhook_token` have unique indexes; `connected_by_id` has an index
- [ ] Column limits match validations (`region` inclusion, `client_id` length ≤ 100, `last_error` truncated to 255)
- [ ] The `documents` index is built online; reversible
- [ ] `schema_test.rb` was synced, not regenerated by `db:migrate` in test

---

## Method Contracts

**`ZohoSignClient`** (Service)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `.exchange_grant_code(region:, client_id:, client_secret:, code:)` | strings | `refresh_token` (String) | `AuthError(reason)` with `reason` ∈ `:invalid_code`, `:invalid_client`, `:invalid_secret`; `TransientError` | none (nothing logged) | No — code is single-use |
| `.new(account)` | `ZohoSignAccount` | client | — | — | — |
| `#create_request(data:, file:)` | Hash, IO | Hash (`requests`) | `RequestError`, `AuthError`, `TransientError`, `RateLimited` | Zoho draft created | No |
| `#submit_request(request_id, actions)` | String, Array | Hash | same | request sent | No |
| `#get_request(request_id)` | String | Hash | same | — | Yes |
| `#download_pdf(request_id)` / `#completion_certificate(request_id)` | String | binary String | same | — | Yes |
| `#recall` / `#remind` / `#delete_request(request_id)` | String | Hash | same | Zoho state | Recall/delete yes; remind no (sends email) |
| `#extend(request_id, date)` | String, Date | Hash | same | Zoho expiry | Yes |
| `#list_requests_probe` | — | Hash | same | — | Yes |

**`ZohoSignAccount`** (Service, `Data.define`)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `.platform` | — | account (`connection: nil`) | — | reads credentials and `ENV["ZOHO_REGION"]` (default `in`) | Yes |
| `.for_document(doc)` | `Document` | account | — | one `ZohoSignConnection.find_by(entity_id:)` | Yes |
| `.for_entity(entity)` | `Entity` | account (as if sending now) | — | same | Yes |
| `#platform?`, `#token_cache_key` | — | Boolean / String | — | — | Yes |

**`ZohoSignConnection`** (Model)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `#account` | — | `ZohoSignAccount` | — | — | Yes |
| `#mark_needs_reauth!(reason)` | String | Boolean (true when this call transitioned) | — | conditional update; notifies on transition | Yes (only first call notifies) |
| `#mark_connected!` | — | — | — | status, `last_error` nil | Yes |
| `#documents_out_for_signature` | — | `Document` relation | — | — | Yes |
| `#reveal_webhook_secret!` | — | String or nil (nil once revealed) | — | sets `webhook_secret_revealed_at` | Yes |
| `#regenerate_webhook_secret!` | — | String | — | new secret, revealed now | No |

**`ZohoSignConnectionSetup`** (Service; returns `ZohoResult`-shaped `Struct(:success, :errors, :message)`)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `#connect(entity, params, user)` | Entity, permitted params, User | result | — (errors mapped to messages) | inserts connection | No; unique index rejects the second |
| `#reconnect(connection, params)` | | result | — | updates credentials, keeps `connected_at` | Yes for same inputs (code single-use) |
| `#verify(connection)` | | result | — | `last_verified_at`, status | Yes |
| `#disconnect(connection)` | | result | — | destroy if no documents out | Yes |

**`ZohoEsignHelper`** (existing, changed signatures)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `.verify_signature(raw_body, signature, secret)` | Strings | Boolean | — | — | Yes |
| `#update_signature_progress(doc, payload)` | Document, Hash | — | Zoho client errors (retried by job) | statuses, completion, `EsignLog` | Yes (absolute writes; completion claimed once) |
| `#extend_expiry(doc, date_param)` | Document, String | `ZohoResult` (message on refusal) | — | Zoho + `esign_expires_at` | Yes |
| `#update_esign_status(doc)` | Document | — | `TransientError`, `RateLimited` (retried by job); `AuthError` handled | statuses | Yes |

**`ZohoWebhookJob`** (Job)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `#perform(connection_id, raw_body)` | Integer or nil, String | — | client errors → retry | via helper | Yes |

**Reviewer checks**
- [ ] Every raised error is handled by a caller or listed in [Error Mapping](#error-mapping-and-logging)
- [ ] `remind` is never retried automatically (only user clicks call it)
- [ ] `mark_needs_reauth!` notifies only when its conditional update changed a row

---

## Controllers, Params and Responses

| Action | Permitted params | Policy method | Success response | Failure response |
|---|---|---|---|---|
| `ZohoSignConnectionsController#create` | `zoho_sign_connection: [:region, :client_id, :client_secret, :grant_code]` | `ZohoSignConnectionPolicy#create?` (record: the entity's new connection) | turbo_stream replace `#zoho_sign_connection_panel` | 422 turbo_stream panel with field errors / mapped message |
| `#update` (reconnect) | same | `update?` | same | 422 same; stored record untouched |
| `#destroy` | — | `destroy?` | turbo_stream panel ("Using CapHive's") | 422 panel with "N documents are still out…" |
| `#verify` | — | `update?` | turbo_stream panel + "Connection verified" | turbo_stream panel with reconnect message |
| `#reveal_webhook_secret` | — | `update?` | turbo_stream panel showing secret once | panel without secret |
| `#regenerate_webhook_secret` | — | `update?` | turbo_stream panel showing new secret | — |
| `ZohoSignWebhooksController#create` | none (raw body) | none — `skip_before_action :authenticate_user!, :verify_authenticity_token, :set_current_entity`; `skip_after_action :verify_authorized` | 200 `"Ok"` | 404 head (unknown token) / 401 `"Invalid signature"` |
| `DocumentsController#signature_progress` (Zoho branch) | none (raw body) | as today | 200 `"Ok"` | 401 `"Invalid signature"` |
| `DocumentsController#extend_esign_expiry` | `expire_by` | `extend_esign_expiry?` | redirect + notice | redirect + alert (window message / Zoho error) |

Entity is loaded from `params[:entity_id]` with `Entity.find`; the connection is
`ZohoSignConnection.find_by(entity_id: entity.id)` — never from a param id.

**Reviewer checks**
- [ ] No action without `authorize`; the policy record always carries the entity from the URL
- [ ] Permitted params can't set `entity_id`, `status`, `connected_at`, `webhook_*` or `connected_by_id`
- [ ] Webhook controllers read `request.raw_post` for HMAC, never re-serialised params

---

## Queries and Indexes

| Where | Query shape | Index used | Rows expected | Preload / batching |
|---|---|---|---|---|
| `ZohoSignAccount.for_document` | `ZohoSignConnection.find_by(entity_id:)` | unique `entity_id` | 0–1 | memoised per job/request on the helper |
| `ZohoSignWebhooksController#create` | `ZohoSignConnection.find_by(webhook_token:)` | unique `webhook_token` | 0–1 | — |
| `ZohoWebhookJob` (company) | `Document.where(entity_id:, provider_doc_id:).first` | `provider_doc_id` (new) | 0–1 | — |
| `ZohoWebhookJob` (shared) | `Document.where(provider_doc_id:).first` then platform check | `provider_doc_id` (new) | 0–1 | — |
| Signer match | `doc.e_signatures.to_a` → `index_by(&:provider_signer_id)` + email fallback | `document_id` | ≤ 25 | one load per event |
| `#documents_out_for_signature` | `Document.where(entity_id:, sent_for_esign: true).where(sent_for_esign_date: connected_at..).where(esign_status: Document::ESIGN_ACTIVE_STATUSES)` | `entity_id` | entity's documents; counted with `.count` | no load |
| Notifier recipients | `entity.employees.active.company_admins` | existing | few | — |

**Reviewer checks**
- [ ] Every query is scoped by `entity_id`, except the shared-address lookup, which is followed by the platform-account check before any write
- [ ] No unbounded loads; disconnect uses `count`, not `size` on a loaded relation

---

## Transactions, Locking and Concurrency

| Operation | Transaction scope | Lock | Race it prevents | Idempotency key |
|---|---|---|---|---|
| Connect | insert only (token exchange happens before, outside) | — | double-click → two rows | unique `entity_id` (`RecordNotUnique` → "already connected") |
| Reconnect | update one row (exchange before, outside) | `connection.with_lock` around the write only | two reconnects interleaving fields | last write wins, both valid |
| Needs reconnect | single `update_all ... WHERE id = ? AND status = 'connected'` | row-level by the UPDATE | duplicate emails | returned row count = 1 |
| Access token | `Rails.cache.fetch(token_cache_key, expires_in: expires_in - 60)` | none | — (Zoho does not rotate refresh tokens; parallel refresh yields two valid tokens) | cache key includes SHA-256(refresh_token) |
| Completion | existing `Document#signature_completed` `update_all` claim | row-level | double signed copy / certificate | `esign_status != completed` predicate |
| Disconnect | `count` then `destroy` | `connection.with_lock` | sending while disconnecting: a send that starts first is counted; one that starts after uses the platform account | — |

**Reviewer checks**
- [ ] No Zoho HTTP call or email inside a transaction (exchange/verify run before the write; notifier runs after the conditional update)
- [ ] Only one row is ever locked at a time (no lock ordering issue)

---

## Background Jobs

| Job | Queue | Trigger | Retry / backoff | Discard on | Concurrency guard | Timeout |
|---|---|---|---|---|---|---|
| `ZohoWebhookJob` (new) | `default` | webhook accepted | `retry_on ZohoSignClient::TransientError, ZohoSignClient::RateLimited, wait: :polynomially_longer, attempts: 5` | `ZohoSignClient::AuthError` (connection already marked), `ActiveRecord::RecordNotFound` | absolute writes + completion claim | client timeouts (5 s / 30 s / 60 s) |
| `EsignUpdateJob` (existing) | as today | daily `DocumentEsignUpdateJob`, manual fetch | add same `retry_on` | same `discard_on` | same | same |
| `EsignJob` (existing) | as today | send | unchanged (no retry) | — | `resend_for_esign?` | same |

Final failure after 5 attempts → `ErrorReport.notify(e, source: "ZohoWebhookJob")`. No new cron.
`DocumentsController#fetch_esign_updates` calls `DocumentEsignUpdateJob.new.perform` inline (existing),
which enqueues `EsignUpdateJob`, so manual fetches get the same retries.

**Reviewer checks**
- [ ] Running a webhook job twice, or two events out of order (signed after completed), leaves the same final state
- [ ] `remind` is not reachable from any retried job

---

## External Integrations

| Call | Method + path | Auth | Timeouts | Rate limit handling | Error → exception |
|---|---|---|---|---|---|
| Grant exchange | `POST {accounts}/oauth/v2/token` (`authorization_code`) | client id/secret | open 5 s / read 30 s | — | `error=invalid_code` → `AuthError(:invalid_code)`; `invalid_client` → `AuthError(:invalid_client)`; `invalid_client_secret` → `AuthError(:invalid_secret)` |
| Token refresh | `POST {accounts}/oauth/v2/token` (`refresh_token`) | client id/secret | 5 / 30 | `Access Denied` "too many requests" → `RateLimited` | `invalid_code` / `invalid_client` → `AuthError` |
| Create / submit | `POST {sign}/api/v1/requests`, `/:id/submit` (multipart / `data` form field) | `Zoho-oauthtoken` | 5 / 30 | 429 → `RateLimited` | 401 → refresh once, retry once, then `AuthError`; 5xx → `TransientError`; other 4xx → `RequestError(message)` |
| Get / recall / remind / extend / delete | as in [design ④](design.md#-zoho-caller) | same | 5 / 30 | same | same |
| PDF / certificate | `GET .../pdf`, `.../completioncertificate` | same | 5 / 60 | same | same |
| Verify | `GET {sign}/api/v1/requests` (`row_count` 1) | same | 5 / 30 | same | same |

HTTParty `debug_output` is removed (it printed tokens in development). Logging is at `info` with
request path and Zoho `code`/`message` only — never headers or bodies of token calls.

**Reviewer checks**
- [ ] Secrets never logged (no `debug_output`, no token-call bodies in `EsignLog`)
- [ ] Every non-2xx status maps to a named exception; timeouts and `SocketError`/`Errno::ECONNREFUSED` → `TransientError`

---

## Error Mapping and Logging

| Exception | Raised in | Handled by | User sees | Logged / alerted |
|---|---|---|---|---|
| `AuthError` (company account) | client | client calls `mark_needs_reauth!`; jobs discard; send path returns failure | panel "Needs reconnect"; send refused with reconnect message | warn log; notifier email once |
| `AuthError` (platform) | client | same paths, no connection to mark | send: "Error sending … - Zoho rejected CapHive's credentials" | `ErrorReport.notify(source: "ZohoSignClient platform")` |
| `AuthError(:invalid_code / :invalid_client / :invalid_secret)` during connect | `exchange_grant_code` | `ZohoSignConnectionSetup` | proposal messages (expired code / wrong region / wrong secret) | info log, no alert |
| `TransientError`, `RateLimited` | client | jobs retry; send path → failure | send: Failed + reason; poll: nothing | `ErrorReport.notify` after final attempt |
| `RequestError` | client | send → failure; extend/remind/recall → existing error messages | "Error …" messages | `EsignLog` + warn |
| `PDF::Reader::MalformedPDFError` | helper | `ZohoEsigning` rescue | "Error sending … - <message>" | `ErrorReport.notify(source: "ZohoEsignHelper send")` |
| Unknown status / event | helper | logged | nothing | `EsignLog` |
| Certificate failure | helper | logged | nothing; Completed stands | `ErrorReport.notify` |

All Zoho code uses `ErrorReport.notify(e, source:)` (repo convention), replacing the POC's
`ExceptionNotifier.notify_exception`. Log lines carry `entity_id`, `document_id`, `provider_doc_id`.

**Reviewer checks**
- [ ] No bare `rescue => e` without re-raise or report
- [ ] Log lines carry entity, document and Zoho request ids

---

## Security Review

| Concern | Decision |
|---|---|
| Authorization | `ZohoSignConnectionPolicy` → `EntityPolicy#update?` for every panel action; `DocumentPolicy#extend_esign_expiry?` / `#send_esign_reminder?` use `esign_supports?` |
| Tenant isolation | Connection only via `params[:entity_id]` + policy, or via the webhook token; webhook job scopes documents by `entity_id` and the cutover; shared address only touches platform-account documents |
| Secrets | `encrypts :client_secret, :refresh_token, :webhook_secret`; never rendered after submit (inputs blank on reconnect); `grant_code` filtered (`secret`, `token` already filtered); `audited except:` the three secrets |
| Webhook auth | HMAC-SHA256 base64 over `request.raw_post`, `secure_compare`; missing header = refuse; secret required on the shared address outside `Rails.env.local?` |
| SSRF | URLs only from `ZohoSignClient::REGIONS` |
| Input / output sanitisation | `region` inclusion; `client_id` stripped, ≤ 100; panel uses ERB escaping; `last_error` truncated |
| Mass assignment | permitted params listed above only |

**Reviewer checks**
- [ ] A user from another entity cannot reach any connection through any route, job or MCP tool (no MCP surface added)
- [ ] An unsigned or wrongly signed request never reaches `ZohoWebhookJob`

---

## Configuration and Rollout

| Item | Value / location |
|---|---|
| Platform credentials | Rails credentials per environment: `ZOHO_CLIENT_ID`, `ZOHO_CLIENT_SECRET`, `ZOHO_REFRESH_TOKEN`, `ZOHO_WEBHOOK_SECRET` (new). Present today: `development`, `staging.in` (no webhook secret). Missing: `staging.us`, `production.in`, `production.us` |
| Platform region | `ENV["ZOHO_REGION"]`, default `in`; old `ZOHO_SIGN_URL` / `ZOHO_ACCOUNTS_URL` removed |
| Active Record encryption | Required for PR 2 in every deployed environment (`config/application.rb` fetches `active_record_encryption` from credentials outside local/test); `production.in` has it; confirm `staging.in`, `staging.us`, `production.us` |
| Feature flag | None — the panel is visible only when `esign_provider` is Zoho, which support sets per company |
| Cron | None new |
| Deploy order | PR 1: credentials (webhook secret) **then** code, and enable HMAC on CapHive's Zoho webhook with the same secret. PR 2: migration → code |
| Rollback | PR 1: revert code; no data. PR 2: revert code; the table can stay (unused) or be dropped by the down migration — companies fall back to the platform account |

**Reviewer checks**
- [ ] Safe to deploy with no company connected (platform behaviour identical except webhook signing)
- [ ] `ZOHO_WEBHOOK_SECRET` set and Zoho webhook HMAC enabled before PR 1 reaches staging/production

---

## Test Plumbing

| Feature file | Stubs / fixtures | Factories | New step definitions |
|---|---|---|---|
| `features/core/zoho_sign_connections.feature` (`@zoho-http`) | `zoho_sign_stub.rb`: token endpoint per region returning success / `invalid_code` / `invalid_client`; list probe 200/401 | `:zoho_sign_connection` (region `com`, `connected_at`, secrets) | `Given Arka has connected its Zoho account in "<region>"`, `When Meera connects with region "<region>" and grant code "<code>"`, panel assertions |
| `features/core/zoho_esign.feature` (`@zoho-http`) | create/submit/get/recall/remind/extend/delete/pdf/certificate stubs per region; request-body capture helpers | existing document/e_signature factories | rewritten send/poll steps; time frozen with `travel_to` |
| `features/core/zoho_esign_webhook.feature` (`@zoho-http`) | HMAC helper `zoho_signed_post(path, body, secret)`; jobs run inline (`active_job_inline_patch.rb`) | same | `When Zoho posts "<event>" for "<signer>" to Arka's address signed with "<secret>"` |

Each scenario starts with a comment `# <ID> — <spec>/<scenario>` (design worked examples).

---

## Project Rules Checklist

| Rule | Applies? | How it is met |
|---|---|---|
| No `blank?`/`present?` on relations; use `exists?`/`none?` | Applies | `documents_out_for_signature.count` / `.exists?`; `check_and_update_document_status` already uses `none?` |
| Dedup in SQL (`distinct.pluck`), batch bulk operations (`find_each`/`in_batches`) | Applies | signer updates per document (≤ 25); webhook `update_all` for submitted/recalled/expired |
| Select only needed columns when loading many `account_entries`; no speculative `includes` of big associations | N/A | No account entries touched |
| Screen dates via `l(...)`; emails render `Mon dd, yyyy` via `EmailDateLocalization`; no human-format `strftime` | Applies | `documents/show` and the extend modal switch from `strftime("%d %b %Y")` to `l(date)` (locale default, `28/11/2026` in `en`); reconnect email uses `EmailDateLocalization`; `strftime("%d %B %Y")` remains only for Zoho's API `expire_by` payload (machine format) |
| Date inputs use `f.date_field` / `date_field_tag`; JS dates via `locale_date_format.js` | Applies | extend modal keeps `date_field_tag` |
| Every query entity-scoped; Pundit `authorize`/`policy_scope` on every action | Applies | see [Security Review](#security-review); webhook controllers are the documented unauthenticated exception (HMAC instead) |
| MCP tool surfaces changed only via the ontology YAML | N/A | No MCP surface added |
| Cucumber only (no RSpec); `TEST_ENV_NUMBER=$RANDOM` on every run | Applies | three feature files; runs use `TEST_ENV_NUMBER=$RANDOM` |
| `bundle exec rubocop` clean, including the `IRM/RelationBlankPresent` cop | Applies | run on every changed Ruby file per PR |

---

## Sign-off

| Reviewer | Date | Decision | Notes |
|---|---|---|---|
| | | | |
