# Account Entries Period Report — Performance Assessment and Plan

Assessment of `/account_entry_reports/fund_report` (and the sibling `folio_report`)
written 2026-09-05. Status: **assessment only, nothing implemented yet**. Entities with
very large `account_entries` ledgers can take the replica down with a single page load.

Code under review:

- `app/packs/funds/capital_commitments/controllers/account_entry_reports_controller.rb`
- `app/packs/funds/capital_commitments/services/account_entry_report_page.rb`
- `app/packs/funds/capital_commitments/services/account_entry_report.rb`
- `app/packs/funds/capital_commitments/services/account_entry_pivot.rb`
- `app/packs/funds/capital_commitments/views/account_entry_reports/*`

Related: `CLAUDE.md` (large-table query hygiene), `lib/tasks/partitions.rake`
(`account_entries` is `PARTITION BY RANGE (YEAR(reporting_date))`).

---

## 1. What one page load costs today

Everything on the page is an aggregate, but each aggregate is computed by a separate
pass over the raw ledger. For a fund-level load with a date range:

| Section | Query | Bounded by |
|---|---|---|
| `available_entry_names` | `distinct.pluck(:name)` over the fund's **whole history** | nothing — no date filter |
| `summary_kpis` | `sum`, `count`, `distinct.count(:capital_commitment_id)`, `distinct.count(:name)` | 4 separate range scans |
| `breakdown_by_name` | `group(:name).sum` | 1 range scan |
| `trailing_trend` | `group(quarter, name).sum`, 15 months back | top-5 names → uses `idx_fund_id_and_name_and_reporting_date`, fine |
| pivot rows | `distinct.pluck(:commitment_name, :capital_commitment_id)` | 1 range scan |
| pivot headers | `distinct.pluck(:name, :reporting_date)` | 1 range scan |
| pivot page | 20 folios' rows via `where(capital_commitment_id: [...])` | uses `idx_ae_cc_name_date`, fine |

That is ~8 full passes over the fund's rows in the range per request. Every pagination
click repeats all of them because the whole page re-renders.

### Why each pass is expensive

- **No `(fund_id, reporting_date)` index.** The fund indexes are
  `[fund_id, entry_type, reporting_date]`, `[fund_id, name, reporting_date]` and
  `[fund_id]`. With `entry_type`/`name` sitting between fund and date, a date range for a
  fund cannot be seeked. MySQL prunes to the year partition, then walks every row of the
  fund for that year via the `fund_id` index, doing a clustered-key lookup per row to read
  `amount_cents`/`cumulative`. A one-quarter report reads the whole year.
- **No covering index.** Every lookup lands on the wide row (`json_fields`, `notes`,
  `explanation`), so the passes are IO-bound, not just CPU-bound.
- **No range cap and no statement timeout.** `start_date=2000-01-01&end_date=2030-12-31`
  scans every partition and holds a replica connection and a Puma worker until it
  finishes.

### Smaller problems found in the same pass

- **Folio dropdown**: `@fund.capital_commitments.map { |cc| [cc.to_s, cc.id] }` in both
  report views loads every commitment as a full AR object per page load.
- **Trend chart ignores the filters** (correctness bug): `AccountEntryReport#trailing_trend`
  applies neither `@capital_commitment_ids` nor `@entry_names`, so a filtered fund-level
  report shows fund-wide trend numbers next to filtered KPIs.
- The `AccountEntryReportInsight.fingerprint_for` staleness check is itself a
  `COUNT + SUM` full pass over the scope.

---

## 2. Plan

### Step 1 — make the existing page cheap (no model change)

1. **Collapse the scans to two.**
   - `GROUP BY name, reporting_date → COUNT(*), SUM(amount_cents)` yields the breakdown,
     total amount, entry count, distinct-name count **and** the pivot column headers.
   - `GROUP BY capital_commitment_id → MAX(commitment_name), COUNT(*)` yields the pivot row
     list **and** the distinct-folio count.
   - Trend and the pivot page-of-20 stay as they are (already well indexed).
2. **Covering index** on
   `(fund_id, cumulative, reporting_date, name, capital_commitment_id, amount_cents)`.
   Both remaining passes become index-only range seeks. This is the single biggest DB win.
   It is an online DDL / `pt-online-schema-change` job on a partitioned table with hundreds
   of millions of rows — plan it as an operational change, not a plain migration.
3. **Turbo-frame the pivot** so pagination re-runs only the pivot, never KPIs/charts.
4. **Guard rails**: cap the range (e.g. 24 months), default to the latest quarter, and add
   a `/*+ MAX_EXECUTION_TIME(n) */` optimizer hint on the report scopes so a runaway query
   fails fast instead of holding the replica.
5. **Dropdowns**: bound `available_entry_names` to the selected range; make the folio
   select a Select2 AJAX source (or at minimum a `pluck`).
6. **Fix the trend filter bug** in `trailing_trend`.

### Step 2 — stop reading the ledger for this screen (the real rethink)

`account_entries` are written in batches by allocation runs and imports, never
continuously, and the report only ever needs `SUM`/`COUNT` at one of two grains. Maintain
two rollup tables:

| Table | Grain | Columns | Serves |
|---|---|---|---|
| `account_entry_folio_rollups` | fund, capital_commitment, name, reporting_date | sum_amount_cents, entry_count, commitment_name | pivot rows/cells, folio report |
| `account_entry_name_rollups` | fund, name, reporting_date | sum_amount_cents, entry_count, folio_count | KPIs, breakdown, trend, pivot headers |

- Refresh per **(fund, reporting_date)** after each allocation run, import, or delete —
  the same unit of change that `AccountEntry#index_reporting_date` and
  `bulk_update_tracking_currency_numbers` already key on. Delete-and-reinsert the slice,
  never patch it.
- Rows are narrow and collapse the per-parent fan-out (`parent_id`/`parent_type`/
  `entry_type`/`ref_id`), so every section becomes a small indexed read.
- Also makes the folio report, `AccountEntryChartsHelper#account_entries_chart` and the
  XLSX pivot export cheap.
- The refresh must be a Trailblazer operation (project convention), enqueued from the
  allocation-run / import completion path.
- Optional intermediate: cache `AccountEntryReport` in Solid Cache keyed by
  `[fund_id, ledger_version, start, end, filters]` where `ledger_version` is a counter on
  `Fund` bumped by the same hooks. Fixes repeat views only, not the first hit on a wide
  range — go straight to rollups unless time is very short.

```mermaid
sequenceDiagram
    participant AR as AllocationRun / Import
    participant Op as AccountEntryRollupRefresh (Trailblazer op, bg job)
    participant AE as account_entries
    participant RU as account_entry_*_rollups
    participant C as AccountEntryReportsController
    participant P as AccountEntryReportPage / Report / Pivot

    AR->>AE: write entries for (fund, reporting_date)
    AR-->>Op: enqueue refresh(fund_id, reporting_date)
    Op->>RU: DELETE slice (fund, reporting_date)
    Op->>AE: SELECT ... GROUP BY capital_commitment_id, name (one pass, covering index)
    Op->>RU: INSERT folio rollups + name rollups
    Note over Op,RU: Idempotent per slice; safe to re-run

    C->>P: fund_report(fund, start, end, filters)
    P->>RU: name rollups WHERE fund, date range → KPIs, breakdown, headers, trend
    P->>RU: folio rollups WHERE fund, date range, folio IN (page) → pivot cells
    P-->>C: report (no account_entries reads)
```

### Step 3 — safety valve: background build for oversized reports

If a requested range still exceeds a threshold (estimated from rollup row counts), enqueue
a job that builds the report snapshot and let the page poll. `AccountEntryReportInsight`
already has the `pending → generating → complete` lifecycle and per-section cache row; this
is the same shape extended to report data. With rollups in place this should rarely
trigger, but it guarantees the interactive request path never scans the raw table.

---

## 3. Recommendation

Do **Step 1 immediately** (a day or two of work plus the index rollout), **Step 2 as the
next piece of work**, and **Step 3 only if** funds keep growing past what the rollups
handle comfortably.

## 4. Open questions

- Fraction of `cumulative = true` rows per fund — affects whether `cumulative` belongs
  early in the covering index.
- Whether `deleted_at` rows must be excluded: `AccountEntry` has no soft-delete default
  scope, so today the report includes them if any exist.
- Index rollout window on production (replica first, then primary) and expected duration
  at current table size.
