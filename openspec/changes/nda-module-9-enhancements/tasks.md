# Tasks

> **Phase gate:** each numbered group below is a phase. A phase's last task is always to run its
> Cucumber feature and get it green. Do not start the next phase until that happens — if it fails,
> fix the phase you're on rather than moving forward and coming back later.

## 1. Signatory Gating — Folder Gate & Blocked Page

- [ ] 1.1 Add `GET /nda_acceptances/blocked` route to `config/routes/core.rb`. Define it inside the existing `nda_acceptances` collection block, before the `resources` line to avoid routing conflicts. Verify with `rails routes | grep blocked`. _(LLD: [Controllers, Params and Responses](#controllers-params-and-responses))_

- [ ] 1.2 Add `blocked` action to `NdaAcceptancesController`. The action loads `@nda_config` and `@folder` via existing `before_action`s, builds `@nda_acceptance` for Pundit authorization (`authorize @nda_acceptance, :show?`), and renders `blocked.html.erb`. _(LLD: [Method Contracts](#method-contracts), [Controllers, Params and Responses](#controllers-params-and-responses))_

- [ ] 1.3 Create `app/packs/core/nda_configs/views/nda_acceptances/blocked.html.erb`. Follow the layout pattern from `declined.html.erb` / `lapsed.html.erb`: wrap in `turbo_frame_tag "documents_frame"`, show entity logo, "Non-Disclosure Agreement" title, entity + folder context, `alert-info` with lock icon and message "Please ensure that the authorised signatory has signed the NDA to access the documents.", contact email (if configured), and "Back to Data Rooms" link. No PDF iframe, no Accept/Decline buttons. Include `# frozen_string_literal: true` comment and ERB header comment per project conventions. _(LLD: [File Map](#file-map))_

- [ ] 1.4 Add signatory check branch to `DocumentsController#ensure_nda_accepted`. After the existing exemption check passes and before the acceptance-status redirect, add: if the user is NOT a signatory (`NdaSignatory.exists?(nda_config_id: nda_config.id, user_id: current_user.id)` returns false), redirect to `blocked_nda_acceptances_path(nda_config_id: nda_config.id, folder_id: @folder.id)` and return. The check runs only when NDA is needed and not yet accepted/needs re-acceptance. If the user IS a signatory, fall through to the existing acceptance redirect. _(LLD: [Queries and Indexes](#queries-and-indexes))_

- [ ] 1.5 Verify locally: log in as a non-signatory LP, navigate to an NDA-protected folder → see blocked page. Log in as a signatory LP, navigate to the same folder → see acceptance screen. Log in as exempt LP → folder opens. _(Design: [Walkthrough](#walkthrough-one-example-start-to-finish))_

- [ ] 1.6 Write `features/nda_signatory_gating/folder_gate.feature` covering worked examples H1 (signatory sees acceptance screen), H2 (non-signatory sees blocked page), E2 (non-signatory blocked after version bump), E3 (exempt bypasses gate). Run with `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/nda_signatory_gating/folder_gate.feature` and confirm green before starting phase 2.

## 2. Signatory Gating — Accept/Decline Guard

- [ ] 2.1 Add `ensure_signatory` private `before_action` to `NdaAcceptancesController`, scoped to `only: %i[index create decline]`. It must NOT run on `blocked` (to avoid redirect loop). The guard queries `NdaSignatory.exists?(nda_config_id: @nda_config.id, user_id: current_user.id)` and, if false, redirects to `blocked_nda_acceptances_path(nda_config_id: @nda_config.id, folder_id: params[:folder_id])`. Place it after `set_nda_config` and `set_folder` but before `resolve_investor` in the before_action order. _(LLD: [Controllers, Params and Responses](#controllers-params-and-responses))_

- [ ] 2.2 Verify locally: as a non-signatory LP, manually navigate to the acceptance screen URL → redirected to blocked page. Manually POST to `/nda_acceptances` (accept) → redirected to blocked page, no NdaAcceptance created. Manually POST to `/nda_acceptances/decline` → redirected to blocked page, no NdaAcceptance created. _(Design: [card ④](#④-acceptdecline-guard))_

- [ ] 2.3 Write `features/nda_signatory_gating/accept_decline_guard.feature` covering worked examples E1 (non-signatory POST accept), X1 (non-signatory POST decline), and H1 (signatory can accept). Run with `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/nda_signatory_gating/accept_decline_guard.feature` and confirm green before starting phase 3.

## 3. Auto-Tag Default Signatories & Dashboard Warnings

- [ ] 3.1 Add auto-tag logic to `NdaConfigsController#create`: after successful `@nda_config.save`, query all approved `InvestorAccess` records for this entity, group by `investor_id`, select the oldest record per investor (by `created_at`), and create `NdaSignatory` for each oldest user's `user_id` with `tagged_by_id: current_user.id`. Rescue `ActiveRecord::RecordNotUnique` silently (idempotent). _(Design: [card ⑤](#⑤-auto-tag-signatories))_

- [ ] 3.2 Remove the first-creation redirect (`Turbo.visit()`) from `create.turbo_stream.erb`. The turbo_stream response should only clear the modal, update tree icons, and show flash — no redirect to dashboard. Also remove the `first_creation` param from the `format.html` fallback redirect. _(Design: [card ⑤](#⑤-auto-tag-signatories))_

- [ ] 3.3 Remove first-creation banner and related Stimulus code: remove the `firstCreationBanner` target, `firstCreation` value, and `connect()` hook from `nda_status_controller.js`. Remove the banner div and `data-nda-status-first-creation-value` from `nda_status/index.html.erb`. _(Design: [card ⑥](#⑥-dashboard-warnings))_

- [ ] 3.4 Verify zero-signatory warning on `nda_status/index.html.erb` still works (already implemented). In each investor row's status column, the ⚠ icon shows when no user has `nda_tagged: true` and investor is not exempt. _(Design: [card ⑥](#⑥-dashboard-warnings))_

- [ ] 3.5 Verify locally: as GP, create a new NDA on a folder → modal closes, tree updated, check NDA Status Dashboard → signatories auto-tagged (first user per investor). Update an existing NDA → modal closes normally, no auto-tagging. _(Design: [Walkthrough](#walkthrough-one-example-start-to-finish))_

- [ ] 3.6 Write `features/nda_signatory_gating/auto_tag_and_dashboard.feature` covering worked examples H3 (auto-tag on creation), E4 (update does NOT auto-tag), E5 (zero-signatory warning). Run with `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/nda_signatory_gating/auto_tag_and_dashboard.feature` and confirm green before starting phase 4.

## 4. Full Integration & QA

- [ ] 4.1 Run the full Cucumber suite to check for regressions: `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/nda_signatory_gating/`. Fix any failures.

- [ ] 4.2 Run `bundle exec rubocop` on all changed files and fix any offences.

- [ ] 4.3 Run `qa-checklist.md` on a deployed build (staging or local) and record the sign-off in the checklist's Sign-off table. This task is for QA, not for the apply agent.
