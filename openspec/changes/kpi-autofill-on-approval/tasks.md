# Tasks

## 1. Scoped Report Processing in KpiCumulateJob

- [x] 1.1 Add optional `report_ids` keyword parameter to `KpiCumulateJob#perform` and thread it through to `run_cumulation`. Verify: job accepts `report_ids: [1,2,3]` without error and passes it to `get_kpi_reports`.
- [x] 1.2 Update `get_kpi_reports` to return only the specified reports (ordered chronologically) when `report_ids` is present, bypassing the `autofill_completed` / recency gate. Verify: calling with `report_ids` for 3 reports out of 12 returns only those 3; calling without `report_ids` preserves existing gate behavior.
- [ ] 1.3 Add RSpec tests for `KpiCumulateJob` covering: (a) `report_ids` scopes to specified reports, (b) without `report_ids` existing gate logic is unchanged, (c) `force: true` bypasses the completion gate. Verify: `bundle exec rspec spec/jobs/kpi_cumulate_job_spec.rb` passes.

## 2. Approval-Triggered Cumulation in KpiApproveService

- [x] 2.1 Update `KpiApproveService.call` to collect `kpi_report_id` from approved KPIs, pass them as `report_ids` with `force: true` and `compute_percentage_change: true` to `KpiCumulateJob.perform_later`. Verify: approving 3 monthly KPIs enqueues a job with exactly those 3 report IDs.
- [ ] 2.2 Add RSpec tests for `KpiApproveService` verifying the job is enqueued with correct `report_ids`, `force: true`, and `compute_percentage_change: true`. Verify: `bundle exec rspec spec/services/kpi_approve_service_spec.rb` passes.

## 3. Mapping Backfill in KpiCumulative Concern

- [x] 3.1 Update `KpiCumulative` to assign `investor_kpi_mapping` via `||=` on both new and existing cumulated KPI records (not just new records). Verify: a cumulated record with nil mapping gets the source KPI's mapping after cumulation.
- [x] 3.2 Update the same-value skip guard to allow save when `investor_kpi_mapping_id` changed even if the numeric value is unchanged. Verify: a record with matching value but nil mapping is saved (not skipped).
- [ ] 3.3 Add RSpec tests for the concern covering: (a) nil mapping gets backfilled from source, (b) nil mapping gets backfilled from fallback when source has none, (c) mapping-only change triggers save. Verify: `bundle exec rspec spec/models/concerns/kpi_cumulative_spec.rb` passes.

## 4. Integration Verification

- [x] 4.1 End-to-end QA: approve monthly KPIs for a portfolio company with cumulate mappings on local, confirm Quarter/YTD/Year columns populate without manual recompute within the Sidekiq processing window. Verify: grid view shows cumulated values after page refresh.
- [ ] 4.2 Regression: trigger manual "Recompute Cumulative" action and confirm it still processes all reports for the portfolio company. Verify: all cumulative values recomputed as before.

## 5. Bug Fixes (QA)

- [x] 5.1 Fix array-to-nil casting in `KpiApproveService`: pass `@result_kpis.first.portfolio_company_id` (scalar integer) instead of `.pluck(:portfolio_company_id).uniq` (array). Add `Array()` defensive guard in `KpiCumulateJob` Phase 2 Compute loop. Verify: approval no longer queries reports with `portfolio_company_id IS NULL`.
- [x] 5.2 Add forward fill quarterly fallback in `KpiCumulative`: `process_quarterly_derived_forward_fill` reads Quarter KPIs to populate YTD when `fetch_related_monthly_kpis` returns empty. Uses `skip_years` to avoid double-processing fiscal years with monthly data. Verify: quarterly-only companies get YTD values after approval.
- [x] 5.3 Update `KpisController` approval notice messages: `approve` and `approve_all` display "Cumulative values are being computed — refresh the page in a few seconds." Verify: notice appears after approving KPIs.
