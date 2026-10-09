# Proposal

## Why

Approving monthly KPIs does not trigger recomputation of cumulative values (Quarter, YTD, Year) or percentage changes (MoM/YoY). Fund managers must manually click "Recompute Cumulative" after every approval cycle, which is unintuitive and leads to stale grid views showing "N/A" until someone remembers to recompute.

## What Changes

- **KpiApproveService** passes scoped `report_ids` and `force: true` to the cumulation job after approval, so only the affected reports are reprocessed and the `autofill_completed` gate is bypassed.
- **KpiCumulateJob** gains an optional `report_ids` parameter that restricts processing to a caller-specified set of reports, bypassing the normal gate logic.
- **KpiCumulative concern** backfills `investor_kpi_mapping` on existing cumulated KPI records that lack one (legacy records predating mapping inheritance), preventing grid view "N/A" display. Records are saved when only the mapping changed, even if the numeric value is unchanged.
- **KpiApproveService** passes a single integer `portco_id` instead of an array — `Kpi.new(portfolio_company_id: [id])` silently casts arrays to nil, which broke Phase 2 (Compute) by querying reports with `portfolio_company_id IS NULL`.
- **KpiCumulateJob** Phase 2 wraps `portfolio_company_id` in `Array()` as a defensive guard against any caller that might still pass an array.
- **KpiCumulative concern** forward fill gains a quarterly fallback — `process_quarterly_derived_forward_fill` reads Quarter KPIs to populate YTD values when companies report quarterly with no monthly data.
- **KpisController** approval actions (`approve`, `approve_all`) show a notice informing users that cumulative values are being computed and to refresh the page.
- Percentage change job (`KpiPercentageChangeJob`) continues to run inline after cumulation when triggered by approval, guaranteeing correct ordering.
- Manual "Recompute Cumulative" action remains available as a fallback.

## Capabilities

### New Capabilities

- `kpi-autofill-on-approval`: Automatic cumulative KPI recomputation triggered by approval — scoped processing, force bypass of completion gate, mapping backfill for legacy records, and guaranteed percentage-change ordering.

### Modified Capabilities

<!-- No existing specs are affected -->

## Impact

- **Code:** `KpiApproveService`, `KpiCumulateJob`, `KpiCumulative` concern, `KpisController` (4 files under `app/packs/startups/kpis/`)
- **Background jobs:** `KpiCumulateJob` signature changes (new optional `report_ids` keyword argument) — backward compatible, existing callers unaffected
- **Data:** Legacy cumulated KPI records with nil `investor_kpi_mapping_id` will be backfilled on next cumulation run
- **Dependencies:** None — uses existing Sidekiq infrastructure
