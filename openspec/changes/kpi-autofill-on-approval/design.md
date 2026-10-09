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

### 5. Scalar `portco_id` with `Array()` defensive guard

**Choice:** `KpiApproveService` passes `@result_kpis.first.portfolio_company_id` (single integer) instead of `.pluck(:portfolio_company_id).uniq` (array). Phase 2 Compute in `KpiCumulateJob` wraps the parameter in `Array()` before iterating.

**Rationale:** `Kpi.new(portfolio_company_id: [1719])` silently casts the array to `nil` via ActiveRecord's integer type casting. This caused Phase 2 to query `KpiReport.where(portfolio_company_id: nil)`, finding orphan reports instead of the intended company. The `Array()` guard protects against any other caller that might still pass an array.

### 6. Forward fill quarterly fallback via `process_quarterly_derived_forward_fill`

**Choice:** When `fetch_related_monthly_kpis` returns empty (no monthly data), fall back to reading Quarter KPIs directly to derive YTD values. A `skip_years` parameter avoids double-processing fiscal years that already have monthly data.

**Alternative considered:** Requiring all companies to have monthly data for forward fill. Rejected because many portfolio companies report quarterly only, and forward fill YTD was silently broken for all of them — both on main and our branch.

### 7. Approval notice message over auto-refresh

**Choice:** Show a flash notice ("Cumulative values are being computed — refresh the page in a few seconds") on `approve` and `approve_all` actions.

**Alternatives considered:** (a) Turbo Stream polling for job completion, (b) `perform_now` to block the response until computation finishes. Both rejected: (a) adds frontend complexity for a rare interaction, (b) blocks the HTTP response for seconds, degrading UX. The notice is simple, honest, and matches the async nature of the Sidekiq job.

## Risks / Trade-offs

- **[Risk] Large approval batches could slow the job** → Mitigated by scoping to only the approved reports' IDs. The concern handles downstream Quarter/YTD/Year internally, so the input set stays small.
- **[Risk] `report_ids` parameter changes the job signature** → Mitigated by making it an optional keyword argument with `nil` default. Existing callers are unaffected.
- **[Risk] Mapping backfill on existing records could overwrite intentional nil** → Mitigated by using `||=` (only assigns when nil). No known case where a nil mapping is intentional on a cumulated record.
- **[Trade-off] Incremental mapping backfill vs. one-time migration** → Accepted: convergence is slower but requires zero operational effort. Records are fixed as they're naturally reprocessed.
- **[Risk] Array passed to `Kpi.new` silently casts to nil** → Fixed at source (`KpiApproveService` now passes scalar) and guarded at destination (`Array()` in job). Both layers needed because other callers may exist.
- **[Risk] Forward fill quarterly fallback could double-process fiscal years with monthly data** → Mitigated by `skip_years` parameter that excludes years already handled by the monthly-based forward fill path.
- **[Trade-off] Flash notice vs. auto-refresh** → Accepted: notice is simpler than Turbo Stream polling, and the async delay is typically 2–5 seconds. Can be upgraded to polling in a future iteration.
