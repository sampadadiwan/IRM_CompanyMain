# Tasks

> **Phase gate:** each numbered group below is a phase. A phase's last task is always to run its
> Cucumber feature and get it green. Do not start the next phase until that happens — if it fails,
> fix the phase you're on rather than moving forward and coming back later.

## 1. Version Bump (Model + Controller + Form)

- [ ] 1.1 Add `before_save :increment_version_if_document_changed` callback to `NdaConfig` model
      (`app/packs/core/nda_configs/models/nda_config.rb`). Guard: only increment when `enabled?`
      and the Shrine document file id actually changed (compare parsed JSON ids from
      `nda_document_data_was` vs current — see LLD Method Contracts → NdaConfig). Include YARD
      comment on the method explaining the Shrine dirty-tracking approach.
      Verify: `rails c` — create an enabled NdaConfig with PDF, update with a new PDF, confirm
      version increments. Update a non-document field, confirm version stays.

- [ ] 1.2 Relax `validity_date_must_be_future` validation in `NdaConfig` to only run on new
      records or when `validity_date` itself changed (see LLD Method Contracts → NdaConfig).
      Change the `if:` condition to `-> { validity_type == "specific_date" && validity_date.present? && (new_record? || will_save_change_to_validity_date?) }`.
      Verify: `rails c` — find an NdaConfig with a past `validity_date`, update `contact_email`,
      confirm save succeeds without validation error.

- [ ] 1.3 Add accepted investor count to `NdaConfigsController#edit` for the version warning.
      Query: `NdaAcceptance.where(nda_config_id: @nda_config.id, status: "accepted").select(:investor_id).distinct.count`.
      Set as `@accepted_count` instance variable (see LLD Queries and Indexes).
      Verify: open NDA Settings modal on a folder with accepted investors — `@accepted_count`
      should be available in the view.

- [ ] 1.4 Add version display and warning banner to `_form.html.erb`
      (`app/packs/core/nda_configs/views/nda_configs/_form.html.erb`). Show "Version N" next to
      the current PDF filename. Add a hidden warning banner div with `data-nda-settings-target="versionWarning"`
      containing the accepted count in a `data-accepted-count` attribute. Include ERB header
      comment explaining the version warning UI addition.
      Verify: open NDA Settings modal — version number visible. Warning banner hidden.

- [ ] 1.5 Add Stimulus action to `nda_settings_controller.js`
      (`app/javascript/controllers/nda_settings_controller.js`). On new file selected via Uppy,
      show the version warning banner. On file removed, hide it. Use the `data-accepted-count`
      attribute to build the warning text. Include JSDoc comment on the new action method.
      Verify: open NDA Settings, select a new PDF — warning appears. Remove file selection —
      warning disappears.

- [ ] 1.6 Write `features/core/nda_version_bump.feature` covering worked examples H3, H7, E5,
      E7, E12, E13 (version bump on PDF change, warning with count, no bump on settings-only
      change, no bump on disabled config, no warning when zero accepted, same-filename bump).
      Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/nda_version_bump.feature`
      and confirm it passes before starting phase 2.

## 2. NDA Gate Enhancement (Version + Time Expiry Checks)

- [ ] 2.1 Modify `DocumentsController#ensure_nda_accepted`
      (`app/packs/core/documents/controllers/documents_controller.rb`). Replace the single
      `return if latest&.accepted?` line with the expanded check flow (see LLD Method Contracts →
      DocumentsController). Add private helper methods `acceptance_version_current?(acceptance, nda_config)`
      and `acceptance_time_valid?(acceptance, nda_config)`. Include YARD comments on each helper.
      The `reason` param is appended to the redirect URL for version_mismatch, expired, and lapsed
      cases. The lapsed case redirects to `lapsed_nda_acceptances_path(...)` instead of
      `nda_acceptances_path(...)`. Include a code comment on the check order explaining why
      version is checked before time.
      Verify: `rails c` — manually trace the gate logic with test data to confirm the check
      order: GP bypass → exempt → exists+accepted → version → specific_date lapsed → fixed_period expired.

- [ ] 2.2 Write `features/core/nda_gate_expiry.feature` covering worked examples H1, H4, H6,
      E1, E3, E8, E9, E10 (fixed-period expiry, version mismatch, until_revoked pass-through,
      specific-date not expired, exempt after version bump, retroactive validity change,
      version-before-time priority, exempt after time expiry).
      Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/nda_gate_expiry.feature`
      and confirm it passes before starting phase 3.

## 3. Acceptance Screen & Lapsed Page (Re-acceptance UX)

- [ ] 3.1 Add `VALID_REASONS` constant and `@reason` assignment to `NdaAcceptancesController#index`
      (`app/packs/core/nda_configs/controllers/nda_acceptances_controller.rb`). Whitelist:
      `%w[version_mismatch expired].freeze`. Set `@reason = VALID_REASONS.include?(params[:reason]) ? params[:reason] : nil`.
      Include code comment explaining the whitelist approach for security (see LLD Security Review).
      Verify: visit acceptance URL with `reason=version_mismatch` — `@reason` set. Visit with
      `reason=foo` — `@reason` is nil.

- [ ] 3.2 Add contextual note banner to `nda_acceptances/index.html.erb`
      (`app/packs/core/nda_configs/views/nda_acceptances/index.html.erb`). Between the entity/folder
      context line (④) and the PDF iframe (⑤), add a conditional banner:
      - `@reason == "version_mismatch"`: "The NDA has been updated since you last signed. Please review and accept the new version."
      - `@reason == "expired"`: "Your NDA acceptance has expired. Please review and re-accept."
      - `@reason.nil?`: no banner.
      Style: Bootstrap `alert alert-info` div. Include ERB header comment.
      Verify: visit acceptance URL with each reason param — correct banner text. No reason — no banner.

- [ ] 3.3 Add `GET /nda_acceptances/lapsed` route to `config/routes/core.rb`. Add
      `get :lapsed, on: :collection` inside the `nda_acceptances` resource block.
      Verify: `rails routes | grep lapsed` — shows `lapsed_nda_acceptances GET /nda_acceptances/lapsed`.

- [ ] 3.4 Add `lapsed` action to `NdaAcceptancesController`. Authorize via
      `authorize NdaAcceptance.new(nda_config: @nda_config), :show?`. Set `@return_to`. Render
      `lapsed` template. Include YARD comment on the action (see LLD Method Contracts →
      NdaAcceptancesController).
      Verify: visit `/nda_acceptances/lapsed?nda_config_id=X&folder_id=Y` as LP user — renders
      without error.

- [ ] 3.5 Create `lapsed.html.erb` view
      (`app/packs/core/nda_configs/views/nda_acceptances/lapsed.html.erb`). Model on
      `declined.html.erb` — same `turbo_frame_tag "documents_frame"`, same logo/back pattern.
      Show: folder name, expiry date via `l(@nda_config.validity_date)`, message "This NDA expired
      on [date]", contact email (if present), "Back to Data Rooms" link. No form, no checkbox, no
      Accept/Decline buttons. Include ERB header comment explaining this is a dead-end page for
      specific-date expired NDAs.
      Verify: visit the lapsed URL — page renders with correct content, no form elements.

- [ ] 3.6 Write `features/core/nda_reacceptance.feature` covering worked examples H1, H2, H4,
      H5, E2, E4, E11, X1 (LP sees expired note, LP re-accepts after expiry, LP sees updated note,
      LP re-accepts after version bump, lapsed dead-end page, lapsed with contact email, lapsed
      without contact email, invalid reason param ignored).
      Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/nda_reacceptance.feature`
      and confirm it passes before starting phase 4.

## 4. Dashboard Expired Status

- [ ] 4.1 Modify `NdaStatusResolver#build_investor_rows`
      (`app/packs/core/nda_configs/services/nda_status_resolver.rb`). Insert version and time
      expiry checks between the `accepted?` check and the `"Accepted"` return. Add private method
      `acceptance_expired?(acceptance)` that checks version match and validity period (see LLD
      Method Contracts → NdaStatusResolver). Each investor row gains `:expiry_reason` key (nil,
      "version", or "period"). Include YARD comment on the new method.
      Verify: `rails c` — call `NdaStatusResolver.resolve(nda_config, folder)` with a version-mismatched
      acceptance — investor row shows status "Expired" with expiry_reason "version".

- [ ] 4.2 Update `compute_counters` and `empty_result` in `NdaStatusResolver` to include
      `:expired` key. Add `when "Expired" then c[:expired] += 1` case.
      Verify: `rails c` — counters hash includes `:expired` key.

- [ ] 4.3 Update dashboard views to show Expired status. In `nda_status/index.html.erb`
      (`app/packs/core/nda_configs/views/nda_status/index.html.erb`): add Expired badge with
      reason indicator (tooltip showing "Version" or "Period"), add Expired to the status filter
      dropdown, add Expired counter to the summary row. In `nda_status/_summary.html.erb`
      (`app/packs/core/nda_configs/views/nda_status/_summary.html.erb`): add Expired counter badge.
      Include ERB header comments on the changes.
      Verify: visit dashboard with expired investors — Expired badge visible, counter correct,
      filter works.

- [ ] 4.4 Update XLSX export (if exists) to include "Expired" status and reason column. If the
      export template is in the NdaStatus controller or a separate exporter, add the Expired
      status and expiry_reason to the export data.
      Verify: export XLSX — Expired investors included with reason column.

- [ ] 4.5 Write `features/core/nda_dashboard_expired.feature` covering worked examples H8, H9,
      E6, E8, E10 (Expired for version mismatch on dashboard, Expired for time expiry on
      dashboard, Pending unaffected by version bump, retroactive validity change on dashboard,
      exempt after time expiry on dashboard).
      Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/nda_dashboard_expired.feature`
      and confirm it passes before starting phase 5.

## 5. Integration & QA

- [ ] 5.1 Run all NDA Cucumber features together to verify no regressions:
      `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/nda_version_bump.feature features/core/nda_gate_expiry.feature features/core/nda_reacceptance.feature features/core/nda_dashboard_expired.feature`
      Fix any failures.

- [ ] 5.2 Run `bundle exec rubocop` on all modified files. Fix any offenses.

- [ ] 5.3 Run the full existing NDA feature suite to confirm no regressions in Modules 1–3:
      `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber --tags @nda`
      Fix any failures.

- [ ] 5.4 Deploy to staging and run `qa-checklist.md` manually. Record sign-off in the QA
      checklist document (tester, build, environment, date, result, open defects).
