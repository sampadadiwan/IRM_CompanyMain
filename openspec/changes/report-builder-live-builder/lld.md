# Report Builder with live preview, and a reworked guided wizard — Low-Level Design

> **Audience:** The developer who reviews the implementation plan before coding starts.
> **Companion documents:** [Design](design.md) · [Spec](specs/) · [Business rules](business-rules.md) · [Tasks](tasks.md)

> **Planning phase — no code changes.** Adds to [design.md](design.md).

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
- [Security Review](#security-review)
- [Configuration and Rollout](#configuration-and-rollout)
- [Test Plumbing](#test-plumbing)
- [Project Rules Checklist](#project-rules-checklist)
- [Sign-off](#sign-off)

---

## Review Summary

- **Stream responder on every mutating action.** Check that each builder action calls `respond_with_builder_update` and that HTML (wizard) and JSON (API) callers keep their current responses ([Controllers](#controllers-params-and-responses)).
- **Splitting `edit.html.erb`** into a shell and tab partials happens first, with no behaviour change, and is verified by the existing features before anything else changes.
- **Undo digest.** `ReportBuilderUndo` stores a digest of the template's definition after the removal. Any later definition change makes undo refuse. Check which keys are in the digest ([Method Contracts](#method-contracts)).
- **Pick-list queries** are `distinct.limit(31)` and skipped for the four large tables ([Queries](#queries-and-indexes)).
- **Health check** queries are bounded. The filter check only runs when the report is empty.
- **Auto-join on bulk add** of a related key whose relation isn't configured (used by wizard step 2). This is limited to `ReportBuilderModelDiscovery.associations_for` (curated, pack-gated).

---

## File Map

Under `app/packs/core/base/` unless shown.

| Boundary | File | New / Modified | Responsibility |
|---|---|---|---|
| ① | `views/report_builder/edit.html.erb` | Modified | Shell: header, settings frame, preview frame, modals |
| ① | `views/report_builder/_builder_header.html.erb` | New | Name, root badge, Guide, ⌘K, Health badge (`report_builder_health` frame), Templates, Guided setup, Export, Open report |
| ① | `views/report_builder/_settings_panel.html.erb` + `_tab_columns`, `_tab_related`, `_tab_filters`, `_tab_sort`, `_tab_formulas`, `_tab_delivery` | New | One partial per tab (content moved from `edit.html.erb`) |
| ② | `views/report_builder/_column_groups.html.erb` | New | Grouped checkboxes + Add selected (shared with wizard step 2) |
| ② | `models/report_builder_column_catalog.rb` | Modified | `grouped_for(config, relation = nil)`, label disambiguation, `_id`/`_cents` hiding for pickers |
| ③ | `views/report_builder/_preview_table.html.erb` | Modified | `builder:` local → header dropdowns |
| ③ | `views/report_builder/_column_menu.html.erb` | New | One header dropdown |
| ④ | `models/report_builder_filter_field.rb` | New | Kind, operators, options, value validation |
| ④ | `views/report_builder/_filter_row.html.erb` | New | One filter row (server-rendered; builder and wizard) |
| ⑤ | `views/report_builder/_formula_modal.html.erb` | New | Column buttons, expression, sample table |
| ⑥ | `controllers/concerns/report_builder/builder_updates.rb` | New | `respond_with_builder_update` |
| ⑥ | `models/report_builder_undo.rb` | New | snapshot / restore / drop |
| ⑥ | `controllers/report_builder_controller.rb` | Modified | bulk add, `move_column`, `undo`, `pivot_preview`, `filter_row`, stream responses, `validate_formula` samples; `after_action :drop_undo` |
| ⑧ | `controllers/concerns/report_builder/wizard.rb` | New | Wizard actions moved out of the controller: steps, old-step redirects, `wizard_fund`, `wizard_save`, step 1 cards |
| ① | `app/javascript/controllers/confirm_controller.js` | Modified | The confirm popup copies the original form's `data-turbo-frame`, so a confirmed removal answers with the builder's streams (and its Undo) |
| ② | `app/javascript/controllers/report_builder_select_controller.js` | New | Counts ticked columns, filters the picker and the step 1 cards |
| ⑥ | `helpers/report_builder_helper.rb` | Modified | `remove_join_summary(relation, column_labels)`, `wizard_filter_sentences(config, entity)`; the inline filter-row helper is removed (now `_filter_row`) |
| ⑦ | `models/report_builder_health_check.rb` | New | Checks → items |
| ⑦ | `views/report_builder/_health.html.erb` | New | Badge + panel (shared) |
| ⑦ | `models/report_builder_pivot_aggregator.rb` | Modified | `preview_columns(limit:)` (distinct values without running the pivot); a Count of an amount is a row count, not money |
| ⑦ | `models/report_builder_query_engine.rb` | Modified | `pivot_preview`, `rows_scope`, `related_scope(relation)` for the health check |
| ⑦ | `models/report_builder_child_aggregator.rb` | Modified | A Count of an amount column is a row count, not cents ÷ 100 (found by H2) |
| ⑧ | `views/report_builder/wizard/new.html.erb` | Modified | Card grid |
| ⑧ | `views/report_builder/wizard/show.html.erb`, `fund_filters.html.erb`, `order.html.erb`, `check.html.erb` | New | Steps 2–5 |
| ⑧ | `views/report_builder/wizard/{columns,joins,aggregates,filters,sort,review}.html.erb`, `_pivot_form`, `_help_box` | Removed | Replaced by the steps above |
| ⑧ | `views/report_builder/wizard/_steps.html.erb` (replaces `_progress`), `_header`, `_footer_nav`, `_sample` | New / Modified | 5-step bar as nav pills; the 5-row sample frame |
| ⑧ | `views/report_builder/wizard/_summary_cards.html.erb` | New | Plain-language summary (wizard step 5; reusable by Phase 4) |
| ⑧ | `models/report_builder_suggestions.rb` | New | Suggested formulas and name |
| ⑧ | `app/assets/stylesheets/custom/report_builder_wizard.scss` (+ its import) | Removed | App components instead |
| JS | `app/javascript/controllers/report_builder_controller.js` | Modified | Remove `switchMode`; `addSelected`/`toggleSelect`, `filterChanged` (debounce, validate, stream save), formula insert + samples, `pivotPreview`, `undo`, stream-aware `_save` |
| Routes | `config/routes/core.rb` | Modified | `move_column`, `undo`, `pivot_preview`, `wizard_fund`, `wizard_save` |
| Tests | `features/core/report_builder/editor_{live,columns,filters,formulas,undo,health,pivot,page}.feature`, `wizard.feature` (rewritten) | New / Modified | business-rules.md IDs |
| Tests | `features/step_definitions/report_builder_editor_steps.rb`, `report_builder_wizard_steps.rb` (rewritten) | New / Modified | Steps |
| Docs | `docs/user_guides/report_builder_user_guide.md` | Modified | Layout, header menus, filters, undo, health, wizard |

**Reviewer checks**
- [ ] Every class in the class diagram has a file here
- [ ] Removed wizard views aren't referenced anywhere (grep `wizard/columns` etc.)

---

## Schema Detail

N/A — no tables or columns change. `reports.template["undo"]` = `{ "token" => String(16 hex), "at" => ISO8601, "label" => String, "template" => Hash (definition without "undo"), "gvps" => [{key, name, label, sequence}], "after_digest" => String(SHA256) }`.

**Reviewer checks**
- [ ] The snapshot never nests a previous snapshot (`template` excludes `"undo"`)

---

## Method Contracts

**`ReportBuilder::BuilderUpdates`** (controller concern)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `respond_with_builder_update(notice:, level: :success, undo_token: nil, status: :ok)` | — | renders | — | runs the preview (20 rows) and the health check | Yes |

**`ReportBuilderUndo`**

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `.snapshot!(report, label:, before:, removed:)` | Report, String, Hash (template before the removal), Array<GVP> (rows removed) | token | — | writes `template["undo"]` with the removed rows' attributes and the after-removal digest | No (new token) |
| `.restore!(report, token, now: Time.current)` | Report, String | `[:ok, label]` or `[:refused, reason]` | — | restores template and GVPs; clears `undo` | Yes (second call refused) |
| `.drop!(report)` | Report | — | — | removes `undo` if present | Yes |
| `.definition_digest(template)` | Hash | String | — | — | Yes — SHA256 of JSON of `root_model, joins, aggregates, root_filters, sort, formulas, group_rows_by, currency` + GVP keys/labels/sequence |

**`ReportBuilderFilterField`** (`new(config:, relation:, key:, entity:)`)

| Method | Returns |
|---|---|
| `#kind` | `:date`, `:boolean`, `:fund`, `:number`, `:choice`, `:text` |
| `#operators` | `[[label, predicate]]` per the design table |
| `#options` | `[[label, value]]` for `:boolean`, `:fund`, `:choice`; else `[]` |
| `#validate(op, value)` | `nil` or a message ("needs a value", "Enter a date like 19/08/2026", "Enter a number") |
| `LARGE_TABLES` | `%w[account_entries capital_remittances capital_distribution_payments documents]` |
| `CHOICE_LIMIT` | 30 |

**`ReportBuilderHealthCheck`** (`new(report:, entity:)`)

| Method | Returns |
|---|---|
| `#items` | `[{level:, message:, tab:}]`, warnings first |
| `#warnings_count` | Integer |
| `EXPORT_INFO_ROWS` | 50_000 |
| `PIVOT_WARN_COLUMNS` | 20 |

**`ReportBuilderSuggestions`**

| Method | Returns |
|---|---|
| `.for(config, gvps)` | `[{name:, expression:, in_words:, added: Boolean}]` |
| `.name(config, gvps, entity)` | String |

**`ReportBuilderColumnCatalog.grouped_for(config, relation = nil)`** → `[{kind:, label:, columns: [{key:, label:, hint:, icon:}]}]`.

**`ReportBuilderPivotAggregator#preview_columns(limit: 5)`** → `{count:, headers: [String]}`; raises nothing (invalid columns → `{error:}`).

**Reviewer checks**
- [ ] `restore!` refuses on token mismatch, age > 10 min, or digest mismatch
- [ ] `drop!` runs (as an `after_action`, so a refused request never touches it) on every action that changes the definition: `update_template add_column update_column_label add_join update_aggregate update_sort update_pivot update_join_settings move_column add_formula remove_formula apply_template`. Not on `remove_column` / `remove_join` (they take the snapshot), `undo`, renaming the report or delivery settings (outside the digest).

---

## Controllers, Params and Responses

| Action | Permitted params | Policy method | Success response | Failure response |
|---|---|---|---|---|
| `add_column` (changed) | `key` or `keys[]`, `tab` | `update?` | streams "N columns added" (+ red part naming refused keys) / redirect | streams red "No columns added — <keys> aren't available" |
| `remove_column` (changed) | `gvp_id` | `update?` | streams "Removed <label> — Undo" | 404 |
| `remove_join` (changed) | `relation` | `update?` | streams "Removed <relation> and N columns — Undo" | — |
| `move_column` (new) | `gvp_id`, `direction` ∈ left/right | `update?` | streams | 422 bad direction / at the end |
| `undo` (new) | `token` | `update?` | streams "Restored <label>" | 422 streams with the reason |
| `pivot_preview` (new, GET) | `relation`, `group_bys[]`, `value_col` | `update?` | JSON `{count, headers}` | 422 `{error}` |
| `validate_formula` (changed) | `expression` | `update?` | JSON `{ok, error, samples}` | — |
| `update_column_label`, `update_aggregate`, `update_sort`, `update_template`, `update_pivot`, `update_join_settings`, `add_join`, `add_formula`, `remove_formula`, `apply_template` (changed) | as today | `update?` | streams when the request accepts Turbo Streams; else as today | as today |
| `preview` (changed) | `q`, `limit` (1–20), `builder` | `show?` | partial (builder mode adds header menus) | error card (E19) |
| `wizard_create` (changed) | `root_model` | `create?` | redirect to step `show` | step 1 with "Choose one of the listed tables" |
| `wizard_step` (changed) | `step` ∈ show, fund_filters, order, check; old names redirect | `update?` | page | redirect |
| `wizard_fund` (new) | `fund_id` or `all` | `update?` | redirect to `fund_filters` | — |
| `wizard_save` (new) | `name` | `update?` | redirect to the report page | — |

**Reviewer checks**
- [ ] No action without `authorize`
- [ ] `keys[]` can't add columns outside `column_key_allowed?`; `fund_id` must belong to `current_user.entity`

---

## Queries and Indexes

| Where | Query shape | Index used | Rows expected | Preload / batching |
|---|---|---|---|---|
| Pick-list | `RootOrChild.where(entity_id:).unscope(:order).distinct.limit(31).pluck(col)` — skipped for `LARGE_TABLES` | `entity_id` | ≤ 31 | — |
| Fund options | `Fund.where(entity_id:).order(:name).pluck(:name, :id)` | `entity_id` | tens | — |
| Mixed currencies | `Fund.where(id: child_scope.select(:fund_id)).distinct.count(:currency)` | FK indexes | 1 row | — |
| Filter matches nothing | `root_scope_with(filter).count` per root filter, only when total is 0 | as root filters | ≤ number of filters | — |
| Pivot size | `child_scope.distinct.count(group cols)` via `preview_columns` | child FK | 1 row | — |
| Formula samples | `engine.run(limit: 5)` | as engine | 5 | — |

**Reviewer checks**
- [ ] No `distinct` query on the four large tables
- [ ] `unscope(:order)` before `distinct.pluck` (MySQL DISTINCT/ORDER)

---

## Transactions, Locking and Concurrency

| Operation | Transaction scope | Lock | Race it prevents | Idempotency key |
|---|---|---|---|---|
| Bulk add | GVPs + aggregates + auto-join | none | half-added selection | `exists?(key:)` per key |
| Remove + snapshot | GVP delete + template update | none | snapshot without removal | token |
| Undo restore | template + GVP recreate | `report.lock!` | double undo | token cleared inside the transaction |

**Reviewer checks**
- [ ] Undo restore locks the report row

---

## Background Jobs

N/A — no jobs.

**Reviewer checks**
- [ ] None

---

## External Integrations

N/A.

**Reviewer checks**
- [ ] None

---

## Error Mapping and Logging

| Exception | Raised in | Handled by | User sees | Logged / alerted |
|---|---|---|---|---|
| Engine error in preview | `preview` | rescue → error card | message in the preview frame | warn with report id |
| Health check error | `ReportBuilderHealthCheck` | rescue in `_health` render | "Health unavailable" | warn with report id |
| Undo refused | `ReportBuilderUndo.restore!` | 422 stream | reason | none |
| Invalid move | `move_column` | 422 | red toast | none |

**Reviewer checks**
- [ ] No bare rescue without a log line naming the report

---

## Security Review

| Concern | Decision |
|---|---|
| Authorization | `authorize @report` on every action (`update?` for changes, `show?` for preview) |
| Tenant isolation | Engine entity scoping unchanged; fund options and `wizard_fund` limited to `current_user.entity` funds; undo restores only GVPs of the same report |
| Input / output | Labels for bulk add from the catalog, not params; toast text escaped (Phase 1); popup HTML built with `tag`/`safe_join` |
| Mass assignment | Params listed above only |

**Reviewer checks**
- [ ] A user of another entity can't call undo, move, pivot_preview or wizard actions on the report (X1, X5)

---

## Configuration and Rollout

| Item | Value / location |
|---|---|
| Credentials / env vars | None |
| Feature flag | None |
| Deploy order | Code only; precompile assets (wizard stylesheet removed) |
| Rollback | Revert. `template["undo"]` keys are ignored by the old code. |

**Reviewer checks**
- [ ] `report_builder_wizard.scss` import removed from the manifest with the file

---

## Test Plumbing

| Feature file | Stubs / fixtures | Factories | New step definitions |
|---|---|---|---|
| `editor_columns`, `editor_filters`, `editor_formulas`, `editor_undo`, `editor_health`, `editor_pivot`, `editor_page` | Acme fixture; `travel_to` (E12); export threshold stub (E18); extra investors/commitments (E8, E17) | as Phase 1 | `report_builder_editor_steps.rb`: stream requests (`Accept: text/vnd.turbo-stream.html`), stream target assertions, health item assertions |
| `editor_live` (`@javascript`) | Acme fixture | as Phase 1 | browser steps for menus, filters, formula editor |
| `wizard` | Acme fixture | as Phase 1 | rewritten wizard steps |

Every run: `TEST_ENV_NUMBER=$RANDOM`; Redis on 6379.

---

## Project Rules Checklist

| Rule | Applies? | How it is met |
|---|---|---|
| No `blank?`/`present?` on relations | Applies | Health uses `count`/`exists?` |
| Dedup in SQL, batch bulk operations | Applies | `distinct.limit(31).pluck`; bulk add loops over ≤ tens of keys |
| `account_entries` hygiene | Applies | No pick-list on large tables; no new `account_entries` reads |
| Screen dates via `l(...)`; date inputs via `date_field_tag` | Applies | Filter dates use `date_field_tag` + `locale-date` |
| JS dates via `locale_date_format.js` | Applies | Date validation reads the hidden ISO input; no JS date library |
| Entity scoping; Pundit on every action | Applies | See Security Review |
| MCP ontology | N/A | No MCP change |
| Cucumber only; `TEST_ENV_NUMBER=$RANDOM` | Applies | — |
| RuboCop clean incl. `IRM/RelationBlankPresent` | Applies | — |
| Reuse existing UI styling | Applies | `nav-pills`, standard tables/badges/buttons; wizard stylesheet removed |

---

## Sign-off

| Reviewer | Date | Decision | Notes |
|---|---|---|---|
| | | | |
