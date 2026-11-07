# Table columns and custom fields in place — Low-Level Design

> **Audience:** The developer who reviews the implementation plan before coding starts.
> **Companion documents:** [Design](design.md) · [Business rules](business-rules.md) · Specs: [columns](specs/ui/grid-columns-inline-settings/spec.md), [fields](specs/forms/custom-fields-inline-settings/spec.md) · [Tasks](tasks.md)

> **Planning phase — no code changes.** Adds to [design.md](design.md); links rather than repeats.

---

## Contents

- [Review Summary](#review-summary)
- [File Map](#file-map)
- [Schema Detail](#schema-detail)
- [Method Contracts](#method-contracts)
- [Controllers, Params and Responses](#controllers-params-and-responses)
- [Queries and Indexes](#queries-and-indexes)
- [Transactions, Locking and Concurrency](#transactions-locking-and-concurrency)
- [Background Jobs](#background-jobs)
- [External Integrations](#external-integrations)
- [Error Mapping and Logging](#error-mapping-and-logging)
- [Security Detail](#security-detail)
- [Configuration and Rollout](#configuration-and-rollout)
- [Test Plumbing](#test-plumbing)
- [Project Rules Checklist](#project-rules-checklist)
- [Changed during the build](#changed-during-the-build)
- [Sign-off](#sign-off)

---

## Review Summary

- New `GridColumnsController` (`settings`, `save`) with three params — design [D3](design.md#d3-new-gridcolumnscontroller).
- Signed `GridColumnsContext` carries what the table showed — design [D2](design.md#d2-signed-column-context).
- `GridColumnsSave` replaces the owner's rows under an owner row lock — design [D4](design.md#d4-replace-the-set-in-one-locked-transaction).
- Key allowlist from `GridColumnOptions` (extracted from `configure_grids`, behaviour unchanged) — design [D5](design.md#d5-key-allowlist), [D7](design.md#d7-gridcolumnoptions-extracted).
- Two flagged existing-model edits: `GridViewPreference#touch_entity` touches a Report owner; `RansackTableHeader` form-type lookup ordered by id and cache key versioned by report — design [D6](design.md#d6-form-type-auto-created), [D10](design.md#d10-fresh-report-columns).
- `side_panel.js` extracted from `widget_settings_controller.js` (behaviour unchanged) — design [D12](design.md#d12-shared-panel-helpers-and-styles).
- Phase 3: `FormTypeFieldsController` + `FormTypeFieldsSave` on the Form Types nested update — design [D14](design.md#d14-fields-save-through-the-form-types-nested-update);
  icon from `display_custom_fields` anchor row — [D13](design.md#d13-fields-icon-from-display_custom_fields-via-an-anchor-row);
  positions reslotted — [D15](design.md#d15-positions-reslotted-within-the-listed-fields); page refresh — [D16](design.md#d16-page-refresh-in-place-after-a-fields-save).
- Flagged existing-code edits (phase 3): `FormTypesController#update` calculation guard moved to
  `FormType#calculation_change_allowed?` (same rule); `FormTypeHelper#display_custom_fields` renders the anchor.

**Reviewer checks**
- [ ] Every item above has a matching row in the File Map

---

## File Map

| Box | File | New / Modified | Responsibility |
|---|---|---|---|
| ① | `app/packs/core/components/ransack_table.html.erb` | Modified | `grid-columns-host` wrapper; render `grid_columns/_button` |
| ① | `app/packs/core/components/ransack_table_header.rb` | Modified | `grid_columns_context`, `grid_columns_allowed?` (memoised); `form_type` via `GridColumnsContext.form_type_for`; cache key with report record |
| ① | `app/packs/misc/grid_view_preferences/views/grid_columns/_button.html.erb` | New | Icon link (`header:` local) |
| ① (phase 2) | `capital_commitments/_index_ag`, `account_entries/_index_ag`, `interests/_index_ag`, `portfolio_investments/_index.html.erb` (AG branch) | Modified | Host wrapper + `_button` |
| ① | `app/packs/misc/grid_view_preferences/model/grid_columns_context.rb` | New | PORO; token sign/verify; owner lookup |
| ② | `app/javascript/controllers/grid_columns_controller.js` | New | Panel shell, open, Esc, saved marker, frame reload, shimmer, toast |
| ②⑦ | `app/javascript/custom/side_panel.js` | New | `showToast`, `prefersReducedMotion`, `bindEscape` |
| ②⑦ | `app/javascript/controllers/widget_settings_controller.js` | Modified | Import helpers from `side_panel.js` (no behaviour change) |
| ③ | `app/packs/misc/grid_view_preferences/controller/grid_columns_controller.rb` | New | `settings`, `save` |
| ③ | `app/packs/misc/grid_view_preferences/views/grid_columns/settings.html.erb` | New | Panel body in frame `grid_columns` |
| ③ | `app/javascript/controllers/grid_columns_form_controller.js` | New | Drag, rename, remove, add, reset, serialise |
| ④ | `app/packs/misc/grid_view_preferences/services/grid_columns_save.rb` | New | Replace rows |
| ④ | `app/packs/misc/grid_view_preferences/views/grid_columns/_saved.html.erb` | New | Saved marker |
| ⑤ | `app/packs/misc/grid_view_preferences/services/grid_column_options.rb` | New | Addable columns, grouped |
| ⑤ | `app/packs/misc/grid_view_preferences/controller/grid_view_preferences_controller.rb` | Modified | `configure_grids` uses `GridColumnOptions` |
| ⑤ | `app/packs/misc/grid_view_preferences/model/grid_view_preference.rb` | Modified | `touch_entity` touches Report owner |
| ⑤ | `app/packs/misc/grid_view_preferences/policies/grid_view_preference_policy.rb` | Modified | `inline_columns?` |
| ⑦ | `app/assets/stylesheets/custom/grid_columns.scss` | New | Host/icon, list rows, chips (picked up by `custom/*` import) |
| — | `config/routes/misc.rb` | Modified | `get 'grid_columns/settings'`, `patch 'grid_columns/save'`; `grid_view_preferences` without `new`/`create` (D19) |
| ① (D18) | `grid_columns/_button.html.erb`, `grid_columns_controller.js`, `grid_columns.scss` | Modified | Visible button; moved next to the search box |
| D19 | `grid_columns/_editor.html.erb` | New | The list, add controls and Save, shared by the panel and Configure Grids |
| D19 | `grid_view_preferences/configure_grids.html.erb` | Modified | Renders `_editor` embedded + per-row Show / Edit / Delete |
| D19 | `GridViewPreferencesController` | Modified | `configure_grids` builds the owner's context; `new`, `create` removed |
| D19 | `grid_view_preferences/new.html.erb` | Removed | Adding is in the shared list |
| D19 | `features/core/custom_grid_view.feature` + steps, security steps for M15/L14 | Modified | Adds go through the shared list; create/new scenarios retargeted |
| D19 | `features/security/allowlists/*` | Modified if listed | Removed actions dropped |
| ① (P3) | `app/packs/misc/form_types/helpers/form_type_helper.rb` | Modified | `display_custom_fields` renders `_anchor` when `custom_fields:` is empty and allowed |
| ① (P3) | `app/packs/misc/form_types/views/form_type_fields/_anchor.html.erb` | New | Hidden `<tr>` with controller + settings URL |
| ② (P3) | `app/javascript/controllers/form_type_fields_controller.js` | New | Place icon on card, open panel, saved → `refreshPage` |
| ③ (P3) | `app/packs/misc/form_types/controllers/form_type_fields_controller.rb` | New | `settings`, `save` |
| ③ (P3) | `app/packs/misc/form_types/views/form_type_fields/settings.html.erb`, `_saved.html.erb` | New | Panel body; saved marker |
| ③ (P3) | `app/javascript/controllers/form_type_fields_form_controller.js` | New | Drag, rename, flags, help, remove/undo, add, serialise |
| ④ (P3) | `app/packs/misc/form_types/services/form_type_fields_save.rb` | New | Build nested attrs, update, reslot, link record |
| ④ (P3) | `app/packs/misc/form_types/models/form_type.rb` | Modified | `calculation_change_allowed?(user, attrs)` |
| ④ (P3) | `app/packs/misc/form_types/controllers/form_types_controller.rb` | Modified | `update` uses `calculation_change_allowed?` |
| ④ (P3) | `app/packs/misc/form_types/policies/form_type_policy.rb` | Modified | `inline_fields?` |
| — (P3) | `config/routes/core.rb` | Modified | `get 'form_type_fields/settings'`, `patch 'form_type_fields/save'` |
| ⑦ (P3) | `app/assets/stylesheets/custom/grid_columns.scss` | Modified | Field row toggles, removed state (shared list styles) |
| Tests (P3) | `features/core/custom_fields_inline_settings.feature`, `features/security/custom_fields_inline_settings_isolation.feature`, `features/step_definitions/custom_fields_inline_settings_steps.rb` | New | §3 rows |
| Tests | `features/core/grid_columns_inline_settings.feature`, `features/security/grid_columns_inline_settings_isolation.feature`, `features/step_definitions/grid_columns_inline_settings_steps.rb` | New | H/E/X |

- The grid_view_preferences pack keeps its folder names (`model/`, `controller/`, `services/`, `policies/`, `views/`);
  `services/` is new in form_types (same pack).

**Reviewer checks**
- [ ] The 22 index views are not edited in phase 1
- [ ] None of the 36 show views is edited in phase 3
- [ ] No new file outside the grid_view_preferences pack except the component, JS, scss, routes

---

## Schema Detail

N/A — no schema change. `grid_view_preferences.label` is `varchar(255)`; the 100-character heading limit is an
app rule (spec "Save validation").

**Reviewer checks**
- [ ] No migration in the diff

---

## Method Contracts

| Method | Signature | Returns | Notes |
|---|---|---|---|
| `GridColumnsContext.new` | `(model_class:, entity:, report: nil, shown:, required: [], excluded: [])` | context | `shown`: ordered `Array<[label, key]>`, keys cleaned (`split(";").first.strip`), snapshot column removed |
| `GridColumnsContext#to_token` | `→ String` | signed | `message_verifier(:grid_columns).generate(payload, expires_in: 12.hours, purpose: :grid_columns)`; payload ids + strings only |
| `GridColumnsContext.from_token` | `(token, user:) → context` | context | Raises `ActiveRecord::RecordNotFound` on invalid/expired token, unknown model (`model_class_from_param` + `STANDARD_COLUMNS`), entity not `users_firm?`; report via `ReportPolicy::Scope` |
| `GridColumnsContext.form_type_for` | `(entity, model_class) → FormType?` | first by id | `entity.form_types.where(name:).order(:id).first` — used by header and save |
| `GridColumnsContext#owner` | `→ Report \| FormType` | owner | report if given, else the explicit form type (payload `f`, D19/E26), else `form_type_for`, else `FormType.new(entity:, name:)` (unsaved) |
| `GridColumnsContext.for_owner` | `(owner) → context` | context | Form Types / Reports pages: model from `FormType#name` / `Report#model`, `shown` = standard columns, form type id or report |
| `GridColumnOptions#call` | `(model_class, entity_id) → {group => {label => key}}` | grouped | Same entries as today's `configure_grids` `@field_options`, grouped |
| `GridColumnOptions#allowed_key?` | `(key) → Boolean` | — | Clean-key compare against every value |
| `GridColumnsSave.call` | `(user:, context:, rows:, reset:) → Result(ok?, errors, owner)` | Result | See steps below |
| `GridViewPreferencePolicy#inline_columns?` | `→ Boolean` | — | `create? && !user.curr_role_investor? && (!owner.is_a?(Report) \|\| ReportPolicy.new(user, owner).update?)` |
| `RansackTableHeader#grid_columns_allowed?` | `→ Boolean` | memoised | `STANDARD_COLUMNS` defined, user + entity present, policy `inline_columns?` on `GridViewPreference.new(owner: context.owner, entity_id: entity.id)` |

- `GridColumnsSave` steps:
  1. Parse `rows` (JSON array, ≤ 100 items, each `{id?, key?, label?}`); bad JSON → error "Columns could not be read".
  2. `transaction`: owner = `context.owner`; `FormType` new → `save!` (tag default "Default"); `owner.lock!`.
  3. `reset` → `owner.grid_view_preferences.destroy_all`; skip to 7.
  4. Resolve each row: `id` → `existing[id]` (skip if missing — E5); else `key` → `options.allowed_key?(key) || context.shown_key?(key)`, else error "{key} cannot be added" + rollback (X4).
  5. Dedup by clean key, first wins (E8); none left → error "Keep at least one column" (X6).
  5b. D20 — each row may carry `data_type` (∈ `DATA_TYPES`, else "X is not a data type" — X19) and `alignment`
      (∈ `text-start text-center text-end` or blank; an unchanged stored value is kept); a derived row
      (`derived: true`) carries `key` (required, ≤ 255) and `label` (required) — new derived rows are created with
      `derived_field: true`, `name: label`.
  6. Destroy existing rows not kept; kept rows: `label` = submitted (blank → nil; > 100 → error); new rows: `create!(key:, name: GridViewPreference.get_column_name(context.form_type_or_model, key), label:, entity_id: owner.entity_id)`; then every row `set_list_position(i + 1)`.
  7. Steps 2–6 run inside `GridViewPreference.no_touching` (Entity, Report); after commit: `owner.is_a?(Report) ? owner.touch : owner.entity.touch`.
- `get_column_name(parent, key)` takes the FormType or Report (it resolves `parent.name`/`parent.model`) — same as `GridViewPreferencesController#create`.

**Phase 3 contracts**

| Method | Signature | Returns | Notes |
|---|---|---|---|
| `FormTypeFieldsController#load_record` | private | record | `klass = model_class_from_param(params[:record_type])`; 404 unless `klass.include?(WithCustomField)`; `policy_scope(klass).find(params[:record_id])`; `authorize record, :show?` |
| `FormTypeFieldsController#form_type_for(record)` | private | FormType | record's form type, else the firm's `.last` by name (same pick as `setup_form_type`), else `FormType.new(entity: record.entity, name: klass.name)` |
| `FormTypePolicy#inline_fields?` | `→ Boolean` | — | `update? && !user.curr_role_investor?` |
| `FormType#calculation_change_allowed?` | `(user, attrs_list) → Boolean` | — | support user, local env, or no Calculation in the attrs — today's controller rule |
| `FormTypeFieldsSave.call` | `(user:, form_type:, record:, fields:) → Result(ok?, errors)` | Result | Steps below |

- `FormTypeFieldsSave` steps:
  1. Parse `fields` JSON (≤ 200 items); bad JSON → "Fields could not be read".
  2. Transaction: new form type → `save!`; `form_type.lock!`; load `form_custom_fields` once, index by id.
  3. Existing item → skip if id unknown (E18), regulatory, or calculation and not `user.support?` (X16); attrs
     `label`, `required`, `read_only`, `internal`, `help_text` (cast), plus `_destroy`.
  4. New item → label blank → error (X14); `field_type` not in Text/Number/Date/TextArea/CheckBox/Select/Money
     → error; Select options blank → "Add at least one option" (X15); attrs `name: FormCustomField.to_name(label)`,
     `label`, `field_type`, `meta_data` (options, or `entity.currency` for Money — E20).
  5. `form_type.update(form_custom_fields_attributes: attrs)`; errors (name uniqueness → "A field named X already
     exists", X13) → rollback, Result errors; `RecordNotUnique` → same message.
  6. Reslot: listed survivors' current positions sorted → assigned in panel order; new fields after the max
     position; `set_list_position` each (D15).
  7. `record.update_column(:form_type_id, form_type.id)` when it was nil (H13, E13) — only the link is written.

**Reviewer checks (phase 3)**
- [ ] `FormTypesController#update` behaves the same after the guard extraction (existing Form Types features)
- [ ] An existing field's `name`, `field_type`, `meta_data`, conditions, `vr_*`, `step` are never in the attrs (E17, X17)
- [ ] Regulatory fields keep their positions (E16)

**Reviewer checks**
- [ ] `configure_grids` renders the same `@field_options` (same keys, same order) before/after D7
- [ ] A derived row's `key`, `data_type`, `alignment` are never assigned in the save (E1)
- [ ] Positions are 1..n after any save (E6)
- [ ] Label blank → `nil`, so `GridViewPreference#label` falls back to `name` (E7)

---

## Controllers, Params and Responses

| Action | Route | Loads | Authorize | Params | Success | Failure |
|---|---|---|---|---|---|---|
| `settings` | `GET /grid_columns/settings` | `GridColumnsContext.from_token(params[:context], user:)` | `GridViewPreference.new(owner:, entity_id:)`, `:inline_columns?` | `context` | 200, frame `grid_columns` (layout false) | 404 bad token / model / report; 403 policy |
| `save` | `PATCH /grid_columns/save` | same | same | `context`, `rows`, `reset` | 200 frame `_saved` | 422 frame `settings` with errors and the submitted rows; 403; 404 |

- Permitted: `params.permit(:context, :rows, :reset)`; anything else ignored (X8).

| Action (P3) | Route | Loads | Authorize | Params | Success | Failure |
|---|---|---|---|---|---|---|
| `FormTypeFieldsController#settings` | `GET /form_type_fields/settings` | record via `policy_scope`; form type as above | record `show?`, form type `inline_fields?` | `record_type`, `record_id` | 200 frame `form_type_fields` | 404 model/record; 403 |
| `FormTypeFieldsController#save` | `PATCH /form_type_fields/save` | same | same | + `fields` | 200 `_saved` (`data-refresh="page"`) | 422 panel with errors and the submitted list |
- `verify_authorized` applies (controller inherits the after_action from `ApplicationController` pattern used by
  `GridViewPreferencesController`).

**Reviewer checks**
- [ ] No `verify_authorized` exclusion
- [ ] `rows` is never passed to `update`/`new` as a hash
- [ ] Fields actions: `record_type`, `record_id`, `fields` only; `fields` never passed through as params
- [ ] 422 renders inside the frame

---

## Queries and Indexes

| Query | Shape | Index |
|---|---|---|
| Form type for model | `form_types WHERE entity_id = ? AND name = ? ORDER BY id LIMIT 1` | `index_form_types_on_entity_id` |
| Owner rows | `grid_view_preferences WHERE owner_type = ? AND owner_id = ? ORDER BY sequence` | `index_grid_view_preferences_on_owner` |
| Report has rows (header) | `EXISTS ... owner_type='Report' AND owner_id=?` | same |
| Options | `form_types WHERE entity_id = ? AND name IN (...)` + `form_custom_fields` preload | existing |

| Record's form type fields (P3) | `form_custom_fields WHERE form_type_id = ? ORDER BY position` | `form_type_id` FK index |
| Firm form type for model (P3) | `form_types WHERE entity_id = ? AND name = ? ORDER BY id DESC LIMIT 1` | `index_form_types_on_entity_id` |

- No large tables touched (CLAUDE.md list); no `blank?/present?` on relations — `exists?` for "report has rows".

**Reviewer checks**
- [ ] `PROSOPITE=1` run shows no N+1 on settings, save and table renders
- [ ] No `pluck(...).uniq`

---

## Transactions, Locking and Concurrency

| Case | Mechanism | Outcome |
|---|---|---|
| Two admins save the same owner | `owner.lock!` (SELECT … FOR UPDATE) | Second waits, then replaces whole set |
| Double click | Same as above + replace semantics | Same rows (E6) |
| Two first saves, no form type | `FormType` name uniqueness (non-multiple models); multiple-allowed models: both may create — header and save use lowest id | One form type used |
| Row deleted between panel open and save | Missing id skipped | E5 |
| Two admins save fields of one form type | `form_type.lock!` | Second applies on top of the first |
| Double click on fields Save | Button disabled while saving; a repeated add fails uniqueness | One field (E22) |

**Reviewer checks**
- [ ] `lock!` happens before reading existing rows
- [ ] Touch happens after the transaction, once

---

## Background Jobs

N/A — the save is a fast request (≤ ~40 rows).

**Reviewer checks**
- [ ] No job added

---

## External Integrations

N/A — none.

**Reviewer checks**
- [ ] No HTTP calls

---

## Error Mapping and Logging

| Condition | Exception / result | HTTP | User sees |
|---|---|---|---|
| Bad / expired token | `ActiveSupport::MessageVerifier::InvalidSignature` → `RecordNotFound` | 404 | Not found |
| Unknown model / no `STANDARD_COLUMNS` | `RecordNotFound` | 404 | Not found |
| Report outside scope | `RecordNotFound` | 404 | Not found |
| Policy refuses | `Pundit::NotAuthorizedError` | 403 (app handler) | Existing refusal |
| Bad JSON / forged key / empty / label too long | `Result(errors)` | 422 | Message in the panel |

- Nothing logged beyond the request log; `rows` holds no PII.

**Reviewer checks**
- [ ] Forged-key message names the key, escaped

---

## Security Detail

| Action | Policy method | Load scope | Permitted params | Scenario |
|---|---|---|---|---|
| `GridColumnsController#settings` | `GridViewPreferencePolicy#inline_columns?` | Context entity must be `users_firm?`; report via `ReportPolicy::Scope`; form type via that entity | `context` | X1, X2, X3, X5, X9 |
| `GridColumnsController#save` | same | same | `context`, `rows`, `reset` | X1–X9 |
| Icon render | same (memoised per table) | header entity | — | X1, X2 |
| `FormTypeFieldsController#settings` | record `show?` + `FormTypePolicy#inline_fields?` | `policy_scope(klass)`; form type via the record | `record_type`, `record_id` | X10, X11, X12, X18 |
| `FormTypeFieldsController#save` | same | same | + `fields` | X10–X18 |
| Fields anchor render | `inline_fields?` once per call | page's record | — | X10, X11 |

- Keys reaching `ransack_table_row`'s `send` chain come only from `GridColumnOptions`, the signed `shown` list, or
  rows already stored (D5).
- Brakeman run on the diff before the gate.

**Reviewer checks**
- [ ] `features/security/grid_columns_inline_settings_isolation.feature` covers every row
- [ ] Brakeman: 0 new warnings

---

## Configuration and Rollout

- No flag; the icon follows the existing company-admin rule.
- Phase 1 (Ransack tables) and phase 2 (AG grids) ship separately; each passes its gate.
- Token key: `Rails.application.message_verifier(:grid_columns)` (secret_key_base) — no new credential.

**Reviewer checks**
- [ ] Phase 2 can be skipped without breaking phase 1

---

## Test Plumbing

- Phase 3 steps: custom fields via `FormCustomField.create!`; records on / without a form type; panel selectors
  `[data-form-type-fields-row]`, `[data-form-type-fields-add]`, `[data-flag=required]`; scroll kept checked via
  `window.scrollY` before and after.
- Steps: log in as company admin (existing), create form type + custom field, saved columns via
  `GridViewPreference.create!`, open a table, click `.grid-columns-btn`, panel actions by `data-` selectors
  (`[data-grid-columns-row]`, `[data-grid-columns-add]`, `[data-grid-columns-reset]`).
- Drag in Playwright: `locator.drag_to`; fallback a "move up" keyboard path is not added (YAGNI).
- Direct requests: `@rack_test` with a token generated by `GridColumnsContext#to_token` in the step; tampered =
  last char changed; expired = `travel 13.hours`.
- Distinct `TEST_ENV_NUMBER` per run; Redis up.

**Reviewer checks**
- [ ] Each scenario carries its `# H1 — …` comment

---

## Project Rules Checklist

| Rule | Applies | How |
|---|---|---|
| Large-table hygiene | N/A | No large table read |
| No `blank?`/`present?` on relations | Applies | `exists?` for report rows |
| Dedup in SQL | N/A | Dedup is of the submitted list |
| Date formatting | Applies (P3) | Field values render through the existing `display_custom_fields` renderers; nothing new |
| Tenant scoping | Applies | Context entity `users_firm?`, report scope, owner entity |
| MCP ontology | N/A | No ransackable change |
| `IRM/RelationBlankPresent` cop | Applies | rubocop on changed files |
| Inline comments | Applies | Steps commented with H/E/X IDs |
| Authorization in policies | Applies | `inline_columns?` only |
| Reuse UI styling | Applies | Widget settings panel copied |
| Ask before changing existing models | Applies | `GridViewPreference#touch_entity`, `FormType#calculation_change_allowed?` (extraction) — approved 2026-11-07 |

**Reviewer checks**
- [ ] rubocop clean on changed files

---

## Changed during the build

| Log # | What changed | Why |
|---|---|---|
| B1 | `_button` uses `ti-table-options` + label; `grid_columns.scss` hides the label at the corner | Design B1 |
| B2 | `configure_grids.html.erb` two columns + `_detail_empty`; `show`/`edit` wrapped in frame `grid_column_detail`; `update` redirects to `configure_grids` with `show_id` | Design B2 |
| B3 | `GridViewPreferencesController#edit_params` → `GridColumnsSave.stored_label` | Design B3 |
| B4 | `_row` selects carry `data-initial`; `grid_columns_form_controller#serialise` sends only changes | Design B4 |
| B5 | `GridColumnOptions#build_groups` maps relationships `to_s` | Design B5 |
| B6–B9 | Phase 2: 14 lists (Deals dropped); `LIST_COLUMNS` / `GRID_COLUMNS` per model, decorators, `RansackTable#money_column_indexes`; Allocations/Investment Opportunities keep server sort/pagy; added columns named by their offered label; Allocations row passes the undecorated record to sale policies | Design B6–B9 |
| B10, B12 | `form_type_fields_controller.js#placeButton`: form card header → collapsible card's minimize button → breadcrumb bar → card corner; `custom_form_fields` renders the anchor too; `FormTypeFieldsController#load_form_type` (`form_type_id`, no record) | Design B10, B12 |
| B11 | `FormTypeFieldsSave` skips calculation rows for non-support users with no local exception | Design B11 |
| B13 | `ExpressionOfInterestsController#eoi_row_stream` — approve/update re-render the row with the list's columns | Phase 2 regression |
| B14 | Funds list: responsive details on (▶ expander), so a firm's extra columns fold instead of vanishing | User report 2026-11-07 |

---

## Sign-off

| Reviewer | Date | Decision |
|---|---|---|
| | | |
