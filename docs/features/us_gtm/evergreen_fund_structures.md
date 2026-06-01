# Evergreen Fund Structures

**Approach:** Build (extend existing `FundUnit` engine) — rolling subscription/redemption engine and fund-level NAV computation are new; unit issuance, unit type/class configuration, and LP holding views already exist
**Phase:** P2 — builds on P0/P1 commitment and capital events foundation; meaningful for GPs offering semi-liquid or perpetual capital vehicles

---

## What This Is

Evergreen funds — also called open-end or perpetual capital vehicles — are one of the fastest-growing structures in private markets. In private credit alone, the number of evergreen funds more than doubled in five years: from 141 in 2020 to 318 by mid-2025. US net AUM across semi-liquid evergreen funds reached $457 billion across 486 vehicles by end of 2025, with more than half launched in the preceding four years.

Unlike traditional closed-end PE funds with a fixed commitment period and 10-year term, evergreen funds operate continuously:
- **LPs subscribe at the current NAV** (not a fixed price set at a discrete capital call)
- **No fixed exit date** — investors hold until they choose to redeem
- **Redemption queues and gates** manage liquidity without forced asset sales
- **Management fees are on NAV** (not committed capital), computed monthly or quarterly

The model supports perpetual fundraising without the pressure of a discrete fundraise window. For investors, it offers duration flexibility — they choose when to enter and exit rather than committing to a fixed 5–10 year term.

**CapHive already has a strong foundation for evergreen funds.** The `FundUnit` model tracks per-investor unit holdings (quantity, price, issue date) linked to `CapitalCommitment`. The `DefaultUnitAllocationEngine` automatically issues units on verified capital call remittances and redeems units on completed distribution payments. `FundUnitSetting` configures unit types/classes with management fee %, carry %, and ISIN per class. `FundFormula` + `AccountEntryAllocationJob` can compute any fund-level or per-commitment number — including management fee on trailing NAV — via configurable formula rules.

What is genuinely missing is the **evergreen-specific operational layer**: a fund-level NAV computation model (so NAV per unit is dynamically computed, not manually set per call), rolling subscriptions that price at current NAV rather than a discrete call's unit price, a redemption request queue with gate enforcement, and evergreen-specific LP reporting.

---

## Who Uses It

| Persona | When | What They Need |
|---------|------|----------------|
| **COO / Head of Operations** | Configuring a new evergreen vehicle | Enable evergreen mode; set gate limit, subscription/redemption frequency, liquidity reserve target |
| **Finance / Fund Admin** | Monthly or quarterly NAV computation | Input portfolio valuations; system computes fund NAV and per-unit NAV; approves for LP portal publication |
| **IR Director** | Ongoing subscriptions and redemptions | Process new subscriptions at current NAV; manage redemption queue; communicate gate status to LPs |
| **LP (via portal)** | Entering or exiting the fund | See current NAV, units held, holding value, redemption request status, expected liquidity timeline |
| **Operations** | Fee computation | Run management fee formula against trailing NAV via `AccountEntryAllocationJob`; post fee accrual entries |
| **CFO** | Liquidity planning | Monitor redemption queue depth, available liquidity reserves, and deployment rate |

---

## Use Cases

### UC-1: LP Subscription at Current NAV

A new LP wants to invest $5M in the fund. They submit a subscription request on the LP portal. At the next subscription window, the system reads the latest approved `EvergreenNav.nav_per_unit` ($1,023.45/unit) and issues 4,885 `FundUnit` records for the LP — using the existing `DefaultUnitAllocationEngine` extended to accept NAV-based pricing instead of a call's `unit_prices` JSONB. No discrete capital call is issued; the LP wires funds against the subscription confirmation, which maps to a `SubscriptionRequest` (new) rather than a `CapitalRemittance`.

### UC-2: Rolling Subscriptions — Multiple Windows

The fund accepts subscriptions on the first business day of each month. Between windows, subscription requests queue in `pending` status in `SubscriptionRequest`. On the processing date, the system prices all pending requests at the latest approved NAV and triggers `DefaultUnitAllocationEngine` to issue `FundUnit` records. A dashboard shows: pending subscriptions for the next window, total capital to be deployed, and current liquidity capacity.

### UC-3: Redemption Request and Queue Management

An LP submits a redemption request for $2M (1,954 units at current NAV). The system records the `RedemptionRequest` with date received and queue position. Redemptions process quarterly, subject to a 5% gate (maximum 5% of fund NAV redeemed in any quarter). If total requests exceed the gate, the system processes in FIFO order up to the limit and rolls remaining requests to the next quarter. Processed redemptions trigger `DefaultUnitAllocationEngine` to create a negative-quantity `FundUnit` record — using the same redemption path as an existing `CapitalDistributionPayment`, but sourced from the `RedemptionRequest` instead.

### UC-4: Gate Mechanism During Market Stress

Fund NAV declines 8% in Q3 due to portfolio markdowns. Redemption requests spike to 12% of NAV. The system automatically applies the gate, processes 5% of NAV in FIFO order, and notifies all affected LPs that their remaining requests are queued to Q4. The GP team receives a summary: total queued redemptions, NAV coverage ratio, projected liquidity from asset repayments in Q4, and whether the gate is likely to be triggered again.

### UC-5: Monthly NAV Calculation and Approval

At month-end, the fund admin enters updated portfolio valuations for all holdings. The system aggregates fair value across all positions, adds fund cash, subtracts liabilities (fee accruals, subscription line draws), and divides by total `FundUnit.quantity` outstanding to produce a per-unit NAV. The result is stored as an `EvergreenNav` record. The CFO reviews and approves; only after approval does the per-unit NAV publish to the LP portal. LPs see their holding value as units held × current NAV per unit. The full computation and approval chain are stored for audit.

### UC-6: Management Fee on NAV (Not Committed Capital)

The fund charges 1.5% per annum management fee on trailing month-end NAV. A `FundFormula` rule of type `GenerateAccountEntry` is configured: formula reads the prior month-end `EvergreenNav.net_asset_value`, applies the annual rate prorated to the month, and posts a management fee accrual entry via `AccountEntryAllocationJob`. The accrued fee becomes a fund-level liability that reduces NAV in the next computation. Quarterly, the accrued fee settles as a cash payment to the management company. LPs see the fee accrual as a per-unit NAV adjustment in their quarterly statement.

### UC-7: Vintage / Series Tracking Within an Evergreen Vehicle

Some GPs operate an evergreen structure using a vintage model: each vintage has a defined subscription window and investment period, runs off as loans or investments mature, and returns capital while the next vintage deploys. `FundUnitSetting` already captures the series/class name, management fee %, carry %, and ISIN. `EvergreenVintage` (new) adds the investment period dates and run-off status: `subscription_open_date`, `investment_period_end_date`, and `status` (open / investment_period / run_off). Units issued during a vintage's subscription window are tagged to that vintage; the run-off dashboard shows capital returned per vintage.

### UC-8: Semi-Liquid LP Quarterly Report

Quarterly reporting for evergreen LPs differs materially from PE quarterly reports. CapHive generates an evergreen-specific quarterly report showing:
- Opening and closing NAV per unit
- Units held at opening and closing (sourced from `FundUnit` records)
- Subscriptions and redemptions in the period
- NAV change drivers (valuation changes, income earned, fees paid)
- Redemption queue status and next processing date
- Liquidity reserves as % of NAV
- Deployment statistics (% invested vs. cash)

---

## Current CapHive State

| Capability | Status | Notes |
|------------|--------|-------|
| `FundUnit` model — per-investor unit tracking (quantity, price, issue date, unit type) | ✅ Exists | Tracks units issued on calls and redeemed on distributions; linked to `CapitalCommitment` and `Investor` |
| `FundUnitSetting` — unit class/series configuration (management fee %, carry %, ISIN) | ✅ Exists | Configures named unit types per fund; validates against `fund.unit_types` |
| `DefaultUnitAllocationEngine` — auto-issues units on remittances; redeems on distribution payments | ✅ Exists | Idempotent; handles price + premium; sets issue date; handles PIK/premium structures |
| `FundUnitTransfer` + service — LP-to-LP unit transfers | ✅ Exists | Supports transfer ratio, pricing, dated transfers between commitments |
| LP unit holding views (quantity, price, amount) | ✅ Exists | `fund_units` views show per-investor unit ledger; linked to commitment and investor |
| `FundFormula` + `AccountEntryAllocationJob` — general-purpose computation and fee accrual engine | ✅ Exists | Can compute management fee on trailing NAV via `GenerateAccountEntry` formula type; runs against any fund variable |
| Unit price set per capital call | ✅ Exists | `unit_prices` JSONB on `CapitalCall` and `CapitalDistribution`; per unit type |
| Fund-level NAV computation (fair values → NAV → per-unit) | ❌ Missing | No `EvergreenNav` model; price per unit is set manually per call, not derived from fund NAV ÷ total units |
| Rolling subscription processing without a discrete capital call | ❌ Missing | `DefaultUnitAllocationEngine` requires a `CapitalRemittance` tied to a `CapitalCall`; no subscription-window processing path |
| `SubscriptionRequest` queue (pending → processed at NAV on subscription date) | ❌ Missing | No subscription request model or window-based processing |
| Redemption request queue | ❌ Missing | Redemption exists only via `CapitalDistributionPayment`; no queue, FIFO ordering, or gate enforcement |
| Gate mechanism (% of NAV cap per redemption period) | ❌ Missing | No gate configuration or enforcement |
| `EvergreenFundConfig` (subscription/redemption frequency, gate %, liquidity reserve target) | ❌ Missing | No evergreen-specific fund configuration model |
| `EvergreenVintage` — investment period and run-off date tracking | ⚠️ Partial | `FundUnitSetting` has class/series name and fee structure; lacks `investment_period_end_date` and run-off status |
| Evergreen-specific LP quarterly report template | ❌ Missing | Existing PE quarterly report does not cover NAV per unit, units held, redemption queue status |

---

## Build Approach: Extend existing `FundUnit` engine with evergreen-specific NAV and subscription/redemption machinery

### New Model: `EvergreenFundConfig` (belongs to Fund)

```ruby
# app/packs/funds/funds/models/evergreen_fund_config.rb
```

- `fund_id` FK — only for funds with `fund_structure_type = :evergreen`
- `subscription_frequency` enum: `monthly`, `quarterly`
- `redemption_frequency` enum: `quarterly`, `semi_annual`
- `redemption_gate_pct` decimal — max redemptions as % of NAV per period (e.g., 0.05 = 5%)
- `notice_period_days` integer — LP must submit redemption request N days before window
- `liquidity_reserve_target_pct` decimal — target cash % of NAV held as liquidity buffer

### New Model: `EvergreenNav` (belongs to Fund, User)

```ruby
# app/packs/funds/funds/models/evergreen_nav.rb
```

- `fund_id` FK
- `nav_date` date
- `gross_asset_value` decimal — sum of portfolio fair values + cash
- `total_liabilities` decimal — fee accruals, subscription line balance, other
- `net_asset_value` decimal — gross - liabilities
- `units_outstanding` decimal — sum of positive `FundUnit.quantity` for the fund at nav_date
- `nav_per_unit` decimal — net_asset_value / units_outstanding
- `computed_by_user_id` FK
- `approved_at`, `approved_by_user_id` — approval required before LP portal publication

The `units_outstanding` is read from the existing `FundUnit` records (`fund.fund_units.sum(:quantity)`). No new unit tracking model needed — `FundUnit` is the source of truth.

### New Model: `SubscriptionRequest` (belongs to Fund, Investor, CapitalCommitment)

```ruby
# app/packs/funds/funds/models/subscription_request.rb
```

- `fund_id`, `investor_id`, `capital_commitment_id` FK
- `amount_requested` decimal
- `status` enum: `pending`, `processed`, `cancelled`
- `requested_at` timestamp
- `processing_date` date — subscription window assigned to
- `nav_per_unit_applied` decimal — `EvergreenNav.nav_per_unit` at time of processing
- `units_issued` decimal — computed: amount / nav_per_unit

On processing: calls `DefaultUnitAllocationEngine` with NAV-based pricing (reads `EvergreenNav.nav_per_unit` instead of `CapitalCall.unit_prices`) to create the `FundUnit` record. Extends the existing engine with a `allocate_subscription(subscription_request, reason)` method alongside the existing `allocate_call`.

### New Model: `RedemptionRequest` (belongs to Fund, CapitalCommitment)

```ruby
# app/packs/funds/funds/models/redemption_request.rb
```

- `fund_id`, `capital_commitment_id` FK
- `units_requested` decimal
- `amount_requested` decimal — units × NAV at request date
- `status` enum: `pending`, `partially_processed`, `fully_processed`, `cancelled`
- `requested_at` timestamp
- `queue_position` integer — FIFO ordering within a redemption window
- `gate_applied` boolean — true if gate was enforced on this request
- `amount_processed` decimal — settled so far

On processing: gate check runs first (total requested units × NAV vs. gate_pct × fund NAV). Requests up to the gate are processed in FIFO order; `DefaultUnitAllocationEngine.allocate_redemption` creates a negative-quantity `FundUnit` record (parallel to existing `allocate_distribution_payment`). Remaining requests are carried forward.

### Enhancements to Existing Models

**`FundUnitSetting`** — add evergreen vintage fields:
- `vintage_label` string — e.g., "2024-Q1" (optional)
- `investment_period_end_date` date — after this, vintage enters run-off
- `run_off` boolean — true when investment period has ended

**`DefaultUnitAllocationEngine`** — add two new public methods:
- `allocate_subscription(subscription_request, reason)` — reads `EvergreenNav.nav_per_unit` for pricing; creates `FundUnit`
- `allocate_redemption(redemption_request, reason)` — creates negative-quantity `FundUnit`; uses `EvergreenNav.nav_per_unit` at redemption date

**`Fund`** — add `fund_structure_type` enum value `:evergreen` (alongside `:closed_end`, `:continuation`).

### Management Fee on Trailing NAV — Using Existing `FundFormula`

No new fee computation model needed. Configure a `FundFormula` rule:

```
# FundFormula: "Management Fee Accrual"
# rule_type: GenerateAccountEntry
# entry_type: management_fee

monthly_nav = fund.evergreen_navs.where(nav_date: ..@end_date).order(:nav_date).last&.net_asset_value || 0
annual_rate = fund.fund_unit_settings.first&.management_fee.to_d / 100
days_in_period = (@end_date - @start_date).to_i
(monthly_nav * annual_rate * days_in_period / 365).round(2)
```

`AccountEntryAllocationJob` runs this formula monthly. The resulting account entry flows into fund-level liabilities and reduces NAV at next computation.

### New Services and Jobs

- `SubscriptionProcessingJob` — runs on subscription date; prices all `pending` `SubscriptionRequest` records at latest approved `EvergreenNav`; calls `DefaultUnitAllocationEngine.allocate_subscription` per request
- `RedemptionProcessingJob` — runs on redemption date; enforces gate; processes in FIFO order; calls `DefaultUnitAllocationEngine.allocate_redemption`; updates queue for carried-forward requests
- `EvergreenNavService` — aggregates portfolio fair values + fund cash - liabilities + reads `FundUnit` total quantity to produce `EvergreenNav` record for approval

### UI Additions

- **Evergreen Operations Dashboard:** subscription queue for next window; redemption queue depth with gate status; NAV history chart; units outstanding over time
- **NAV Approval Flow:** finance team enters valuations → system computes NAV via `EvergreenNavService` → CFO approves → publishes per-unit NAV to LP portal
- **LP Portal — Evergreen View:** units held (from `FundUnit`), current value (units × latest NAV per unit), cost basis, unrealized gain/loss, redemption request form, pending redemption queue status
- **Fund Config — Evergreen Settings:** gate %, subscription/redemption frequency, notice period, liquidity reserve target

---

## Integration Points

| Integration | Purpose |
|-------------|---------|
| `FundUnit` | Source of truth for per-investor unit holdings; units_outstanding feeds `EvergreenNav` computation |
| `DefaultUnitAllocationEngine` | Extended with `allocate_subscription` and `allocate_redemption` methods; existing call/distribution paths unchanged |
| `FundFormula` + `AccountEntryAllocationJob` | Management fee on trailing NAV via `GenerateAccountEntry` formula; no new fee engine needed |
| LP portal | Subscription request submission; redemption request form; units held and NAV per unit display |
| Fund Admin Exchange (`fund_admin_exchange.md`) | Export NAV, unit registry, and redemption activity to fund administrator |
| Report Builder | Evergreen-specific quarterly LP report template (NAV per unit, units, performance attribution, queue status) |
| AI Document Intelligence (`ai_document_intelligence.md`) | Extract evergreen-specific LPA terms: gate %, notice period, redemption frequency |
