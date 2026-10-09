# Tasks

> **Phase gate:** each numbered group below is a phase. A phase's last task is always to run its
> Cucumber feature and get it green. Do not start the next phase until that happens — if it fails,
> fix the phase you're on rather than moving forward and coming back later.

## 1. Schema & Model

- [ ] 1.1 Create migration `create_nda_config_versions` with columns: `nda_config_id` (bigint, not null, FK), `version` (integer, not null), `nda_document_data` (text, not null), `resign_required` (boolean, not null, default: true), `uploaded_by_id` (bigint, not null, FK to users), `created_at`, `updated_at`. Add unique index on `[nda_config_id, version]` and composite index on `[nda_config_id, resign_required, version]`. Run `rails db:migrate:up VERSION=<timestamp>` and verify with `rails dbconsole` → `DESCRIBE nda_config_versions`. _(LLD: [Schema Detail](#schema-detail))_

- [ ] 1.2 Create `app/packs/core/nda_configs/models/nda_config_version.rb` with `belongs_to :nda_config`, `belongs_to :uploaded_by, class_name: "User"`, and `validates :version, uniqueness: { scope: :nda_config_id }`. Include `# frozen_string_literal: true` and YARD class comment. Do NOT include `FileUploader::Attachment`. _(LLD: [Method Contracts](#method-contracts))_

- [ ] 1.3 Add `has_many :nda_config_versions, dependent: :destroy` to `NdaConfig` model (`app/packs/core/nda_configs/models/nda_config.rb`). Verify in Rails console: `NdaConfig.reflect_on_association(:nda_config_versions)` returns the association. _(Design: [① Version history table](#①-version-history-table))_

- [ ] 1.4 Write `features/nda_version_history/schema_and_model.feature` covering: version record creation via console (create config → create version record → verify attributes), uniqueness constraint (duplicate version for same config → rejected). Run with `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/nda_version_history/schema_and_model.feature` and confirm green before starting phase 2.

## 2. Resign Toggle & Version Record Creation

- [ ] 2.1 Add resign checkbox to `app/packs/core/nda_configs/views/nda_configs/_form.html.erb` inside the existing `versionWarning` div (lines 103–112). Add a checkbox: `<%= check_box_tag "nda_config[resign_required]", "1", true, class: "form-check-input", id: "resign_required" %>` with label "Require existing signatories to re-sign this version". Only render when `nda_config.persisted?`. _(Design: [② Resign toggle on form](#②-resign-toggle-on-form))_

- [ ] 2.2 Add private method `create_version_record(nda_config, resign_required:)` to `NdaConfigsController`. After save, if `saved_change_to_version?`, create `NdaConfigVersion` with `nda_config_id`, `version`, `nda_document_data` (from config), `resign_required`, `uploaded_by: current_user`. Rescue `StandardError` and log with `[NdaVersionHistory]` tag. _(LLD: [Method Contracts](#method-contracts))_

- [ ] 2.3 Update `NdaConfigsController#update`: after `@nda_config.update`, if version changed, parse `resign_required` from `params.dig(:nda_config, :resign_required)` (default to `true`), call `create_version_record`, and call `notify_version_change` only if `resign_required` is true. _(Design: [③ Version record creation](#③-version-record-creation), [⑤ Conditional notifications](#⑤-conditional-notifications))_

- [ ] 2.4 Update `NdaConfigsController#create`: after `auto_tag_default_signatories`, call `create_version_record(@nda_config, resign_required: false)` to seed version 1. _(Design: [③ Version record creation](#③-version-record-creation))_

- [ ] 2.5 Verify locally: as GP, edit NDA settings and upload a new PDF → resign checkbox visible and checked by default. Save with checkbox checked → version increments, version record created with `resign_required: true`, notification sent. Save with checkbox unchecked → version record with `resign_required: false`, no notification. Create a brand new NDA → version 1 record created with `resign_required: false`.

- [ ] 2.6 Write `features/nda_version_history/resign_toggle.feature` covering: H1 (upload with resign, version record + notifications), H2 (upload without resign, version record, no notifications), E5 (edit without uploading = no version change), E6 (first creation = no checkbox), H7 (first creation creates v1 record). Run with `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/nda_version_history/resign_toggle.feature` and confirm green before starting phase 3.

## 3. Conditional Acceptance Gate

- [ ] 3.1 Update `DocumentsController#acceptance_version_current?` (`app/packs/core/documents/controllers/documents_controller.rb`, lines 624–626). Replace strict equality with: if versions match → true; else query `NdaConfigVersion.where(nda_config_id:, version: (acceptance.nda_version + 1)..nda_config.version, resign_required: true).exists?` — if true → false (stale); else if any version records exist for config → true (all non-resign); else → false (fallback to strict). _(Design: [④ Conditional acceptance check](#④-conditional-acceptance-check), LLD: [Queries and Indexes](#queries-and-indexes))_

- [ ] 3.2 Verify locally: LP accepted at v2, GP uploads v3 without resign → LP can still access folder. GP uploads v4 with resign → LP redirected to acceptance screen. Non-signatory LP → blocked page after resign bump, folder access after non-resign bump. _(QA: H3, H4, E1, E2, E3, E4)_

- [ ] 3.3 Write `features/nda_version_history/conditional_gate.feature` covering: H3 (LP access after non-resign bump), H4 (LP access after resign bump), E1 (mixed history — non-resign then resign), E2 (all non-resign across multiple bumps), E3 (non-signatory blocked after resign), E4 (non-signatory access after non-resign), E7 (exempt investor unaffected). Run with `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/nda_version_history/conditional_gate.feature` and confirm green before starting phase 4.

## 4. Version History UI & Backfill

- [ ] 4.1 Update `NdaStatusController#index` (`app/packs/core/nda_configs/controllers/nda_status_controller.rb`) to load `@version_records = @nda_config.nda_config_versions.includes(:uploaded_by).order(version: :desc)`. _(Design: [⑥ Version history UI](#⑥-version-history-ui))_

- [ ] 4.2 Add collapsible version history section to `app/packs/core/nda_configs/views/nda_status/index.html.erb` below the status counters. Use Bootstrap collapse: toggle button "Version History (N versions)", table with columns: Version, Uploaded, Uploaded By, Resign, Download. Current version marked with badge. For download link, reconstruct Shrine URL from stored `nda_document_data` JSON. _(Design: [⑥ Version history UI](#⑥-version-history-ui))_

- [ ] 4.3 Create backfill migration `backfill_nda_config_versions`. For each `NdaConfig` where `nda_document_data IS NOT NULL`, insert `NdaConfigVersion` with `version: nda_config.version`, `nda_document_data: nda_config.nda_document_data`, `resign_required: false`, `uploaded_by_id: nda_config.created_by_id`, `created_at: nda_config.created_at`. Use `insert_all` with `ON DUPLICATE KEY IGNORE` for idempotency. Run with `rails db:migrate:up VERSION=<timestamp>`. _(Design: [⑦ Backfill migration](#⑦-backfill-migration))_

- [ ] 4.4 Verify locally: as GP, view NDA Status Dashboard → version history section visible, collapsed. Expand → shows all versions with correct data. Download link for each version works. Backfilled configs show v1 with "(Initial upload)" label.

- [ ] 4.5 Write `features/nda_version_history/version_history_ui.feature` covering: H5 (version history visible on dashboard), H6 (download historical PDF), J2.1–J2.3 (UI journey steps). Run with `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/nda_version_history/version_history_ui.feature` and confirm green before starting phase 5.

## 5. Full Integration & QA

- [ ] 5.1 Run the full Cucumber suite to check for regressions: `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/nda_version_history/`. Fix any failures.

- [ ] 5.2 Run `bundle exec rubocop` on all changed files and fix any offences.

- [ ] 5.3 Run `qa-checklist.md` on a deployed build (staging or local) and record the sign-off in the checklist's Sign-off table. This task is for QA, not for the apply agent.
