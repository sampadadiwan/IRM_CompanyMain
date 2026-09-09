# Two-factor: every gate, switch and validation

**What this is for.** Three delivery modes (authenticator, WhatsApp, SMS), each gated by a
different combination of environment variable, database column and computed check. When a
user reports "the SMS option isn't there" or "I can't save this phone number", this page
says which gate closed and where to look. Nothing here is new policy — it is the current
code, written down in one place.

Companion to [`twilio_sms_otp_design.md`](twilio_sms_otp_design.md), which explains *why*
the SMS controls are shaped this way. This page is the *what*.

---

## 1. What switches two-factor on and off

Read top to bottom: an outer layer being off makes every layer below it irrelevant.

| Layer | Switch | Where it lives | Default | Scope | Effect when off |
|---|---|---|---|---|---|
| Deployment | `SMS_OTP_ENABLED` | `.env.<rails_env>.<variant>` | `false` | SMS only, every tenant on that deployment | SMS mode hidden everywhere; sends refused before any API call |
| Twilio account | Verify service credentials | `config/credentials/<env>.<variant>.yml.enc` | — | SMS only, whole account | `no_verify_service_configured` logged, delivery recorded as failed |
| Twilio account | **Geo Permissions** | Twilio console | — | SMS only, whole account | Twilio rejects the send. **The app cannot see this in advance** — the user enrols, then cannot log in |
| User | `users.two_factor_enabled` | User form toggle | `false` | That user, all modes | No 2FA challenge at all; password alone signs them in |
| User | `users.two_factor_mode` | Chosen by the user at enrollment | `nil` | That user | `nil` sends them to the mode-selection screen on next login |
| User | `users.whatsapp_enabled` | User form checkbox | `false` | That user, WhatsApp only | WhatsApp row renders greyed out with "contact your administrator" |
| User | `users.phone` / `call_code` | User form | — | That user, WhatsApp + SMS | Both phone modes disappear; authenticator is preselected |

**Two traps in this table.**

`entity.permissions.enable_whatsapp?` is **not** in it. That permission gates WhatsApp
*notifications* (`app/packs/core/notifications/delivery_methods/whats_app.rb`), not WhatsApp
two-factor. `whatsapp_otp_enabled?` checks only `whatsapp_enabled? && phone.present?`, so an
entity with the permission off still offers WhatsApp 2FA. Easy to assume otherwise.

`CURRENT_SITE` used to gate SMS destinations and no longer does. It now only sets the
libphonenumber parsing region for numbers stored without a country code
(`SmsDeliverable.default_region`). See §5.

---

## 2. Mode availability — every condition, in evaluation order

Each mode is offered only when **every** row for it is true. Evaluation stops at the first
failure.

### Authenticator

| # | Condition | Where |
|---|---|---|
| 1 | `two_factor_enabled?` | `TwoFactorDispatch#two_factor_challenge_path_for` |

Always available. It is the fallback that needs no phone, no signal and no vendor, which is
why it is preselected whenever WhatsApp is unavailable.

### WhatsApp — `whatsapp_otp_enabled?`

| # | Condition | Where | User sees when false |
|---|---|---|---|
| 1 | `whatsapp_enabled?` | `users.whatsapp_enabled` column | Row visible but disabled: "Not enabled for your account — contact your administrator" |
| 2 | `phone.present?` | same column the form writes | Whole row omitted (the `phone.present?` wrapper hides both phone modes) |

### SMS — `sms_otp_enabled?` = `SmsDeliverable.feature_enabled? && sms_available?`

| # | Condition | Where | User sees when false |
|---|---|---|---|
| 1 | `ENV["SMS_OTP_ENABLED"] == "true"` | `SmsDeliverable.feature_enabled?` | Row omitted entirely |
| 2 | `phone` parses at all | `SmsDeliverable#parsed_phone` | Row omitted entirely |
| 3 | `parsed.valid?` | `sms_available?` | Row omitted entirely |
| 4 | mobile or fixed-or-mobile line type | `mobile_phone?` | Row omitted entirely |

**The asymmetry in the last column is deliberate and is the thing that confuses people.** An
unavailable WhatsApp row still renders, greyed out, with a reason. An unavailable SMS row is
omitted with no explanation. So a landline user sees a disabled WhatsApp option and simply no
SMS option, which reads as "WhatsApp lost, SMS was never built" when in fact both failed
their own checks.

### Where each gate is re-checked

The mode-selection screen is not a security boundary — the POST behind it is unauthenticated
(the user is mid-2FA and signed out), so every gate is checked again server-side.

| Point | Re-checks | Why |
|---|---|---|
| `select_mode` view | all | Renders the options |
| `select_mode_post` | `whatsapp_otp_enabled?`, `sms_otp_enabled?` | Attacker-controlled body; without it a user can set themselves to a mode they can never satisfy and lock their own account out |
| `enroll_sms` (GET) | `sms_otp_enabled?` + cooldown | A GET that spends money |
| `send_sms` (POST) | `sms_otp_enabled?` + cooldown | Costs money per call |
| `TwoFactorDispatch` at login | `sms_otp_enabled?` | The number or the kill switch may have changed since enrollment |
| `TwilioSmsDelivery#check_number_usable` | `normalized_sms_number` + `sms_otp_enabled?` | Last gate before spending money; a second caller cannot bypass it |

---

## 3. Field validations on `User`

| Field | Rule | Fires when | Notes |
|---|---|---|---|
| `first_name`, `last_name` | presence | always | |
| `email` | presence, `/\A[^@\s]+@[^@\s]+\z/` | always | Deliberately loose |
| `call_code` | presence | `phone.present?` | |
| `call_code` | length ≤ 3 | always | |
| `phone` | length ≤ 100 | always | `investor_accesses.phone` is capped at 15 and truncated on sync |
| `phone` | **normalized**: `delete("^0-9")` | on assignment | Strips spaces, dashes, brackets — **and the `+`** |
| `phone` | `phone_must_be_dialable` | `phone.present? && call_code.present? && (phone_changed? \|\| call_code_changed?)` | See below |

### `phone_must_be_dialable`

| Aspect | Decision | Reason |
|---|---|---|
| Test applied | `parsed_phone&.valid?` | Same parse as `sms_available?`, so the form and the SMS gate cannot disagree |
| Landlines | **Accepted** | `users.phone` is the app-wide contact number, not just the OTP path. A landline still fails `sms_available?` and is simply never offered SMS |
| Country | **Not checked** | Any country's valid number is storable — see §5 |
| When it runs | **Only when the number changes** | A fifth of existing rows hold unparseable numbers. Validating them unconditionally would block unrelated edits — a role change, a permission toggle — on users whose phone column someone else got wrong years ago |
| When `call_code` is blank | Skipped | The presence validation above owns that message; both firing reads as two problems |

**What this does not cover.** The validation is a data-entry guard, not a database
constraint, so `sms_available?` must keep re-checking rather than trusting the column. Three
kinds of writer get past it:

| Writer | How it bypasses | Why it must |
|---|---|---|
| `update_columns`, `update_all` | Skip validation by definition | Bulk and internal writes |
| `UsersSyncController` | Sets `skip_phone_validation` | The origin region is authoritative for its own users. A refusal answers 422 and never stamps `last_synced_ccf_hex`, so the sender retries that payload forever and replication sticks permanently |
| `InvestorAccess#update_user` | Sets `skip_phone_validation` | `investor_accesses.user_id` is nullable and the `belongs_to` autosave discards a failed `save`, so a refusal silently yields an access row pointing at nobody |

Both flagged paths accepted any number before this validation existed. The opt-out keeps them
exactly as they were rather than making them the first casualties of a form-level rule.

**Known rough edge.** The normalizer strips `+` before validation runs, so pasting
`+91 9449 025878` into the form stores `919449025878`; with `call_code = "91"` that parses as
`+91919449025878` and is rejected. The user is now told, rather than silently losing SMS —
but the message ("not a valid phone number for country code +91") does not explain that the
country code was doubled.

---

## 4. Number examples

Real outcomes, useful when reading a support ticket. `sms_available?` needs *valid* **and**
*mobile*; `phone_must_be_dialable` needs only *valid*.

| `call_code` | `phone` | Parses as | Valid | Line type | Saves | SMS offered |
|---|---|---|---|---|---|---|
| 91 | 9449025878 | +919449025878 | ✅ | mobile | ✅ | ✅ |
| 91 | 944902587 | +91944902587 | ❌ (9 digits) | — | ❌ | ❌ |
| 91 | 8028319623 | +918028319623 | ✅ | fixed line | ✅ | ❌ landline |
| 91 | 1234567890 | +911234567890 | ✅ | fixed line | ✅ | ❌ landline |
| 1 | 4155550134 | +14155550134 | ✅ | fixed-or-mobile | ✅ | ✅ |
| 1 | 9449025878 | +19449025878 | ❌ (no such area code) | — | ❌ | ❌ |
| 44 | 7400123456 | +447400123456 | ✅ | mobile | ✅ | ✅ |
| 44 | 7700900123 | +447700900123 | ❌ (Ofcom drama range, unassignable) | — | ❌ | ❌ |
| 91 | *(blank)* | — | — | — | ✅ | ❌ no number |

US-format numbers in the `555-01xx` range parse as valid; the UK `7700 900xxx` range does
not. Both are "fictional number" ranges, and libphonenumber treats them differently — worth
knowing before picking test data.

---

## 5. Destination countries

**There is no application-side destination allowlist.** Any valid mobile number may be
texted, from any deployment. `SmsDeliverable.allowed_countries` was removed: it refused real
users, because a US-deployment account holding an Indian mobile is ordinary rather than
suspicious, and such a user was shown no SMS option with nothing on screen to explain it.

| Concern | Before | Now |
|---|---|---|
| Which destinations the app will dial | `CURRENT_SITE` → `US` or `IN` only | Any valid mobile |
| Which destinations Twilio will dial | Geo Permissions (backstop) | Geo Permissions (**only** control) |
| Parsing region for a bare number | `allowed_countries.first` | `SmsDeliverable.default_region` — `IN` on the IN deployment, `US` elsewhere |
| Where a bad destination is refused | At enrollment, mode still selectable | At send time, after the user has enrolled |

**Operationally this moves work into the Twilio console.** Geo Permissions is now
load-bearing rather than redundant:

- Every country enabled there is a country this application will dial.
- A country the app offers but Geo Permissions blocks produces the worst failure in the
  system: the user enrols in SMS successfully, then cannot log in, and **SMS mode issues no
  backup codes** — recovery is an administrator reset.

`OtpSmsRateLimiter` is unchanged and remains the control that sees a toll-fraud pattern
spread across accounts.

---

## 6. Rate limits and cooldowns

| Limit | Value | Keyed on | Stored in | Enforced in |
|---|---|---|---|---|
| One code in flight | 1 per 60s | destination number | `Rails.cache` | `OtpSmsRateLimiter` |
| Hourly | 5 per hour | destination number | `Rails.cache` | `OtpSmsRateLimiter` |
| Daily | 10 per 24h | destination number | `Rails.cache` | `OtpSmsRateLimiter` |
| Daily | 10 per 24h | user | `Rails.cache` | `OtpSmsRateLimiter` |
| Long window | 50 per 30 days | destination number | **`otp_deliveries` table** | `OtpSmsRateLimiter` |
| Resend endpoint | 3 per 60s | client IP | Rack::Attack | `config/initializers/rack_attack.rb` |
| UI cooldown | `min_number_window` (60s) | session | cookie | `TwoFactorController#recently_sent_sms?` |
| Failed code entries | 3, then re-login | session | cookie | `TwoFactorController#create` |
| Verify attempts | 5 per verification | Twilio | Twilio | Twilio Verify |

The 30-day window is counted in the database rather than the cache on purpose: SolidCache
trims by age and size regardless of `expires_in`, so a 30-day counter in the cache would
reset weekly while claiming to enforce 50/30 days.

The per-number keys hash the **normalized** number. Hashing the raw column would let the
same handset be re-saved in a different format to reset its own limit.

---

## 7. What the user sees when a gate closes

| Situation | Where they hit it | Message | Recovery |
|---|---|---|---|
| No phone stored | mode selection | Phone modes absent, authenticator preselected | Admin adds a number |
| WhatsApp not enabled | mode selection | Row greyed: "contact your administrator" | Admin ticks `whatsapp_enabled` |
| Number not textable | mode selection | SMS row simply absent | Admin corrects the number |
| Forced SMS via crafted POST | `select_mode_post` | "Text message codes are not available for your account." | Choose another mode |
| Kill switch thrown mid-enrollment | `enroll_sms` | "Text message codes are not available for your account." | Choose another mode |
| Resend too soon | `send_sms` | "Please wait a moment before requesting another code." | Wait 60s |
| Durable limit hit | inside the job | "A new code is on its way" — then nothing arrives | Wait for the window; check `otp_deliveries` |
| SMS-mode user whose number went bad | login | Refused before the code box: "contact your administrator" | Admin reset of the 2FA method |
| 3 wrong codes | login | "Too many failed attempts. Please sign in again." | Sign in again |

The "durable limit hit" row is the one that reads as a bug in a support ticket. The endpoint
answers optimistically because the send is asynchronous, and the per-number limit is enforced
later, inside the job. Claiming success for a message that never went out was judged the
lesser evil versus making the endpoint an oracle for probing the thresholds — but it means
"it said a code was sent and none came" is an expected report, answerable from
`otp_deliveries`.

---

## 8. Backup codes

| Mode | Backup codes | Consequence |
|---|---|---|
| Authenticator | 8, generated at enrollment, shown once | User can self-recover a lost device |
| WhatsApp | **None** | Lost number → administrator reset |
| SMS | **None** | Lost number → administrator reset |

Who may reset a method (`UserPolicy#reset_two_factor?`): the user themselves (they re-prove
their password inside `TwoFactorReset`), a company admin of the same entity, or support. Only
once a method has actually been chosen — before that the user is already headed for the
mode-selection screen.

A reset clears `two_factor_mode` back to `nil`, which is why it needs no login-flow changes:
the `nil` branch in `TwoFactorDispatch` already routes to mode selection.

---

## 9. Where the code lives

| Concern | File |
|---|---|
| Phone parsing, eligibility, region | `app/packs/core/users/models/concerns/sms_deliverable.rb` |
| Mode predicates, send helpers, backup codes | `app/packs/core/users/models/concerns/two_factor_authenticatable.rb` |
| Field validations | `app/packs/core/users/models/user.rb` |
| Login branch across all three modes | `app/packs/core/users/controllers/concerns/two_factor_dispatch.rb` |
| Enrollment, verification, resend | `app/packs/core/users/controllers/users/two_factor_controller.rb` |
| Twilio Verify send | `app/packs/core/users/services/twilio_sms_delivery.rb` |
| Twilio Verify check | `app/packs/core/users/services/twilio_sms_verification.rb` |
| Rate limits | `app/packs/core/users/services/otp_sms_rate_limiter.rb` |
| Delivery audit rows | `app/packs/core/users/models/otp_delivery.rb` |
| Coverage | `features/login/two_factor_*.feature`, `features/core/user.feature` |

Tests cannot reach the real Twilio API: `TwilioSmsDelivery.client` raises
`TestEnvironmentSendBlocked` under `RAILS_ENV=test`. Scenarios that exercise sends must be
tagged `@stub-twilio`, which replaces the client with a recorder.
