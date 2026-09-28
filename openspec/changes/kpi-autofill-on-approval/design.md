# Design

## Context

See [proposal.md](proposal.md) for motivation. The current cumulation pipeline has three layers:

1. **KpiApproveService** — orchestrates approval, enqueues cumulation
2. **KpiCumulateJob** — Sidekiq job that selects reports and delegates to the concern
3. **KpiCumulative concern** — the actual cumulation logic (sum monthly → Quarter/YTD/Year)

Before this change, `KpiApproveService` called `KpiCumulateJob` without `force: true` and without scoping to specific reports. The job's `get_kpi_reports` gate skipped reports already marked `autofill_completed`, so freshly approved values were never rolled up until a manual recompute.

A secondary issue: legacy cumulated KPI records created before mapping inheritance have nil `investor_kpi_mapping_id`, causing grid view to show "N/A" because it cannot match the KPI to its row.

## Goals / Non-Goals

**Goals:**

- Approval triggers cumulation for the approved reports only
- Legacy mapping gaps are backfilled during cumulation
- Backward compatibility: existing callers of `KpiCumulateJob` are unaffected

**Non-Goals:**

- Changing the cumulation algorithm itself (sum logic, period detection)
- Removing the manual "Recompute Cumulative" action
- Backfilling all historical mapping gaps in a one-time migration (happens incrementally during cumulation runs)

## Decisions

### 1. Scoped `report_ids` parameter over processing all reports

**Choice:** Add an optional `report_ids` keyword to `KpiCumulateJob` that, when present, restricts `get_kpi_reports` to only those IDs.

**Alternative considered:** Always process all reports with `force: true` on approval. Rejected because large portfolio companies can have hundreds of reports, and approval typically affects 1–3 months — full reprocessing would be unnecessarily slow and could cause Sidekiq queue contention.

### 2. `force: true` on approval path

**Choice:** Always pass `force: true` from `KpiApproveService` alongside `report_ids`.

**Rationale:** The `autofill_completed` gate exists to prevent redundant processing during bulk imports. After approval, reprocessing is intentional and expected — the gate should not block it.

### 3. Inline mapping backfill in cumulation concern

**Choice:** Assign `investor_kpi_mapping` on both new and existing cumulated KPI records inside the concern, and allow save when only the mapping changed.

**Alternative considered:** A separate data migration to backfill all nil mappings. Rejected because (a) it's a one-time script that needs maintenance, and (b) the incremental approach fixes records as they're naturally touched, converging without operational overhead.

### 4. Inline percentage change execution

**Choice:** Keep the existing `compute_percentage_change: true` pattern where `KpiCumulateJob` runs `KpiPercentageChangeJob.perform_now` after cumulation completes.

**Rationale:** Two independently queued Sidekiq jobs have no ordering guarantee. The percentage job must run after cumulated Quarter/YTD/Year KPIs exist. `perform_now` inside the cumulation job guarantees this ordering.

## Risks / Trade-offs

- **[Risk] Large approval batches could slow the job** → Mitigated by scoping to only the approved reports' IDs. The concern handles downstream Quarter/YTD/Year internally, so the input set stays small.
- **[Risk] `report_ids` parameter changes the job signature** → Mitigated by making it an optional keyword argument with `nil` default. Existing callers are unaffected.
- **[Risk] Mapping backfill on existing records could overwrite intentional nil** → Mitigated by using `||=` (only assigns when nil). No known case where a nil mapping is intentional on a cumulated record.
- **[Trade-off] Incremental mapping backfill vs. one-time migration** → Accepted: convergence is slower but requires zero operational effort. Records are fixed as they're naturally reprocessed.
