# Private Credit Fund Operations

**Approach:** Build — new loan-level tracking module; enhances existing `PortfolioCompany`, `Fund`, capital events, and reporting infrastructure
**Phase:** P1/P2 — loan accounting and NAV core are P1; covenant monitoring, credit-specific reporting, and fund-level leverage are P2

---

## What This Is

Private credit has become one of the fastest-growing asset classes in global private markets. AUM grew 76% in five years to $1.73 trillion as of December 2024, driven by banks pulling back from leveraged lending and institutional LPs seeking stable, predictable, yield-oriented returns. As more PE fund managers expand into private credit to diversify revenue, the operational demands of running a credit fund are landing on platforms that were designed for equity fund workflows.

Private credit loans are fundamentally different from PE equity investments:
- **Each loan is customized** — negotiated spread, structure, covenant package, maturity, PIK toggle — making administration more complex than tracking equity NAV
- **Income is earned continuously** — interest accrues daily and is distributed to LPs quarterly or monthly, not via discrete capital events
- **Collateral and covenants require active monitoring** — covenant breaches must be detected early; collateral coverage ratios must be computed per loan
- **The asset class is diversifying** beyond direct lending into asset-backed finance, infrastructure debt, jumbo residential mortgages, and commercial real estate credit — each with distinct cash flow and documentation patterns
- **Fund-level leverage is common** — subscription credit facilities and NAV lending facilities add a layer of fund-level liability that affects LP reporting

This feature adds loan-level tracking, interest accrual, covenant monitoring, credit-specific fund NAV, and investor reporting tailored to private credit fund mechanics.

---

## Who Uses It

| Persona | When | What They Need |
|---------|------|----------------|
| **Portfolio / Credit Manager** | Originating and managing loans | Record loan terms, track principal and interest, flag covenant breaches, manage loan amendments |
| **Finance / Fund Accounting** | Monthly/quarterly close | Compute interest income per loan; update loan fair values; compute fund NAV (gross asset value - liabilities); generate LP capital account statements |
| **COO / Operations** | Day-to-day fund ops | Monitor subscription line utilization; track outstanding capital calls for unfunded commitments; manage borrower reporting obligations |
| **IR Director** | LP reporting | Generate credit-specific quarterly reports: fund yield, weighted average spread, default rates, portfolio composition; field LP questions about individual loan performance |
| **CFO** | Fee computation and fund-level leverage | Monitor credit facility utilization and cost of leverage; compute management fee on fair value of loans (not committed capital) |
| **Compliance / General Counsel** | Regulatory and audit | Document valuation methodology for each loan; produce evidence of covenant monitoring and breach response |
| **Fund Administrator** | Receiving data from GP | Receive loan ledger, interest accrual schedule, and capital account data for independent NAV calculation |

---

## Use Cases

### UC-1: Loan Origination Record

A credit fund closes a $25M senior secured term loan to ABC Corp. The deal team enters the loan in CapHive:
- Borrower: ABC Corp (linked to `PortfolioCompany` record)
- Principal: $25,000,000
- Facility type: senior secured term loan
- Interest rate: SOFR + 550bps (with SOFR floor of 3.0%)
- PIK toggle: no
- Original issue discount (OID): 1.5% ($375,000)
- Maturity date: June 2029
- Closing date: June 2026
- Commitment fee: 0.5% on unfunded revolving portion (if applicable)
- Collateral: first lien on all assets; collateral description and pledge agreement document attached
- Covenant package: recorded as structured covenant records (see UC-4)

The system computes the effective yield (all-in return including OID amortization) and stores it alongside the loan record.

### UC-2: Daily Interest Accrual

Interest accrues daily on each outstanding loan principal. CapHive runs a nightly accrual job that computes:
- Floating rate loans: reads current SOFR rate (pulled from a rate provider) + loan spread; applies any SOFR floor; calculates daily interest = (rate / 365) × outstanding principal
- PIK loans: adds accrued PIK interest to principal balance (compounding)
- Fixed rate loans: applies fixed coupon rate

Accrued interest aggregates at the fund level to produce the fund's accrued income balance. At each quarter-end, accrued interest is swept into the cash distribution or added to principal (PIK).

### UC-3: Quarterly Interest Distribution to LPs

At quarter-end, the fund has accrued $2.1M in interest income from its loan portfolio. After deducting management fees and fund expenses, $1.85M is distributable. The system generates an interest distribution — modeled as a `CapitalDistribution` with `distribution_type = :interest_income`. Per-LP amounts are computed pro-rata based on their LP interest in the fund. Distribution notices are generated and sent via the LP portal. Fund NAV is updated to reflect the distribution.

### UC-4: Covenant Monitoring and Breach Alerting

For each loan, covenant conditions are recorded as structured `LoanCovenant` records:
- **Financial covenants:** Total Leverage Ratio ≤ 5.0× (tested quarterly), Debt Service Coverage Ratio ≥ 1.25× (tested quarterly), Minimum Liquidity $5M (tested monthly)
- **Reporting covenants:** Borrower must deliver audited financials within 90 days of fiscal year-end
- **Maintenance covenants:** Collateral coverage ratio ≥ 125%

When borrower financial data is entered (manually by the credit team or extracted by AI from uploaded borrower reports), the system tests each covenant. If a covenant is breached:
1. A `CovenantBreach` record is created with the tested value, threshold, and breach date
2. An alert is sent to the credit manager and compliance team
3. The loan's status updates to `covenant_breach`
4. The breach is surfaced in the fund's covenant monitoring dashboard and logged for auditor review

### UC-5: Loan Valuation and Fair Value Update

Private credit loans are not mark-to-market like public bonds; they require GP-assigned fair value estimates. Quarterly, the credit team enters updated fair values for each loan in the portfolio, subject to independent review:
- For performing loans near par: GP marks at or near face value
- For loans trading at a discount: GP enters market-based price supported by comparable transaction data or third-party pricing service reference
- For non-accrual loans: loan is flagged `non_accrual`; interest stops accruing; write-down is recorded

Each valuation record is stored with: entered value, methodology description (cost, market, income approach), and the approving user. Independent valuation review produces a linked document. The valuation feeds directly into fund-level NAV computation.

### UC-6: Fund NAV Computation for Credit Fund

Credit fund NAV = fair value of loan portfolio + cash - fund-level liabilities. The system computes this quarterly:
1. Aggregates `LoanValuation.fair_value` for all active loans
2. Adds fund cash balance
3. Subtracts subscription line balance (drawn credit facility)
4. Subtracts accrued management fee
5. Subtracts accrued fund expenses
6. Produces NAV per LP based on their economic interest

The NAV feeds into LP capital account statements and is the basis for management fee computation when fees are charged on NAV.

### UC-7: Subscription Credit Facility (Fund-Level Leverage)

The fund has a $50M subscription line of credit from a bank, collateralized by unfunded LP commitments. The GP draws on the facility to fund loans before calling capital from LPs, improving LP cash-on-cash returns at the expense of adding fund-level leverage. CapHive tracks:
- Facility limit and lender details
- Outstanding balance and available capacity
- Draw dates and amounts
- Repayment dates (typically when the corresponding LP capital call is settled)
- Interest accrual on the drawn balance
- Leverage ratio: drawn balance ÷ fund NAV (flagged if it exceeds policy limits)

### UC-8: Credit-Specific LP Quarterly Report

Private credit LP reports are materially different from PE quarterly reports. A credit fund quarterly report includes:
- Gross and net yield (gross interest income / average fair value of loans)
- Weighted average spread over benchmark (e.g., WAS over SOFR)
- Weighted average maturity (WAM) of the loan portfolio
- Portfolio composition by strategy (direct lending, asset-backed, infrastructure debt, CRE)
- Non-accrual rate (% of portfolio principal on non-accrual)
- Default rate (loans in default as % of total originations in the vintage)
- Realized loss rate (actual losses as % of total principal originated)
- Covenant breach summary (number of breaches in period, resolution status)
- Subscription line utilization and leverage ratio
- Unfunded commitments (revolving facilities not yet drawn by borrowers)

### UC-9: Asset-Backed Finance Loan Tracking

The fund has expanded into asset-backed finance (ABF) — a $30M facility secured by a pool of small business receivables. ABF differs from direct lending:
- Collateral is a pool of assets, not a single company
- Cash flows are pool-level (collections on receivables), not corporate cash flows
- Covenants are collateral-coverage-based (advance rate, overcollateralization tests), not financial ratio covenants

The `LoanFacility` model supports an `asset_type` field: `direct_lending`, `asset_backed`, `infrastructure_debt`, `real_estate_credit`. Asset-backed facilities have pool-level collateral records and pool performance metrics (collection rate, delinquency rate, loss rate) instead of borrower financial statement covenants.

---

## Current CapHive State

| Capability | Status | Notes |
|------------|--------|-------|
| `PortfolioCompany` model for portfolio tracking | ✅ Exists | Used for PE equity investments; can serve as borrower record for credit |
| Capital call, distribution, and commitment models | ✅ Exists | Closed-end fund mechanics; distribution model usable for interest distributions |
| Fund ratios and performance metrics | ✅ Exists | TVP/MOIC/IRR for PE; not credit-specific metrics |
| Report Builder for custom LP exports | ✅ Exists | Can generate data tables; no credit-specific templates |
| Document management | ✅ Exists | Loan agreement, pledge, amendment docs can be stored |
| Loan facility model with interest accrual | ❌ Missing | No `LoanFacility` model; no daily interest accrual engine |
| Loan-level interest income tracking | ❌ Missing | No interest accrual, PIK toggle, OID amortization |
| Covenant tracking and breach alerting | ❌ Missing | No `LoanCovenant` or `CovenantBreach` models |
| Loan fair value / valuation records | ❌ Missing | No loan-level quarterly valuation input; no non-accrual flag |
| Fund-level NAV for credit fund | ❌ Missing | No aggregated loan fair-value-to-NAV computation for credit |
| Subscription credit facility tracking | ❌ Missing | No fund-level credit facility model, draw/repayment tracking, or leverage ratio |
| Credit-specific LP report (yield, WAS, WAM, defaults) | ❌ Missing | No credit-specific metrics or report templates |
| Asset-backed finance collateral pool tracking | ❌ Missing | No pool-level collateral model or ABF-specific metrics |

---

## Build Approach: New `private_credit` pack — loan-level engine alongside existing portfolio and capital events

### New Models

**`LoanFacility`** (belongs to Fund, PortfolioCompany)

```ruby
# app/packs/funds/private_credit/models/loan_facility.rb
```

- `fund_id` FK
- `portfolio_company_id` FK — the borrower entity
- `facility_type` enum: `term_loan`, `revolving_credit`, `delayed_draw`, `asset_backed`, `infrastructure_debt`, `real_estate_credit`
- `commitment_amount` decimal — total facility size
- `outstanding_principal` decimal — current drawn balance
- `interest_rate_type` enum: `floating`, `fixed`, `pik`, `hybrid`
- `benchmark` string — e.g., `"SOFR"`, `"PRIME"` (for floating)
- `benchmark_floor` decimal — minimum benchmark rate (e.g., 3.0%)
- `spread_bps` integer — spread over benchmark
- `fixed_rate` decimal — used when `interest_rate_type = :fixed`
- `pik_toggle` boolean — whether PIK election is available
- `pik_elected` boolean — current PIK election status
- `oid_pct` decimal — original issue discount percentage
- `closing_date` date
- `maturity_date` date
- `status` enum: `performing`, `covenant_breach`, `non_accrual`, `default`, `repaid`
- `accrued_interest` decimal — running accrued interest balance

**`LoanAccrualEntry`** (belongs to LoanFacility)

```ruby
# app/packs/funds/private_credit/models/loan_accrual_entry.rb
```

- `loan_facility_id` FK
- `accrual_date` date
- `rate_applied` decimal — effective rate for that day (benchmark + spread, floored)
- `principal_balance` decimal — outstanding principal at accrual date
- `interest_amount` decimal — daily interest computed
- `pik_addition` decimal — principal increase if PIK elected

**`LoanValuation`** (belongs to LoanFacility, User)

```ruby
# app/packs/funds/private_credit/models/loan_valuation.rb
```

- `loan_facility_id` FK
- `valuation_date` date
- `fair_value` decimal
- `methodology` enum: `cost`, `market`, `income`, `third_party`
- `methodology_description` text
- `approved_by_user_id` FK
- `approved_at` timestamp
- `independent_review_document_id` FK (nullable)

**`LoanCovenant`** (belongs to LoanFacility)

```ruby
# app/packs/funds/private_credit/models/loan_covenant.rb
```

- `loan_facility_id` FK
- `covenant_type` enum: `financial`, `reporting`, `maintenance`, `collateral`
- `description` string — e.g., "Total Leverage Ratio"
- `threshold_operator` enum: `lte`, `gte`, `eq`
- `threshold_value` decimal
- `test_frequency` enum: `monthly`, `quarterly`, `annual`, `on_delivery`
- `last_tested_value` decimal (nullable)
- `last_tested_at` date (nullable)
- `status` enum: `compliant`, `breached`, `waived`, `not_tested`

**`CovenantBreach`** (belongs to LoanCovenant, LoanFacility)

```ruby
# app/packs/funds/private_credit/models/covenant_breach.rb
```

- `loan_covenant_id` FK
- `breach_date` date
- `tested_value` decimal
- `threshold_value` decimal
- `status` enum: `open`, `waived`, `cured`
- `resolution_notes` text
- `resolved_at` date (nullable)

**`FundCreditFacility`** (belongs to Fund)

```ruby
# app/packs/funds/private_credit/models/fund_credit_facility.rb
```

- `fund_id` FK
- `lender_name` string
- `facility_limit` decimal
- `outstanding_balance` decimal
- `available_capacity` decimal — computed: limit - outstanding
- `interest_rate` decimal — cost of the facility
- `maturity_date` date
- `collateral_type` enum: `subscription_line`, `nav_facility`
- `leverage_ratio` decimal — computed: outstanding ÷ fund NAV (flagged if > policy_max)
- `policy_max_leverage_ratio` decimal — configured limit; alert triggered if breached

**`CreditFacilityDraw`** (belongs to FundCreditFacility)

- `draw_date` date
- `amount` decimal
- `purpose` string
- `corresponding_capital_call_id` FK (nullable — set when LP call repays this draw)
- `repaid_at` date (nullable)

### Services and Jobs

- `LoanAccrualJob` — daily job; computes interest accrual for each performing loan; records `LoanAccrualEntry`; handles PIK addition to principal; skips non-accrual loans
- `OidAmortizationJob` — monthly; amortizes OID into interest income over loan term (straight-line or effective interest method)
- `CovenantTestingService` — run when borrower financials are entered; tests each `LoanCovenant` against the submitted value; creates `CovenantBreach` if threshold is violated; sends alerts
- `CreditFundNavService` — quarterly; aggregates `LoanValuation.fair_value` + fund cash - liabilities to produce fund NAV; feeds into LP capital account statements
- `CreditQuarterlyReportJob` — generates credit-specific LP quarterly report: yield, WAS, WAM, non-accrual rate, default rate, covenant breach summary, leverage ratio

### UI Additions

- **Loan Portfolio view:** table of all loans with status, principal, current fair value, accrued interest, yield, maturity — sortable and filterable
- **Loan detail page:** facility terms, accrual history, valuation history, covenant status, amendments, documents
- **Covenant Monitoring Dashboard:** fund-level view of all covenants across all loans; traffic-light status (green/amber/red); breach log
- **Fund Credit Facility panel:** draws, repayments, outstanding balance, leverage ratio gauge
- **Credit LP Report Builder template:** pre-built template with all credit-specific metrics, configurable per fund

---

## Integration Points

| Integration | Purpose |
|-------------|---------|
| `PortfolioCompany` | Borrower entity; links loan to portfolio tracking |
| `CapitalDistribution` | Interest distributions to LPs modeled as `distribution_type = :interest_income` |
| `CapitalCommitment` | Unfunded revolving facility balances add to LP unfunded commitment exposure |
| Fund Admin Exchange (`fund_admin_exchange.md`) | Loan ledger, accrual schedule, covenant status export to fund administrator |
| AI Document Intelligence (`ai_document_intelligence.md`) | Extract loan terms from credit agreements; extract covenant packages from term sheets |
| Report Builder | Credit-specific quarterly report template |
| LP portal | Interest distribution notices; covenant breach communications to LPs |
