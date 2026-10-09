# Tasks

> **Reference:** [Design](design.md) · [LLD](lld.md) · [Spec](specs/) · [QA Checklist](qa-checklist.md)

---

## 1. Schema & Models — Revocation + Idempotency

- [ ] 1.1 Create migration `add_reason_to_nda_acceptances`: add `reason` column (text, nullable) to `nda_acceptances`. Verify with `rails db:migrate` and check `db/schema.rb` shows the column. *LLD: Schema Detail → nda_acceptances.*

- [ ] 1.2 Create migration `create_nda_expiry_reminders`: create `nda_expiry_reminders` table with columns `nda_config_id` (bigint, not null, FK), `investor_id` (bigint, not null, FK), `expiry_date` (date, not null), `kind` (string, limit 20, not null), `sent_at` (datetime, not null), timestamps. Add unique index `idx_nda_expiry_reminders_dedup` on `[nda_config_id, investor_id, expiry_date, kind]`. Add FK indexes on `nda_config_id` and `investor_id`. Verify with `rails db:migrate`. *LLD: Schema Detail → nda_expiry_reminders.*

- [ ] 1.3 Update `NdaAcceptance` model: add "revoked" to `STATUSES` constant (`%w[accepted declined revoked]`), add `revoked?` convenience method matching `accepted?`/`declined?` pattern. Verify `STATUSES` includes all three values in console. *LLD: Method Contracts → NdaAcceptance.*

- [ ] 1.4 Create `NdaExpiryReminder` model at `app/packs/core/nda_configs/models/nda_expiry_reminder.rb`: `KINDS = %w[approaching expired]`, `belongs_to :nda_config`, `belongs_to :investor`, `validates :kind, inclusion: { in: KINDS }`, uniqueness validation on `[:nda_config_id, :investor_id, :expiry_date]` scoped to kind (exclude no kind — both are one-shot, unlike ObligationReminder's overdue). Add `.already_sent?(nda_config_id, investor_id, expiry_date, kind)` class method returning boolean via `exists?`. Add `has_many :nda_expiry_reminders` to `NdaConfig`. *LLD: Schema Detail + Method Contracts → NdaExpiryReminder.*

- [ ] 1.5 Update `NdaStatusResolver`: add "Revoked" status derivation — when latest NdaAcceptance has `status == "revoked"`, return `["Revoked", nil]`. Add `:revoked` to `compute_counters`. Verify in console that a revoked acceptance shows "Revoked" status. *LLD: File Map → NdaStatusResolver.*

- [ ] 1.6 Write `features/core/nda_revocation.feature` covering worked examples H3 (GP revokes accepted investor), E3 (revoke unavailable for Pending), E4 (revoke without reason), and the full lifecycle audit trail (accept → revoke → re-accept = 3 NdaAcceptance records). Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/nda_revocation.feature` until green before starting phase 2.

---

## 2. Mailer & Notifiers — Email Infrastructure

- [ ] 2.1 Create `NdaMailer` at `app/packs/core/nda_configs/mailers/nda_mailer.rb` inheriting from `ApplicationMailer`. Define 8 email methods: `nda_accepted`, `nda_acceptance_confirm`, `nda_declined`, `nda_revoked`, `nda_new_version`, `nda_expiry_approaching`, `nda_expired`, `nda_reminder`. Each method accepts a params hash and calls `mail(to:, subject:)`. For GP-direct methods (nda_accepted, nda_declined, nda_expiry_approaching, nda_expired), support a dual code path: when `params[:direct_to]` is present, set `to:` directly (GP external email); otherwise use `setup_defaults` (Noticed LP delivery). Verify class loads in console. *LLD: Method Contracts → NdaMailer.*

- [ ] 2.2 Create 8 mailer view templates at `app/packs/core/nda_configs/views/nda_mailer/`: `nda_accepted.html.erb`, `nda_acceptance_confirm.html.erb`, `nda_declined.html.erb`, `nda_revoked.html.erb`, `nda_new_version.html.erb`, `nda_expiry_approaching.html.erb`, `nda_expired.html.erb`, `nda_reminder.html.erb`. Use `<%= %>` for all dynamic content (auto-escaped). Render dates with `l(date, format: :long)` or `EmailDateLocalization`. Include subject lines matching design.md Part 3 Card ④ table. Verify templates render with `NdaMailer.nda_accepted(test_params).deliver_now` in console. *LLD: File Map → Mailer views.*

- [ ] 2.3 Create `NdaEventNotifier` at `app/packs/core/nda_configs/models/nda_event_notifier.rb` inheriting from `BaseNotifier`. Implement `mailer_name` → `NdaMailer`, `email_method` → `params[:email_method]`, `email_data(notification)` → hash with notification_id, user_id, entity_id, and all template placeholders from params. Required param: `entity_id`. Verify in console that `NdaEventNotifier.with(entity_id: 1, email_method: :nda_acceptance_confirm, record: acceptance).deliver_later(user)` enqueues without error. *LLD: Method Contracts → NdaEventNotifier.*

- [ ] 2.4 Create `NdaReminderNotifier` at `app/packs/core/nda_configs/models/nda_reminder_notifier.rb` inheriting from `BaseNotifier`. Implement `mailer_name` → `NdaMailer`, `email_method` → `:nda_reminder`, `email_data(notification)` → hash with folder_name, folder_link, contact_email. Required param: `entity_id`. *LLD: Method Contracts → NdaReminderNotifier.*

- [ ] 2.5 Create `NdaNotificationRecipients` service at `app/packs/core/nda_configs/services/nda_notification_recipients.rb`. Implement `.resolve(event_type, nda_config, investor, options = {})` returning `{ gp_emails:, lp_users: }` per the resolution rules table in design.md Part 3 Card ②. Use `InvestorAccess.where(entity_id:, investor_id:, approved: true).includes(:user)` for LP users. Parse `notification_emails` JSON for GP emails. Check `exempt_from_nda` via `.exists?`. Exclude signer via `options[:exclude_user_id]`. Verify in console with test data. *LLD: Method Contracts + Queries and Indexes → NdaNotificationRecipients.*

- [ ] 2.6 Write `features/core/nda_notifications.feature` covering worked examples H1 (GP notified on accept), H2 (LP users notified), E1 (no notification_emails), E2 (investor has only one user), and X1 (acceptance not delayed). Use `ActionMailer::Base.deliveries` for email assertions. Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/nda_notifications.feature` until green before starting phase 3.

---

## 3. Triggers — Accept, Decline, Revoke, Version Change

- [ ] 3.1 Add notification trigger to `NdaAcceptancesController#create`: after successful `@nda_acceptance.save`, resolve recipients via `NdaNotificationRecipients.resolve(:accepted, ...)` and send GP emails directly via `NdaMailer.nda_accepted(params).deliver_later` per email, and LP confirmation via `NdaEventNotifier.with(...).deliver_later(user)` per LP user (excluding signer). Verify accept still redirects immediately. *LLD: Controllers → NdaAcceptancesController, Trigger mapping.*

- [ ] 3.2 Add notification trigger to `NdaAcceptancesController#decline`: after successful save, send GP decline email via direct `NdaMailer.nda_declined(params).deliver_later` per notification_email. No LP notification on decline. *LLD: Controllers → NdaAcceptancesController.*

- [ ] 3.3 Add revoke route in `config/routes/core.rb`: `post "nda_status/revoke", controller: "nda_status", action: :revoke, as: :nda_status_revoke`. *LLD: Controllers → Route additions.*

- [ ] 3.4 Add `revoke?` policy method to `NdaStatusPolicy` delegating to `gp_same_entity?`. *LLD: Security Review → Authorization.*

- [ ] 3.5 Implement `NdaStatusController#revoke`: find latest accepted NdaAcceptance for the investor, validate status is "Accepted", create new NdaAcceptance with status "revoked", reason from params, user from current_user. After save, fire revocation notification to LP users via NdaEventNotifier. Respond with Turbo Stream updating the investor row. *LLD: Controllers + Method Contracts.*

- [ ] 3.6 Add version change notification trigger to `NdaConfigsController#update`: after successful `@nda_config.update(...)`, check `@nda_config.saved_change_to_version?`. If true, find investors with stale acceptances (`NdaAcceptance.where(nda_config_id:, status: "accepted").where.not(nda_version: @nda_config.version).select(:investor_id).distinct.pluck(:investor_id)`), resolve LP users per investor, and send version change notification via NdaEventNotifier. *LLD: Queries and Indexes → stale acceptances.*

- [ ] 3.7 Update `features/core/nda_notifications.feature` to add scenarios for decline notification (GP receives, LP does not), revocation notification (LP receives), and version change notification (E8 — stale investors notified, Pending not notified). Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/nda_notifications.feature` until green before starting phase 4.

---

## 4. Reminders — Send Reminders Button + Job

- [ ] 4.1 Add send_reminders route in `config/routes/core.rb`: `post "nda_status/send_reminders", controller: "nda_status", action: :send_reminders, as: :nda_status_send_reminders`. *LLD: Controllers → Route additions.*

- [ ] 4.2 Add `send_reminders?` policy method to `NdaStatusPolicy` delegating to `gp_same_entity?`. *LLD: Security Review → Authorization.*

- [ ] 4.3 Create `NdaReminderJob` at `app/packs/core/nda_configs/jobs/nda_reminder_job.rb`. `perform(nda_config_id)`: find NdaConfig, find Pending investors (from NdaStatusResolver or inline query), for each Pending investor find signatories via NdaSignatory, send reminder via NdaReminderNotifier per signatory. Skip exempt investors. Return count of users notified. *LLD: Background Jobs → NdaReminderJob.*

- [ ] 4.4 Implement `NdaStatusController#send_reminders`: authorize via NdaStatusPolicy, count Pending investors and signatory users, enqueue NdaReminderJob, respond with Turbo Stream flash "Reminders sent to X users". If no Pending investors, respond with 422 + flash. *LLD: Controllers → send_reminders.*

- [ ] 4.5 Write `features/core/nda_reminders.feature` covering worked examples H4 (GP sends bulk reminders), E5 (no pending investors), E6 (exempt investor excluded). Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/nda_reminders.feature` until green before starting phase 5.

---

## 5. Expiry Scanner — Daily Cron Job + Idempotency

- [ ] 5.1 Create `NdaExpiryCheckJob` at `app/packs/core/nda_configs/jobs/nda_expiry_check_job.rb`. `perform`: iterate entities with time-based NdaConfigs (not until_revoked). For each entity's NdaConfigs, find accepted acceptances and compute expiry date per acceptance (fixed_period: `accepted_at + validity_days.days`; specific_date: `validity_date`). For each acceptance within 7-day window or past expiry: check `NdaExpiryReminder.already_sent?`, if not, resolve recipients (GP emails + LP signatories), send notifications, create NdaExpiryReminder record. Rescue `ActiveRecord::RecordNotUnique` silently (concurrent job). Rescue `StandardError` per-entity with error logging and continue. *LLD: Background Jobs + Queries and Indexes + Error Mapping.*

- [ ] 5.2 Register NdaExpiryCheckJob in `config/initializers/sidekiq.rb`: add cron variable `nda_expiry_check_cron = in_region ? '15 20 * * *' : '15 6 * * *'` and `Sidekiq::Cron::Job.create(name: 'NdaExpiryCheckJob', cron: nda_expiry_check_cron, class: 'NdaExpiryCheckJob')`. Update the comment block to include the new slot. *LLD: Background Jobs → Cron registration.*

- [ ] 5.3 Write `features/core/nda_expiry.feature` covering worked examples H5 (approaching expiry alert), H6 (expired alert), E7 (duplicate alert prevented), and until_revoked NDA never triggers. Use `travel_to` for date simulation. Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/nda_expiry.feature` until green before starting phase 6.

---

## 6. Dashboard UI — Revoke Button, Send Reminders, Revoked Status

- [ ] 6.1 Update `app/packs/core/nda_configs/views/nda_status/index.html.erb`: add "Revoked" to status counters bar, add "Reason" column to the investor table, add "Revoke" button in Actions column (visible only for Accepted investors), add "Send Reminders" button to toolbar. *LLD: File Map → nda_status/index.html.erb.*

- [ ] 6.2 Create `app/packs/core/nda_configs/views/nda_status/_revoke_dialog.html.erb`: Turbo Frame modal with investor name, consequence text, optional reason textarea, Cancel and "Revoke Access" buttons. POST to `nda_status_revoke_path`. *LLD: File Map → _revoke_dialog.html.erb.*

- [ ] 6.3 Create `app/packs/core/nda_configs/views/nda_status/_remind_dialog.html.erb`: Turbo Frame modal showing pending investor count and signatory count. POST to `nda_status_send_reminders_path`. *LLD: File Map → _remind_dialog.html.erb.*

- [ ] 6.4 Update `app/packs/core/nda_configs/views/nda_status/index.xlsx.axlsx`: add "Reason" column to the XLSX export, populated from investor row's latest revoked acceptance reason. *LLD: File Map → XLSX export.*

- [ ] 6.5 Update `app/packs/core/nda_configs/views/nda_status/_summary.html.erb`: add "Revoked" counter to the modal summary tab if it displays status counts. *LLD: File Map → NdaStatusResolver.*

- [ ] 6.6 Run all NDA Cucumber features together to verify no regressions: `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/nda_acceptance.feature features/core/nda_config.feature features/core/nda_status.feature features/core/nda_revocation.feature features/core/nda_notifications.feature features/core/nda_reminders.feature features/core/nda_expiry.feature`. All must be green before starting phase 7.

---

## 7. Polish & QA

- [ ] 7.1 Run `bundle exec rubocop` on all new and modified files. Fix any violations. Verify clean output.

- [ ] 7.2 Run full NDA Cucumber suite one final time: `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/nda_acceptance.feature features/core/nda_config.feature features/core/nda_inheritance.feature features/core/nda_status.feature features/core/nda_revocation.feature features/core/nda_notifications.feature features/core/nda_reminders.feature features/core/nda_expiry.feature`. All green.

- [ ] 7.3 Deploy to staging (`bundle exec cap staging deploy`). Run `qa-checklist.md` on the staging build and record sign-off. This task is for QA, not the developer.
