# Tasks — nda-data-room-module-5

> **Phase gate:** each numbered group below is a phase. A phase's last task is always to run its
> Cucumber feature and get it green. Do not start the next phase until that happens — if it fails,
> fix the phase you're on rather than moving forward and coming back later.

## 1. Data model

- [ ] 1.1 Add migration `add_nda_inheritance_mode_to_folders`: `nda_inheritance_mode` (string(10), not null, default: "inherit"). Add index on `[nda_inheritance_mode]`. Verify: `git diff db/schema.rb` shows only the new column and index.
- [ ] 1.2 Add data migration `backfill_nda_inheritance_mode_for_existing_configs`: sets `nda_inheritance_mode = "own"` for all folders that have an associated `NdaConfig` where `owner_type = 'Folder'` and `deleted_at IS NULL`. All other folders stay at the default `"inherit"`. Verify: `rails runner "puts Folder.where(nda_inheritance_mode: 'own').count"` matches the count of folders with NdaConfig records.
- [ ] 1.3 Add validation on `Folder`: `validates :nda_inheritance_mode, inclusion: { in: NDA_INHERITANCE_MODES }`. Add `NDA_INHERITANCE_MODES = %w[inherit own opt_out].freeze` constant. Add convenience methods: `nda_inheriting?`, `nda_opted_out?`, `nda_has_own?`. Verify: `rails runner` — validation rejects invalid values; methods return correct booleans.
- [ ] 1.4 Add `effective_nda_config` on `Folder`: checks opt-out first (`return nil if nda_opted_out?`), then checks own enabled config, then recurses on parent. Memoized as `@_effective_nda_config`. Add `nda_source_folder` method that returns the folder owning the effective config. Memoized as `@_nda_source_folder`. Private helper `resolve_effective_nda` returns `[config, source_folder]`. Verify: `rails runner` — opt-out returns nil; own returns self; inherited returns ancestor's config; source folder returns correct ancestor.
- [ ] 1.5 Write `features/core/nda_inheritance_model.feature` covering model-level worked examples: H1 (direct child inherits), H2 (grandchild inherits), E1 (grandchild inherits child's override), E2 (child of opted-out has no NDA), E4 (no NDA in ancestry), E5 (new folder inside opted-out parent). Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/nda_inheritance_model.feature` until green.

## 2. Inheritance resolver (batch)

- [ ] 2.1 Add `NdaInheritanceResolver` in `app/packs/core/nda_configs/services/nda_inheritance_resolver.rb`: takes a flat list of folders and a config_map hash (`{ folder_id => NdaConfig }`), provides `effective_config_for(folder)` and `source_folder_for(folder)`. Resolves top-down with memoization in `@resolved` hash. O(N) for N folders. Zero DB queries. Verify: `rails runner` on a tree with mixed own/inherited/opted-out folders — correct resolutions.
- [ ] 2.2 Integrate resolver into `DocumentHelper`: build `@nda_resolver` from the preloaded folder tree (already `.includes(:nda_config)` from Module 1). Pass `@nda_resolver` to the tree partial via `locals`. Verify: dev server — folder tree renders; no N+1 queries in logs.
- [ ] 2.3 Write `features/core/nda_inheritance_resolver.feature` covering batch resolution: resolver returns correct effective config and source folder for own, inherited, opted-out, and no-NDA folders. Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/nda_inheritance_resolver.feature` until green.

## 3. Folder tree icons

- [ ] 3.1 Update `_tree_view.html.erb` to use `@nda_resolver.effective_config_for(folder)` and `@nda_resolver.source_folder_for(folder)` instead of direct `folder.nda_required?` for lock icon rendering. Show:
  - Solid lock icon for folders where `nda_inheritance_mode == "own"` and enabled NdaConfig exists.
  - Solid lock + `<span class="text-muted small ms-1">(Inherited)</span>` for folders where `nda_inheritance_mode == "inherit"` AND `@nda_resolver.effective_config_for(folder)` is present.
  - No icon for opted-out folders and folders with no NDA in ancestry.
  - Icons visible to GP/admin only (existing guard).
  Verify: dev server — correct icons on own, inherited, and opted-out folders.
- [ ] 3.2 Update `_tree_caret.html.erb` to add the "(Inherited)" label and tooltip for inherited folders. Tooltip: `title="Inherits NDA from: #{folder.nda_source_folder&.name}"`. Uses `folder.effective_nda_config` and `folder.nda_source_folder` directly for single-folder Turbo Stream updates (max 2-3 hops, acceptable). Verify: dev server — hovering shows correct tooltip.
- [ ] 3.3 Write `features/core/nda_inheritance_tree.feature` covering tree icon worked examples: solid lock for own, lock + "(Inherited)" for inherited, no icon for opted-out, tooltip shows source folder name, icons GP-only. Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/nda_inheritance_tree.feature` until green.

## 4. Settings tab variants

- [ ] 4.1 Add `detect_inheritance_state` private method to `NdaConfigsController`: determines `@inheritance_state` as one of: `:own_with_parent`, `:own_no_parent`, `:inherited`, `:opted_out`, `:fresh`. Called in `new` and `edit` actions before rendering. Sets `@effective_config`, `@source_folder`, and `@parent_has_nda` instance variables. Verify: dev server — correct state detected for each folder type.
- [ ] 4.2 Update `_modal.html.erb` to render the correct partial based on `@inheritance_state`: `:inherited` → `_settings_inherited`, `:opted_out` → `_settings_opted_out`, `:own_with_parent` → `_form` with revert option, `:own_no_parent` and `:fresh` → `_form` standard. Verify: dev server — correct partial renders for each state.
- [ ] 4.3 Create `_settings_inherited.html.erb` partial:
  - Header: "This folder inherits NDA from: [source_folder.name]"
  - Read-only display of parent's NDA details (document name, validity, acceptance method).
  - Three radio buttons (`inheritance_choice`): "Use parent's NDA" (selected), "Set different NDA for this folder", "No NDA required for this folder."
  - When "Set different NDA" is selected: expand the full Module 1 config form inline (via Stimulus toggle).
  - Save button.
  Verify: dev server — partial renders correctly; radio buttons work.
- [ ] 4.4 Create `_settings_opted_out.html.erb` partial:
  - Header: parent NDA info + "This folder is opted out."
  - Three radio buttons with "No NDA required" selected.
  - Save button.
  Verify: dev server — partial renders correctly.
- [ ] 4.5 Modify existing `_form.html.erb` for own-NDA folders that have a parent with NDA: add a "Remove this NDA and use parent's" link below the form. Only visible when `@parent_has_nda` is true. Verify: dev server — option visible only when parent has NDA.
- [ ] 4.6 Write `features/core/nda_inheritance_settings.feature` covering Settings tab worked examples: H5 (inherited tab), E8 (own with revert), E9 (opted-out tab), fresh folder (no NDA context). Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/nda_inheritance_settings.feature` until green.

## 5. Controller state transitions

- [ ] 5.1 Extend `NdaConfigsController` create/update actions to handle the `inheritance_choice` param:
  - `"use_parent"` → wrap in transaction: set `nda_inheritance_mode = "inherit"`, destroy any own NdaConfig (soft-delete via `acts_as_paranoid`).
  - `"set_own"` → wrap in transaction: create/update `NdaConfig` with submitted params, set `nda_inheritance_mode = "own"`.
  - `"opt_out"` → wrap in transaction: set `nda_inheritance_mode = "opt_out"`, destroy any own NdaConfig (soft-delete).
  Turbo Stream response: replace modal + replace target folder caret + replace descendant carets (inheriting descendants only: `@folder.descendants.where(nda_inheritance_mode: "inherit")`).
  Verify: dev server — each transition works; database state correct; folder tree icons update.
- [ ] 5.2 Add confirmation prompt for opt-out: `data-turbo-confirm` attribute on the form when `inheritance_choice = opt_out`. Text: "LPs will be able to access this folder without accepting an NDA. Are you sure?" Verify: dev server — prompt appears on opt-out save.
- [ ] 5.3 Update `create.turbo_stream.erb` and `update.turbo_stream.erb` to include descendant caret replacements for inheriting descendants. Verify: dev server — descendant icons update on save.
- [ ] 5.4 Write `features/core/nda_inheritance_transitions.feature` covering transition worked examples: H6 (override), H7 (opt-out), H9 (revert), E7 (parent NDA removal uncascades), E10 (acceptances preserved on revert), H3/H4 (cross-folder acceptance coverage), E3 (own NDA on child of opted-out), E6 (different configs need separate acceptance). Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/nda_inheritance_transitions.feature` until green.

## 6. Stimulus and auto-inherit

- [ ] 6.1 Extend `nda_settings_controller.js` to handle inheritance radio buttons: toggling "Set different NDA" expands the full config form inline (Bootstrap collapse or `d-none` toggle). Other radios collapse it. Verify: dev server — form expands/collapses on radio change without server round-trip.
- [ ] 6.2 Verify that new folders are created with default `nda_inheritance_mode = "inherit"` (column default). Verify: dev server — create a new folder inside an NDA-protected parent; it shows lock + "(Inherited)" and inherits the NDA. Also verify: new folder inside opted-out parent resolves to no NDA.
- [ ] 6.3 Update `FoldersController` to permit `nda_inheritance_mode` in params (needed for admin operations). Verify: `grep -n nda_inheritance_mode app/packs/core/folders/controllers/folders_controller.rb` shows the param.
- [ ] 6.4 Write `features/core/nda_inheritance_ui.feature` covering: H8 (auto-inherit on new folder), E5 (new folder inside opted-out), Stimulus form expand/collapse, X1 (LP denied), X2 (GP without rights denied). Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/nda_inheritance_ui.feature` until green.

## 7. Status tab and wrap-up

- [ ] 7.1 Update Status tab rendering for inherited folders: the controller passes the `effective_nda_config` to the status view. Add heading: "Showing NDA status for: [source_folder.name]." Verify: dev server — Status tab on inherited folder shows parent config's data with the clarifying heading.
- [ ] 7.2 Verify `NdaInheritanceResolver` resolves the entire folder tree with no N+1 queries — check Rails log for query count during tree rendering.
- [ ] 7.3 Verify backward compatibility: `effective_nda_config` on folders that had NDA before Module 5 returns the same config as `nda_config` (since those are backfilled to `own`). Module 2 gate, Module 3 status service, and Module 4 expiry job all work correctly.
- [ ] 7.4 Add YARD-style "Changed/Why" comments on all modified existing files (folder.rb, nda_configs_controller.rb, folders_controller.rb, document_helper.rb, _form.html.erb, _modal.html.erb, _tree_view.html.erb, _tree_caret.html.erb, nda_settings_controller.js).
- [ ] 7.5 Verify Rubocop clean: `bundle exec rubocop --only-changed`.
- [ ] 7.6 Verify Brakeman clean: `bundle exec brakeman -q`.
- [ ] 7.7 Run full NDA Cucumber suite: `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/nda_config.feature features/core/nda_inheritance_model.feature features/core/nda_inheritance_resolver.feature features/core/nda_inheritance_tree.feature features/core/nda_inheritance_settings.feature features/core/nda_inheritance_transitions.feature features/core/nda_inheritance_ui.feature` — all green.
- [ ] 7.8 /code-review gate before marking the module complete.
