# Report Builder — UX & Interaction Spec

**Date:** 2026-04-22  
This document describes exactly what the user sees and does at every step, how each interaction maps to the stored report definition, and how the definition is persisted.

---

## 1. Entry Points

| Where | Link/Button |
|-------|-------------|
| Reports list page | "New Report (Builder)" button — opens builder |
| Saved report row | "Edit" → reopens builder pre-populated |
| Any grid view page | "Save as Report" → seeds builder with current model + current Ransack filters |

---

## 2. Screen 1 — Root Model Picker

User opens the builder. They see a modal (or full page — TBD based on viewport):

```
┌─────────────────────────────────────────────────────┐
│  New Report — Choose a starting table               │
│  [Search models...          ]                       │
│                                                     │
│  FUNDS                                              │
│  ┌──────────────┐  ┌──────────────┐                 │
│  │ 💼 Fund      │  │ 📋 Capital   │                 │
│  │              │  │ Commitment   │                 │
│  └──────────────┘  └──────────────┘                 │
│  ┌──────────────┐  ┌──────────────┐                 │
│  │ 📞 Capital   │  │ 💸 Capital   │                 │
│  │ Call         │  │ Distribution │                 │
│  └──────────────┘  └──────────────┘                 │
│                                                     │
│  CORE                                               │
│  ┌──────────────┐  ┌──────────────┐                 │
│  │ 👤 Investor  │  │ 🏢 Investor  │                 │
│  │              │  │ KYC          │                 │
│  └──────────────┘  └──────────────┘                 │
│  ...                                                │
└─────────────────────────────────────────────────────┘
```

**User action:** Clicks "Investor".

**What happens:**  
- A draft `Report` record is created server-side with `report_builder: true`, `entity_id`, `user_id`, `name: "Untitled Report"`, and `template: { root_model: "Investor", joins: [], aggregates: {}, root_filters: {}, sort: {} }`.  
- The builder page loads with `report_id` in the URL.

---

## 3. Screen 2 — The Builder

Single page, three-panel layout. No wizard steps — the user works in one place and sees changes immediately.

```
┌──────────────────────────────────────────────────────────────────────────────────┐
│ Report name: [Untitled Report              ]  [Preview]  [Download ▾]  [Save]    │
├─────────────────────────────────────────────────────────────────────────────────┤
│  COLUMNS                      │  FILTERS                    │  SORT & OPTIONS   │
│                               │                             │                   │
│  ▾ Investor                   │  Investor filters           │  Sort by:         │
│    ☑ investor_name  "Name"    │  [+ Add filter]             │  [Name       ▾]   │
│    ☑ email          "Email"   │                             │  [A → Z      ▾]   │
│    ☑ category       "Type"    │  Capital Commitment filters │                   │
│    ☐ city                     │  [+ Add filter]             │  Currency:        │
│    ☐ tag_list                 │                             │  [Entity default▾]│
│    [+ Add column]             │                             │                   │
│                               │                             │                   │
│  ▾ Capital Commitments  [✕]   │                             │                   │
│    [include zero rows ☑]      │                             │                   │
│    ☑ amount [sum ▾] "Committed"│                            │                   │
│    ☑ called_amount [sum ▾]    │                             │                   │
│    ☑ id [count ▾] "# Commits" │                             │                   │
│    ☐ distributed_amount       │                             │                   │
│    [+ Add column]             │                             │                   │
│                               │                             │                   │
│  [+ Join another table]       │                             │                   │
└──────────────────────────────────────────────────────────────────────────────────┘
```

### 3.1 Columns Panel — Root Section

The root section shows all columns from `Investor::STANDARD_COLUMNS` + `Investor::ADDITIONAL_COLUMNS` (if defined) as checkboxes. Checked by default: none (or the model's own default set if defined).

**User checks "investor_name":**
- POST `/grid_view_preferences` with `{ key: "investor_name", owner_type: "Report", owner_id: <draft_id>, data_type: "String" }`
- A `GridViewPreference` row is created. The column appears checked.

**User unchecks "investor_name":**
- DELETE `/grid_view_preferences/<id>`
- The `GridViewPreference` row is removed.

**User double-clicks the label "Name":**
- The label becomes an `<input>` inline.
- On blur: PATCH `/grid_view_preferences/<id>` with `{ label: "Investor Name" }`

**User drags a row to reorder:**
- Uses existing `draggable-row` Stimulus controller.
- Fires POST `/grid_view_preferences/update_column_sequence` with `{ id:, index: }` — same mechanism as existing configure_grids.

### 3.2 Columns Panel — Join Section

The Capital Commitments section appears after the user adds it (see 3.3). It shows `CapitalCommitment::STANDARD_COLUMNS` + `ADDITIONAL_COLUMNS` as checkboxes, each with an aggregate dropdown.

**User checks "amount" with aggregate "sum":**
- POST `/grid_view_preferences` with `{ key: "capital_commitments.amount; num-col", owner_type: "Report", owner_id: <id>, data_type: "Decimal", label: "Committed" }`
- PATCH `/reports/<id>` with `{ template: { aggregates: { "capital_commitments.amount": "sum" } } }` (merge into existing template)

**User changes aggregate from "sum" to "avg":**
- PATCH `/reports/<id>` with `{ template: { aggregates: { "capital_commitments.amount": "avg" } } }` (update just that key)

The aggregate dropdown only appears for columns from has_many joins. For belongs_to joins (flat joins like `investor_kyc`) there is no aggregate dropdown — values are shown directly.

**User toggles "include zero rows":**
- PATCH `/reports/<id>` with `{ template: { joins: [{ relation: "capital_commitments", include_zero_rows: false }] } }`
- The toggle is a Bootstrap toggle switch, default ON.

### 3.3 Adding a Join

**User clicks "+ Join another table":**
- A dropdown or modal appears listing all `has_many`, `has_one`, and `belongs_to` associations on `Investor`, grouped by type:

```
  has_many (one-to-many — supports aggregation)
  ──────────────────────────────────────────────
  ☐ Capital Commitments
  ☐ Investor KYCs
  ☐ Investor Accesses
  ☐ Notes
  ☐ Documents
  ☐ Tasks
  ☐ ...

  belongs_to / has_one (flat — columns shown directly)
  ──────────────────────────────────────────────────────
  ☐ Investor Entity (Entity)
```

**User picks "Investor KYCs":**
- PATCH `/reports/<id>` with `{ template: { joins: [...existing..., { relation: "investor_kycs", model: "InvestorKyc", include_zero_rows: true, child_filters: {} }] } }`
- A new section "Investor KYCs" appears in the columns panel with `InvestorKyc::STANDARD_COLUMNS` (or DB columns if `STANDARD_COLUMNS` not defined).

**User clicks ✕ on a join section:**
- All `GridViewPreference` rows for keys prefixed `investor_kycs.` are deleted (bulk DELETE).
- PATCH `/reports/<id>` removes the join from `template["joins"]`.
- The section collapses and disappears.

### 3.4 Filters Panel

**User clicks "+ Add filter" under "Investor filters":**
- A new filter row appears:

```
  [Select field ▾]  [operator ▾]  [value]  [✕]
```

**User selects field "investor_type":**
- The field dropdown lists all `ransackable_attributes` on `Investor`. Shows human labels.
- On selection, the operator dropdown populates with valid operators for the column type (String → eq, not_eq, cont, in, blank, present; Decimal → eq, gt, lt, gte, lte, between).

**User picks operator "equals" and types "Individual":**
- For an enum/string field with known values, the value input becomes a `<select>` populated with distinct DB values or predefined choices (e.g. `Investor::INVESTOR_CATEGORIES`).
- The filter row reads: `investor_type | equals | [Individual ▾]`

**On any filter change (field, operator, or value):**
- PATCH `/reports/<id>` with `{ template: { root_filters: { "investor_type_eq": "Individual" } } }`
- The whole `root_filters` object is replaced with the current state of all root filter rows.

**User clicks "+ Add filter" under "Capital Commitment filters":**
- Same UI, but the field dropdown lists `ransackable_attributes` on `CapitalCommitment`.
- Fund filter: User picks "fund", operator "is one of", value = multi-select of funds in this entity.

```
  fund  |  is one of  |  [Fund A ✕] [Fund B ✕] [+ add]
```

**On save:**
- PATCH `/reports/<id>` with `{ template: { child_filters: { "capital_commitments": { "fund_id_in": [1, 2] } } } }`

**User clicks "✕" on a filter row:**
- The row is removed.
- PATCH `/reports/<id>` removes that predicate from the relevant filters object.

### 3.5 Sort & Options Panel

**Sort by:** A `<select>` populated with all currently checked columns (by their labels). The user picks one and picks direction (A→Z / Z→A, or ↑/↓ for numbers).

On change: PATCH `/reports/<id>` with `{ template: { sort: { key: "investor_name", dir: "asc" } } }`

**Currency:** A `<select>` for entities with multi-currency — defaults to entity reporting currency.

On change: PATCH `/reports/<id>` with `{ template: { currency: "USD" } }`

---

## 4. Screen 3 — Preview

**User clicks "Preview":**
- A Turbo Frame below the builder (or a modal) loads with the first 50 rows.
- Request: GET `/report_builder/preview?report_id=<id>` — reads the saved `Report` record (GridViewPreferences + template JSON) and runs the query.
- The HTML table uses the same Bootstrap table styling as the rest of the app.
- Zero-aggregate rows (investors with no commitments) are shown with a subtle grey background and `0` / `—` in child columns.
- Row count badge: "Showing 50 of 312 rows"

```
┌──────────────────────────────────────────────────────────────────┐
│ Preview — 50 of 312 rows                          [Close ✕]      │
├──────────┬───────────────┬───────────┬────────────┬─────────────┤
│ Name     │ Email         │ Type      │ Committed  │ # Commits   │
├──────────┼───────────────┼───────────┼────────────┼─────────────┤
│ A Sharma │ a@example.com │ Individual│ ₹50,00,000 │ 2           │
│ B Patel  │ b@example.com │ Individual│ ₹25,00,000 │ 1           │
│ C Singh  │ c@example.com │ Individual│ 0          │ 0           │  ← grey
│ ...      │               │           │            │             │
└──────────┴───────────────┴───────────┴────────────┴─────────────┘
```

If the query takes > 3s, a warning banner shows: "This report is large — download may take a moment."

---

## 5. Save & Download

### 5.1 Naming

The report name field at the top is always editable. On blur: PATCH `/reports/<id>` with `{ report: { name: "Investor Commitment Summary" } }`.

### 5.2 Download

**User clicks "Download ▾":**
- Dropdown: `[ Download now ]  [ Download (background, email me) ]`

**Download now (≤ 1,000 rows):**
- GET `/report_builder/download?report_id=<id>` — synchronous, streams XLSX file.
- Browser downloads "Investor Commitment Summary — 22-Apr-2026.xlsx".

**Download background (> 1,000 rows or user's choice):**
- POST `/report_builder/download_async?report_id=<id>`
- Page shows: "Preparing your report… you'll be notified when it's ready."
- Turbo stream updates a banner when the job completes: "Your report is ready — [Download]"

### 5.3 Saving vs Downloading

The draft `Report` is created when the user first picks a root model. "Save" just updates `name` and marks the report non-draft (removes a `draft: true` flag). The report then appears on the Reports list.

Users can download without saving — the draft is cleaned up after 24 hours if never saved.

---

## 6. Complete Report Definition — What Gets Stored

After a full session the report record looks like this:

**`reports` table row:**
```
id:               42
name:             "Investor Commitment Summary"
entity_id:        1
user_id:          7
report_builder:   true
shared:           false
last_run_at:      2026-04-22 14:30:00
template:         (JSON below)
```

**`reports.template` JSON:**
```json
{
  "version": 1,
  "root_model": "Investor",
  "joins": [
    {
      "relation":          "capital_commitments",
      "model":             "CapitalCommitment",
      "include_zero_rows": true,
      "child_filters":     { "fund_id_in": [1, 2] }
    },
    {
      "relation":          "investor_kycs",
      "model":             "InvestorKyc",
      "include_zero_rows": true,
      "child_filters":     {}
    }
  ],
  "aggregates": {
    "capital_commitments.amount; num-col":        "sum",
    "capital_commitments.called_amount; num-col": "sum",
    "capital_commitments.id":                     "count",
    "investor_kycs.status":                       "latest"
  },
  "root_filters": {
    "investor_type_eq": "Individual"
  },
  "sort":     { "key": "investor_name", "dir": "asc" },
  "currency": "INR"
}
```

**`grid_view_preferences` rows for this report (owner_type: "Report", owner_id: 42):**

| sequence | key | name | label | data_type |
|----------|-----|------|-------|-----------|
| 1 | `investor_name; text-col` | Stakeholder | Investor Name | String |
| 2 | `email; text-col` | Email | Email | String |
| 3 | `category; text-col` | Category | Type | String |
| 4 | `capital_commitments.amount; num-col` | Committed | Total Committed | Decimal |
| 5 | `capital_commitments.called_amount; num-col` | Called | Total Called | Decimal |
| 6 | `capital_commitments.id` | # Commits | # Commitments | Integer |
| 7 | `investor_kycs.status` | KYC Status | KYC Status | String |

The query engine reads `report.ag_selected_columns` (which pulls from `grid_view_preferences` ordered by sequence), looks up the aggregate for each key from `template["aggregates"]`, looks up child filters from `template["joins"]`, and runs the two-pass query.

---

## 7. Stimulus Controller Design

All builder state management lives in a single `report-builder` Stimulus controller attached to the builder page.

```
data-controller="report-builder"
data-report-builder-report-id-value="42"
```

**Actions wired to UI elements:**

| User action | Stimulus action | Server call |
|-------------|----------------|-------------|
| Check a root column | `toggleRootColumn` | POST /grid_view_preferences |
| Uncheck a root column | `toggleRootColumn` | DELETE /grid_view_preferences/:id |
| Edit column label | `updateLabel` | PATCH /grid_view_preferences/:id |
| Drag to reorder | (existing draggable-row controller) | POST .../update_column_sequence |
| Check a child column | `toggleChildColumn` | POST /grid_view_preferences + PATCH /reports/:id (aggregates) |
| Change aggregate | `changeAggregate` | PATCH /reports/:id (aggregates key) |
| Toggle include zero rows | `toggleZeroRows` | PATCH /reports/:id (joins[n].include_zero_rows) |
| Add join | `addJoin` | PATCH /reports/:id (joins array) |
| Remove join | `removeJoin` | bulk DELETE /grid_view_preferences + PATCH /reports/:id |
| Add root filter | `addRootFilter` | PATCH /reports/:id (root_filters) |
| Change root filter | `updateRootFilter` | PATCH /reports/:id (root_filters) |
| Remove root filter | `removeRootFilter` | PATCH /reports/:id (root_filters) |
| Add child filter | `addChildFilter` | PATCH /reports/:id (joins[n].child_filters) |
| Change sort | `changeSort` | PATCH /reports/:id (sort) |
| Preview | `preview` | GET /report_builder/preview (Turbo Frame) |
| Download | `download` | GET /report_builder/download |
| Save name | `saveName` | PATCH /reports/:id (name) |

Every PATCH to `/reports/:id` sends only the changed key via a deep-merge on the server — the full template JSON is never sent back from the client, only the delta. This avoids race conditions when multiple quick changes are fired.

---

## 8. Filter UI — Operator Mapping

The filter row is a three-part control. When the user picks a field, the operator dropdown populates based on the field's type:

| Field type | Available operators (shown to user → Ransack predicate) |
|-----------|-------------------------------------------------------|
| String | equals `_eq`, not equals `_not_eq`, contains `_cont`, starts with `_start`, is empty `_blank`, is not empty `_present` |
| Decimal / Integer | equals `_eq`, ≥ `_gteq`, ≤ `_lteq`, > `_gt`, < `_lt`, between `_between`, is empty `_blank` |
| Date | equals `_eq`, on or after `_gteq`, on or before `_lteq`, between `_between`, is empty `_blank` |
| Enum / foreign key | is `_eq`, is not `_not_eq`, is one of `_in`, is not one of `_not_in`, is empty `_blank` |
| Boolean | is true `_true`, is false `_false` |

Value input adapts to the operator:
- `_in` / `_not_in` → token input (multi-select)
- `_between` → two inputs (from / to)
- `_blank` / `_present` → no value input
- Foreign key (e.g. `fund_id`) → `<select>` populated from entity's funds
- Enum → `<select>` with known values (from `model.defined_enums` or model constant)
- Date → date picker

---

## 9. Editing a Saved Report

User clicks "Edit" on a saved report in the Reports list.

The builder page opens, pre-populated by:
1. Reading `report.template` → renders join sections, filter rows, sort, currency
2. Reading `report.grid_view_preferences.order(:sequence)` → renders checked columns with correct labels

All checkboxes, aggregates, filters, and sort are restored exactly. The user makes changes and the same auto-save-on-change mechanism applies.

---

## 10. Key UX Decisions

| Decision | Choice | Reason |
|----------|--------|--------|
| Auto-save vs explicit save | Auto-save every change | Prevents data loss; draft record created at model pick step |
| Join sections: always shown or on demand | On demand (+ Join button) | Avoids overwhelming new users with 20 sections |
| Filter predicate naming | Human labels in UI, Ransack keys in JSON | Users see "equals", "contains" etc.; no Ransack leakage |
| Aggregate picker location | Inline next to column checkbox (not in a separate panel) | Column and its aggregate are one logical decision |
| Zero-rows toggle | Per-join toggle, default ON | Inclusion of zero rows is the safe default; users can tighten |
| Column picker source | `STANDARD_COLUMNS + ADDITIONAL_COLUMNS` (same as configure_grids) | Consistency with existing grid views; no new metadata needed |
| Join target columns without STANDARD_COLUMNS | Show raw DB columns in a flat list | Allows full flexibility; not as pretty but always works |
| Report naming | Editable at top of builder, auto-saved | Users don't have to remember to name before building |
