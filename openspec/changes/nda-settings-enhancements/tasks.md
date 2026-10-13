# Tasks

> **Phase gate:** each numbered group below is a phase. A phase's last task is always to run its
> Cucumber feature and get it green. Do not start the next phase until that happens — if it fails,
> fix the phase you're on rather than moving forward and coming back later.

> **Note:** This change is already implemented on branch `fix/nda-resign-on-override-inheritance`
> (4 commits). The tasks below document what was done and what remains (cleanup + testing).

## 1. NDA Status Dropdown Fix and Cleanup

- [x] 1.1 Add `style="overflow: visible;"` on `.table-responsive` div and `table` element in
      `app/packs/core/nda_configs/views/nda_status/index.html.erb`. Add `data-bs-display="static"`
      on the kebab dropdown toggle button. Verify by opening NDA Status with 1 investor → kebab
      dropdown renders fully visible. (LLD: [File Map](#file-map) ⑦)
- [ ] 1.2 Write `features/core/nda_settings_dropdown.feature` covering H5 (single-row dropdown
      visible) and E9 (multiple-row regression). Run with
      `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/nda_settings_dropdown.feature`
      and confirm it passes before starting phase 2.

## 2. Resign Checkbox on Override

- [x] 2.1 In `NdaConfigsController#new`, detect `params[:override]`, resolve `effective_nda_config`
      via `@folder.effective_nda_config`, count accepted investors scoped to folder via
      `Investor.owner_access_rights`, set `@inherited_accepted_count`. (LLD: [Method Contracts](#method-contracts))
- [x] 2.2 In `_form.html.erb`, add resign checkbox section: visible when `!persisted? &&
      inherited_accepted_count > 0`. Use `check_box_tag` for `nda_config[resign_required]`,
      unchecked by default. Show accepted count in info banner. (LLD: [File Map](#file-map) ②)
- [x] 2.3 In `NdaConfigsController#create`, capture `effective_nda_before_override` before
      `@folder.update!(nda_inheritance_mode: "own")`. Read `resign_required` from params via
      `ActiveModel::Type::Boolean.new.cast`. Pass actual value to `create_version_record`.
      (LLD: [Controllers, Params and Responses](#controllers-params-and-responses))
- [x] 2.4 Add private method `migrate_inherited_acceptances(source_nda, target_nda)`. Scope source
      acceptances to `folder_investor_ids`. Create copies with `nda_version: 1`, preserved
      `accepted_at`, include `entity_id`. Rescue `RecordNotUnique`/`RecordInvalid`.
      (LLD: [Method Contracts](#method-contracts))
- [x] 2.5 In `create` action, call `migrate_inherited_acceptances` when `!resign_required &&
      effective_nda_before_override&.enabled?`. Verify by: parent NDA with LP accepted → Set Own
      NDA on child → leave resign unchecked → save → child NDA Status shows LP as Accepted.
- [ ] 2.6 Remove all 4 `Rails.logger.info("[NDA_DEBUG]...")` lines from the `create` action.
      Verify by grepping: `grep -n "NDA_DEBUG" app/packs/core/nda_configs/controllers/nda_configs_controller.rb`
      returns no results. (LLD: [Error Mapping](#error-mapping-and-logging))
- [ ] 2.7 Write `features/core/nda_resign_on_override.feature` covering H1 (resign unchecked,
      acceptances migrated), H2 (resign checked, fresh start), E1 (no inherited acceptances,
      no checkbox), E2 (parent acceptances untouched after override), and X1 (duplicate
      acceptance rescue). Run with
      `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/nda_resign_on_override.feature`
      and confirm it passes before starting phase 3.

## 3. Validity Locking and Expiry Summary

- [x] 3.1 In `NdaConfigsController#edit`, compute `@accepted_count` via
      `nda_acceptances.where(status: "accepted").select(:investor_id).distinct.count`.
      For `fixed_period`: pluck `accepted_at`, compute `@earliest_expiry` and `@latest_expiry`
      as `min/max + validity_days.days`. (LLD: [Queries and Indexes](#queries-and-indexes))
- [x] 3.2 In `_form.html.erb`, compute `validity_locked = persisted? && accepted_count > 0`.
      Add `disabled: validity_locked` to all three validity type radio buttons. Show lock icon
      and explanation text. Filter `period_options` to `>= current_days`. Set date min to
      current `validity_date` when locked. (LLD: [File Map](#file-map) ④)
- [x] 3.3 In `_form.html.erb`, add expiry summary display: for `fixed_period` show
      "Earliest expiry: [date] · Latest expiry: [date]"; for `specific_date` show
      "All NDAs expire on: [date]". Only when `persisted?` and data exists.
      (LLD: [File Map](#file-map) ⑤)
- [ ] 3.4 Write `features/core/nda_validity_locking.feature` covering H3 (locked validity with
      expiry summary), E3 (no acceptances, radios enabled), E4 (no accepted dates, no summary),
      E6 (fixed period dropdown filtered), E7 (specific date min enforced), and E8 (specific
      date expiry summary). Run with
      `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/nda_validity_locking.feature`
      and confirm it passes before starting phase 4.

## 4. Expired NDA Edit Fix

- [x] 4.1 In `_form.html.erb`, change `date_min` computation for the locked case from
      `nda_config.validity_date.to_s` to `[nda_config.validity_date, Date.tomorrow].max.to_s`.
      Verify by: set NDA to expired specific_date via console (`update_columns`) → open edit →
      click Save → form submits. (LLD: [Method Contracts](#method-contracts))
- [ ] 4.2 Write `features/core/nda_expired_edit.feature` covering H4 (save expired NDA with new
      date) and E5 (save expired NDA changing only email). Run with
      `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/nda_expired_edit.feature`
      and confirm it passes before starting phase 5.

## 5. Final Verification

- [ ] 5.1 Traceability coverage check: list every H/E/X ID in design.md and every ID comment
      in `features/core/nda_settings_*.feature` and `features/core/nda_resign_*.feature` and
      `features/core/nda_validity_*.feature` and `features/core/nda_expired_*.feature`. Confirm
      the two sets are equal — no ID without a scenario, no scenario without an ID.
- [ ] 5.2 Run `bundle exec rubocop` on all changed files and fix any offenses.
      (LLD: [Project Rules Checklist](#project-rules-checklist))
- [ ] 5.3 Run full NDA feature suite:
      `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/nda_settings_dropdown.feature features/core/nda_resign_on_override.feature features/core/nda_validity_locking.feature features/core/nda_expired_edit.feature`
      and confirm all green.
- [ ] 5.4 Run QA checklist (`qa-checklist.md`) on a deployed build and record sign-off in the
      checklist's Sign-off table.
