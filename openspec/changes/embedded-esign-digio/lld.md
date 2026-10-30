# Embedded eSigning with Digio — Low-Level Design

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

- **Authorization is identity, not entity.** `ESignaturePolicy#sign?` compares the login email with `e_signatures.email` and
  refuses impersonation via `current_user.support_user_id`; it deliberately does **not** use `belongs_to_entity?` or
  `DocumentPolicy#show?` — see [Security Review](#security-review).
- **The result endpoint never writes a signer status.** It appends to `esign_logs.sdk_events`, maps the code, and at most
  enqueues `DocumentEsignUpdateJob` — see [Controllers](#controllers-params-and-responses).
- **Webhook routing keeps the legacy rule as fallback**, and `process_esign_success` gets a nil guard; this is the only
  change that applies to every entity regardless of the switch — see [Method Contracts](#method-contracts) (`DigioEsignHelper`).
- **`rejected` is sticky in `ESignature#new_status?`** except against `signed`, because Digio's status pull does not
  know "rejected" and would flip it back — see [Method Contracts](#method-contracts).
- **No token anywhere.** `generate_access_token` stays false; nothing new is stored beyond `esign_logs.sdk_events` and
  `e_signatures.signing_notified_at` — see [Schema Detail](#schema-detail).
- **Notifications are claimed once and never block.** `ESignature#claim_signing_notification!` is an atomic `update_all`;
  `Document#notify_ready_signers` has three call sites and every one rescues and reports. WhatsApp is deferred, so the
  notifier must not respond to `custom_notification` — see [Method Contracts](#method-contracts) and
  [Error Mapping and Logging](#error-mapping-and-logging).
- **The permission flag is appended last** in `EntityEnabled`'s `permissions` list; the admin tick-box appears
  automatically — see [Configuration and Rollout](#configuration-and-rollout).

---

## File Map

Pack: `app/packs/core/documents/` (existing sub-domain; no new package).

| Boundary | File | New / Modified | Responsibility |
|---|---|---|---|
| ① | `app/packs/core/documents/views/documents/_embedded_sign_banner.html.erb` | New | Banner (ready and waiting-turn variants) |
| ① | `app/packs/core/documents/views/documents/show.html.erb` | Modified | Render the banner above the card |
| ① | `app/packs/core/documents/views/e_signatures/_e_signature.html.erb` | Modified | **Sign now** on the viewer's own row; **Rejected** uses the badge helper |
| ② | `app/packs/core/documents/policies/e_signature_policy.rb` | Modified | `sign?`, `sign_result?` |
| ②⑧⑨ | `app/packs/core/documents/models/e_signature.rb` | Modified | `signable_by?`, `signing_state`, `status_badge`, `new_status?`, `claim_signing_notification!` |
| ② | `app/packs/core/entities/models/concerns/entity_enabled.rb` | Modified | Append `enable_embedded_esign` to the `permissions` flag list |
| ③ | `app/packs/core/documents/controllers/e_signatures_controller.rb` | Modified | `sign`, `sign_result`, `set_signing_e_signature` |
| ③ | `config/routes/core.rb` | Modified | `get :sign` and `post :sign_result` as members of `e_signatures` (both in PR 1) |
| ③ | `app/packs/core/documents/views/e_signatures/sign.html.erb` | New | The signing page (state partials inline) |
| ③ | `app/javascript/controllers/digio_esign_controller.js` | New | Loads the SDK, `init`/`submit`, posts results |
| ③ | `app/packs/core/documents/services/digio_sdk_config.rb` | New | `script_url`, `environment` |
| ⑤ | `app/packs/core/documents/services/digio_sdk_errors.rb` | New | Frozen code → group/message/action table |
| ⑤ | `app/packs/core/documents/models/esign_log.rb` | Modified | `append_event(column, payload)` |
| ⑤ | `db/migrate/20261012100000_add_sdk_events_to_esign_logs.rb` | New | `esign_logs.sdk_events` |
| ⑤⑨ | `db/schema.rb`, `db/schema_test.rb` | Modified | Columns added (`esign_logs.sdk_events`, `e_signatures.signing_notified_at`); the latter file via `bin/sync_schema_test.rb` |
| ⑦⑨ | `app/packs/core/investor_kycs/models/concerns/digio_esign_helper.rb` | Modified | Route on `event`; `process_esign_rejected`; nil guard; guarded `notify_ready_signers` calls in `update_document`, `process_esign_success`, `update_esign_status` |
| ⑦ | `app/packs/core/investor_kycs/models/helper/esign_helper.rb` | Modified | Dispatcher returns after reporting an unsupported payload instead of calling the helper on nil (PR 1) |
| ⑨ | `app/packs/core/documents/mailers/esign_signing_notifier.rb` | New | `EsignSigningNotifier < BaseNotifier`: `message`, `url`, `mailer_name`, `email_method`, `email_data` |
| ⑨ | `app/packs/core/documents/mailers/esign_signing_mailer.rb` | New | `EsignSigningMailer#signature_requested` |
| ⑨ | `app/packs/core/documents/views/esign_signing_mailer/signature_requested.html.erb` | New | Email body (exact copy in the proposal's Behavior Rules) |
| ⑨ | `app/packs/core/documents/models/document.rb` | Modified | `notify_ready_signers` |
| ⑨ | `app/packs/core/documents/services/resend_document_for_esign.rb` | Modified | Clear `signing_notified_at` with the statuses |
| ⑨ | `db/migrate/20261012110000_add_signing_notified_at_to_e_signatures.rb` | New | `e_signatures.signing_notified_at` |
| docs | `docs/user_guides/esigning_user_guide.md` | Modified | Section on signing inside CapHive and on the notification |
| tests | `features/documents/embedded_esign_eligibility.feature`, `embedded_esign_page.feature`, `embedded_esign_result.feature`, `esign_webhook_events.feature`, `embedded_esign_notifications.feature` | New | One per phase, committed with the code in PR 1 (eligibility, page, webhooks) or PR 2 (result, notifications) |
| tests | `features/step_definitions/embedded_esign_steps.rb` | New | Steps and Digio payload builders |

**Reviewer checks**
- [ ] Every class in the design's class diagram has a file here, and nothing here is missing from it
- [ ] Files follow the pack layout (`app/packs/<domain>/<sub_domain>/...`) and Packwerk boundaries
- [ ] No file under `app/controllers` or `app/models`
- [ ] Files are grouped into the PRs in [design.md › Delivery](design.md#delivery-pull-requests) and no PR exceeds 15 application files (not counting `openspec/` or `features/`)

---

## Schema Detail

**`esign_logs`** (existing): gains one column for the audit trail of results reported from the signing page.

| Column | Change | Type | Limit | Null | Default | Index / FK | Why it's needed |
|---|---|---|---|---|---|---|---|
| `sdk_events` | Added | `json` | — | yes | none | none | Same shape and type as `webhook_data` / `manual_update_data` so `EsignLog#append_event` is uniform; nullable because most logs never get one; no index — read only by support through the document |

**`e_signatures`** (existing): gains one column recording that a signer has been notified for the current request.

| Column | Change | Type | Limit | Null | Default | Index / FK | Why it's needed |
|---|---|---|---|---|---|---|---|
| `signing_notified_at` | Added | `datetime` | — | yes | none | none | The atomic "notify once per request" claim; null means not yet notified; cleared on **Re-Send**; no index because it is only tested in the `update_all` that is keyed by the row's primary key |

**Migration safety:** `esign_logs` is cleaned by `EsignLogCleanupJob` (≤ 91 days), so it is small; adding a nullable JSON
column is a metadata-only change on MySQL 8 (no table rewrite). Reversible with `remove_column`. Update `db/schema.rb`,
then `ruby bin/sync_schema_test.rb` and `RAILS_ENV=test bin/rails db:test:load_schema`. **Never** run `db:migrate` under
`RAILS_ENV=test` (its dump hook truncates `schema_test.rb`). No data migration; no new status column — `rejected` is a
new value of the existing string `e_signatures.status` (limit-free, default `""`). The second migration,
`20261012110000_add_signing_notified_at_to_e_signatures.rb`, adds a nullable `datetime` to `e_signatures`
(metadata-only on MySQL 8; no backfill — null means "not yet notified", and nothing is notified retroactively).

**Reviewer checks**
- [ ] Every new or changed column and index has a "why", and none is unjustified
- [ ] No foreign key or uniqueness rule is introduced
- [ ] `schema.rb` and `schema_test.rb` both show both columns and agree
- [ ] `signing_notified_at` is nullable with no default and no index
- [ ] Migration is reversible and safe on the production table size

---

## Method Contracts

**`ESignature`** (Model)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `signable_by?(user)` | `User`, or nil | `Boolean`; `email.to_s.casecmp?(user.email.to_s)`, false for nil user or blank email | — | none | Yes |
| `signing_state` | — | `:closed` if document `esign_status` is not `requested`, `sent_for_esign` false, or signer status is `cancelled/expired/rejected/voided`; else `:signed` if `status == "signed"`; else `:waiting_turn` if `document.force_esign_order` and `document.e_signatures.not_signed.where("position < ?", position).exists?`; else `:ready` | — | none | Yes |
| `status_badge` | — | adds `when "rejected"` → `"danger"` | — | none | Yes |
| `new_status?(payload_status)` | `String` | as today; the protected-status list is `%w[signed expired]` plus `"rejected"` unless `payload_status == "signed"` | — | `update_all` of `status` (existing) | Yes — same input leaves the same state |
| `claim_signing_notification!` | — | `Boolean`: `ESignature.where(id:, signing_notified_at: nil).update_all(signing_notified_at: Time.zone.now).positive?` | — | Sets the column on the claimed row only | Yes — false after the first claim |

**`ESignaturePolicy`** (Policy)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `sign?` | — (`user`, `record`) | true only if: `document.entity.permissions.enable_embedded_esign?`, `entity_setting.esign_provider == "Digio"`, `document.provider_doc_id.present?`, `record.signable_by?(user)`, `user.support_user_id.blank?` | — | none | Yes |
| `sign_result?` | — | as `sign?` — the state is **not** consulted (it may already have moved by webhook) | — | none | Yes |

**`DigioSdkConfig`** (Service, module functions)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `.base_url` | — | `ENV["DIGIO_SDK_BASE_URL"].presence`, else `https://ext.digio.in` when `ENV["DIGIO_BASE_URL"]` includes `ext.digio.in`, else `https://app.digio.in` | — | none | Yes |
| `.script_url` | — | `"#{base_url}/sdk/v11/digio.js"` | — | none | Yes |
| `.environment` | — | `"sandbox"` if `base_url` includes `ext.digio.in`, else `"production"` | — | none | Yes |

**`DigioSdkErrors`** (Service, frozen map)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `.lookup(code)` | `String` or nil; normalised with `strip.upcase` | `Result(group, message, action, check, alert)` — see the table in [design card ⑤](design.md#⑤-result-handler); unknown or blank → group `:ours` | — | none | Yes |
| `.completed?(event)` | `String` | true for `sign.electronic.completed`, `sign.aadhaar.completed`, `sign.dsc.completed` | — | none | Yes |
| `.client_event(name)` | `"client.cancelled"` or `"client.panel_unavailable"` | `Result` for the two browser-originated pseudo-events (messages "Signing was cancelled…" / "We couldn't load the signing panel…") | — | none | Yes |

**`EsignLog`** (Model)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `#append_event(column, payload)` | `Symbol` in `%i[sdk_events]` (whitelist; existing columns keep their inline code), `Hash` | the log | `ArgumentError` for a column outside the whitelist | `with_lock`; merges `{ Time.zone.now.to_s => payload }` | No — appends; duplicates are acceptable for an audit trail |

**`DigioEsignHelper`** (Service)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `#update_signature_progress(params)` | webhook params | — | none | Routes on `params["event"].to_s.downcase`: `doc.signed` → success; `doc.sign.failed` → failure; `doc.sign.rejected` → rejected; anything else → legacy rule (`error_code.blank?` → success, else failure). Existing missing-document-id branch is kept. | Yes (statuses guarded by `new_status?`) |
| `#process_esign_rejected(params)` (private) | webhook params | — | none | Finds `Document` by `provider_doc_id`; signer by `signer_identifier` lower-cased; `update_esign_response("rejected", payload)`; appends `webhook_data` like its siblings; `ErrorReport.notify(StandardError.new("eSign rejected …"), source: "DigioEsignHelper webhook", **ErrorReport.document_context(doc))` — **always**, including when the signer or document is not found | Yes |
| `#process_esign_success(params)` (private) | webhook params | — | none | Adds guard: `signing_parties` nil or empty → `ErrorReport.notify` and return before iterating; after the signer loop calls `doc.notify_ready_signers` inside `rescue StandardError` → `ErrorReport.notify` | Yes |
| `#update_document(response, doc, user_id)` | existing | existing | existing | Success branch additionally calls `doc.notify_ready_signers` inside `rescue StandardError` → `ErrorReport.notify` | Yes (claim) |
| `#update_esign_status(doc)` | `Document` | — | none | After the signer loop, calls `doc.notify_ready_signers` inside `rescue StandardError` → `ErrorReport.notify` | Yes (claim) |

**`Document`** (Model)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `#notify_ready_signers` | — | `Integer` — signers notified in this call | none (each call site also rescues) | For each `e_signatures.not_signed` ordered by `position` whose `signing_state` is `:ready`: `User.find_by(email: email.downcase)`; skip unless `ESignaturePolicy.new(user, esign).sign?`; skip unless `esign.claim_signing_notification!`; then `EsignSigningNotifier.with(record: esign, entity_id: entity_id).deliver_later(user)` | Yes — the claim makes a repeat a no-op |

**`EsignSigningNotifier`** (Notifier, `< BaseNotifier`)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `#mailer_name` / `#email_method` | notification | `EsignSigningMailer` / `:signature_requested` | — | none | Yes |
| `#email_data(notification)` | notification | `{ notification_id:, user_id: notification.recipient_id, entity_id: params[:entity_id], e_signature_id: record.id }` | — | none | Yes |
| `message` (`notification_methods`) | — | `"Your signature is requested: #{record.document.name} from #{entity.name}"` | — | none | Yes |
| `url` (`notification_methods`) | — | `sign_e_signature_path(record)` | — | none | Yes |

The notifier defines **no** `custom_notification`, so `NotificationExtensions#custom_notification_whatsapp_present?` is false
and the shared `:whats_app` delivery never fires; no WhatsApp code is added.

**`EsignSigningMailer`** (Mailer, follows `ApplicationMailer` conventions: `from_email(entity)`, sandbox handling, `mark_delivered`)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `#signature_requested` | params from `email_data` | `Mail::Message` with subject `"Your signature is requested: #{document.name}"`, to the recipient, body = sender entity name, document name, **Sign now** button to `sign_e_signature_url`, and the Digio line (exact copy in the proposal) | — | none | Yes |

**`ResendDocumentForEsign`** (Service, existing)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `#reset_doc_esignature` | `document:` | existing | existing | `document.e_signatures.update_all(status: "", signing_notified_at: nil)` | Yes |

**Reviewer checks**
- [ ] `Document#notify_ready_signers` is the only caller of `EsignSigningNotifier`
- [ ] `EsignSigningNotifier` does not respond to `custom_notification`
- [ ] Every raised error is handled by a caller or listed in Error Mapping
- [ ] Anything a retry can repeat is idempotent (webhooks and the status job are retried by Digio / Sidekiq)
- [ ] `signing_state` and `sign?` are the only places eligibility is decided; no view re-derives it
- [ ] `new_status?` still returns `false` without writing when a `signed` signer receives `failed` or `rejected`

---

## Controllers, Params and Responses

| Action | Permitted params | Policy method | Success response | Failure response |
|---|---|---|---|---|
| `ESignaturesController#sign` (GET `/e_signatures/{id}/sign`) | none (id from path) | `sign?` | 200 HTML: state-driven partial (`:ready` shows **Start signing** and data attributes `provider-doc-id`, `signer-email`, `sdk-url`, `environment`, `result-url`, `fallback-message`; other states show their message and **Back to document**) | not authorized → redirect to `root_path` with alert "This signature request is not available for your account."; unknown id → standard 404 |
| `ESignaturesController#sign_result` (POST `/e_signatures/{id}/sign_result`) | `params.permit(:event, :error_code, :txn_id)`; each value `to_s.first(100)` | `sign_result?` | 200 JSON `{ "message": String, "action": "retry" \| "none" \| "done" }` | not authorized → 403 JSON `{ "message": "This signature request is not available for your account.", "action": "none" }`; missing `event` → 422 JSON with the generic "ours" message |
| `Document#notify_ready_signers` | `e_signatures.not_signed.order(:position)`, then `User.find_by(email: email.downcase)` per ready signer (Devise stores emails lower-cased) | `index_e_signatures_on_document_id`; `index_users_on_email` | ≤ ~10 signers | none |

Flow inside `sign_result` (in order): authorize → resolve `Result` (`completed?` → done, else `lookup(error_code)`, or
`client_event` for pseudo-events) → `esign_log.append_event(:sdk_events, { at:, signer_email:, event:, error_code:, txn_id:, group: })`
(create the log if absent, as the helper does) → if `Result.check` then `DocumentEsignUpdateJob.perform_later(document.id, current_user.id)`
→ if `Result.alert` then `ErrorReport.notify` → render JSON. **No branch writes `status`, `esign_status` or any document column.**

**Reviewer checks**
- [ ] No action without `authorize`; `sign_result` cannot be reached by a user who is not the signer
- [ ] Permitted params can't set `entity_id`, `user_id`, `status` or other ownership fields — only three strings
- [ ] The existing `set_e_signature` before_action still only covers `show edit update destroy`
- [ ] Responses never include a Digio error code, a payload, or another signer's data

---

## Queries and Indexes

| Where | Query shape | Index used | Rows expected | Preload / batching |
|---|---|---|---|---|
| `ESignature#signing_state` | `document.e_signatures.not_signed.where("position < ?", position).exists?` | `index_e_signatures_on_document_id` | ≤ ~10 per document | none; `exists?` |
| `documents/show` banner | `document.e_signatures.find_by("LOWER(email) = ?", user.email.downcase)` | `index_e_signatures_on_document_id` (then filters ≤ 10 rows) | 0–1 | none; one query per page |
| `ESignaturePolicy#sign?` | `document.entity` and `entity.entity_setting` | primary keys | 1 + 1 | `includes(document: { entity: :entity_setting })` where several rows render (Signatures tab) |
| `ESignaturesController#sign_result` | `esign_log` for the document (create if absent) | `index_esign_logs_on_document_id` | 1 | none |

Entity scoping: every read hangs off a document reached through one `e_signature` id; there is no list endpoint and no
cross-document query. Authorization is the identity check, not an `entity_id` filter, because the signer may belong to a
different entity than the document.

**Reviewer checks**
- [ ] Every query is scoped by the document, or explains why not
- [ ] No N+1 on the Signatures tab: policy lookups on rows use the preloaded entity
- [ ] `exists?` is used; no `.present?` / `.blank?` on a relation

---

## Transactions, Locking and Concurrency

| Operation | Transaction scope | Lock | Race it prevents | Idempotency key |
|---|---|---|---|---|
| `EsignLog#append_event` | the read-modify-write of one JSON column | `with_lock` on the `esign_logs` row | Two near-simultaneous results (retry clicks) losing one entry | none — duplicates are acceptable |
| Status update from webhook and from the job | single `update_all` in `new_status?` (existing) | none | Webhook and job landing together | statuses are monotonic: `signed`/`expired` are never overwritten, `rejected` only by `signed` |
| Document completion | existing `update_all(...).positive?` guard in `signature_completed` | none | Two paths completing the same document | `esign_status != "completed"` guard (existing) |
| Notification claim | single `update_all` keyed by the signer row and `signing_notified_at IS NULL` | none | The webhook and the status check (or Digio retries) confirming the same signature together | The null check itself |

**Reviewer checks**
- [ ] No external HTTP call or email inside the `with_lock` block (the enqueue and `ErrorReport` happen after it)
- [ ] `deliver_later` happens after the claim, never inside a status update
- [ ] The first-time creation of an `EsignLog` cannot raise on a double click (rescue `RecordNotUnique` or `find_or_create_by`)

---

## Background Jobs

| Job | Queue | Trigger | Retry / backoff | Discard on | Concurrency guard | Timeout |
|---|---|---|---|---|---|---|
| `DocumentEsignUpdateJob` (existing) | `:low` | `sign_result` (completion, `ALREADY_SIGNED`, `DUPLICATE_REQUEST`); existing daily run and manual button | default Sidekiq | — (existing) | `eligible_for_esign_update?` per document | existing |
| `EsignUpdateJob` (existing) | default | enqueued by the job above | default Sidekiq | `RecordNotFound` (existing) | `esign_completed?` short-circuit in the helper | existing |
| Noticed delivery jobs (existing) | per Noticed config | `deliver_later` from `Document#notify_ready_signers` | Noticed defaults | — | `signing_notified_at` claim | — |

No new job class and no cron entry (notification delivery uses Noticed's existing jobs, the email delayed by `email_delay`). Latency note: the check goes through the `:low` queue then the default queue; in practice
Digio's own notification usually lands first, so this is the backstop and the manual "being confirmed" state is expected.

**Reviewer checks**
- [ ] A job that runs twice, or out of order, is harmless (two completions enqueue two checks; the second is a no-op)
- [ ] No cron entries are added

---

## External Integrations

| Call | Method + path | Auth | Timeouts | Rate limit handling | Error → exception |
|---|---|---|---|---|---|
| SDK script (browser) | `GET {base_url}/sdk/v11/digio.js` | none | browser default; page shows the "could not load" message on `error` / 8 s without `window.Digio` | n/a | load failure → pseudo-event `client.panel_unavailable` |
| Status check (server, existing) | `GET {DIGIO_BASE_URL}/v2/client/document/{provider_doc_id}` | per-entity Basic token or the shared one (existing cutover logic) | existing | existing | existing (`signatures_failed`) |
| Signing (browser → Digio) | via SDK `submit(provider_doc_id, email)` | Digio verifies the signer | Digio's | Digio's | codes → [design card ⑤](design.md#⑤-result-handler) |
| CapHive email (existing mailer pipeline) | `EsignSigningMailer#signature_requested` via `deliver_by :email` | n/a | existing | spread by `email_delay` | handled by Noticed and the mailer as for other notifiers |
| WhatsApp | none | n/a | n/a | n/a | Not built; the shared `:whats_app` stays off because the notifier has no `custom_notification` |

**Reviewer checks**
- [ ] Secrets never logged; nothing new carries a token (`generate_access_token` is still false)
- [ ] Every non-success SDK outcome maps to a named group in `DigioSdkErrors`
- [ ] No WhatsApp send is possible from `EsignSigningNotifier` (no `custom_notification`, no `whatsapp_message`)

---

## Error Mapping and Logging

| Exception / condition | Raised in | Handled by | User sees | Logged / alerted |
|---|---|---|---|---|
| `Pundit::NotAuthorizedError` | `sign` | rescued in the action | redirect to root with the refusal alert | Rails log at info |
| `Pundit::NotAuthorizedError` | `sign_result` | rescued in the action | 403 JSON, page shows the refusal text | Rails log at info |
| `:ours` group or unmapped code | `sign_result` | `DigioSdkErrors.lookup` | generic "Something went wrong on our side…" | `ErrorReport.notify` source `ESignaturesController sign_result` with code, `txn_id`, signer email, `document_context` |
| `EsignLog#append_event` failure | `sign_result` | `rescue StandardError` around the append only | unaffected — the message is still returned | `ErrorReport.notify` (not silent) |
| `doc.signed` with no `signing_parties` | `process_esign_success` | guard | n/a | `ErrorReport.notify`, then skip |
| `doc.sign.rejected` | `process_esign_rejected` | handler | signer row **Rejected** | `ErrorReport.notify` with `signer_email` |
| Any error in `notify_ready_signers` (lookup, claim, enqueue) | `Document`, at its three call sites | `rescue StandardError` at the call site | Nothing — the send or webhook continues | `ErrorReport.notify` source `Document notify_ready_signers` with `document_context` and the signer email |
| Email delivery failure | Noticed / mailer | Existing delivery handling | The bell entry still exists | Existing delivery tracking for notifications |
| Webhook without a document id | `update_signature_progress` | existing branch | n/a | existing `ErrorReport.notify` |

Log lines carry `document_id`, `e_signature_id`, `provider_doc_id` and the signer email (never the Digio payload body in
application logs; the body is already kept in `esign_logs`).

**Reviewer checks**
- [ ] No bare `rescue => e` that swallows errors silently
- [ ] Log lines carry the ids needed to debug (entity, document, signer, provider id)

---

## Security Review

| Concern | Decision |
|---|---|
| Authorization | `sign?` / `sign_result?` on every new action; identity-based (login email equals signer email, case-insensitive) plus entity switch, provider and Digio-id checks; support impersonation refused via `current_user.support_user_id` (mirrors the intent of `InternalDocPolicy#staff?`) |
| Tenant isolation | A record is reached by one `e_signature` id and then authorized by identity; there is no list or search route; document name and signer detail are rendered only after `sign?` passes; non-signers, impersonation, switch-off and a missing id all get the same refusal text, so existence is not disclosed |
| Secrets | None handled. Only `provider_doc_id` (not a secret without the signer's own OTP) and the signer's own email reach the page. No token is requested, stored, or returned |
| Input / output sanitisation | `event`, `error_code`, `txn_id` stored as truncated strings and never echoed back; messages are server constants; no user-supplied HTML is rendered |
| Mass assignment | `params.permit(:event, :error_code, :txn_id)`; no model attributes are assigned from params |
| CSRF / framing | `sign_result` uses the normal CSRF token (`@rails/request.js`); we frame Digio, nobody frames us (framework default `X-Frame-Options` unchanged) |
| Spoofed results | The browser's result cannot set a status: the only effect of a spoofed `completed` is one extra status check (E17) |
| Notification content and links | The bell entry and email go only to the matched signer's own account; they carry the document name, the sender's name and a link to the signing page, never a token; the link re-authorizes with `sign?` on arrival |

**Reviewer checks**
- [ ] A user from another entity — or any non-signer — cannot reach any record through `sign` or `sign_result`
- [ ] A support user impersonating a signer is refused on both actions
- [ ] No response, log line or HTML attribute contains a token or another signer's email

---

## Configuration and Rollout

| Item | Value / location |
|---|---|
| Credentials / env vars | `DIGIO_BASE_URL` already set per env (`ext.digio.in:444` staging/dev/test, `api.digio.in` production IN and US). Optional `DIGIO_SDK_BASE_URL` override; no new variable required |
| Feature flag | `Entity.permissions` → `enable_embedded_esign`, appended to the end of the list in `EntityEnabled`; default off; toggled at `/admin/entities` (the tick-box renders from `Entity.permissions.pairs`, label "Enable Embedded Esign") |
| Cron / schedules | None |
| Deploy order | migrations (`esign_logs.sdk_events`, `e_signatures.signing_notified_at`) → code → CapHive admin ticks the flag per entity |
| Rollback | Untick the flag (immediate; sent requests still sign by email). Notifications stop with the flag (`sign?` becomes false); bell entries already created remain. Code revert is safe; the columns may stay. The webhook change is **not** flag-gated: it is additive with a legacy fallback |

**Reviewer checks**
- [ ] Safe to deploy with the feature unused, and safe to roll back
- [ ] The flag is last in the list (existing bit positions unchanged) and the label reads sensibly in the admin
- [ ] Production response headers allow `script-src`/`frame-src` for `*.digio.in` (no CSP is set in the app)

---

## Test Plumbing

| Feature file | Stubs / fixtures | Factories | New step definitions |
|---|---|---|---|
| `features/documents/embedded_esign_eligibility.feature` | none for Digio; `Entity.permissions` toggled in a step | `:entity`, `:user`, `:investor`, `:document` (approved, `sent_for_esign`, `provider_doc_id`), `ESignature.create!` rows | `Given an agreement sent for eSignature to signers {string}`; `Given Embedded eSigning is {string} for the entity`; `Given I am logged in as the signer {string}`; `Given a support user is impersonating {string}`; `Then I should see the signature banner` / `the Sign now button` |
| `features/documents/embedded_esign_page.feature` (`@javascript`) | Playwright route for `**/sdk/v11/digio.js` serving a stub `window.Digio` that records `new Digio(options)`, `init`, `submit(...)`, and fires a scripted `event_listener`/`callback`; `DIGIO_SDK_BASE_URL` fixed to a test host | as above | `Given the Digio panel stub reports {string}`; `Then the panel should have been started with document {string} and signer {string}`; `Given the Digio script cannot be loaded`; phone viewport step |
| `features/documents/embedded_esign_result.feature` | rack_test POST to `sign_result`; `allow_any_instance_of(DigioEsignHelper).to receive(:retrieve_signed)` returning the existing builders (status per scenario); `ErrorReport.notify` spied | as above | `When the signing page reports {string} code {string}`; `Then a status check should be enqueued`; `Then the eSign log should record {string}`; `Then support should be alerted` |
| `features/documents/esign_webhook_events.feature` | existing `hit_signature_progress`; new builders `digio_callback_failed`, `digio_callback_rejected`, `digio_callback_rejected_no_parties`, `digio_callback_unknown_event`, `digio_callback_no_event`; `download` stubbed as in `the document get digio callbacks` | as above | `When Digio posts a {string} notification for {string}`; `Then the signer {string} should be {string}` |
| `features/documents/embedded_esign_notifications.feature` | `ActionMailer::Base.deliveries` and `Noticed::Notification` rows asserted per recipient; Digio status stub as in the result feature; `EsignSigningNotifier.with` forced to raise for X12 | as above plus an `:investor` with an `InvestorAccess` whose `email_enabled` is false | `Then {string} should have a signing notification`; `Then {string} should have received the signing email`; `Given the investor access for {string} has email {string}`; `When the document is re-sent for eSignature` |

CDN cache: the Digio host is not in `CdnAssetCache::HOSTS`, so the stub route is unaffected; install the route in the
scenario's browser context before `visit`.

---

## Project Rules Checklist

| Rule | Applies? | How it is met |
|---|---|---|
| No `blank?`/`present?` on relations; use `exists?`/`none?` | Applies | `signing_state` uses `exists?`; only strings use `blank?` |
| Dedup in SQL (`distinct.pluck`), batch bulk operations (`find_each`/`in_batches`) | N/A | No collection loops; at most ~10 signer rows per document |
| Select only needed columns when loading many `account_entries`; no speculative `includes` of big associations | N/A | No `account_entries`; the only `includes` is `document -> entity -> entity_setting` |
| Screen dates via `l(...)`; emails render `Mon dd, yyyy` via `EmailDateLocalization`; no human-format `strftime` | N/A | No dates are rendered on screens or in the signing email; the audit timestamp is stored as an ISO string |
| Date inputs use `f.date_field` / `date_field_tag`; JS dates via `locale_date_format.js` | N/A | No date inputs |
| Every query entity-scoped; Pundit `authorize`/`policy_scope` on every action | Applies (with a stated exception) | `authorize` on both new actions; scoping is by identity because the signer may be outside the document's entity — see [Queries](#queries-and-indexes) and [Security Review](#security-review) |
| MCP tool surfaces changed only via the ontology YAML (run the ontology drift feature) | N/A | No MCP tool or ontology change |
| Cucumber only (no RSpec); `TEST_ENV_NUMBER=$RANDOM` on every run | Applies | Five feature files; every run prefixed with `TEST_ENV_NUMBER=$RANDOM` |
| `bundle exec rubocop` clean, including the `IRM/RelationBlankPresent` cop | Applies | Run on all modified Ruby files before completion |

---

## Sign-off

| Reviewer | Date | Decision | Notes |
|---|---|---|---|
| | | | |
