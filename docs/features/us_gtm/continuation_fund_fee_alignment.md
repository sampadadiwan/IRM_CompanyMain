# Continuation Funds & Fee Alignment

**Approach:** Build — no existing continuation vehicle model or fee step-down configuration; builds on existing `Fund`, `CapitalCommitment`, `CapitalDistribution`, and carry waterfall infrastructure
**Phase:** P2 — requires P1 capital events, closing room, and side letter foundation; meaningful only when multiple fund vehicles are live on the platform

---

## What This Is

Two of the most consequential structural trends reshaping private fund management in 2025–2026 are GP-led continuation funds and the evolution of fee structures toward investor alignment. A record 64 managers globally closed their first continuation fund in 2024 — a 25% year-on-year increase — while average hedge fund management fees have fallen to 1.38%, well below the traditional 2/20 structure, as LPs push for tighter fee-to-value alignment.

This feature covers two related but distinct capabilities:

**1. Continuation Fund Workflow.** A continuation fund is a new fund vehicle that acquires one or more assets from an existing GP-managed fund, offering existing LPs the choice to cash out or roll their economic interest into the new vehicle. The transaction requires: a new fund linked to the source fund, asset-level transfer records, a formal LP election process with tracked responses, carry crystallization at the transfer valuation, final reporting for exiting LPs, and ongoing reporting for the continuation fund.

**2. Fee Structure Configuration.** As LPs demand tighter alignment, fee structures have become highly customized: management fees that step down when AUM crosses thresholds, performance hurdles tied to index or risk-free rates, and catch-up mechanisms that balance GP and LP value capture. CapHive needs a flexible fee configuration model that supports these terms and auto-computes fees based on the configured rules.

---

## Who Uses It

| Persona | When | What They Need |
|---------|------|----------------|
| **CFO / COO** | Structuring a continuation fund | Create the continuation vehicle, link it to the source fund, designate transferring assets, configure transfer valuation |
| **IR Director** | LP election period | Distribute election packages, track each LP's response (cash out / roll), field LP questions; see live election progress |
| **Fund Counsel / GP team** | Carry crystallization | Review and approve carry computation at the transfer valuation; generate carry distribution to eligible fund participants |
| **Finance / Operations** | Post-transaction reporting | Generate final capital account statements and K-1s for exiting LPs; initialize new fund accounting for continuation vehicle LPs |
| **CFO** | Fee schedule configuration | Set up management fee step-downs, performance hurdles, and catch-up mechanisms at the fund level |
| **LP (via portal)** | Receiving election notice | Review detailed election package: transfer valuation, asset performance, fee structure of new vehicle, election deadline |

---

## Use Cases

### UC-1: Continuation Vehicle Creation from Source Fund

The GP identifies Fund II's best-performing portfolio company for transfer to a continuation vehicle. In CapHive, they create "Fund II Continuation" as a new Fund record linked to "Fund II" (`source_fund_id` FK). They mark the portfolio company as a transferring asset (`ContinuationAsset` record) with:
- Transfer valuation amount (set by independent third-party appraisal)
- Implied ownership percentage being transferred
- Transfer date
- Independent valuation firm name and report document

The system validates that the valuation methodology is documented before the LP election can be initiated.

### UC-2: LP Election Workflow — Cash Out or Roll

Once the transfer valuation is set and legal counsel approves, the GP triggers the LP election process. CapHive:
1. Generates an `LpElection` record for every LP in Fund II with their pro-rata entitlement to the continuation vehicle at the transfer price
2. Sends election packages via the LP portal: valuation summary, GP rationale, continuation fund terms (fee structure, expected duration, new fund admin details), election deadline
3. Tracks each LP's response: `cash_out`, `roll_over`, or `pending`
4. Shows the GP a live election dashboard: % electing to roll, % cashing out, total unreached, 48-hour deadline reminders auto-sent

LPs electing to roll have their `CapitalCommitment` in Fund II partially closed and a new `CapitalCommitment` created in Fund II Continuation at the equivalent NAV value.

### UC-3: Carry Crystallization at Transfer Valuation

The transfer valuation triggers a carry computation event on Fund II. The carry waterfall runs using the independent valuation as the realized value for the transferring asset:
- Return of contributed capital on that asset to LPs first
- Preferred return (per the Fund II LPA)
- GP catch-up and 20% carried interest on remaining profits

The carry computation generates a `CarryCrystallization` record showing: total profit on the asset, carried interest amount, GP catch-up, and per-LP impact. The CFO reviews and approves before carry is distributed. The system ensures that carry crystallization only proceeds if the transfer valuation is above the GP's carry threshold — preventing premature crystallization on flat or underperforming assets.

### UC-4: Dual Reporting — Exiting LPs Get Finals, Continuation Fund Gets Ongoing

After election closes, the system enters dual-reporting mode:
- **Exiting LPs:** Final capital account statement generated; Schedule K-1 flagged for year-end generation; LP portal access transitions to read-only archive mode
- **Continuation Fund LPs:** New fund reporting cycle begins; opening NAV, commitment record, and quarterly report template initialized; LP portal shows continuation fund under their portfolio alongside any retained Fund II interest

### UC-5: Management Fee Step-Down at AUM Threshold

Fund III is configured with a tiered management fee schedule: 2.0% on AUM up to $500M, 1.75% on AUM from $500M–$1B, 1.5% on AUM above $1B. The GP configures `FundFeeSchedule` records for Fund III in CapHive. The monthly fee calculation job reads current AUM (sum of committed capital minus returned capital), looks up the applicable tier, and computes the management fee for that period. LPs see the exact fee tier applied in their quarterly statements.

### UC-6: Performance Hurdle with Catch-Up Mechanism

A hedge fund configures a performance hurdle: 5% annual return (based on trailing 12-month Treasury yield + 200bps) before any incentive fee is earned. If the hurdle is cleared, a 50% GP catch-up applies until the GP has received 20% of profits above the hurdle; thereafter the standard 20% incentive fee applies. The `FundFeeSchedule` model captures: hurdle type (fixed or index-linked), hurdle rate, catch-up percentage, and standard incentive fee rate. The quarterly performance fee computation runs the waterfall and shows LPs the calculation in their statement.

---

## Current CapHive State

| Capability | Status | Notes |
|------------|--------|-------|
| Fund model with custom fields | ✅ Exists | `Fund` is the central entity; FormCustomField supports config fields |
| Capital commitment, call, and distribution models | ✅ Exists | Full production-ready capital events engine |
| Carry waterfall computation | ⚠️ Partial | Fund ratios and waterfall configuration exist; carry crystallization on a per-asset transfer basis is not modeled |
| Multiple fund vehicles per entity | ✅ Exists | Entities can have multiple funds; feeder/master fund links exist |
| Document generation and LP portal delivery | ✅ Exists | Notice templates, LP portal document delivery, statement generation |
| LP election workflow | ❌ Missing | No `LpElection` model; no election-period status, package delivery, or response tracking |
| Continuation vehicle fund type with source fund link | ❌ Missing | No `source_fund_id` FK or continuation vehicle classification on `Fund` |
| Asset-level continuation transfer record | ❌ Missing | No `ContinuationAsset` model tracking which portfolio company is being transferred and at what valuation |
| Management fee step-down by AUM tier | ❌ Missing | Fee rates are flat; no tiered AUM-based step-down configuration |
| Performance hurdle configuration (fixed or index-linked) | ❌ Missing | No hurdle type, hurdle rate, or catch-up percentage on fee schedule |
| Carry crystallization at transfer valuation | ❌ Missing | Carry runs at fund level at realized exit; per-asset transfer crystallization not supported |

---

## Build Approach: New `ContinuationFund` workflow + `FundFeeSchedule` model

### New Model: `ContinuationAsset` (belongs to Fund, PortfolioCompany)

```ruby
# app/packs/funds/funds/models/continuation_asset.rb
```

- `source_fund_id` FK — the original fund the asset is being transferred from
- `continuation_fund_id` FK — the new continuation vehicle receiving the asset
- `portfolio_company_id` FK — the company being transferred
- `transfer_valuation` decimal — independent third-party valuation amount
- `transfer_date` date
- `valuation_firm_name` string
- `valuation_report_document_id` FK — linked document (required before election can be initiated)
- `status` enum: `pending`, `election_open`, `election_closed`, `transferred`

### New Model: `LpElection` (belongs to Fund, CapitalCommitment, User)

```ruby
# app/packs/funds/funds/models/lp_election.rb
```

- `continuation_fund_id` FK
- `capital_commitment_id` FK — the LP's interest in the source fund
- `lp_entitlement_amount` decimal — their pro-rata share of the transfer valuation
- `election` enum: `pending`, `cash_out`, `roll_over`
- `elected_at` timestamp
- `election_package_sent_at` timestamp
- `reminder_sent_at` timestamp
- `notes` text — LP's stated reason (optional)

### New Model: `FundFeeSchedule` (belongs to Fund)

```ruby
# app/packs/funds/funds/models/fund_fee_schedule.rb
```

- `fund_id` FK
- `fee_type` enum: `management_fee`, `performance_fee`
- `tiers` JSONB — array of `{ aum_from, aum_to, rate }` for management fee step-downs
- `hurdle_type` enum: `fixed`, `index_linked` — for performance fees
- `hurdle_rate` decimal — fixed annual rate (e.g., 0.05 for 5%)
- `hurdle_index` string — e.g., `"SOFR"`, `"T_BILL_1Y"` (used when hurdle_type = index_linked)
- `hurdle_spread_bps` integer — basis points added to index (e.g., 200 = +2%)
- `catch_up_percentage` decimal — GP catch-up rate before standard incentive applies
- `incentive_fee_rate` decimal — standard incentive fee rate after catch-up

### Enhancements to `Fund`

- `source_fund_id` FK (nullable) — if set, this fund is a continuation vehicle
- `fund_structure_type` enum addition: `continuation`, `evergreen`, `credit` — extends existing structure type

### Services and Jobs

- `LpElectionService` — generates `LpElection` records, sends packages via LP portal, tracks responses, triggers reminders
- `CarryCrystallizationService` — runs carry waterfall on a per-asset transfer at the `ContinuationAsset.transfer_valuation`; generates `CarryCrystallization` report for CFO approval
- `FeeComputationJob` — monthly job that reads `FundFeeSchedule`, current AUM, and fund performance; computes management fee tiers and performance fee (with hurdle and catch-up); posts fee accrual entries

### UI Additions

- **Fund detail page:** "Continuation Fund" tab (visible when `fund_structure_type = continuation`) showing source fund link, asset transfer records, and LP election status board
- **Election dashboard:** live grid showing each LP's election status, entitlement amount, and deadline countdown; bulk reminder send
- **Fee schedule config:** UI in fund settings to add/edit tiered management fee and performance fee hurdle configuration

---

## Integration Points

| Integration | Purpose |
|-------------|---------|
| LP portal | Election package delivery; LP response capture; read-only archive mode for exiting LPs |
| Document generation | Final capital account statements for exiting LPs; continuation fund opening statements |
| Tax Center (`tax_center.md`) | Final K-1 generation for exiting LPs at year end |
| `CapitalCommitment` | Creating rollover commitments in continuation fund; closing source fund commitment for rolling LPs |
| `FundAdminExchangeLayer` (`fund_admin_exchange.md`) | Exporting election results and continuation fund investor master to fund administrator |
