# PRD: Generic Report Builder

**Status:** Draft  
**Date:** 2026-04-22

---

## 1. Problem Statement

Fund managers, compliance officers, and RMs regularly need custom data exports that cut across multiple models — e.g. "all investors with their commitment amounts, total called, KYC status, and number of capital calls received, including investors with no calls". Today this requires a developer. The Report Builder gives non-technical users a self-service UI to compose, save, and download these exports as `.xlsx` files without writing code.

---

## 2. Goals

| # | Goal |
|---|------|
| G1 | Pick any model with `STANDARD_COLUMNS` as the report root |
| G2 | Join to any associated model (has_many, has_one, belongs_to, has_many :through) |
| G3 | Select any columns from root and joined models — no column count limit |
| G4 | Aggregate one-to-many children: sum, count, avg, min, max, latest, list |
| G5 | Filter root and child scopes using Ransack predicates |
| G6 | Root rows always appear even when children are absent (LEFT JOIN / 0 aggregates) |
| G7 | Column selection, ordering, and custom labels managed via existing `GridViewPreference` |
| G8 | Reports respect multi-tenancy (entity scoping) and Pundit policies |
| G9 | Reports can be saved, named, shared, and re-run |
| G10 | Output is a well-formatted `.xlsx` file via caxlsx |

**Out of scope (v1):** Charts, scheduled email delivery, cross-entity reports, raw SQL mode, pivot tables.

---

## 3. Fit with Existing Architecture

### 3.1 What already exists and will be reused

| Existing piece | Role in report builder |
|---------------|----------------------|
| `Report` model | Root record for each saved report (already has all needed associations) |
| `WithGridViewPreferences` concern (already included in `Report`) | Column selection, ordering, custom labels — **no duplication** |
| `GridViewPreference` model | One row per selected column; `sequence` = order; `label` = custom header; `key` = `column_key` or `relation.column_key`; `data_type` for formatting |
| `STANDARD_COLUMNS` constant on each model | The column palette the user picks from |
| `ADDITIONAL_COLUMNS` constant | Extra columns on the same model (tracking amounts etc.) |
| `ADDITIONAL_COLUMNS_FROM` constant | Pre-declared associations whose columns can be joined — extended by the builder |
| `configure_grids` controller action | Column picker UI — reused/extended for the builder |
| `acts_as_list` on `GridViewPreference` | Drag-to-reorder already works |
| `FormType` custom fields | User-defined custom fields appear as selectable columns automatically |
| Ransack (already in use across the app) | Filter language for root and child scopes |
| `caxlsx` / `caxlsx_rails` (already in Gemfile) | XLSX export |
| `Report#template` (`:json` attribute) | Stores builder-specific config (joins, aggregates, filters, sort) |

### 3.2 What is new

- **Builder UI** — multi-step wizard to select root model, add joins, configure aggregates, add filters
- **Query engine** — two-pass strategy (root query + one aggregation query per child relation)
- **Aggregate config** — stored in `Report#template` JSON; linked to `GridViewPreference` keys
- **`include_zero_rows` flag** — per-join toggle (default on) for LEFT JOIN semantics
- **Dynamic join discovery** — exposes any AR association on the root model as a joinable source, not only the ones pre-listed in `ADDITIONAL_COLUMNS_FROM`

---

## 4. Core Concepts

### 4.1 Model Discovery

Any model that defines `STANDARD_COLUMNS` is eligible as a report root. The system discovers them at boot:

```ruby
ReportBuilder::ModelDiscovery.roots
# => All AR subclasses that define STANDARD_COLUMNS and have a table
```

Models without `STANDARD_COLUMNS` can still appear as *join targets* (their DB columns are used directly) but cannot be report roots until they define the constant.

### 4.2 Column Selection via GridViewPreference

Column choices are stored as `GridViewPreference` records on the `Report`, exactly as they are for existing grid views. No new persistence mechanism.

**Column key conventions** (same as current `ADDITIONAL_COLUMNS_FROM` pattern):

| Column source | Key format | Example |
|--------------|-----------|---------|
| Root model field | `column_name` | `investor_name` |
| Belongs-to field (flat join) | `relation.column_name` | `investor_kyc.full_name` |
| Has-many field (aggregated) | `relation.column_name` | `capital_commitments.amount` |
| Custom field (root) | `custom_fields.field_name` | `custom_fields.risk_category` |
| Custom field (joined) | `relation.custom_fields.field_name` | `capital_commitments.custom_fields.notes` |

The `; col-type` suffix convention (`num-col`, `text-col`, `label-col`) is preserved so AG Grid rendering continues to work.

### 4.3 Report Template JSON

`Report#template` stores everything that is NOT column selection (which lives in `GridViewPreference`):

```json
{
  "version": 1,
  "root_model": "Investor",
  "joins": [
    {
      "relation": "capital_commitments",
      "model": "CapitalCommitment",
      "include_zero_rows": true,
      "child_filters": { "fund_id_in": [1, 2, 3], "amount_gteq": 1000000 }
    },
    {
      "relation": "investor_kycs",
      "model": "InvestorKyc",
      "include_zero_rows": true,
      "child_filters": {}
    }
  ],
  "aggregates": {
    "capital_commitments.amount":       "sum",
    "capital_commitments.called_amount":"sum",
    "capital_commitments.id":           "count",
    "capital_commitments.fund_name":    "list",
    "investor_kycs.status":             "latest"
  },
  "root_filters": {
    "investor_type_eq": "Individual",
    "name_cont": "Sharma"
  },
  "sort": { "key": "investor_name", "dir": "asc" }
}
```

Column order and labels are in `GridViewPreference`, aggregate type per column is in `aggregates` map, join config (including per-join Ransack filters and `include_zero_rows`) is in `joins` array.

### 4.4 Aggregation Types

| Aggregate | SQL / Ruby equivalent | Value when 0 children |
|-----------|----------------------|----------------------|
| `sum`     | `SUM(col)` | `0` |
| `count`   | `COUNT(*)` | `0` |
| `avg`     | `AVG(col)` | blank |
| `min`     | `MIN(col)` | blank |
| `max`     | `MAX(col)` | blank |
| `latest`  | most recent row by `created_at DESC`, single value | blank |
| `list`    | `GROUP_CONCAT(DISTINCT col SEPARATOR ", ")` | blank |

No limit on distinct values in `list`. The cell contains however many values exist.

### 4.5 Ransack Filters

Both root and child scopes use Ransack predicates directly. This is the same pattern already used in every controller in the app.

**Root filter** — applied to the root model scope:
```ruby
Investor.ransack(template["root_filters"]).result
```

**Child filter** — applied per join before aggregation:
```ruby
CapitalCommitment
  .where(investor_id: root_ids)
  .ransack(join_config["child_filters"]).result
```

All Ransack predicates are available: `_eq`, `_not_eq`, `_in`, `_not_in`, `_cont`, `_gteq`, `_lteq`, `_gt`, `_lt`, `_blank`, `_present`, `_between`, `_start`, `_end`.

`ransackable_attributes` and `ransackable_associations` guards on each model are respected — no fields can be filtered that the model hasn't explicitly allowed.

Models that use `RansackerAmounts` (Fund, CapitalCommitment, etc.) automatically expose their amount ransackers in child filters.

### 4.6 LEFT JOIN / Zero Row Semantics

When `include_zero_rows: true` (default) for a join, root rows with no matching children appear with `0` (for sum/count) or blank (for avg/min/max/latest/list) in child columns.

This is implemented in Ruby during the merge step — no SQL LEFT JOIN needed. Root IDs not found in the child aggregation result are filled with zero values. This keeps each sub-query composable with Ransack without fighting GROUP BY + LEFT JOIN interactions.

---

## 5. UI/UX Design

### 5.1 Flow

```
Report List ──► New Report ──► Step 1: Root Model ──► Step 2: Columns & Joins ──► Step 3: Filters ──► Preview ──► Save / Download
```

### 5.2 Step 1 — Root Model Picker

Searchable list of all models that define `STANDARD_COLUMNS`, grouped by pack (Funds, Core, Startups, Secondaries, Misc). Shows model name and a short description.

### 5.3 Step 2 — Columns & Joins

Reuses the existing `configure_grids` UI pattern extended with:

```
┌────────────────────────────────────────────────────────────────────┐
│  ▾ Investor (root)                                                 │
│    ☑ investor_name       "Investor Name"  [text-col]               │
│    ☑ email               "Email"          [text-col]               │
│    ☐ category                                                      │
│    ☐ city                                                          │
│    + Add column                                                    │
│                                                                    │
│  ▾ Capital Commitments  [+ Add join ▾]    [include zero rows ☑]   │
│    ☑ amount      [sum ▾]    "Total Committed"   [num-col]          │
│    ☑ called_amount [sum ▾]  "Total Called"                         │
│    ☑ id          [count ▾]  "# Commitments"                        │
│    ☐ distributed_amount                                            │
│    + Add column                                                    │
│                                                                    │
│  ▾ Investor KYC  [+ Add join ▾]           [include zero rows ☑]   │
│    ☑ status      [latest ▾] "KYC Status"                           │
│    + Add column                                                    │
│                                                                    │
│  [+ Add joined model]                                              │
└────────────────────────────────────────────────────────────────────┘
```

Key interactions:
- **Column checkboxes** — same as existing `configure_grids`; checked columns become `GridViewPreference` records
- **Aggregate dropdown** — appears only for has_many joins; options: sum / count / avg / min / max / latest / list; choice stored in `template["aggregates"]`
- **"Include zero rows" toggle** — per-join toggle (default on); stored in `template["joins"][n]["include_zero_rows"]`
- **`+ Add joined model`** — shows a searchable picker of all AR associations on the current root model (not limited to `ADDITIONAL_COLUMNS_FROM`); selecting one adds a new join section
- **Column ordering** — drag handle (acts_as_list, same as existing grid views)
- **Custom label** — double-click to edit inline, saved to `GridViewPreference#label`

### 5.4 Step 3 — Filters

Two sections: root filters and per-join child filters.

```
┌────────────────────────────────────────────────────────────────────┐
│  Root filters (Investor)                                           │
│    investor_type  [equals ▾]  [Individual ▾]        [✕]           │
│    name           [contains ▾] [__________]          [✕]           │
│  + Add filter                                                      │
│                                                                    │
│  Capital Commitment filters (applied before aggregation)           │
│    fund           [is one of ▾]  [Fund A, Fund B ▾]  [✕]          │
│    amount         [≥ ▾]          [10,00,000]          [✕]          │
│  + Add filter                                                      │
└────────────────────────────────────────────────────────────────────┘
```

Filter UI: field picker → operator dropdown (mapped to Ransack predicates) → value input (type-aware: date picker, number input, multi-select for `_in`, etc.).

### 5.5 Preview

- Renders first 50 rows as an HTML table
- Shows total row count: "Showing 50 of 1,247 rows"
- Performance warning if query > 3s
- Zero-aggregate rows are visually distinguished (faint row color)

### 5.6 Saved Reports

- Reports are named (`Report#name`) and saved per entity
- **Share with team** toggle (`Report#shared`) — visible to all entity users with reporting access
- Report list shows: name, root model, column count, last run date, owner
- Actions: Run (download), Edit, Duplicate, Delete

---

## 6. Backend Architecture

### 6.1 Module Layout

```
app/packs/core/report_builder/
  models/
    concerns/
      with_report_builder.rb       # DSL to opt models in (optional, for virtual cols)
    model_discovery.rb             # finds all models with STANDARD_COLUMNS
    association_resolver.rb        # walks AR reflections from relation strings
    query_engine.rb                # orchestrates pass 1 + pass 2
    child_aggregator.rb            # ransack filter + group + aggregate per join
    xlsx_exporter.rb               # caxlsx rendering
  controllers/
    report_builder_controller.rb   # preview + download; Report CRUD reuses existing ReportsController
  policies/
    report_builder_policy.rb       # Pundit
```

Saved report CRUD (create/update/delete/list) reuses the existing `ReportsController` since `Report` is already the data model. The builder adds a `report_builder_controller.rb` only for `preview` and `download` actions.

### 6.2 Query Engine — Two-Pass Strategy

**Pass 1 — Root**

```ruby
root_class = config.root_model.constantize
scope = EntityScope.apply(root_class, current_entity)   # tenancy
scope = scope.ransack(config.root_filters).result        # ransack
scope = scope.order(sort_clause)
root_records = scope.select(:id, *root_column_keys).to_a
root_ids = root_records.map(&:id)
```

**Pass 2 — One query per join**

```ruby
config.joins.each do |join_config|
  fk     = resolve_fk(root_class, join_config.relation)
  child_scope = join_config.model_class
    .where(fk => root_ids)
    .ransack(join_config.child_filters).result

  aggregated[join_config.relation] = child_scope
    .group(fk)
    .select(fk, *aggregate_select_expressions(join_config))
    .index_by { |r| r.send(fk) }
end
```

`latest` aggregate uses a window function (MySQL 8+ `ROW_NUMBER()`) or a correlated sub-select:

```ruby
# Window approach
child_scope
  .select("#{fk}, #{col},
           ROW_NUMBER() OVER (PARTITION BY #{fk} ORDER BY created_at DESC) AS _rn")
# Wrap: WHERE _rn = 1
```

**Merge**

```ruby
root_records.map do |root|
  gvps.map do |gvp|
    source, field = gvp.key.split('.', 2)
    if source == 'root'
      root.send(field)
    else
      agg_row = aggregated[source][root.id]
      agg_row ? agg_row.send(field) : zero_value_for(gvp)
    end
  end
end
```

This issues `1 + N_joins` queries regardless of root row count. No N+1.

### 6.3 GridViewPreference Integration

Column selection is entirely handled by the existing `WithGridViewPreferences` concern on `Report`. The query engine reads columns from `report.ag_selected_columns` (already returns `[{key:, label:, data_type:}]`).

The aggregate type for a given column is looked up from `template["aggregates"][gvp.key]`. No schema changes to `GridViewPreference` needed for v1 — aggregate is stored in `template` JSON and keyed by the same `key` used by the preference.

If a clean separation is preferred, a future migration can add an `aggregate` column to `grid_view_preferences` and move it out of the template JSON.

### 6.4 Security

| Concern | Approach |
|---------|---------|
| Tenancy | `EntityScope.apply` wraps all root scopes; child queries are further filtered to `root_ids` already scoped to entity |
| Column allow-listing | Only keys present in the model's `STANDARD_COLUMNS + ADDITIONAL_COLUMNS + ADDITIONAL_COLUMNS_FROM` (or DB columns for join targets) are accepted |
| Filter injection | All filters go through Ransack parameterised binds; `ransackable_attributes` enforced |
| Association injection | `relation` strings validated against `reflect_on_all_associations` — no arbitrary joins |
| Model injection | `root_model` validated against `ModelDiscovery.roots` — no arbitrary constant eval |
| Policy | `ReportBuilderPolicy` gates actions to entity members with `:reports` permission |

### 6.5 Large Reports

| Row count | Behaviour |
|-----------|-----------|
| ≤ 1,000 | Synchronous `send_data` |
| 1,001 – 50,000 | Background ActiveJob; Turbo polling; download link on completion |
| > 50,000 | Background job + email notification with download link |

---

## 7. XLSX Output Format

Column selection and ordering come from `report.ag_selected_columns` (which reads `GridViewPreference` records ordered by `sequence`). Column labels from `GridViewPreference#label`.

```
Sheet 1: "Data"
  Row 1:  Report name (bold, merged)
  Row 2:  "Generated: DD-MMM-YYYY HH:MM  |  Filters: fund=Fund A, amount≥10L"
  Row 3:  Column headers from GridViewPreference#label (bold, frozen row, autofilter)
  Row 4+: Data rows, alternating row fill

Sheet 2: "Totals" (when any sum/count column exists)
  Column totals matching Sheet 1 layout
```

**Type formatting** derived from `GridViewPreference#data_type` and `col-type` suffix:

| data_type / col-type | XLSX format |
|---------------------|------------|
| `num-col` / Integer | `#,##0` |
| `num-col` / Decimal | `#,##0.00` |
| Date | `DD-MMM-YYYY` |
| Datetime | `DD-MMM-YYYY HH:MM` |
| Boolean | `Yes` / `No` |
| String / text-col | General |
| nil | empty cell |

Currency columns: header includes `(₹)` or the entity reporting currency symbol. Amounts converted to entity reporting currency via existing `WithExchangeRate` concern unless raw-currency mode is toggled.

Column widths: auto-fitted, no cap.

---

## 8. Data Model Changes

`Report` already has `WithGridViewPreferences` and `attribute :template, :json`. Minimal additions:

```ruby
# Migration — check existing columns before running
add_column :reports, :report_builder, :boolean, default: false  # distinguishes builder reports from URL-based reports
add_column :reports, :shared,         :boolean, default: false   # if not already present
add_column :reports, :last_run_at,    :datetime                  # if not already present
```

No changes to `grid_view_preferences` table in v1.

---

## 9. Implementation Phases

### Phase 1 — Core Engine (1 sprint)
- `ModelDiscovery`, `AssociationResolver`, `QueryEngine`, `ChildAggregator`
- Ransack integration for root + child scopes
- Zero-fill merge for missing child rows
- XLSX export via caxlsx reading from `ag_selected_columns`
- REST endpoints: `POST /report_builder/preview`, `POST /report_builder/download`
- Unit + integration tests

### Phase 2 — Builder UI (1–2 sprints)
- Root model picker
- Column & join panels (extending `configure_grids` pattern)
- Aggregate dropdown per has-many column
- "Include zero rows" toggle per join
- Dynamic join picker (beyond `ADDITIONAL_COLUMNS_FROM`)

### Phase 3 — Filters UI (0.5 sprint)
- Root filter builder (Ransack predicate picker)
- Per-join child filter builder
- Preview table with zero-row highlighting

### Phase 4 — Save, Share & Polish (0.5 sprint)
- Save / duplicate / delete reports
- Share toggle
- XLSX Totals sheet
- Background job for large reports
- Currency conversion toggle

---

## 10. Decisions

| # | Decision |
|---|----------|
| D1 | Aggregate type stored in `Report#template["aggregates"]` map (no migration to `GridViewPreference` needed). May be moved to a `GridViewPreference#aggregate` column in v2. |
| D2 | `latest` aggregate orders by `created_at DESC` by default. User-configurable sort column deferred to v2. |
| D3 | Child filter has a per-filter "exclude root row if no matching children" checkbox. Default: root rows always shown (zero-fill). |
| D4 | `list` aggregate has no value cap. Preview shows a warning if any cell exceeds 500 chars. |
| D5 | Join targets without `STANDARD_COLUMNS` expose raw DB columns. Only models with `STANDARD_COLUMNS` are available as report roots. |
