# Tasks

> **Phase gate:** each numbered group below is a phase. A phase's last task is always to run its
> Cucumber feature and get it green. Do not start the next phase until that happens — if it fails,
> fix the phase you're on rather than moving forward and coming back later.

## 1. Database and Model

- [ ] 1.1 Create migration `db/migrate/YYYYMMDDHHMMSS_create_nda_acceptances.rb` with the schema from [LLD Schema Detail](lld.md#schema-detail): `nda_config_id` (bigint FK NOT NULL), `investor_id` (bigint FK NOT NULL), `user_id` (bigint FK NOT NULL), `entity_id` (bigint FK NOT NULL), `status` (string limit 20 NOT NULL), `nda_version` (integer NOT NULL default 1), `ip_address` (string limit 45 nullable), `user_agent` (string limit 500 nullable), `accepted_at` (datetime nullable), `declined_at` (datetime nullable), `created_at` (datetime NOT NULL). Four indexes: `idx_nda_acceptances_gate_lookup [nda_config_id, investor_id, created_at]` (stakeholder-level gate), `idx_nda_acceptances_entity [entity_id]`, `idx_nda_acceptances_user [user_id]`, `idx_nda_acceptances_investor [investor_id]`. No `updated_at` — append-only. Verify: `rails db:migrate` succeeds and `nda_acceptances` table exists in `schema.rb`.

- [ ] 1.2 Create `app/packs/core/nda_configs/models/nda_acceptance.rb` per [LLD Method Contracts](lld.md#method-contracts): `belongs_to :nda_config`, `belongs_to :investor`, `belongs_to :user`, `belongs_to :entity`. Validate `status` inclusion in `%w[accepted declined]`. Add `accepted?` predicate method. Include `# frozen_string_literal: true` and YARD class comment. Verify: `rails c` — `NdaAcceptance.new` works, validations fire.

- [ ] 1.3 Add `has_many :nda_acceptances, dependent: :destroy` to `NdaConfig` model (`app/packs/core/nda_configs/models/nda_config.rb`). Verify: `NdaConfig.new.nda_acceptances` returns an association.

- [ ] 1.4 Update `db/schema_test.rb` to sync with `schema.rb`. Verify: `diff db/schema.rb db/schema_test.rb` shows only the expected test-specific differences.

- [ ] 1.5 Write `features/core/nda_acceptance.feature` Phase 1 scenarios: create an NdaAcceptance record, verify status and audit fields (covers X4 — acceptance record audit fields). Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/nda_acceptance.feature` and confirm green before starting phase 2.

## 2. Policy and Routes

- [ ] 2.1 Create `app/packs/core/nda_configs/policies/nda_acceptance_policy.rb` per [LLD Security Review](lld.md#security-review) and [design Policy](design.md#policy): deny if `user.entity_id == record.nda_config.entity_id` (GP), allow if user has investor relationship with the NDA config's entity. Methods: `show?`, `create?`, `decline?` — all use the same logic. Include `# frozen_string_literal: true` and YARD class comment. Verify: policy instantiates in `rails c`.

- [ ] 2.2 Add routes to `config/routes/core.rb` per [design Controllers and Routes](design.md#controllers-and-routes): `resources :nda_acceptances, only: [:index, :create] do; post :decline, on: :collection; end`. The `index` action maps to `show` in the controller (collection route renders the acceptance screen). Verify: `rails routes | grep nda_acceptance` shows expected routes.

- [ ] 2.3 Add `features/core/nda_acceptance.feature` Phase 2 scenarios: verify policy blocks GP, allows LP, blocks other-entity user (covers R1-R5 from QA role sweep). Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/nda_acceptance.feature` and confirm green before starting phase 3.

## 3. Controller and Views

- [ ] 3.1 Create minimal layout `app/packs/core/base/views/layouts/nda_minimal.html.erb` per [design UI Changes Build notes](design.md#build-notes-for-implementers): DOCTYPE, meta tags, CSRF, importmap tags, core CSS link (`/modernize/css/styles.css`), `<%= yield %>`. No sidebar, topbar, preloader, searchbar, command palette, DataTables, AG Grid, PDFTron, Select2, or x-spreadsheet. Verify: layout file renders without error in a test action.

- [ ] 3.2 Create `app/packs/core/nda_configs/controllers/nda_acceptances_controller.rb` per [LLD Controllers](lld.md#controllers-params-and-responses): `layout "nda_minimal"`. Actions: `index` (renders show — loads NdaConfig by `params[:nda_config_id]`, Folder by `params[:folder_id]`, authorizes, renders acceptance screen), `create` (resolves `investor_id` via `InvestorAccess.where(user_id: current_user.id, entity_id: @nda_config.entity_id, approved: true).first!.investor_id`, creates NdaAcceptance with investor_id, user_id, status=accepted, nda_version from config, ip from `request.remote_ip`, user_agent from `request.user_agent` truncated to 500 chars, accepted_at=Time.current, entity_id from nda_config, redirects to `safe_return_to`), `decline` (resolves investor_id same way, creates NdaAcceptance with investor_id, user_id, status=declined, declined_at=Time.current, renders decline page). Private: `set_nda_config`, `set_folder`, `resolve_investor`, `safe_return_to`. Include `# frozen_string_literal: true` and YARD class comment. Verify: controller loads without error.

- [ ] 3.3 Register `nda_acceptances` view path in `config/application.rb` (same pattern as existing `nda_configs` registration). Verify: views resolve from the pack path.

- [ ] 3.4 Create `app/packs/core/nda_configs/views/nda_acceptances/show.html.erb` per [design Journey 1](design.md#journey-1-lp-accepts-nda-to-access-folder): company logo, "Back to Data Rooms" link, title, entity/folder context, NDA PDF iframe (`@nda_config.nda_document_url`), confirmation checkbox, Accept button (disabled by default), Decline button, contact email (if configured). Form posts to `nda_acceptances_path` with hidden fields: `nda_config_id`, `folder_id`, `return_to`. Include ERB header comment. Verify: view renders in browser.

- [ ] 3.5 Create `app/packs/core/nda_configs/views/nda_acceptances/declined.html.erb` per [design Journey 2](design.md#journey-2-lp-declines-nda): "NDA Declined" heading, folder name, explanation text, contact email if configured, "Try Again" link (back to acceptance screen with same params), "Back to Data Rooms" link. Include ERB header comment. Verify: view renders.

- [ ] 3.6 Create `app/javascript/controllers/nda_acceptance_controller.js` per [design Build notes](design.md#build-notes-for-implementers): Stimulus controller with `toggleAccept` method — enables/disables Accept button target based on checkbox target state. Include JSDoc header comment. Verify: checkbox toggles button state in browser.

- [ ] 3.7 Add `features/core/nda_acceptance.feature` Phase 3 scenarios: acceptance screen shows all elements (H5), LP accepts NDA on behalf of stakeholder (H1), LP declines NDA (H3), LP retries after decline (H4), accept button disabled without checkbox (E10), acceptance screen without contact email (E8), another user of same stakeholder accesses folder after first user accepted — no NDA screen (H6). Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/nda_acceptance.feature` and confirm green before starting phase 4.

## 4. NDA Gate on DocumentsController

- [ ] 4.1 Add `before_action :ensure_nda_accepted, only: [:folder]` to `app/packs/core/documents/controllers/documents_controller.rb` per [design Key Components](design.md#key-components) and [LLD Method Contracts](lld.md#method-contracts). Private method `ensure_nda_accepted`: load `@folder` from `params[:folder_id]`, return early if folder nil or `@folder.entity_id == current_user.entity_id` (GP bypass), get `effective_nda_config`, return if nil or not enabled, resolve investor via `InvestorAccess.where(user_id: current_user.id, entity_id: nda_config.entity_id, approved: true).pluck(:investor_id)`, query latest NdaAcceptance (`where(nda_config_id:, investor_id: investor_ids).order(created_at: :desc).limit(1)`), return if accepted at current version, else redirect to `nda_acceptances_path` with `nda_config_id`, `folder_id`, `return_to: request.fullpath`. Private method `safe_return_to(path)`: validate relative path per [LLD Security Review](lld.md#security-review) — accept if starts with `/` and not `//` and not containing `://`, else fallback to `data_rooms_folders_path`. Verify: LP hits NDA screen when navigating to NDA-protected folder; GP bypasses; User B of same stakeholder bypasses after User A accepted.

- [ ] 4.2 Add `features/core/nda_acceptance.feature` Phase 4 scenarios covering the full gate flow: LP accesses folder after acceptance (H2), inherited NDA already accepted (E1), child with own NDA requires separate acceptance (E2), opted-out folder (E3), folder with no NDA (E4), GP employee bypasses (E5), NDA disabled (E6), e-sign falls back to click-through (E7), multiple records preserved (E9), invalid return_to URL (X1), missing return_to (X2), NDA config not found (X3), decline by one user does not block another user of same stakeholder (E11), user with no InvestorAccess cannot reach NDA screen (E12). Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/nda_acceptance.feature` and confirm all scenarios green before starting phase 5.

## 5. Cleanup and QA

- [ ] 5.1 Run `bundle exec rubocop` on all new and modified files. Fix any offenses. Verify: zero offenses on NDA acceptance files.

- [ ] 5.2 Run `bundle exec brakeman -q` and verify no new warnings from NDA acceptance code.

- [ ] 5.3 Run the full NDA Cucumber suite: `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/nda_acceptance.feature features/core/nda_config.feature features/core/nda_inheritance.feature` — all green, no regressions.

- [ ] 5.4 Manual QA on dev server following `qa-checklist.md`. Record results and sign-off in the checklist. This task is for QA, not the apply agent.
