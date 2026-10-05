# Tasks

> **Phase gate:** each numbered group below is a phase. A phase's last task is always to run its
> Cucumber feature and get it green. Do not start the next phase until that happens — if it fails,
> fix the phase you're on rather than moving forward and coming back later.

## 1. Data Layer — NdaSignatory model + exempt_from_nda migration

- [ ] 1.1 Create migration `add_exempt_from_nda_to_investor_accesses.rb`: `add_column :investor_accesses, :exempt_from_nda, :boolean, default: false, null: false`. Verify: `rails db:migrate` succeeds, `schema.rb` shows the new column.

- [ ] 1.2 Update `db/schema_test.rb` to include the `exempt_from_nda` column on `investor_accesses`.

- [ ] 1.3 Create migration `create_nda_signatories.rb` with columns: `nda_config_id` (bigint, not null), `user_id` (bigint, not null), `tagged_by_id` (bigint, not null), `timestamps`. Add unique index `[nda_config_id, user_id]`, index `[user_id]`. Foreign keys to `nda_configs`, `users` (x2). Verify: `rails db:migrate` succeeds and `schema.rb` shows the new table.

- [ ] 1.4 Create model `app/packs/core/nda_configs/models/nda_signatory.rb` with `belongs_to :nda_config`, `belongs_to :user`, `belongs_to :tagged_by, class_name: "User"`. Validates `user_id` uniqueness scoped to `nda_config_id`. Include `frozen_string_literal: true` and YARD class comment.

- [ ] 1.5 Add `has_many :nda_signatories, dependent: :destroy` to `app/packs/core/nda_configs/models/nda_config.rb`. Verify: `rails c` -> `NdaConfig.new.respond_to?(:nda_signatories)` returns true.

- [ ] 1.6 Add `:exempt_from_nda` to permitted params in `investor_accesses_controller.rb`. Add the checkbox to `investor_accesses/_form.html.erb`.

- [ ] 1.7 Write Cucumber feature covering: creating a signatory record, uniqueness constraint, destroying NdaConfig cascades signatories, `exempt_from_nda` default is false on new InvestorAccess. Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber` on the feature and confirm it passes before starting phase 2.

## 2. NDA Gate — Stakeholder exemption check

- [ ] 2.1 Modify `app/packs/core/documents/controllers/documents_controller.rb` method `ensure_nda_accepted`. Insert the exemption check AFTER the GP bypass and BEFORE the stakeholder acceptance check: `return if InvestorAccess.exists?(user_id: current_user.id, entity_id: nda_config.entity_id, approved: true, exempt_from_nda: true)`. Add a YARD comment explaining the gate order: GP bypass -> exemption check -> stakeholder acceptance -> redirect.

- [ ] 2.2 Write `features/core/nda_stakeholder_exemption_gate.feature` covering: exempt investor's user accesses folder (E1), exemption removed (delete+re-add InvestorAccess) then redirect to NDA screen (E2), gate check order. Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/nda_stakeholder_exemption_gate.feature` and confirm it passes before starting phase 3.

## 3. Service — NdaStatusResolver

- [ ] 3.1 Create `app/packs/core/nda_configs/services/nda_status_resolver.rb`. Method `.resolve(nda_config, folder)` returns a StatusData struct with `counters` hash and `investor_rows` array. Three batched queries: InvestorAccess -> investors + users + exempt_from_nda, NdaAcceptance -> latest per investor, NdaSignatory -> signatory user_ids. Include `frozen_string_literal: true` and YARD class/method comments.

- [ ] 3.2 Implement investor-level status derivation logic inside the resolver: any InvestorAccess has `exempt_from_nda` -> "Exempt", latest acceptance "accepted" -> "Accepted", latest acceptance "declined" -> "Declined", no acceptance -> "Pending".

- [ ] 3.3 Implement user-level detail: mark the user who physically signed the NDA as "Signer", flag signatory users from NdaSignatory records (not `tag_list`). No user-level exempt status.

- [ ] 3.4 Write `features/core/nda_status_resolver.feature` covering resolver scenarios. Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/nda_status_resolver.feature` and confirm it passes before starting phase 4.

## 4. Policy + Routes + Controller scaffold

- [ ] 4.1 Create `app/packs/core/nda_configs/policies/nda_status_policy.rb`. All actions check `user.curr_role_employee? && record.entity_id == user.entity_id`. Include `frozen_string_literal: true` and YARD comments.

- [ ] 4.2 Create `app/packs/core/nda_configs/controllers/nda_status_controller.rb` with actions: `summary`, `index`, `create_signatory`, `destroy_signatory`. No exemption actions. No `send_reminders`. Controller inherits from `ApplicationController`. Include `frozen_string_literal: true` and YARD comments for each action.

- [ ] 4.3 Add routes in `config/routes/core.rb`. Under the nda_configs section, add routes for the NdaStatusController: `get "nda_status/summary"`, `get "nda_status"` (index), `post "nda_status/signatories"` (create_signatory), `delete "nda_status/signatories/:id"` (destroy_signatory). No exemption routes. No reminder route. Verify: `rails routes | grep nda_status` shows all 4 routes.

- [ ] 4.4 Implement `#summary` action: calls `NdaStatusResolver.resolve(@nda_config, @folder)`, renders `_summary.html.erb` partial inside a Turbo Frame.

- [ ] 4.5 Implement `#index` action with `respond_to`: `format.html` renders `index.html.erb` with `modernize` layout, `format.json` renders `index.json.jbuilder`, `format.xlsx` renders `index.xlsx.axlsx`. Uses `NdaStatusResolver.resolve` for data.

- [ ] 4.6 Implement `#create_signatory`: creates `NdaSignatory` with `nda_config_id`, `user_id` from params, `tagged_by_id: current_user.id`. Returns JSON `{ status: "ok", user_id:, signatory: true }`. Rescues `RecordInvalid` -> 422, `RecordNotUnique` -> 409.

- [ ] 4.7 Implement `#destroy_signatory`: finds `NdaSignatory.find(params[:id])`, destroys it. Returns JSON `{ status: "ok", user_id:, signatory: false }`.

- [ ] 4.8 ~~`send_reminders`~~ — descoped (reminders removed from Module 3).

- [ ] 4.9 Write `features/core/nda_status_controller.feature` covering: GP views summary (H1), GP accesses dashboard (H2), GP creates signatory, GP destroys signatory, non-GP denied (X1), other-entity GP denied (X2), invalid NDA config 404 (X3). Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/nda_status_controller.feature` and confirm it passes before starting phase 5.

## 5. Views — Modal Status tab + dedicated dashboard

- [ ] 5.1 Create `app/packs/core/nda_configs/views/nda_status/_summary.html.erb`. Turbo Frame partial with `turbo_frame_tag "nda_status_summary"`. Contains: counter badges (Accepted, Pending, Declined, Exempt), simple HTML table (Investor Name, Status, Signed By, Date), "View Full Dashboard" link. Include ERB header comment.

- [ ] 5.2 Modify `app/packs/core/nda_configs/views/nda_configs/_modal.html.erb`. Enable the Status tab (currently disabled at lines 33-38). Add Turbo Frame lazy-load: `turbo_frame_tag "nda_status_summary", loading: :lazy, src: nda_status_summary_path(nda_config_id: @nda_config.id, folder_id: @folder.id)`. Only show Status tab when `@nda_config.persisted? && @nda_config.enabled`.

- [ ] 5.3 Create `app/packs/core/nda_configs/views/nda_status/index.html.erb`. Dedicated dashboard page with `modernize` layout. Contains: page title ("NDA Status — {folder name}"), toolbar (Filter dropdown, Search input, Export button), AG Grid container with `data-controller="ag"`, `data-source` pointing to JSON endpoint, `data-custom-columns`. Include ERB header comment.

- [ ] 5.4 Create `app/packs/core/nda_configs/views/nda_status/index.json.jbuilder`. Renders AG Grid JSON data from resolver's `investor_rows`. Each investor row includes nested `users` array for row grouping.

- [ ] 5.5 Create `app/packs/core/nda_configs/views/nda_status/index.xlsx.axlsx`. XLSX export following the existing pattern (see `investors/index.xlsx.axlsx`). Columns: Investor Name, User Name, Email, Status, NDA Version, Signed Date, Valid Until, Exempt From NDA. One row per user (flat, not grouped). No "Exemption Reason" column. Include ERB header comment.

- [ ] 5.6 Create or extend a Stimulus controller for the dashboard page to handle: tag/untag signatory actions only (no exempt/revoke buttons). `fetch` POST/DELETE -> update grid via `gridApi.applyTransaction()` or `gridApi.setRowData()`. Export button -> navigate to `.xlsx` URL.

- [ ] 5.7 Hide NDA Settings on Data Room root: modify `documents/_index.html.erb` condition from `@folder&.in_data_room?` to `@folder&.in_data_room? && !@folder&.data_room_root?`.

- [ ] 5.8 Write `features/core/nda_status_views.feature` covering: Status tab visible with counters (H1 UI), dashboard page renders AG Grid (H2 UI), expanding investor shows user rows, export downloads file (H5), Status tab hidden for folder without NDA (E9), inherited NDA shows parent's statuses (E10), NDA Settings hidden on Data Room root folder. Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/nda_status_views.feature` and confirm it passes before starting phase 6.

## 6. Final verification + QA handoff

- [ ] 6.1 Run `bundle exec rubocop` on all new and modified files. Fix any violations. Verify: rubocop exits clean.

- [ ] 6.2 Run the full NDA feature suite: `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/nda_signatory_model.feature features/core/nda_stakeholder_exemption_gate.feature features/core/nda_status_resolver.feature features/core/nda_status_controller.feature features/core/nda_status_views.feature`. All scenarios green.

- [ ] 6.3 Run existing NDA features to confirm no regressions: `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/nda_config.feature features/core/nda_acceptance.feature features/core/nda_inheritance.feature`. All scenarios green.

- [ ] 6.4 Deploy to staging and run `qa-checklist.md` on the deployed build. Record the sign-off in qa-checklist.md's Sign-off table (tester, build/commit, environment, date, result, open defects).
