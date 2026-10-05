# Tasks

> **Phase gate:** each numbered group below is a phase. A phase's last task is always to run its
> Cucumber feature and get it green. Do not start the next phase until that happens — if it fails,
> fix the phase you're on rather than moving forward and coming back later.

## 1. Data Layer — NdaExemption model + migration

- [ ] 1.1 Create migration `db/migrate/YYYYMMDD_create_nda_exemptions.rb` with columns: `nda_config_id` (bigint, not null), `user_id` (bigint, not null), `exempted_by_id` (bigint, not null), `reason` (string, limit: 500, nullable), `timestamps`. Add foreign keys to `nda_configs`, `users` (for user_id), and `users` (for exempted_by_id). Add unique index `idx_nda_exemptions_config_user [nda_config_id, user_id]` and index `idx_nda_exemptions_user [user_id]`. Verify: `rails db:migrate` succeeds and `schema.rb` shows the new table. *(LLD: Schema Detail)*

- [ ] 1.2 Update `db/schema_test.rb` to include the `nda_exemptions` table matching `schema.rb`. Verify: file diff shows only the new table added.

- [ ] 1.3 Create model `app/packs/core/nda_configs/models/nda_exemption.rb` with `belongs_to :nda_config`, `belongs_to :user`, `belongs_to :exempted_by, class_name: "User"`. Add validations: `validates :user_id, uniqueness: { scope: :nda_config_id }`, `validates :reason, length: { maximum: 500 }`. Include `frozen_string_literal: true` and YARD class comment. *(LLD: Method Contracts — NdaExemption)*

- [ ] 1.4 Add `has_many :nda_exemptions, dependent: :destroy` to `app/packs/core/nda_configs/models/nda_config.rb`. Verify: `rails c` → `NdaConfig.new.respond_to?(:nda_exemptions)` returns true. *(LLD: File Map — NdaConfig modified)*

- [ ] 1.5 Write `features/core/nda_exemption_model.feature` covering model-level scenarios: creating an exemption record (H3 setup), uniqueness constraint prevents duplicate (E6), destroying NDA config cascades to exemptions. Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/nda_exemption_model.feature` and confirm it passes before starting phase 2.

## 2. NDA Gate — Exemption check

- [ ] 2.1 Modify `app/packs/core/documents/controllers/documents_controller.rb` method `ensure_nda_accepted`. Insert the exemption check AFTER the GP bypass and BEFORE the stakeholder acceptance check: `return if NdaExemption.exists?(nda_config_id: nda_config.id, user_id: current_user.id)`. Add a YARD comment explaining the gate order: GP bypass → exemption check → stakeholder acceptance → redirect. *(LLD: Queries and Indexes — Gate exemption check)*

- [ ] 2.2 Write `features/core/nda_exemption_gate.feature` covering: exempt user accesses folder before stakeholder signs (E1), exemption revoked then stakeholder not accepted redirects to NDA screen (E2), gate check order — exempted user passes at step 1 without reaching step 2 (spec scenario "Gate check order"). Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/nda_exemption_gate.feature` and confirm it passes before starting phase 3.

## 3. Service — NdaStatusResolver

- [ ] 3.1 Create `app/packs/core/nda_configs/services/nda_status_resolver.rb`. Method `.resolve(nda_config, folder)` returns a StatusData struct with `counters` hash and `investor_rows` array. Implements the four batched queries: AccessRight investor universe, InvestorAccess users+tags, NdaAcceptance latest per investor (MySQL GROUP BY + MAX subquery), NdaExemption exempt user_ids. Include `frozen_string_literal: true` and YARD class/method comments. *(LLD: Method Contracts — NdaStatusResolver, Queries and Indexes)*

- [ ] 3.2 Implement investor-level status derivation logic inside the resolver: all-users-exempt → "Exempt", latest acceptance "accepted" → "Accepted", latest acceptance "declined" → "Declined", no acceptance → "Pending". *(Design: Key Components — Status derivation decision flow)*

- [ ] 3.3 Implement user-level detail: mark the user who physically signed the NDA as "Signer", mark exempt users as "Exempt", flag NDA-tagged users from InvestorAccess `tag_list`. *(Spec: User-level detail in expanded row)*

- [ ] 3.4 Write `features/core/nda_status_resolver.feature` covering: resolver returns correct counters for mixed statuses (H1 data), category-based access right expansion (E3), investor removed from access rights not shown (E4), investor fully exempt status derivation (E11), empty folder with no access rights returns empty data. Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/nda_status_resolver.feature` and confirm it passes before starting phase 4.

## 4. Policy + Routes + Controller scaffold

- [ ] 4.1 Create `app/packs/core/nda_configs/policies/nda_status_policy.rb`. All actions check `user.curr_role_employee? && record.entity_id == user.entity_id`. Include `frozen_string_literal: true` and YARD comments. *(LLD: Security Review — Authorization)*

- [ ] 4.2 Create `app/packs/core/nda_configs/controllers/nda_status_controller.rb` with actions: `summary`, `index`, `create_exemption`, `destroy_exemption`, `send_reminders`. Add `before_action :set_nda_config`, `before_action :set_folder` (for summary/index/send_reminders), and `authorize` per action using `NdaStatusPolicy`. Controller inherits from `ApplicationController`. Include `frozen_string_literal: true` and YARD comments for each action. *(LLD: Controllers, Params and Responses)*

- [ ] 4.3 Add routes in `config/routes/core.rb`. Under the nda_configs section, add routes for the NdaStatusController: `get "nda_status/summary"`, `get "nda_status"` (index), `post "nda_status/exemptions"` (create_exemption), `delete "nda_status/exemptions/:id"` (destroy_exemption), `post "nda_status/send_reminders"`. Verify: `rails routes | grep nda_status` shows all 5 routes. *(LLD: File Map — Routes modified)*

- [ ] 4.4 Implement `#summary` action: calls `NdaStatusResolver.resolve(@nda_config, @folder)`, renders `_summary.html.erb` partial inside a Turbo Frame. *(Design: Sequence Diagrams — GP views status summary)*

- [ ] 4.5 Implement `#index` action with `respond_to`: `format.html` renders `index.html.erb` with `modernize` layout, `format.json` renders `index.json.jbuilder`, `format.xlsx` renders `index.xlsx.axlsx`. Uses `NdaStatusResolver.resolve` for data. *(LLD: Controllers — respond_to in #index)*

- [ ] 4.6 Implement `#create_exemption`: creates `NdaExemption` with `nda_config_id`, `user_id` from params, `exempted_by_id: current_user.id`, `reason` from params. Returns JSON `{ status: "ok", user_id:, exempt: true }`. Rescues `RecordInvalid` → 422, `RecordNotUnique` → 409. *(LLD: Controllers — create_exemption, Error Mapping)*

- [ ] 4.7 Implement `#destroy_exemption`: finds `NdaExemption.find(params[:id])`, destroys it. Returns JSON `{ status: "ok", user_id:, exempt: false }`. *(LLD: Controllers — destroy_exemption)*

- [ ] 4.8 Implement `#send_reminders`: uses resolver to find pending investors, filters NDA-tagged non-exempt users, enqueues `NdaReminderJob.perform_later(nda_config_id, user_ids)`. Returns JSON `{ status: "ok", count: N }`. Returns 422 if no pending users. *(Design: Sequence Diagrams — GP sends bulk reminders)*

- [ ] 4.9 Write `features/core/nda_status_controller.feature` covering: GP views summary (H1), GP accesses dashboard (H2), GP creates exemption (H3), GP revokes exemption (H4), GP sends reminders to pending (H6), non-GP denied (X1), other-entity GP denied (X2), invalid NDA config 404 (X3), no pending investors for reminders (E5). Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/nda_status_controller.feature` and confirm it passes before starting phase 5.

## 5. Views — Modal Status tab + dedicated dashboard

- [ ] 5.1 Create `app/packs/core/nda_configs/views/nda_status/_summary.html.erb`. Turbo Frame partial with `turbo_frame_tag "nda_status_summary"`. Contains: counter badges (Accepted, Pending, Declined, Exempt), simple HTML table (Investor Name, Status, Signed By, Date), "View Full Dashboard" link. Include ERB header comment. *(Design: UI Changes — Journey 1)*

- [ ] 5.2 Modify `app/packs/core/nda_configs/views/nda_configs/_modal.html.erb`. Enable the Status tab (currently disabled at lines 33-38). Add Turbo Frame lazy-load: `turbo_frame_tag "nda_status_summary", loading: :lazy, src: nda_status_summary_path(nda_config_id: @nda_config.id, folder_id: @folder.id)`. Only show Status tab when `@nda_config.persisted? && @nda_config.enabled`. *(Design: UI Changes — At a Glance, Build Notes)*

- [ ] 5.3 Create `app/packs/core/nda_configs/views/nda_status/index.html.erb`. Dedicated dashboard page with `modernize` layout. Contains: page title ("NDA Status — {folder name}"), toolbar (Filter dropdown, Search input, Export button, Send Reminders button), AG Grid container with `data-controller="ag"`, `data-source` pointing to JSON endpoint, `data-custom-columns`. Include ERB header comment. *(Design: UI Changes — Journey 2)*

- [ ] 5.4 Create `app/packs/core/nda_configs/views/nda_status/index.json.jbuilder`. Renders AG Grid JSON data from resolver's `investor_rows`. Each investor row includes nested `users` array for row grouping. *(LLD: File Map — index.json.jbuilder)*

- [ ] 5.5 Create `app/packs/core/nda_configs/views/nda_status/index.xlsx.axlsx`. XLSX export following the existing pattern (see `investors/index.xlsx.axlsx`). Columns: Investor Name, User Name, Email, Status, NDA Version, Signed Date, Valid Until, Exemption Reason. One row per user (flat, not grouped). Include ERB header comment. *(LLD: File Map — index.xlsx.axlsx, Spec: GP exports NDA status)*

- [ ] 5.6 Create or extend a Stimulus controller for the dashboard page to handle: Exempt/Revoke button click → `fetch` POST/DELETE → update grid via `gridApi.applyTransaction()` or `gridApi.setRowData()`, Send Reminders confirmation dialog → `fetch` POST → flash message, Export button → navigate to `.xlsx` URL. *(LLD: Controllers — Exemption toggle uses JSON, not Turbo Stream)*

- [ ] 5.7 Write `features/core/nda_status_views.feature` covering: Status tab visible with counters (H1 UI), dashboard page renders AG Grid (H2 UI), expanding investor shows user rows, export downloads file (H5), Status tab hidden for folder without NDA (E9), inherited NDA shows parent's statuses (E10). Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/nda_status_views.feature` and confirm it passes before starting phase 6.

## 6. Notifications — Reminder job, notifier, mailer

- [ ] 6.1 Create `app/packs/core/nda_configs/jobs/nda_reminder_job.rb`. Inherits `ApplicationJob`. Queue: `:default`. `sidekiq_options retry: 3`. `discard_on ActiveRecord::RecordNotFound`. `#perform(nda_config_id, user_ids)` loads NDA config, loops user_ids, dispatches `NdaReminderNotifier.with(record: nda_config, entity_id: nda_config.entity_id).deliver_later(user)` per user. Include `frozen_string_literal: true` and YARD comments. *(LLD: Background Jobs)*

- [ ] 6.2 Create `app/packs/core/nda_configs/mailers/nda_reminder_notifier.rb`. Inherits `BaseNotifier`. `required_param :entity_id`. Overrides `mailer_name` → `NdaReminderMailer`, `email_method` → `:send_reminder`, `email_data(notification)` → hash with `notification_id`, `user_id`, `entity_id`, `nda_config_id`, `folder_name`. Include `frozen_string_literal: true` and YARD comments. *(LLD: Method Contracts — NdaReminderNotifier)*

- [ ] 6.3 Create `app/packs/core/nda_configs/mailers/nda_reminder_mailer.rb`. Method `send_reminder` renders the reminder email. Uses `EmailDateLocalization` for dates. Include `frozen_string_literal: true` and YARD comments. *(LLD: Error Mapping — NdaReminderMailer)*

- [ ] 6.4 Create `app/packs/core/nda_configs/views/nda_reminder_mailer/send_reminder.html.erb`. Email template with: folder name, entity name, message prompting the user to accept the NDA, clickable link to the Data Room folder. *(Spec: Reminder content directs user to Data Room)*

- [ ] 6.5 Write `features/core/nda_status_reminders.feature` covering: reminder sent to NDA-tagged user of pending investor (H6), reminder targets only NDA-tagged users (E8), reminder skips exempt users (E7), reminder email contains Data Room link (spec scenario "Reminder content directs user to Data Room"). Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/nda_status_reminders.feature` and confirm it passes before starting phase 7.

## 7. Final verification + QA handoff

- [ ] 7.1 Run `bundle exec rubocop` on all new and modified files. Fix any violations. Verify: rubocop exits clean.

- [ ] 7.2 Run the full NDA feature suite: `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/nda_exemption_model.feature features/core/nda_exemption_gate.feature features/core/nda_status_resolver.feature features/core/nda_status_controller.feature features/core/nda_status_views.feature features/core/nda_status_reminders.feature`. All scenarios green.

- [ ] 7.3 Run existing NDA features to confirm no regressions: `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/nda_config.feature features/core/nda_acceptance.feature features/core/nda_inheritance.feature`. All scenarios green.

- [ ] 7.4 Deploy to staging and run `qa-checklist.md` on the deployed build. Record the sign-off in qa-checklist.md's Sign-off table (tester, build/commit, environment, date, result, open defects).
