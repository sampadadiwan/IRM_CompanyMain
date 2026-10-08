# KPI Autofill on Approval — Technical Design

## Architecture Overview

The KPI cumulation pipeline has three layers:

```
Approval Trigger
    └─> KpiApproveService (orchestrator)
            ├─> KpiApprover.call per KPI (status update)
            └─> KpiCumulateJob.perform_later (async, Sidekiq)
                    ├─> Phase 1: Cumulation (cumulate / forward_fill)
                    │       └─> KpiCumulative concern (autofill logic)
                    ├─> Phase 2: Compute (formula evaluation)
                    │       └─> KpiCumulative#compute_value_for_report
                    └─> Phase 3: Percentage Change
                            └─> KpiPercentageChangeJob.perform_now
```

### Pack Location

```
app/packs/startups/kpis/
├── services/
│   ├── kpi_approve_service.rb      # Triggers cumulation with scoped report_ids
│   └── kpi_approver.rb             # Individual KPI approval (unchanged)
├── jobs/
│   ├── kpi_cumulate_job.rb         # Accepts report_ids, force, compute_percentage_change
│   └── kpi_percentage_change_job.rb # MoM/YoY calculation (unchanged)
├── models/
│   ├── concerns/
│   │   └── kpi_cumulative.rb       # Core autofill logic — tag-aware, forward fill, mapping backfill
│   ├── kpi_report.rb               # TAG_LIST = {Actual, Budget, IC}
│   └── kpi.rb                      # KPI record
└── controllers/
    └── kpis_controller.rb          # approve/approve_all flash messages
```

---

## Data Model

### KpiReport

| Column | Type | Purpose |
|--------|------|---------|
| `id` | integer | PK |
| `entity_id` | integer | FK to Entity |
| `portfolio_company_id` | integer | FK to PortfolioCompany |
| `period` | string | `Month`, `Quarter`, `YTD`, `Year` |
| `as_of` | date | End date of the period (e.g., 2026-06-30) |
| `tag_list` | string | `Actual`, `Budget`, or `IC` |
| `user_id` | integer | FK to User who created/owns the report |
| `autofill_completed` | boolean | Gate for skipping already-processed reports |

### Kpi

| Column | Type | Purpose |
|--------|------|---------|
| `id` | integer | PK |
| `entity_id` | integer | FK to Entity |
| `portfolio_company_id` | integer | FK to PortfolioCompany |
| `kpi_report_id` | integer | FK to KpiReport |
| `investor_kpi_mapping_id` | integer | FK to InvestorKpiMapping (required for grid display) |
| `name` | string | KPI name (e.g., "Revenue") |
| `value` | decimal | The numeric value |
| `status` | string | `approved`, `staged` |
| `notes` | text | Auto-generated note (e.g., "Auto-generated Quarter cumulative") |

### InvestorKpiMapping

| Column | Type | Purpose |
|--------|------|---------|
| `autofill` | string | `cumulate`, `forward_fill`, `compute`, or blank |
| `compute_formula` | string | Formula for compute mode (e.g., `Gross Profit / Revenue`) |
| `standard_kpi_name` | string | Canonical KPI name for mapping lookup |

---

## Implementation Details

### 1. KpiApproveService — Trigger Cumulation on Approval

**File:** `app/packs/startups/kpis/services/kpi_approve_service.rb`

After approval completes, the service:
1. Collects `kpi_report_id` from all approved KPIs as `source_report_ids`
2. Passes a **scalar** `portfolio_company_id` (not array) — `Kpi.new(portfolio_company_id: [id])` silently casts arrays to nil via ActiveRecord integer type casting
3. Enqueues `KpiCumulateJob.perform_later` with `force: true`, `report_ids`, and `compute_percentage_change: true`

```ruby
# Pseudocode of the approval trigger:
source_report_ids = @result_kpis.map(&:kpi_report_id).uniq
portco_id = @result_kpis.first.portfolio_company_id  # scalar, not array
KpiCumulateJob.perform_later(
  portco_id,
  user_id: current_user.id,
  force: true,
  report_ids: source_report_ids,
  compute_percentage_change: true
)
```

### 2. KpiCumulateJob — Scoped Report Processing

**File:** `app/packs/startups/kpis/jobs/kpi_cumulate_job.rb`

New optional `report_ids` keyword parameter threaded through `perform` → `run_cumulation` → `get_kpi_reports`.

- When `report_ids` is present: returns only specified reports, ordered chronologically by `as_of`
- When `report_ids` is nil (existing callers): returns all reports, gated by `autofill_completed` check
- Phase 2 (Compute) wraps `portfolio_company_id` in `Array()` to guard against array-to-nil casting

### 3. KpiCumulative Concern — Core Autofill Logic

**File:** `app/packs/startups/kpis/models/concerns/kpi_cumulative.rb`

This is the heart of the feature with the most changes.

#### 3a. Tag-Aware Cumulation (Bug Fix #9 — commit `c16bd38`)

**Problem:** `fetch_related_monthly_kpis` and `fetch_related_quarterly_kpis` hardcoded `tag_list: 'Actual'`. Budget/IC monthly KPIs were silently ignored during cumulation.

**Fix:** Changed to `kpi_report.tag_list` — dynamic, respects whatever tag the current report has.

```ruby
# Before (broken):
.where(kpi_reports: { tag_list: 'Actual', period: 'Month' })

# After (fixed):
.where(kpi_reports: { tag_list: kpi_report.tag_list, period: 'Month' })
```

Also relaxed the future-date guard:
```ruby
# Before: blocked all future-dated cumulation
next if quarter_end > Date.current

# After: only block Actual (Budget/IC are intentionally future-dated)
next if quarter_end > Date.current && kpi_report.tag_list == 'Actual'
```

#### 3b. Tag-Scoped process_cumulative_kpi (Bug Fix #10 — commit `3943d27`)

**Problem:** `process_cumulative_kpi` used `KpiReport.find_by` without `tag_list`. When both Actual and Budget reports existed for the same date/period/entity/portco, the query found whichever report had the lower ID (typically Actual). Computed values for Budget were silently written to the Actual report.

**Fix:** Added `tag_list:` keyword parameter:
- Cumulation/forward_fill callers pass nil → falls back to `kpi_report&.tag_list`
- Compute caller passes `report.tag_list` explicitly (in-memory Kpi has no kpi_report)

```ruby
# Method signature:
def process_cumulative_kpi(_curr_kpi, cumulative_sum, period, _start_date, end_date,
                           note: nil, user_id: nil, force: false, tag_list: nil)
  tag_list ||= kpi_report&.tag_list

  # find_by includes tag_list:
  find_conditions = { period:, as_of: end_date, entity_id:, portfolio_company_id: }
  find_conditions[:tag_list] = tag_list if tag_list.present?
  report_for_period = KpiReport.find_by(find_conditions)

  # find_or_create_by also includes tag_list:
  create_conditions[:tag_list] = tag_list if tag_list.present?
  report_for_period ||= KpiReport.find_or_create_by(create_conditions)
end
```

#### 3c. Forward Fill YTD Per Month (Bug Fix #11 — commit `4600798`)

**Problem:** `process_yearly_forward_fill` only created one YTD record at `kpis_in_year.last` date. Apr/May YTD showed N/A for Balance Sheet items — only Jun had a value.

**Fix:** Iterate each month and create a per-month YTD record:

```ruby
# Before (broken — only last month got YTD):
def process_yearly_forward_fill(related_kpis, force: false)
  kpis_by_year = related_kpis.group_by { ... }
  kpis_by_year.each_value do |kpis_in_year|
    last_val = kpis_in_year.last.value.to_f
    process_cumulative_kpi(nil, last_val, 'YTD', nil, kpis_in_year.last.kpi_report.as_of, ...)
  end
end

# After (fixed — every month gets its own YTD):
def process_yearly_forward_fill(related_kpis, force: false)
  kpis_by_year = related_kpis.group_by { ... }
  kpis_by_year.each_value do |kpis_in_year|
    kpis_in_year.each do |kpi|
      process_cumulative_kpi(nil, kpi.value.to_f, 'YTD', nil, kpi.kpi_report.as_of, ...)
    end
  end
end
```

#### 3d. Mapping Backfill

Cumulated KPIs inherit the source KPI's mapping via `||=`:

```ruby
cumulative_kpi.investor_kpi_mapping ||= investor_kpi_mapping || fallback_investor_kpi_mapping
```

- Applied on both new and existing records
- `fallback_investor_kpi_mapping` does a `find_by(entity_id:, investor_id: portfolio_company_id, standard_kpi_name: name)` for legacy sources
- Only assigns when nil — never overwrites existing mappings

#### 3e. Forward Fill Quarterly Fallback

New method `process_quarterly_derived_forward_fill` for entities that report at Quarter granularity (no monthly data). Mirrors `process_quarterly_derived_cumulatives` but uses last-value semantics:

- Each quarter's value is carried forward as the YTD snapshot
- Year = Q4 value when all 4 quarters present
- `skip_years` prevents double-processing fiscal years that have both monthly and quarterly data

### 4. KpisController — Approval Notices

**File:** `app/packs/startups/kpis/controllers/kpis_controller.rb`

Both `approve` and `approve_all` actions show:
> "Cumulative values are being computed — refresh the page in a few seconds."

---

## Sequence Diagram — Approve All Flow

```
Fund Manager          KpisController       KpiApproveService      KpiCumulateJob         KpiCumulative
    │                      │                      │                      │                      │
    │  POST approve_all    │                      │                      │                      │
    │─────────────────────>│                      │                      │                      │
    │                      │  .call(kpi_ids)      │                      │                      │
    │                      │─────────────────────>│                      │                      │
    │                      │                      │  KpiApprover.call    │                      │
    │                      │                      │  per KPI (approve)   │                      │
    │                      │                      │                      │                      │
    │                      │                      │  collect report_ids  │                      │
    │                      │                      │  scalar portco_id    │                      │
    │                      │                      │                      │                      │
    │                      │                      │  perform_later       │                      │
    │                      │                      │  (force: true,       │                      │
    │                      │                      │   report_ids: [...]) │                      │
    │                      │                      │─────────────────────>│                      │
    │                      │                      │                      │                      │
    │  Flash: "Computing…" │                      │                      │                      │
    │<─────────────────────│                      │                      │                      │
    │                      │                      │       [ASYNC]        │                      │
    │                      │                      │                      │  Phase 1: autofill   │
    │                      │                      │                      │  per report/KPI      │
    │                      │                      │                      │─────────────────────>│
    │                      │                      │                      │  cumulate/fwd_fill   │
    │                      │                      │                      │<─────────────────────│
    │                      │                      │                      │                      │
    │                      │                      │                      │  Phase 2: compute    │
    │                      │                      │                      │─────────────────────>│
    │                      │                      │                      │  eval formula        │
    │                      │                      │                      │<─────────────────────│
    │                      │                      │                      │                      │
    │                      │                      │                      │  Phase 3: % change   │
    │                      │                      │                      │  perform_now         │
    │                      │                      │                      │                      │
    │  [Refresh page]      │                      │                      │                      │
    │  Grid shows Q/YTD/Y  │                      │                      │                      │
```

---

## Query Analysis

### No New N+1 Risks

1. **`KpiApproveService.call`** — `@result_kpis.map(&:kpi_report_id).uniq` operates on an in-memory array. Attribute reads, not additional queries.

2. **`get_kpi_reports` with `report_ids`** — Single query: `KpiReport.where(portfolio_company_id: ...).where(id: report_ids).order(:as_of).distinct`. No joins, no eager loading needed.

3. **Tag-aware queries** — `fetch_related_monthly_kpis` and `fetch_related_quarterly_kpis` use `kpi_report.tag_list` (attribute read on already-loaded association) instead of hardcoded `'Actual'`. Same SQL shape, dynamic bind value instead of constant.

4. **`process_cumulative_kpi`** — `KpiReport.find_by` with tag_list adds one more column to the WHERE clause. Same single-query pattern.

5. **Mapping backfill** — `fallback_investor_kpi_mapping` is a single `InvestorKpiMapping.find_by` query, only hit when both the record's mapping AND the source KPI's mapping are nil — rare edge case for legacy records.

### Index Coverage

`fetch_related_monthly_kpis` and `fetch_related_quarterly_kpis` use `.joins(:kpi_report).preload(:kpi_report)` (not `.includes`) to avoid eager-loading wide `kpi_reports` rows into the sort buffer. The composite index on `(entity_id, portfolio_company_id, name)` shrinks the candidate set before the filesort on `kpi_reports.as_of`.

---

## Bug Summary

All three bugs are **pre-existing on main** — not caused by the approval feature. They were exposed when QA tested Budget data for the first time.

| # | Bug | Root Cause | Fix | Commit |
|---|-----|-----------|-----|--------|
| 9 | Budget/IC cumulation silently skipped | `tag_list: 'Actual'` hardcoded in fetch queries | Use `kpi_report.tag_list` dynamically | `c16bd38` |
| 10 | Computed values saved to wrong tag's report | `process_cumulative_kpi` found reports without tag_list scope | Added `tag_list:` param to find/create conditions | `3943d27` |
| 11 | Forward fill YTD only for last month | `process_yearly_forward_fill` created one YTD at `kpis_in_year.last` | Iterate each month, create per-month YTD | `4600798` |

---

## Existing Infrastructure Reused

| Component | How It's Reused |
|-----------|----------------|
| `KpiCumulateJob` | Same Sidekiq job — new optional `report_ids` param, backward compatible |
| `KpiCumulative` concern | Same cumulation logic — tag-awareness and forward fill fixes |
| `KpiPercentageChangeJob` | Runs inline (`perform_now`) after cumulation, same as before |
| `KpiApproveService` | Extended to collect report IDs and pass to job |
| Sidekiq | Existing background job infrastructure |
| `autofill_completed` gate | Bypassed with `force: true` on approval path; unchanged for other callers |

---

## Files Changed

| File | Change Type | Lines |
|------|------------|-------|
| `app/packs/startups/kpis/services/kpi_approve_service.rb` | Modified | Collect report IDs, pass scalar portco_id, force: true |
| `app/packs/startups/kpis/jobs/kpi_cumulate_job.rb` | Modified | `report_ids` param, `Array()` guard |
| `app/packs/startups/kpis/models/concerns/kpi_cumulative.rb` | Modified | Tag-aware queries, tag-scoped process_cumulative_kpi, forward fill YTD per month, quarterly fallback, mapping backfill |
| `app/packs/startups/kpis/controllers/kpis_controller.rb` | Modified | Approval flash messages |
| `features/startup/kpi_autofill_on_approval.feature` | New | 4 cucumber scenarios |
| `features/step_definitions/kpi_autofill_on_approval_steps.rb` | New | Step definitions |

---

## Test Coverage

### Cucumber Scenarios (4 passing)

1. **Approve-all** — Verifies job enqueued with scalar ID, force, 4 report IDs, YTD KPIs created
2. **Approve-single** — Verifies job enqueued with 1 report ID
3. **Mapping backfill** — Verifies nil mapping gets assigned after cumulation
4. **Forward fill quarterly** — Verifies YTD KPIs derived from quarterly data when no monthly exists

### Regression Test Results

- **341 KPI cucumber scenarios** executed across 20 feature files
- **322 passed**, 19 pre-existing failures (mailer setup, XLSX submit guard timing, Playwright infrastructure — none related to cumulation)
- **Zero regressions** from the changes

### Manual Verification

- Budget tag: Revenue, COGS, Gross Profit (cumulate), Gross Profit Margin (compute), Assets, Liabilities (forward_fill), Equity (compute) — all correct across Month, Quarter, YTD, Year
- IC tag: Code is tag-agnostic — same path as Budget, verified by code review
- Actual tag: Existing behavior preserved

---

## Risks and Mitigations

| Risk | Mitigation |
|------|-----------|
| Large approval batches could slow the job | Scoped to only approved reports' IDs |
| Array-to-nil casting on `portfolio_company_id` | Fixed at source (scalar) and guarded at destination (`Array()`) |
| Mapping backfill overwrites intentional nil | Uses `||=`, only assigns when nil |
| Forward fill double-processing | `skip_years` excludes fiscal years with monthly data |
| Tag cross-contamination | `kpi_report.tag_list` ensures each tag family cumulates independently |
| Future-dated Actual records | Guard only relaxed for Budget/IC; Actual still blocked |

---

## Related Documents

- [Business Design](business_design.md)
- [QA Test Guide](../user_guides/kpi_autofill_on_approval_test_guide.md)
- [KPI Approval Workflow](../modules/portfolio/kpis/kpi_approval_workflow.md)
