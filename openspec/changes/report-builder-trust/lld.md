# Report Builder you can trust — Low-Level Design

> **Audience:** The developer who reviews the implementation plan before coding starts.
> **Companion documents:** [Design](design.md) · [Spec](specs/) · [Tasks](tasks.md)

> **Planning phase — no code changes.** Adds to [design.md](design.md); links to its diagrams and worked examples rather than repeating them.

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

- **Anchored join = `ReportBuilderChildAggregator` with `base_class: root, fk: "id", joins: <path>`**: the riskiest change, because `bare_col`/`db_col` must resolve the whole path from the root. See [Method Contracts](#method-contracts) and [Queries](#queries-and-indexes).
- **Merge lookup by longest configured relation prefix** replaces `split(".", 2).first`. Check it with a first-level and a two-step join on the same relation (H4).
- **Placeholder GVP keys `formula:<key>` / `pivot:<relation>`.** Check that every GVP consumer ignores or handles them ([File Map](#file-map) lists each touch point).
- **Plain-text `READERS` instead of decorators.** Decorators return HTML and need a request; the catalog mirrors the few decorator-only columns as plain-text readers with a declared preload. The drift guard checks every reader's preload is a real association ([Queries](#queries-and-indexes)).
- **`update_aggregate` now refuses unknown totals (422).** Existing callers only send allowed values; check the wizard form and the JS.
- **Excel Totals sheet removed.** `xlsx_exporter.feature` expectations change ([Test Plumbing](#test-plumbing)).

---

## File Map

All paths under `app/packs/core/base/` unless shown otherwise.

| Boundary | File | New / Modified | Responsibility |
|---|---|---|---|
| ① | `controllers/report_builder_controller.rb` | Modified | `add_column` stores default total; `update_aggregate` validates; formula/pivot/join actions manage placeholders; new `update_join_settings`; `view` sort override + totals; `preview` `PREVIEW_LIMIT`; `columns_for_model` delegates to ② |
| ① | `config/routes/core.rb` | Modified | `patch ':id/join_settings', action: :update_join_settings, as: :update_report_builder_join_settings` |
| ① | `models/report_builder_config.rb` | Modified | `effective_aggregate(key)`, `only_with_rows?(relation)` |
| ② | `models/report_builder_column_catalog.rb` | New | `columns_for`, `filter_only_for`, `filter_columns_for`, `related_columns_for`, `preloads_for`, `read`, `READERS` |
| ③ | `models/report_builder_column_type.rb` | New | `AGGREGATES`, `type_for`, `default_aggregate`, `strategy_for`, `totalable?`, `aggregate_label` |
| ④ | `models/report_builder_query_engine.rb` | Modified | `root_scope` (filters + only-with-rows + preloads), strategies, merge by longest prefix, root reads via `ReportBuilderColumnCatalog.read`, placeholder expansion, `sort_override`, `computed_sort_capped?` |
| ④ | `models/report_builder_child_aggregator.rb` | Modified | Anchored mode (`bare_col` keeps the full path for anchored and strips only the first segment for grouped deep keys); polymorphic type condition; `value` internal aggregate (= MAX) for one-per-row |
| ④ | `models/report_builder_pivot_aggregator.rb` | Modified | Header label prefixed with relation label; polymorphic type condition |
| ④ | `models/report_builder_dynamic_column.rb` | Modified | Optional `relation` and `kind` (`:pivot`/`:formula`) attributes used by ③/⑥ |
| ⑤ | `services/report_builder_formula_service.rb` | Modified | `Money` → `BigDecimal` before Dentaku |
| ⑥ | `models/report_builder_value_formatter.rb` | New | `display`, `align`, `xlsx` |
| ⑥ | `models/report_builder_totals.rb` | New | Totals hash + label |
| ⑦ | `components/report_builder_table.rb` / `.html.erb` | Modified | Formatter cells, header sort links, `<tfoot>` totals, capped-sort note |
| ⑦ | `views/report_builder/view.html.erb` | Modified | Passes sort + totals to the component; Edit/Export outline buttons kept |
| ⑦ | `views/report_builder/_preview_table.html.erb` | Modified | Formatter cells, totals row, "N of M rows" / "All N rows" |
| ⑦ | `views/report_builder/edit.html.erb` | Modified | Preview copy (20 rows); only-with-rows switch on grouped join cards; Apply Template via `confirm#popup`; sort dropdown handles placeholders |
| ⑦ | `views/report_builder/wizard/aggregates.html.erb` | Modified | `effective_aggregate` selected; `aggregate_label` text |
| ⑦ | `helpers/report_builder_helper.rb` | New | `apply_template_summary(config)`: action-summary cards (pattern of `DocChecksHelper#doc_check_action_summary`) |
| ⑦ | `views/reports/_card.html.erb` | Modified | Builder report name → `view_report_builder_path` |
| ⑦ | `models/report_builder_xlsx_exporter.rb` | Modified | Formatter values/formats; totals last row (bold); `add_totals_sheet` removed |
| ⑦ | `app/javascript/controllers/report_builder_controller.js` | Modified | `_patch` rejects on non-2xx; error toast; restore `data-saved-value`; `toggleOnlyWithRows` |
| ⑦ | `config/locales/report_builder.en.yml` (or existing reports locale) | New/Modified | Toast, totals label, popup card strings |
| Tests | `features/core/report_builder/{related_data,column_catalog,column_order,only_rows,display_formatting,totals,view_sort,builder_ui}.feature` | New | See [Test Plumbing](#test-plumbing) |
| Tests | `features/core/report_builder/{aggregation,formulas,xlsx_exporter,wizard}.feature` | Modified | New scenarios; Totals-sheet expectation replaced |
| Tests | `features/step_definitions/report_builder_steps.rb`, new `report_builder_ui_steps.rb` | Modified / New | Shared "Acme report builder data" setup; UI steps |
| Docs | `docs/user_guides/report_builder_user_guide.md` | Modified | Totals, header sort, only-with-rows, default totals (FAQ per standard) |

**GVP consumers that must handle placeholder keys:** `ReportBuilderQueryEngine#columns` (expands), `pass2` gvp key selection (prefix `<relation>.`, so ignored), `ReportBuilderController#add_formula`/`validate_formula` `allowed_keys` (harmless extra), `default_search_predicate` (skips keys with `:`), `edit.html.erb` sort/grouping dropdowns (formula → `formula_<ts>` key; pivot skipped), `Report#model_columns_hash` (not keyed by placeholders), `ReportBuilderXlsxExporter` (receives expanded `engine.columns`).

**Reviewer checks**
- [ ] Every class in the design's class diagram has a file here, and nothing here is missing from it
- [ ] Files follow the pack layout and Packwerk boundaries (all inside `core/base` plus the JS controller)
- [ ] Every GVP consumer listed above was checked against `formula:`/`pivot:` keys

---

## Schema Detail

N/A — no tables or columns change. New settings are JSON keys in `reports.template`: `joins[].only_with_rows` (boolean). Placeholders are rows in the existing `grid_view_preferences` (`owner_type: "Report"`, `key` `formula:<key>` / `pivot:<relation>`, `name`/`label` the display label, `sequence` via `acts_as_list`).

**Reviewer checks**
- [ ] No migration in the change
- [ ] Placeholder keys fit `grid_view_preferences.key` length (formula keys are `formula_<10 digits>` → 18 chars + prefix)

---

## Method Contracts

**`ReportBuilderColumnType`** (Service, PORO; built per report: `new(config)`)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `AGGREGATES` | — | `%w[sum count avg min max latest list]` | — | — | — |
| `#strategy_for(relation)` | `String` dotted path | `:grouped` / `:anchored_many` / `:anchored_one` / `nil` (unresolvable) | — | — | Yes |
| `#type_for(column)` | GVP or `ReportBuilderDynamicColumn` | `:money` `:number` `:date` `:datetime` `:boolean` `:text` `:unknown` | — | memoised per key | Yes |
| `#default_aggregate(key)` | clean key | one of `AGGREGATES` or `nil` for one-per-row/root | — | — | Yes |
| `#totalable?(column)` | column | Boolean | — | — | Yes |
| `.aggregate_label(agg, type)` | String, Symbol | "Sum", "Latest date", "Any yes", "All yes"… | — | — | Yes |

**`ReportBuilderColumnCatalog`** (Service, class methods, memoised per class in-process)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `.columns_for(klass)` | AR class | `[{label:, key:, raw_key:, raw_label:}]` sorted by label (same shape as today's `columns_for_model`) | — | instantiates `klass.new` once | Yes |
| `.filter_only_for(klass)` | AR class | same shape | — | — | Yes |
| `.related_columns_for(klass)` | AR class | stored columns only (`column_names` or `_cents`) | — | — | Yes |
| `.preloads_for(klass, keys)` | class, clean keys | Array for `includes` | — | — | Yes |

**`ReportBuilderQueryEngine`** (Service)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `.new(report:, entity:, external_filters: {}, sort_override: nil)` | `sort_override: {key: String, dir: "asc"/"desc"}` | — | — | — | — |
| `#run(limit:, offset:, computed_sort_cap:)` | unchanged | `Array<Hash>` | — | reads only | Yes |
| `#count` | — | Integer via `root_scope.count` (same scope as `run`) | — | — | Yes |
| `#columns` | — | ordered columns with placeholders expanded | — | — | Yes |
| `#computed_sort_capped?` | — | true when a computed sort hit the cap | — | — | Yes |

**`ReportBuilderChildAggregator`**: `join_config` gains `mode: :grouped | :anchored`; for `:anchored`, `base_class` is the root class, `fk` is `"id"`, `joins` is the nested-hash form of the path (e.g. `{capital_commitments: :fund}`), `aggregates` may contain `"value"` (internal, `MAX(col)`). Returns `{root_id => {clean_key => value}}` as today.

**`ReportBuilderFormulaService`**: `#evaluate(row)` signature unchanged; converts `Money` with `to_d` before Dentaku.

**`ReportBuilderValueFormatter`** (Service, `new(config:, column_type:, locale: I18n.locale)`)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `#display(value, column)` | any, column | `String` (HTML-safe text, never markup) | — | — | Yes |
| `#align(column)` | column | `"text-end"` / `""` | — | — | Yes |
| `#xlsx(value, column)` | any, column | `[cell_value, format_code_or_nil]` | — | — | Yes |

**`ReportBuilderTotals`** (Service, `new(rows:, columns:, config:, column_type:, scope: :all | :page | :sample)`)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `#call` | — | `{column_key => BigDecimal}` or `nil` when no totalable column | — | — | Yes |
| `#label` | — | "Total" / "Total (this page)" / "Total (these N rows)" | — | — | Yes |

**`ReportBuilderConfig`**: `#effective_aggregate(key, column_type)` → stored or default; `#only_with_rows?(relation)` → Boolean.

**Reviewer checks**
- [ ] Every raised error is handled by a caller or listed in Error Mapping (none are raised to callers: unresolvable paths return `nil`/`{}`)
- [ ] Anything a retry can repeat is idempotent (all read-only except controller actions, which are naturally idempotent)

---

## Controllers, Params and Responses

| Action | Permitted params | Policy method | Success response | Failure response |
|---|---|---|---|---|
| `ReportBuilderController#update_join_settings` (new) | `relation` (must match a `template.joins[].relation`), `only_with_rows` ("true"/"false") | `update?` | JSON `{ok: true}` | 422 `{errors: ["… isn't many-per-row related data"]}` for anchored joins or unknown relation |
| `#update_aggregate` (changed) | `key`, `aggregate` ∈ `AGGREGATES` or blank (clears to default) | `update?` | JSON `{ok: true}` / HTML redirect back | 422 JSON `{errors: ["Unknown total 'median'"]}` / HTML redirect with alert |
| `#add_column` (changed) | unchanged (`key`, `name`, `label`) | `update?` | redirect back | unchanged |
| `#view` (changed) | `q`, `page`, `per_page`, `sort` (String), `dir` ∈ asc/desc | `show?` | HTML | unknown `sort` ignored (no error) |
| `#preview` (changed) | `q` | `show?` | partial | unchanged |

**Reviewer checks**
- [ ] No action without `authorize`
- [ ] Permitted params can't set `entity_id`, `user_id` or other ownership fields (`update_join_settings` touches only `only_with_rows` of an existing join)

---

## Queries and Indexes

| Where | Query shape | Index used | Rows expected | Preload / batching |
|---|---|---|---|---|
| `QueryEngine#root_scope` | `Root.where(entity_id:).ransack(filters).result` `.where(id: Child.where(fk: …)…)` per only-with-rows join → `Child.where(type cond).ransack(child_filters).result.select(fk)` | root `entity_id`; child FK index (e.g. `capital_commitments.investor_id`) | page (≤ 100) / preview 20 / export all | `includes(preloads_for)` when reader columns are selected |
| `ChildAggregator` grouped | `Child.where(fk => root_ids)[.where(type => root.polymorphic_name)].group(fk).select(fk, aggs)` | child FK | ≤ root ids | — |
| `ChildAggregator` anchored | `Root.joins(path).where(id: root_ids).group(root.id).select(root.id, aggs)` | root PK + each association FK | ≤ root ids | — |
| `PivotAggregator` | unchanged + polymorphic condition | child FK | ≤ root ids × distinct values | — |
| `ReportBuilderColumnCatalog` | none (class introspection, `klass.new`) | — | — | memoised |

**Aggregator results are read as plain rows** (`connection.select_all(relation.to_sql)`, the group id aliased `rb_group_id`), not model instances. Found during apply: a partial `SELECT` on `documents` raised `missing attribute 'send_email'` from `Document`'s `after_initialize`, which the rescue turned into a blank column. Min/max/latest/value results are cast with the target column's `type_for_attribute`, so dates and booleans keep their types; sums and counts stay raw numbers. This also avoids building one model per group on large tables.

The root page query keeps `limit/offset`; the export path keeps `computed_sort_cap: nil` (unchanged). `account_entries` is not a curated join for any root, so no new `account_entries` reads are introduced.

**Reviewer checks**
- [ ] Every query is scoped by `entity_id` (root) or by root ids already entity-scoped (pass 2)
- [ ] No N+1 on the report page: reader columns are preloaded; the drift guard fails for a reader whose preload isn't a real association
- [ ] `IN (subquery)` for only-with-rows uses `select(fk)` (no `pluck` of ids into Ruby)

---

## Transactions, Locking and Concurrency

| Operation | Transaction scope | Lock | Race it prevents | Idempotency key |
|---|---|---|---|---|
| `add_formula` + placeholder | one `Report.transaction` | none | formula without placeholder | formula key unique per report |
| `remove_formula` / `update_pivot` clear / `remove_join` + placeholder delete | one `Report.transaction` | none | orphan placeholder | placeholder key |
| `add_column` + default total | one `Report.transaction` | none | GVP without total | `exists?(key:)` guard (existing) |

Concurrent edits by two builders on one report are last-write-wins on the template JSON, as today.

**Reviewer checks**
- [ ] No external HTTP call or email inside a transaction
- [ ] Placeholder create/delete happens in the same transaction as the template update

---

## Background Jobs

N/A — no jobs added. `ReportBuilderExportJob` and `ReportBuilderSchedulerJob` are unchanged; they call the modified exporter.

**Reviewer checks**
- [ ] The export job still passes `computed_sort_cap: nil` and no `sort_override`

---

## External Integrations

N/A — no third-party calls.

**Reviewer checks**
- [ ] None

---

## Error Mapping and Logging

| Exception | Raised in | Handled by | User sees | Logged / alerted |
|---|---|---|---|---|
| `NameError` / `NoMethodError` on reflection walk | `ColumnType#strategy_for`, aggregators | rescue → `nil` / `{}` | Blank column | `Rails.logger.warn "[ReportBuilder] unresolvable relation #{path} report=#{id}"` |
| `ActiveRecord::StatementInvalid` | aggregators | existing rescue in Pivot; added in Child | Blank column | warn with report id + relation |
| Dentaku error | `FormulaService#evaluate` | existing rescue → `nil` | Blank cell | existing warn |
| Decorator method error | engine root read | rescue → `nil` | Blank cell | warn with model, key, record id |
| Unknown aggregate | `update_aggregate` | 422 | Red toast / alert | none |
| Non-2xx `fetch` | JS `_patch` | rejects | Red toast "{setting} wasn't saved — {message}" | `console.error` |

**Reviewer checks**
- [ ] No bare `rescue => e` without a log line naming the report id
- [ ] Log lines carry report id, relation/key and record id where relevant

---

## Security Review

| Concern | Decision |
|---|---|
| Authorization | Existing `ReportPolicy` via `authorize @report` on every action; `update_join_settings` uses `update?` |
| Tenant isolation | Root scope always `where(entity_id: entity.id)`; anchored joins start from those root ids; grouped joins filter by them |
| Secrets | None |
| Input / output sanitisation | `sort` validated against output column keys before use; formatter returns text, rendered escaped; popup HTML built with `tag`/`safe_join` |
| Mass assignment | `update_join_settings` reads `relation` and `only_with_rows` only; template merge isn't used |
| SQL identifiers | Anchored paths are walked through real reflections (`reflect_on_association`) before any identifier is interpolated, the same boundary as `column_key_allowed?` |

**Reviewer checks**
- [ ] A user from another entity cannot reach any record through any route (X5, X8)
- [ ] `sort` never reaches `order()` unless it is a real root column (computed sorts are in Ruby)

---

## Configuration and Rollout

| Item | Value / location |
|---|---|
| Credentials / env vars | None |
| Feature flag | None (bug fixes and presentation; no opt-in) |
| Cron / schedules | None |
| Deploy order | Code only |
| Rollback | Revert the deploy. Placeholder GVP rows created meanwhile are ignored by the old code's engine *only if* skipped. **The old `columns` would render them as blank columns**, so rollback runs `GridViewPreference.where(owner_type: "Report").where("`key` LIKE 'formula:%' OR `key` LIKE 'pivot:%'").delete_all` (documented in tasks) |

**Reviewer checks**
- [ ] Safe to deploy with the feature unused
- [ ] Rollback note for placeholder rows is in the tasks

---

## Test Plumbing

| Feature file | Stubs / fixtures | Factories | New step definitions |
|---|---|---|---|
| `related_data.feature` | — | `:fund`, `:investor`, `:capital_commitment`, `:capital_remittance`, `:capital_remittance_payment`, `:capital_call`, `:document` | `Given the Acme report builder data`; `Given a "<Root>" report with related "<path>" column "<col>" totalled by "<agg>"`; `Then row "<name>" shows "<value>" in "<column>"` |
| `column_catalog.feature` | — | all root factories | `Then the "<Model>" column list (does not) include(s) "<label>"`; drift-guard step iterating `ROOT_MODELS` |
| `column_order.feature` | — | as above | `When I move column "<label>" to position <n>`; `Then the columns of the preview, report page and export are "<list>"` |
| `only_rows.feature` | — | as above | `When I turn on only-with-rows for "<relation>"` |
| `display_formatting.feature` | `ReportBuilderQueryEngine::MAX_COMPUTED_SORT_ROWS` stubbed where needed | as above | `Then the preview and report page show "<value>" for "<column>" of "<row>"` |
| `totals.feature` | — | as above | `Then the totals row "<label>" shows "<value>" under "<column>"` |
| `view_sort.feature` | cap stub (E23) | as above | `When I open the report page sorted by "<column>" "<dir>"` |
| `builder_ui.feature` (`@javascript`) | Playwright route abort for E25 | as above | `When the server refuses the next save`; `Then I see a red toast "<text>"` |
| `xlsx_exporter.feature` | Roo reads | — | `Then the last row of the Data sheet is a bold totals row`; `And there is no "Totals" sheet` |
| `wizard.feature` | — | — | `Then the Summarize total for "<column>" is "<label>" and saved as "<agg>"` |

Every run: `TEST_ENV_NUMBER=$RANDOM`; local Redis up.

---

## Project Rules Checklist

| Rule | Applies? | How it is met |
|---|---|---|
| No `blank?`/`present?` on relations; use `exists?`/`none?` | Applies | New code checks arrays/hashes only; child scopes used in `IN (subquery)`, never materialised |
| Dedup in SQL (`distinct.pluck`), batch bulk operations | Applies | `list` uses `GROUP_CONCAT(DISTINCT)`; placeholder deletes are `where(...).delete_all` on a handful of rows |
| Select only needed columns for many `account_entries`; no speculative `includes` | Applies | No `account_entries` joins; `includes` only for declared reader preloads of selected columns |
| Screen dates via `l(...)`; no human-format `strftime` | Applies | Formatter uses `I18n.l`; Excel uses date cells with a format code, replacing `strftime("%d-%b-%Y")` |
| Date inputs use `f.date_field` / `date_field_tag` | N/A | No date inputs added (typed filters are Phase 2) |
| Every query entity-scoped; Pundit on every action | Applies | Root `entity_id` scope; `authorize @report` on all actions incl. `update_join_settings` |
| MCP tool surfaces only via ontology YAML | N/A | No MCP tool or ransackable change |
| Cucumber only; `TEST_ENV_NUMBER=$RANDOM` | Applies | All scenarios in `features/core/report_builder/` |
| `bundle exec rubocop` clean incl. `IRM/RelationBlankPresent` | Applies | Run on every touched Ruby file |

---

## Sign-off

| Reviewer | Date | Decision | Notes |
|---|---|---|---|
| | | | |
