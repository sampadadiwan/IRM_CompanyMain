# CapHive LP Mobile App — Low-Level Design

> **Audience:** The developer who reviews the implementation plan before coding starts.
> **Companion documents:** [Design](design.md) · [Spec](specs/) · [Tasks](tasks.md)

> **Planning phase — no code changes.** This document records the implementation-level decisions
> a reviewing developer must check. It adds to [design.md](design.md) and links to its diagrams and
> worked examples rather than repeating them.

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
- [Mobile App Build Detail](#mobile-app-build-detail)
- [Project Rules Checklist](#project-rules-checklist)
- [Sign-off](#sign-off)

---

## Review Summary

> Read [design.md › Changes made during implementation](design.md#changes-made-during-implementation-2026-10-13) first: the File Map and contracts below were written before them; where they disagree, that table wins.

- **Tokens minted by us, not by devise-api's endpoint.** `MobileDevice.register!` creates
  `DeviseApi::Token` rows directly after 2FA. The mobile base controller rejects any token without
  a live device ([Method Contracts](#method-contracts), [Security Review](#security-review)).
- **`TwoFactorVerifier` extraction** from `Users::TwoFactorController` is the riskiest edit to
  existing code. Its contract must preserve every existing branch: TOTP drift, the SMS Twilio
  verify, WhatsApp OTP and the attempt counts ([Method Contracts](#method-contracts)).
- **Push gate placement:** `config.if` on `deliver_by :push` in `BaseNotifier` reuses
  `email_enabled`. Check it really is identical for advisors ([Controllers](#controllers-params-and-responses),
  design [⑤](design.md#⑤-notification-sender)).
- **Idempotency of push** depends on the unique index `[noticed_notification_id, mobile_device_id]`
  and on creating the row before the HTTP call ([Transactions](#transactions-locking-and-concurrency)).
- **Evergreen card extraction** (`Evergreen::LpCardSummary`) changes a live partial. The output
  must be byte-identical ([File Map](#file-map)).
- **Changes to existing models** (`User`, `BaseNotifier`, `NotificationExtensions`): flagged for
  explicit approval per project practice.

---

## File Map

| Boundary | File | New / Modified | Responsibility |
|---|---|---|---|
| ① | `mobile/` (Expo project: `app.config.js`, `eas.json`, `app/`, `src/api`, `src/theme`, `src/format`, `e2e/`) | New | The app ([Mobile App Build Detail](#mobile-app-build-detail)) |
| ② | `app/packs/core/mobile/controllers/api/mobile/v1/sessions_controller.rb` | New | create / verify / resend / refresh / destroy |
| ② | `app/packs/core/mobile/services/mobile/sign_in.rb` | New | Password, persona and 2FA branching → Result |
| ② | `app/packs/core/users/services/two_factor_verifier.rb` | New | Session-free code check and delivery |
| ② | `app/packs/core/users/controllers/users/two_factor_controller.rb` | Modified | Delegates code checks to `TwoFactorVerifier` |
| ③ | `app/packs/core/mobile/models/mobile_device.rb` | New | Registry, authenticate, revoke, scopes |
| ③ | `app/packs/core/mobile/policies/mobile_device_policy.rb` | New | Own devices only |
| ③ | `app/packs/core/users/controllers/users/mobile_devices_controller.rb` + `views/users/mobile_devices/index.html.erb`, `_mobile_device.html.erb` | New | Website Profile › Devices |
| ③ | `app/packs/core/users/models/user.rb` | Modified | `has_many :mobile_devices`; `push_preferences`; revoke callback |
| ③ | `db/migrate/2026xxxx_create_mobile_devices.rb` | New | Table + indexes |
| ④ | `app/packs/core/mobile/controllers/api/mobile/v1/base_controller.rb` | New | Auth via device, app version, Pundit, error mapping |
| ④ | `.../v1/{me,home,commitments,capital_remittances,documents,notifications,personas,devices}_controller.rb` | New | Thin read/write endpoints |
| ④ | `app/packs/core/mobile/views/api/mobile/v1/**/*.json.jbuilder` | New | v1 shapes |
| ④ | `app/packs/core/mobile/services/mobile/home_summary.rb` | New | Cards + to-do |
| ④ | `app/packs/funds/evergreen/services/evergreen/lp_card_summary.rb` | New | Evergreen card values (shared) |
| ④ | `app/packs/funds/evergreen/views/evergreen/funds/_lp_card.html.erb` | Modified | Reads `Evergreen::LpCardSummary` |
| ⑤ | `app/packs/core/notifications/models/base_notifier.rb` | Modified | `deliver_by :push` |
| ⑤ | `config/initializers/noticed.rb` (`NotificationExtensions`) | Modified | `push_enabled` |
| ⑥ | `app/packs/core/notifications/delivery_methods/expo_push.rb` | New | Delivery method |
| ⑥ | `app/packs/core/mobile/services/mobile/{push_category,deep_link,expo_push_client}.rb` | New | Lookups + HTTP client |
| ⑥ | `app/packs/core/mobile/models/mobile_push_delivery.rb`, `jobs/expo_push_receipts_job.rb` | New | Delivery log, receipts |
| ⑥ | `db/migrate/2026xxxx_create_mobile_push_deliveries.rb` | New | Table + indexes |
| ⑦ | `.../v1/web_handoffs_controller.rb`; `app/packs/core/users/controllers/users/mobile_handoffs_controller.rb` | New | Mint and land |
| cross | `config/routes/mobile.rb` (+ `draw :mobile` in `config/routes.rb`); `config/initializers/rack_attack.rb`; `config/initializers/filter_parameter_logging.rb`; `app/packs/core/mobile/package.yml` | New / Modified | Routes, throttles, log filters, pack |
| tests | `features/mobile/*.feature`, `features/step_definitions/mobile_api_steps.rb`, `features/support/expo_push_stub.rb` | New | Cucumber |

**Reviewer checks**
- [ ] Every class in the design's class diagram has a file here, and nothing here is missing from it
- [ ] The new `core/mobile` pack declares its dependencies (`core/users`, `core/notifications`, `core/documents`, `funds/*`) in `package.yml`, and Packwerk passes
- [ ] `_lp_card.html.erb` renders identically before and after (existing evergreen features green)

---

## Schema Detail

**`mobile_devices`** (new): the device registry, with one row per user per app install.

| Column | Change | Type | Limit | Null | Default | Index / FK | Why it's needed |
|---|---|---|---|---|---|---|---|
| `user_id` | Added | bigint | — | no | — | FK users, part of unique | Owner |
| `devise_api_token_id` | Added | bigint | — | yes | — | FK devise_api_tokens (on delete nullify), idx | Current token. Nil after revoke |
| `install_id` | Added | string | 64 | no | — | unique `[user_id, install_id]` | UUID v4 from app (36 chars). 64 leaves headroom |
| `platform` | Added | string | 10 | no | — | — | `ios`/`android`, validated inclusion |
| `name` | Added | string | 100 | yes | — | — | Display only; truncated on input |
| `app_version` | Added | string | 20 | yes | — | — | Semver |
| `region_code` | Added | string | 10 | no | — | — | `SiteRegistry.current_code` |
| `push_token` | Added | string | 255 | yes | — | unique | `ExponentPushToken[…]` (~41 chars); 255 for safety |
| `push_enabled` | Added | boolean | — | no | true | — | Per-phone switch |
| `push_status` | Added | string | 20 | no | "none" | — | none/ok/not_registered |
| `last_used_at` | Added | datetime | — | no | — | composite | Expiry and LRU |
| `last_push_at` | Added | datetime | — | yes | — | — | Devices page |
| `revoked_at` | Added | datetime | — | yes | — | composite | Live filter |
| `revoked_reason` | Added | string | 30 | yes | — | — | app_sign_out / website_sign_out / password_changed / deactivated / device_limit / replaced |
| idx `[user_id, revoked_at, last_used_at]` | New index | — | — | — | — | — | `live`/`pushable`/LRU |

**`mobile_push_deliveries`** (new): the per-device push attempt log.

| Column | Change | Type | Limit | Null | Default | Index / FK | Why it's needed |
|---|---|---|---|---|---|---|---|
| `noticed_notification_id` | Added | bigint | — | no | — | FK, unique with device | Which notification |
| `mobile_device_id` | Added | bigint | — | no | — | FK (cascade delete), idx `[mobile_device_id, created_at]` | Which phone |
| `status` | Added | string | 10 | no | "pending" | — | pending/sent/failed |
| `ticket_id` | Added | string | 64 | yes | — | idx | Receipt lookup (UUID) |
| `error` | Added | string | 255 | yes | — | — | Expo error code/message, truncated |
| `created_at`/`updated_at` | Added | datetime | — | no | — | — | Audit |

**`users.preferences`** (existing json): new key `push` → `{"capital_calls":bool,
"distributions":bool, "documents":bool, "other":bool}`. A missing key means true. No migration.

**Migration safety:** both tables are new, so no lock impact. `noticed_notifications` and
`devise_api_tokens` only gain inbound FKs from the new tables (no DDL on them). Both migrations are
reversible (`create_table`). Update `schema.rb` and `schema_test.rb`, and do not run them against
the shared dev DB from this branch without asking. Retention: purge `mobile_push_deliveries`
older than 90 days with a monthly `in_batches` delete (bounded table).

**Reviewer checks**
- [ ] Every new or changed column and index has a "why", and none is unjustified
- [ ] Every foreign key has an index, and every uniqueness rule is enforced by a unique index
- [ ] Column limits match validation limits (`install_id` ≤ 64, `name` ≤ 100, `push_token` ≤ 255)
- [ ] Migration is reversible and safe on the production table size

---

## Method Contracts

**`Mobile::SignIn`** (Service)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `.call(email:, password:, device:)` | strings; device hash (`install_id`, `platform`, `name`, `app_version`) | `Result` with `kind` ∈ `:session, :challenge, :invalid, :locked, :not_investor, :finish_2fa_setup, :undeliverable` and payload | — | Devise `valid_for_authentication?` (failed_attempts); code delivery for SMS/WA; device registration on `:session` | No, each call is a login attempt |
| `.verify(challenge:, code:, device:)` | strings, hash | `Result` `:session, :invalid_code, :locked, :expired, :spent` | — | Attempt counter; `lock_access!` on 5th; claims challenge on success | Yes once claimed (a second call returns `:spent`) |

**`TwoFactorVerifier`** (Service, extracted)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `.verify(user, code)` | User, string | `Result(ok?, reason)`: `:ok, :invalid, :expired` | — | Marks TOTP `consumed_timestep` (replay guard) or Twilio verification consumed | Not for TOTP (by design: replay-protected) |
| `.deliver_code(user)` | User | `:sent`, `:undeliverable`, `:rate_limited`, `:not_needed` (TOTP) | — | Twilio SMS / `SendOtpToWhatsappJob` via `OtpSmsRateLimiter` | No |

**`MobileDevice`** (Model)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `.register!(user, install_id:, platform:, name:, app_version:)` | | `[device, DeviseApi::Token]` | `ActiveRecord::RecordInvalid` | Upsert, revoke the old token, mint a new token (access 3600 s; refresh 90 d), LRU-evict beyond 10 | Re-running revokes and re-mints, which is safe |
| `.authenticate(access_token)` | string | device or nil | — | Touches `last_used_at` when older than 5 min | Yes |
| `#refresh!(refresh_token)` | string | `DeviseApi::Token` or nil | — | Revokes the current token, mints a new one | No (rotation). Reusing an old refresh token returns nil |
| `#revoke!(reason:)` | string | true | — | `revoked_at`, `revoked_reason`, token `revoked_at`, `push_token` nil | Yes |
| `#update_push!(token:, enabled:)` | | device | — | Clears the same token on other rows; `push_status` | Yes |
| `#mark_not_registered!` | | device | — | `push_status` not_registered | Yes |
| `.live`, `.pushable` | scopes | relation | — | — | — |

**`Mobile::HomeSummary`**, **`Mobile::PushCategory`**, **`Mobile::DeepLink`**,
**`Evergreen::LpCardSummary`** (Services)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `HomeSummary.call(user:, scope:)` | user, `policy_scope` proc | `{todo: [...], cards: [...]}` | — | none | Yes |
| `PushCategory.for(event)` | `Noticed::Event` | `:capital_calls / :distributions / :documents / :other` | — | none | Yes |
| `PushCategory.enabled_for?(user, event)` | | bool | — | none | Yes |
| `DeepLink.for(notification)` | `Noticed::Notification` | `"/capital-calls/9031"` or `"web:/approvals/55"` | — | none | Yes |
| `LpCardSummary.call(capital_commitment)` | | `{value, units, nav_per_unit, nav_date, gain, …}` | — | none | Yes |

**`DeliveryMethods::ExpoPush`**, **`Mobile::ExpoPushClient`**, **`ExpoPushReceiptsJob`**

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `ExpoPush#deliver` | (Noticed) | — | `Mobile::ExpoPushClient::TransientError` (5xx / timeout / 429) | Delivery rows; Expo POST; `last_push_at`; enqueue receipts | Yes, via unique delivery rows |
| `ExpoPushClient#send_messages(messages)` | ≤ 100 hashes | Array of tickets `{status, id \| details.error}` | `TransientError`, `PermanentError` | HTTP | No |
| `ExpoPushClient#receipts(ids)` | ≤ 300 ids | `{id => {status, details}}` | `TransientError` | HTTP | Yes |
| `ExpoPushReceiptsJob#perform(delivery_ids)` | Array | — | (retries on Transient) | Delivery `status`/`error`; `mark_not_registered!` | Yes |

**Reviewer checks**
- [ ] Every raised error is handled by a caller or listed in Error Mapping
- [ ] Anything a retry can repeat is idempotent (`ExpoPush#deliver`, receipts job)
- [ ] `TwoFactorVerifier` covers every branch that `Users::TwoFactorController` had (diff the branch list in review)

---

## Controllers, Params and Responses

All mobile controllers inherit `Api::Mobile::V1::BaseController < ActionController::API`
(`include Pundit::Authorization`, `ActionController::MimeResponds`), with
`after_action :verify_authorized` (or `verify_policy_scoped` on index). Prefix: `/api/mobile/v1`.

| Action | Permitted params | Policy method | Success response | Failure response |
|---|---|---|---|---|
| `SessionsController#create` (skips auth) | `email, password, device: [:install_id, :platform, :name, :app_version]` | none (pre-auth) | 201 `{access_token, refresh_token, expires_in, device_id}` / 202 `{challenge, method, destination_hint}` | 401 `invalid_credentials` · 403 `not_investor` / `finish_2fa_setup` · 423 `locked` · 503 `code_undeliverable` |
| `#verify` (skips auth) | `challenge, code, device: [...]` | none | 201 tokens | 422 `invalid_code` `{attempts_left}` · 423 · 401 `challenge_expired` / `challenge_spent` |
| `#resend` (skips auth) | `challenge` | none | 204 | 429 `rate_limited` · 401 |
| `#refresh` (skips auth) | `refresh_token` | none | 201 tokens | 401 |
| `#destroy` | — | `authorize current_device, :destroy?` | 204 | 401 |
| `MeController#show` | — | `authorize current_user, :show?` | 200 `{user:{name,email,locale}, region, date_format, time_format, personas_count, push_preferences}` | 401 |
| `MeController#push_preferences` | `push_preferences: [:capital_calls, :distributions, :documents, :other]` | `:update?` on self | 200 | 422 |
| `PersonasController#index` / `#switch` | `:investor_advisor_id` | `policy_scope(InvestorAdvisor)` / `authorize advisor, :switch?` | 200 | 404 |
| `HomeController#show` | — | `policy_scope(CapitalCommitment)`, `policy_scope(CapitalRemittance)`, `policy_scope(Document)` | 200 `{todo:[{type, id, title, amount, due_date, link}], cards:[{kind, commitment_id, fund_name, entity_name, currency, committed, called, called_pct, due, distributed} \| evergreen fields]}` | 401 |
| `CommitmentsController#show/#calls/#distributions/#documents` | `id, page` | `authorize cc, :show?` then scoped children | 200 `{items, next_page}` | 404 |
| `CapitalRemittancesController#show` | `id` | `authorize remittance, :show?` | 200 `{id, call_name, fund_name, status, call_amount, collected_amount, due_amount, due_date, notice_document_id}` | 404 |
| `DocumentsController#index` | `q (≤100), commitment_id, to_sign, page` | `policy_scope(Document)` | 200 | — |
| `DocumentsController#show` | `id` | `authorize doc, :show?` (existing NDA gate) | 200 `{id, name, content_type, file_url (expires 5 min), sign_action, signature_status}` | 404 |
| `NotificationsController#index/#read/#read_all` | `page`, `id` | `current_user.notifications` (owner scoping; `authorize n, :update?`) | 200 / 204 | 404 |
| `DevicesController#update` | `push_token, push_enabled, app_version` | `authorize current_device, :update?` | 200 | 422 |
| `WebHandoffsController#create` | `path (≤500)` | `authorize current_user, :show?` | 201 `{url}` | 422 `invalid_path` |
| `Users::MobileHandoffsController#show` (web) | `token, path` | none (credential) | 302 to path | 302 to sign-in |
| `Users::MobileDevicesController#index/#destroy` (web) | `id` | `policy_scope(MobileDevice)`, `authorize device, :destroy?` | HTML / turbo_stream | 404 |

Amounts are serialised as strings in major units with currency (`{"amount":"7500000.00",
"currency":"INR"}`) to avoid float issues. Dates are ISO in the payload, and the app formats them
with `date_format`.

**Reviewer checks**
- [ ] No action without `authorize` / `policy_scope` (`verify_authorized` on)
- [ ] Permitted params can't set `entity_id`, `user_id` or other ownership fields
- [ ] 404 (not 403) for out-of-scope records on the mobile API

---

## Queries and Indexes

| Where | Query shape | Index used | Rows expected | Preload / batching |
|---|---|---|---|---|
| `MobileDevice.authenticate` | `DeviseApi::Token.find_by(access_token:, revoked_at: nil)` → `MobileDevice.live.find_by(devise_api_token_id:)` | `index_devise_api_tokens_on_access_token`; `devise_api_token_id` | 1 | — |
| `HomeSummary` cards | `policy_scope(CapitalCommitment).select(:id, :fund_id, :entity_id, :investor_id, :unit_type, *money cols).includes(:fund, :entity)` | existing investor/entity scope indexes | ≤ 50 | `includes(fund: :evergreen_fund_setting)` only for evergreen |
| `HomeSummary` to-do calls | `policy_scope(CapitalRemittance).where(status: %w[Pending Overdue]).joins(:capital_call).order("capital_calls.due_date").limit(20)` | existing remittance scope + `capital_calls` PK | ≤ 20 | `includes(:capital_call, :fund)` |
| `HomeSummary` to-do docs | `policy_scope(Document).where(sent_for_esign: true).joins(:e_signatures).where(e_signatures: {user_id:}).where.not(e_signatures: {status: "signed"}).distinct.limit(20)` | `index_e_signatures_on_user_id` | ≤ 20 | — |
| Fund calls / distributions | `cc.capital_remittances` / `cc.capital_distribution_payments` ordered by date desc, `limit 25 offset` | existing `capital_commitment_id` indexes | 25 / page | select listed columns only |
| Documents index | `policy_scope(Document).not_template.where.not(folder_id: nda_gated_folder_ids).order(id: :desc).limit(25).offset` | documents scope indexes | 25 / page | `includes(:folder)` |
| Notifications | `current_user.notifications.order(created_at: :desc).limit(25)` | `recipient` index on `noticed_notifications` | 25 | `includes(:event)` |
| Push gate | `recipient.mobile_devices.pushable.exists?` | `[user_id, revoked_at, last_used_at]` | 1 | — |
| Unread badge | `current_user.notifications.unread.count` | recipient + `read_at` | count | — |

**Reviewer checks**
- [ ] Every query is scoped by the existing policy scope (entity/investor access), or explains why not
- [ ] No N+1 on list endpoints (bullet clean in features). No unbounded loads (`limit` everywhere)
- [ ] No `includes(:capital_remittances)`, `includes(:account_entries)` or `.blank?`/`.present?` on relations

---

## Transactions, Locking and Concurrency

| Operation | Transaction scope | Lock | Race it prevents | Idempotency key |
|---|---|---|---|---|
| `MobileDevice.register!` | Device upsert + old token revoke + new token + LRU eviction | `user.lock!` | Two parallel sign-ins exceeding 10 devices; duplicate rows | unique `[user_id, install_id]` |
| `#refresh!` | Revoke current + mint new + repoint | `device.lock!` | Two refreshes both succeeding | rotation (old refresh → `previous_refresh_token`) |
| `#update_push!` | Clear the token elsewhere + set here | none (unique index; rescue `RecordNotUnique` → retry once) | Same token on two rows | unique `push_token` |
| `ExpoPush#deliver` | Per device: `create!` the delivery row (pending) **outside** HTTP; after the HTTP call, update the rows | none | Double push on job retry | unique `[noticed_notification_id, mobile_device_id]`; skip rows already `sent` |
| Challenge verify | Cache `increment` of attempts; claim via `Rails.cache.delete` returning true | atomic Redis ops | Parallel verifies with the same challenge | challenge nonce |

**Reviewer checks**
- [ ] No external HTTP call or email inside a transaction (Expo, Twilio outside)
- [ ] Lock order is consistent: user before device everywhere

---

## Background Jobs

| Job | Queue | Trigger | Retry / backoff | Discard on | Concurrency guard | Timeout |
|---|---|---|---|---|---|---|
| Noticed delivery job for `:push` | existing notifications queue | `deliver_by :push` | Noticed default: 5, polynomial | `ActiveRecord::RecordNotFound` | delivery-row unique index | HTTP 5 s open / 10 s read |
| `ExpoPushReceiptsJob` | `:low` | `perform_in(15.minutes)` from `deliver` | 3, polynomial | `RecordNotFound` | idempotent updates | 10 s |
| `MobilePushDeliveriesPurgeJob` | `:low` | cron monthly (sidekiq-cron, non-local envs) | 1 | — | `in_batches(of: 1000)` | — |

**Reviewer checks**
- [ ] A job that runs twice, or out of order, is harmless
- [ ] The cron entry is registered in the sidekiq-cron schedule used in production, not only locally

---

## External Integrations

| Call | Method + path | Auth | Timeouts | Rate limit handling | Error → exception |
|---|---|---|---|---|---|
| Send push | `POST https://exp.host/--/api/v2/push/send` (array ≤ 100, gzip) | `Authorization: Bearer <EXPO_ACCESS_TOKEN>` (enhanced security on) | 5 s / 10 s | 429 → `TransientError` (job retry) | 5xx/timeout → `TransientError`; 400/401 → `PermanentError` (log, no retry); per-ticket `DeviceNotRegistered` → `mark_not_registered!` immediately |
| Receipts | `POST https://exp.host/--/api/v2/push/getReceipts` (≤ 300 ids) | same | 5 s / 10 s | as above | as above |
| Digio signing page | Opened by the app only (no server call) | — | — | — | — |
| Twilio / WhatsApp OTP | existing `TwilioSmsVerification`, `SendOtpToWhatsappJob` | existing | existing | `OtpSmsRateLimiter` | existing → `:undeliverable` |

**Reviewer checks**
- [ ] The Expo access token is never logged. Request bodies are logged at debug only, without push tokens
- [ ] Every non-2xx status maps to a named exception

---

## Error Mapping and Logging

| Exception | Raised in | Handled by | User sees | Logged / alerted |
|---|---|---|---|---|
| `Pundit::NotAuthorizedError`, `ActiveRecord::RecordNotFound` | ④ actions | `BaseController rescue_from` → 404 `not_found` | App: "You no longer have access to this item" | info |
| Missing/invalid token | `authenticate_mobile_device!` | 401 `unauthorised` | App: sign-in screen | info with `device_id` if known |
| App too old | `require_app_version!` | 426 `update_required` | Update screen | info |
| `ActionController::ParameterMissing` | any | 422 `invalid_request` | "Something went wrong — Try again" | warn |
| `Mobile::ExpoPushClient::TransientError` | ⑥ | Noticed retry; final failure → Sentry | none (email still sent) | warn with `notification_id`, `device_id` |
| `Mobile::ExpoPushClient::PermanentError` | ⑥ | rescued in `deliver`, delivery rows failed | none | error + Sentry (configuration problem) |
| Twilio failure | `TwoFactorVerifier.deliver_code` | `:undeliverable` → 503 | "We couldn't send your code — try again" | error + Sentry |
| `CrossSiteLink` verify failure | ⑦ web landing | redirect to sign-in | Website sign-in page | `[mobile_handoff] rejected reason=...` |

**Reviewer checks**
- [ ] No bare `rescue => e` that swallows errors silently
- [ ] Log lines carry `user_id`, `device_id`, `notification_id` as applicable, never tokens or codes

---

## Security Review

| Concern | Decision |
|---|---|
| Authorization | Existing Pundit policies only. `verify_authorized` on every mobile action. Device policies limit users to their own rows |
| Tenant isolation | All data reads through existing `policy_scope` (entity + investor access scoping). Push recipients are the existing notifier recipients, minus members of the sending entity |
| Authentication | Password via Devise `valid_for_authentication?` (lockable). 2FA mandatory when enabled. Tokens are minted only by `MobileDevice.register!`. Every request requires a live device. The devise-api 2FA-less tokens are refused (X7) |
| Secrets | Expo access token in per-region credentials (`mobile.expo_access_token`). Phone tokens live in Keychain/Keystore via `expo-secure-store` (`WHEN_UNLOCKED_THIS_DEVICE_ONLY`). `filter_parameters` += `password code challenge refresh_token access_token push_token token` |
| Brute force | Rack::Attack: `mobile/session/ip` 10/min, `mobile/session/email` 5/min, `mobile/verify/challenge` covered by the 5-attempt cap |
| Input / output sanitisation | JSON only. Push bodies use `full_sanitizer`. Hand-off `path` must be a relative, recognised route (no `//`, no scheme, ≤ 500 chars) |
| Mass assignment | Explicit permitted params (table above). No ownership fields |
| Transport | HTTPS only (SiteRegistry). ATS default on iOS. `usesCleartextTraffic=false` on Android |
| Enumeration | Wrong email and wrong password give the same 401 and timing. Region mismatch is indistinguishable |
| Device loss | Website Devices › Sign out takes effect on the next request. Biometric lock after 5 min background. App switcher privacy overlay |

**Reviewer checks**
- [ ] A user from another entity cannot reach any record through any mobile route, job or hand-off
- [ ] A devise-api token from `/users/tokens/sign_in` gets 401 on every `/api/mobile/v1` route
- [ ] A user with 2FA enabled cannot obtain tokens without a verified code (H1, X2)

---

## Configuration and Rollout

| Item | Value / location |
|---|---|
| Credentials / env vars | Per region, independent: `Rails.application.credentials.mobile[:expo_access_token]`, `mobile[:min_app_version]` (default "1.0.0"). IN and US never share values |
| App config | `mobile/app.config.js`: region list `{IN: https://<in host>, US: https://<us host>}` per EAS profile (development / staging / production), deep-link scheme `caphive`, associated domains per region host |
| Feature flag | None on the server: everything is dormant until a device registers. Kill switch: remove `expo_access_token` from credentials, which disables push (X20) |
| Cron / schedules | `MobilePushDeliveriesPurgeJob` monthly |
| Deploy order | migrations → server code (phases 1–4) → TestFlight / Play internal (pilot GP's LPs) → store release |
| Rollback | Revert code. The tables can stay (unused). Revoking all devices (`MobileDevice.live.find_each { revoke! }`) logs every phone out |
| Store setup | Apple Developer + Google Play accounts, bundle id `com.caphive.lp`, App Store privacy labels (no tracking), Universal Links `apple-app-site-association` and `assetlinks.json` served by Rails from `public/.well-known/` |

**Reviewer checks**
- [ ] Safe to deploy with the feature unused, and safe to roll back
- [ ] No IN credential, URL or token appears in US config, or the reverse

---

## Test Plumbing

| Feature file | Stubs / fixtures | Factories | New step definitions |
|---|---|---|---|
| `features/mobile/mobile_sign_in.feature` | ROTP for TOTP codes; existing Twilio stub; `travel_to` for expiry | existing `:user` with 2FA traits | `When I sign in from a phone as {string} with password {string}`, `And I verify the phone code`, `Then the phone gets a session` |
| `features/mobile/mobile_devices.feature` | — | `:mobile_device` (new) | `Given {string} has a phone {string}`, `When I sign out the phone {string} on the Devices page` (Playwright) |
| `features/mobile/mobile_data.feature` | existing fund/call/distribution setup steps | existing | `When the phone requests {string}`, `Then the JSON at {string} is {string}` |
| `features/mobile/push_delivery.feature` | `features/support/expo_push_stub.rb` (WebMock on exp.host; records messages; configurable ticket/receipt errors) | `:mobile_device` with push token | `Then {int} push(es) were sent to {string}`, `Then the push body is {string}` |
| `features/mobile/mobile_web_handoff.feature` | — | — | `When I open the hand-off for {string}` (Playwright) |
| `mobile/e2e/*.yaml` (Maestro) | Staging seed task `mobile:seed_e2e`; `EXPO_PUBLIC_E2E=1` mocks Digio and biometrics | — | Each flow begins `# <ID> — …` |

Every run: `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/mobile/<file>.feature`, with
Redis up on 6379.

---

## Mobile App Build Detail

| Decision | Value |
|---|---|
| Toolchain | Expo SDK (latest stable at build), TypeScript strict, expo-router v4+, EAS Build + Submit + Update |
| Packages | `@tanstack/react-query` + persister on `react-native-mmkv`; `expo-secure-store`; `expo-local-authentication`; `expo-notifications`; `expo-web-browser` (`openAuthSessionAsync`); `@react-native-community/netinfo`; `react-native-pdf` (inline PDF, dev client); `expo-haptics`; `expo-sharing` |
| Styling | A local fixed theme (graphite + CapHive orange, Manrope, `expo-linear-gradient` sheens, `react-native-svg` gauge, Ionicons). No UI kit, keeping it small. Status components render icon + label + colour |
| API client | One `fetch` wrapper: base URL from region, Bearer, `X-App-Version`, `Accept-Language`. On 401 it tries a single refresh and otherwise signs out. 426 shows the update screen |
| Cache | Query cache persisted (data only), max age 7 days, cleared on sign-out or region change |
| OTA updates | EAS Update for JS-only fixes on the `production` channel. Native changes go through the stores |
| Tests | Maestro flows in `mobile/e2e/`, plus `tsc --noEmit` and eslint in CI |

**Reviewer checks**
- [ ] Tokens are never written to MMKV, logs or crash reports
- [ ] Push permission is requested only after the first sign-in
- [ ] Every pressable has `accessibilityLabel`, and hit slop is at least 44 pt

---

## Project Rules Checklist

| Rule | Applies? | How it is met |
|---|---|---|
| No `blank?`/`present?` on relations; use `exists?`/`none?` | Applies | Push gate uses `pushable.exists?`; reviewed in Queries |
| Dedup in SQL (`distinct.pluck`), batch bulk operations (`find_each`/`in_batches`) | Applies | To-do docs use `.distinct`; purge job uses `in_batches`; revoke-all uses `find_each` |
| Select only needed columns when loading many `account_entries`; no speculative `includes` of big associations | Applies (partly) | No `account_entries` reads; no `includes` of remittances, payments or documents on commitments; select lists on list endpoints |
| Screen dates via `l(...)`; emails render `Mon dd, yyyy` via `EmailDateLocalization`; no human-format `strftime` | Applies | Website Devices page uses `l(...)`; API sends ISO dates plus the locale's `date.formats.default` pattern; no new emails |
| Date inputs use `f.date_field` / `date_field_tag`; JS dates via `locale_date_format.js` | N/A | No date inputs. The app mirrors the same strftime approach natively |
| Every query entity-scoped; Pundit `authorize`/`policy_scope` on every action | Applies | `verify_authorized` on the mobile base controller; existing scopes |
| MCP tool surfaces changed only via the ontology YAML | N/A | No MCP tools changed |
| Cucumber only (no RSpec); `TEST_ENV_NUMBER=$RANDOM` on every run | Applies | Server rows in Cucumber; app rows in Maestro (agreed 2026-10-13); no RSpec |
| `bundle exec rubocop` clean, including `IRM/RelationBlankPresent` | Applies | Run per phase |

---

## Sign-off

| Reviewer | Date | Decision | Notes |
|---|---|---|---|
| | | | |
