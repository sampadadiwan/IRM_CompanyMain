# KPI Autofill on Approval — Business Design

## Purpose

When a fund manager approves monthly KPIs, cumulative values (Quarter, YTD, Year) should automatically recompute. Before this feature, approved values sat in the grid while Quarter/YTD/Year columns showed "N/A" until someone manually clicked **Actions → Recompute Cumulative**. This was unintuitive — approvers expected the grid to update after approval.

Additionally, cumulation was completely broken for **Budget** and **IC** (Investment Committee) tagged KPIs — a pre-existing bug that was never caught because most clients only use Actual data.

---

## User Stories

### US-1: Auto-recompute on approval

**As a** fund manager,
**I want** Quarter/YTD/Year KPIs to update automatically when I approve monthly values,
**So that** I don't have to remember to click "Recompute Cumulative" after every approval cycle.

**Acceptance criteria:**
- Approving one or more monthly KPIs triggers a background job within seconds
- Quarter, YTD, and Year columns populate after a page refresh (5–10 seconds)
- The "Recompute Cumulative" button remains available as a manual fallback
- A flash notice tells the approver: "Cumulative values are being computed — refresh the page in a few seconds"

### US-2: Budget and IC tag cumulation

**As a** fund manager uploading Budget or IC projections,
**I want** cumulative values to compute correctly for Budget and IC tags,
**So that** Budget Q/YTD/Year and IC Q/YTD/Year values appear in the grid — not just Actuals.

**Acceptance criteria:**
- Budget monthly KPIs cumulate into Budget Quarter/YTD/Year
- IC monthly KPIs cumulate into IC Quarter/YTD/Year
- Values never cross between tags (Budget never writes to an Actual report or vice versa)
- Future-dated Budget/IC reports are allowed (Actuals still blocked for future dates)

### US-3: Forward fill for Balance Sheet items

**As a** fund manager viewing Balance Sheet KPIs (Assets, Liabilities, Equity),
**I want** YTD values to appear for every month — not just the last month of the year,
**So that** I can see the snapshot balance at any point during the fiscal year.

**Acceptance criteria:**
- Each month gets its own YTD record (Apr YTD = Apr value, May YTD = May value, etc.)
- Quarter value = last month's value in that quarter (snapshot, not sum)
- Year value = last month of fiscal year (when all 12 months present)

### US-4: Legacy mapping backfill

**As a** fund manager,
**I want** cumulated KPIs that show "N/A" in the grid to be fixed automatically,
**So that** I don't have to re-upload data to see values that were already computed.

**Acceptance criteria:**
- Cumulated KPIs missing their `investor_kpi_mapping` link get it backfilled during any cumulation run
- Grid view displays the value instead of "N/A" after backfill
- Only nil mappings are assigned — existing mappings are never overwritten

---

## UI Behavior

### Approval Flow (Before vs After)

```
BEFORE:
┌─────────────────────────────────────────────────────────┐
│  Grid View — Revenue (Actual)                           │
│                                                         │
│  Jan 2025  │  Feb 2025  │  Mar 2025  │  Q1 2025 │ YTD  │
│  10M       │  12M       │  15M       │  N/A     │ N/A  │
│                                                         │
│  [Approve All Staged]                                   │
│  ✓ Approved — but Q1 and YTD still show N/A             │
│  Must click "Actions → Recompute Cumulative" manually   │
└─────────────────────────────────────────────────────────┘

AFTER:
┌─────────────────────────────────────────────────────────┐
│  Grid View — Revenue (Actual)                           │
│                                                         │
│  Jan 2025  │  Feb 2025  │  Mar 2025  │  Q1 2025 │ YTD  │
│  10M       │  12M       │  15M       │  37M     │ 37M  │
│                                                         │
│  [Approve All Staged]                                   │
│  ✓ Approved — Q1 and YTD auto-populated after refresh   │
│  Flash: "Cumulative values are being computed —          │
│          refresh the page in a few seconds."             │
└─────────────────────────────────────────────────────────┘
```

### Budget Tag Grid (Before vs After Bug Fixes)

```
BEFORE (Bug — pre-existing on main):
┌─────────────────────────────────────────────────────────────────┐
│  Grid View — Revenue (Budget)                                   │
│                                                                 │
│  Apr 2026  │  May 2026  │  Jun 2026  │  Q1 FY27 │ YTD   │ Year │
│  288M      │  297M      │  310.5M    │  N/A     │ N/A   │ N/A  │
│                                                                 │
│  Even "Recompute Cumulative" did NOT work for Budget!           │
└─────────────────────────────────────────────────────────────────┘

AFTER (Fixed):
┌─────────────────────────────────────────────────────────────────┐
│  Grid View — Revenue (Budget)                                   │
│                                                                 │
│  Apr 2026  │  May 2026  │  Jun 2026  │  Q1 FY27 │ YTD   │ Year │
│  288M      │  297M      │  310.5M    │  895.5M  │ 895.5M│  —   │
│                                                                 │
│  Budget cumulates correctly within its own tag family           │
└─────────────────────────────────────────────────────────────────┘
```

### Forward Fill YTD (Before vs After)

```
BEFORE (Bug — Assets only had Jun YTD):
┌──────────────────────────────────────────────┐
│  Grid View — Assets (Budget, forward_fill)   │
│                                              │
│  Apr YTD  │  May YTD  │  Jun YTD             │
│  N/A      │  N/A      │  2,110.5M            │
└──────────────────────────────────────────────┘

AFTER (Fixed — each month gets its own YTD):
┌──────────────────────────────────────────────┐
│  Grid View — Assets (Budget, forward_fill)   │
│                                              │
│  Apr YTD  │  May YTD  │  Jun YTD             │
│  2,047.5M │  2,092.5M │  2,110.5M            │
└──────────────────────────────────────────────┘
```

---

## Behavior Rules

| Rule | Description |
|------|-------------|
| **Approval triggers cumulation** | Any approval path (approve single, approve all, mark reviewed) enqueues `KpiCumulateJob` with scoped report IDs and `force: true` |
| **Scoped processing** | Only the approved reports are reprocessed — not the entire portfolio company's history |
| **Tag isolation** | Actual, Budget, and IC KPIs each cumulate within their own tag. No cross-tag contamination |
| **Future-date guard** | Actual KPIs are blocked from creating future-dated cumulative records. Budget and IC are allowed (they are intentionally future-dated projections) |
| **Forward fill semantics** | Balance Sheet items (Assets, Liabilities) carry the latest value forward as a snapshot — not a sum. Each month gets its own YTD |
| **Compute respects tag** | Computed KPIs (e.g., Gross Profit Margin = Gross Profit / Revenue) are saved to the correct tag's report |
| **Mapping inheritance** | Cumulated KPIs inherit the source KPI's mapping. Legacy records with nil mapping are backfilled incrementally |
| **Manual fallback** | "Recompute Cumulative" button remains functional and unchanged |
| **Async processing** | Cumulation runs as a Sidekiq background job. The approval response is immediate; values appear after a page refresh |

---

## Autofill Modes Explained

| Mode | KPI Examples | What It Does | Period Logic |
|------|-------------|-------------|-------------|
| **cumulate** | Revenue, COGS, Gross Profit | Sums monthly values | Quarter = sum of 3 months; YTD = running sum from FY start; Year = sum of 12 months |
| **forward_fill** | Assets, Liabilities | Carries latest snapshot | Quarter = last month's value; YTD = each month carries its own value; Year = month 12 value |
| **compute** | Gross Profit Margin, Equity | Evaluates a formula | Uses values of other KPIs in the same report (e.g., `Gross Profit / Revenue`) |

---

## Tag Types

| Tag | Purpose | Who Creates It | Future-Dated? |
|-----|---------|---------------|---------------|
| **Actual** | Real reported numbers | Portfolio company / fund manager | No — blocked for future dates |
| **Budget** | Planned/forecast projections | Fund manager | Yes — projections are future by nature |
| **IC** | Investment Committee case projections at time of investment | Fund manager | Yes — projections set at deal time |

---

## Benefits

1. **No manual recompute needed** — cumulative values auto-update on approval, saving time every reporting cycle
2. **Budget/IC tags work** — previously completely broken, now cumulate/compute/forward_fill all function correctly for non-Actual tags
3. **Complete Balance Sheet view** — forward fill creates YTD snapshots for every month, not just the last
4. **Legacy data fixes itself** — nil mapping backfill resolves "N/A" display on cumulated KPIs without a migration
5. **Zero regression risk** — approval triggers the same `KpiCumulateJob` that "Recompute Cumulative" uses, just scoped to the approved reports

---

## Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Trigger mechanism | Scoped `report_ids` + `force: true` | Full reprocessing is wasteful; scoping to approved reports is precise and fast |
| Flash vs auto-refresh | Flash notice | Turbo Stream polling adds frontend complexity for a rare interaction; flash is simple and honest |
| Mapping backfill | Incremental via `||=` | A one-time migration script needs maintenance; incremental fix converges naturally |
| Bug fixes in same PR | Yes | The 3 tag/forward-fill bugs are in the same concern file and were exposed by testing the approval feature. Separate PRs would touch the same lines |

---

## Testing Reference

A detailed QA test guide with step-by-step scenarios is at:
`docs/user_guides/kpi_autofill_on_approval_test_guide.md`

---

## Related Documents

- [Technical Design](technical_design.md)
- [QA Test Guide](../user_guides/kpi_autofill_on_approval_test_guide.md)
- [KPI Approval Workflow](../modules/portfolio/kpis/kpi_approval_workflow.md)
