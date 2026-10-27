# Spec Delta

## Purpose

Defines the fund and company-fund figures a portfolio report template can read: fund money, cost net of exits, fair market value across dates and its changes, the fund's returns for the consolidated report, and sold amount and budget variance for the per-company report.

## ADDED Requirements

### Requirement: Each company's fund line exposes the fund's money figures
In a consolidated report, each fund in a company's `funds` list SHALL expose the fund's committed, call, collected, distribution, target committed and total units premium amounts, and its tracking-currency committed, call, collected and distribution amounts. The figures SHALL be the fund's amounts as of the end date (see the next requirement), except the target committed amount, which is not dated.

#### Scenario: Fund money figures on the company fund line
- **WHEN** a consolidated template reads a company's fund line for a fund committed 502 Cr with 125.5 Cr collected
- **THEN** the line shows committed 502 Cr and collected 125.5 Cr

#### Scenario: Past end date shows the money figures as of that date
- **WHEN** the report is generated for an end date of 30 Sep 2026 and the fund has collected more since
- **THEN** the money figures show the amounts as of 30 Sep 2026

### Requirement: The fund's money figures can be worked out as of a date
The fund's as-of view SHALL give the fund's committed, call, collected, distribution and total units premium amounts, and its tracking-currency committed, call, collected and distribution amounts, as of a date, in the same currencies as the fund's own figures. Committed SHALL be the commitments dated on or before the date. Call SHALL be the remittances of capital calls dated on or before the date. Collected SHALL be the payments received on or before the date against those remittances that the fund has verified. Distribution SHALL be the distribution payments dated on or before the date (tracking distribution: completed payments only). Total units premium SHALL be the premium of fund units issued on or before the date. For today's date each figure SHALL equal the fund's own figure.

#### Scenario: Commitment after the date is not counted
- **WHEN** a commitment of 20 Cr is dated 10 Oct 2026 and the date asked for is 30 Sep 2026
- **THEN** committed as of 30 Sep 2026 does not include it

#### Scenario: Collection after the date is not counted
- **WHEN** a verified payment of 5 Cr is received on 5 Oct 2026 and the date asked for is 30 Sep 2026
- **THEN** collected as of 30 Sep 2026 does not include it

#### Scenario: Unverified collection is not counted
- **WHEN** a payment of 3 Cr was received on 15 Sep 2026 but its remittance is not verified
- **THEN** collected as of 30 Sep 2026 does not include it

#### Scenario: Distribution after the date is not counted
- **WHEN** a distribution payment is dated 5 Oct 2026 and the date asked for is 30 Sep 2026
- **THEN** distribution as of 30 Sep 2026 does not include it

#### Scenario: Units premium counts units issued up to the date
- **WHEN** one fund unit with a premium of 2 Cr was issued on 1 Sep 2026 and another with 1 Cr on 1 Nov 2026
- **THEN** total units premium as of 30 Sep 2026 is 2 Cr

#### Scenario: As of today matches the fund's own figures
- **WHEN** the figures are asked for as of today
- **THEN** committed, call, collected, distribution and total units premium equal the fund's own figures

### Requirement: Cost and value are shown for the prior quarter-end, the period and the end date
Each company fund line SHALL expose, for the investments in that fund on or before the end date: `cost_of_investment_prior` (purchases dated before the start date), `cost_of_investment_between` (purchases dated from the start date to the end date inclusive), `cost_of_investment` (all purchases to the end date), `cost_of_sold_between` (cost of the sales dated from the start date to the end date inclusive, as a positive amount), `fmv_prior` (value as of the day before the start date, of investments dated before the start date) and `fmv` (value as of the end date).

#### Scenario: Purchases split around the start date
- **WHEN** a company has a purchase of 40 Cr dated before 1 Jul 2026 and one of 10 Cr dated 15 Aug 2026, with start date 1 Jul 2026 and end date 30 Sep 2026
- **THEN** `cost_of_investment_prior` is 40 Cr, `cost_of_investment_between` is 10 Cr and `cost_of_investment` is 50 Cr

#### Scenario: Purchase on the start date counts as in the period
- **WHEN** a purchase is dated exactly 1 Jul 2026, the start date
- **THEN** it is in `cost_of_investment_between` and not in `cost_of_investment_prior`

#### Scenario: Purchase on the end date counts as in the period
- **WHEN** a purchase is dated exactly 30 Sep 2026, the end date
- **THEN** it is in `cost_of_investment_between`

#### Scenario: Exits in the quarter are positive
- **WHEN** a company sold part of its holding on 10 Sep 2026 and the cost of what was sold was 5 Cr
- **THEN** `cost_of_sold_between` is 5 Cr, a positive number

#### Scenario: Prior value uses the day before the start date
- **WHEN** a valuation of 50 Cr is dated 30 Jun 2026 and the start date is 1 Jul 2026
- **THEN** `fmv_prior` is 50 Cr

### Requirement: Cost net of exits adds up across the quarter
Each company fund line SHALL expose `cost_of_remaining_prior` and `cost_of_remaining`: the cost of the holdings still held as of the day before the start date and as of the end date. For a company, `cost_of_remaining_prior + cost_of_investment_between − cost_of_sold_between` SHALL equal `cost_of_remaining`. `cost_of_investment` SHALL keep meaning all purchases and SHALL NOT be reduced by exits.

#### Scenario: Roll-forward adds up
- **WHEN** a company's cost still held at 30 Jun 2026 is 40 Cr, it invests 10 Cr in the quarter and exits at a cost of 5 Cr
- **THEN** `cost_of_remaining_prior` is 40 Cr, `cost_of_remaining` is 45 Cr and 40 + 10 − 5 = 45

#### Scenario: No exits
- **WHEN** a company has no sale in the quarter
- **THEN** `cost_of_remaining` equals `cost_of_remaining_prior + cost_of_investment_between`

#### Scenario: Gross cost is unchanged by exits
- **WHEN** a company bought for 50 Cr in total and exited at a cost of 5 Cr
- **THEN** `cost_of_investment` is 50 Cr

#### Scenario: No holding before the start date
- **WHEN** a company's first purchase is in the quarter
- **THEN** `cost_of_remaining_prior` is 0

### Requirement: Fair market value change is shown as a percentage
Each company fund line SHALL expose `fmv_change_percent` as (`fmv` − `fmv_prior`) ÷ `fmv_prior` × 100, comparing total value at the end date with total value as of the day before the start date. When `fmv_prior` is zero the value SHALL be "N/A".

#### Scenario: Value rises
- **WHEN** `fmv_prior` is 50 Cr and `fmv` is 60 Cr
- **THEN** `fmv_change_percent` is 20

#### Scenario: Value falls
- **WHEN** `fmv_prior` is 24 Cr and `fmv` is 21 Cr
- **THEN** `fmv_change_percent` is −12.5

#### Scenario: A purchase in the quarter raises the change
- **WHEN** `fmv_prior` is 10 Cr, 10 Cr more is bought in the quarter and nothing is revalued
- **THEN** `fmv_change_percent` is 100

#### Scenario: No prior value
- **WHEN** `fmv_prior` is 0
- **THEN** `fmv_change_percent` is "N/A"

### Requirement: Value at the start of the financial year and the change since
Each company fund line SHALL expose `fmv_fy_start`, the value as of the day before the financial year containing the end date starts (investments dated before the financial year start), and `fmv_fy_start_change_percent` as (`fmv` − `fmv_fy_start`) ÷ `fmv_fy_start` × 100, or "N/A" when `fmv_fy_start` is zero. The financial year start SHALL be taken from the fund's own setting, otherwise the entity's setting, otherwise the country default (April for India).

#### Scenario: April financial year
- **WHEN** the end date is 30 Sep 2026 and the fund has no setting of its own and the default is April
- **THEN** `fmv_fy_start` is the value as of 31 Mar 2026

#### Scenario: Change since the financial year start
- **WHEN** `fmv_fy_start` is 45 Cr and `fmv` is 60 Cr
- **THEN** `fmv_fy_start_change_percent` is 33.3

#### Scenario: January financial year on the fund
- **WHEN** the fund's financial year setting starts in January and the end date is 30 Sep 2026
- **THEN** `fmv_fy_start` is the value as of 31 Dec 2025

#### Scenario: Entity setting used when the fund has none
- **WHEN** the fund has no setting and the entity's financial year starts in January
- **THEN** `fmv_fy_start` is the value as of 31 Dec of the previous year

#### Scenario: No value at the financial year start
- **WHEN** `fmv_fy_start` is 0
- **THEN** `fmv_fy_start_change_percent` is "N/A"

#### Scenario: Quarter starts at the financial year start
- **WHEN** the start date is 1 Apr 2026 and the end date is 30 Jun 2026 with an April year
- **THEN** `fmv_fy_start` equals `fmv_prior`

### Requirement: Fund totals carry the fund's money figures and collection percentages
Each entry of `fund_totals` SHALL expose the same money figures as the company fund line, taken once from the fund and NOT summed across companies, together with `collected_percent` (collected ÷ committed × 100), `uncollected_amount` (committed − collected) and `uncollected_percent` (uncollected ÷ committed × 100). When committed is zero the percentages SHALL be "N/A".

#### Scenario: Collection percentages
- **WHEN** a fund is committed 502 Cr with 125.5 Cr collected
- **THEN** `collected_percent` is 25, `uncollected_amount` is 376.5 Cr and `uncollected_percent` is 75

#### Scenario: Money figures not multiplied by the number of companies
- **WHEN** two selected companies have investments in the same fund committed 502 Cr
- **THEN** the fund total shows committed 502 Cr, not 1,004 Cr

#### Scenario: Zero commitment
- **WHEN** a fund's committed amount is 0
- **THEN** `collected_percent` and `uncollected_percent` are "N/A"

### Requirement: Fund totals sum cost and value and derive the change
Each entry of `fund_totals` SHALL expose `cost_of_investment`, `cost_of_investment_prior`, `cost_of_investment_between`, `cost_of_remaining`, `cost_of_remaining_prior`, `cost_of_sold_between`, `fmv` and `fmv_prior` as the sum over the selected companies' lines for that fund, and `fmv_change_percent` calculated from the summed `fmv` and `fmv_prior`, not averaged from the companies' percentages. `company_count` SHALL be the number of selected companies with an investment in the fund on or before the end date.

#### Scenario: Totals add up the companies
- **WHEN** Company A has `fmv_prior` 50 Cr and `fmv` 60 Cr and Company B has `fmv_prior` 24 Cr and `fmv` 21 Cr in the same fund
- **THEN** the fund total has `fmv_prior` 74 Cr, `fmv` 81 Cr and `fmv_change_percent` 9.5

#### Scenario: Roll-forward total adds up
- **WHEN** the companies' cost still held at 30 Jun is 40 Cr and 30 Cr, invested 10 Cr and 0, exits 5 Cr and 0
- **THEN** the total shows 70, 10, 5 and 75 Cr, and 70 + 10 − 5 = 75

#### Scenario: Company count counts only companies in the fund
- **WHEN** three companies are selected and two have an investment in the fund on or before the end date
- **THEN** `company_count` is 2

#### Scenario: Investment after the end date is not counted
- **WHEN** a selected company's only investment in the fund is dated after the end date
- **THEN** it is not counted in `company_count` and not in the totals

#### Scenario: Total change with no prior value
- **WHEN** the summed `fmv_prior` is 0
- **THEN** the total's `fmv_change_percent` is "N/A"

### Requirement: Fund totals carry the fund's returns
Each entry of `fund_totals` SHALL expose `irr`, `moic`, `tvpi`, `dpi` and `rvpi` as the fund's own stored ratios: for `irr` the fund's XIRR, otherwise the ratio of the same name; in each case the latest Default-scenario value dated on or before the end date. A ratio that was never run SHALL be "N/A". The fund's returns SHALL be separate from the company's own IRR and MOIC on the company fund line.

#### Scenario: Latest fund ratio on or before the end date
- **WHEN** the fund has TVPI runs dated 30 Jun 2026 (1.1) and 30 Sep 2026 (1.2) and the end date is 30 Sep 2026
- **THEN** `tvpi` is 1.2

#### Scenario: Run after the end date ignored
- **WHEN** the latest run is dated 15 Oct 2026 and the end date is 30 Sep 2026
- **THEN** the earlier run is used

#### Scenario: IRR comes from the fund's XIRR
- **WHEN** the fund has an XIRR of 18.5
- **THEN** `irr` is 18.5

#### Scenario: Ratio never run
- **WHEN** the fund has no DPI run
- **THEN** `dpi` is "N/A"

#### Scenario: Other scenarios ignored
- **WHEN** a ratio exists only in a non-Default scenario
- **THEN** it is "N/A"

### Requirement: The per-company report shows sold amount and cost of remaining per fund
In the per-company report, each fund's data SHALL expose `sold_amount`, the total of the sale investments in that fund dated on or before the end date, as a positive amount, and `cost_of_remaining`, the cost of the holdings still held as of the end date. The existing fields SHALL be unchanged.

#### Scenario: Sold amount
- **WHEN** a company sold shares for 7 Cr on 10 Sep 2026 and the end date is 30 Sep 2026
- **THEN** the fund's `sold_amount` is 7 Cr

#### Scenario: Sale after the end date ignored
- **WHEN** a sale is dated 5 Oct 2026 and the end date is 30 Sep 2026
- **THEN** it is not in `sold_amount`

#### Scenario: No sales
- **WHEN** the company has sold nothing in the fund
- **THEN** `sold_amount` is 0

#### Scenario: Cost of remaining on the company page
- **WHEN** a company bought for 50 Cr and sold at a cost of 5 Cr
- **THEN** `cost_of_remaining` is 45 Cr and `cost_of_investment` stays 50 Cr

### Requirement: Key metrics show Actual against Budget as a percentage change
For every Actual KPI column the per-company report SHALL also offer `<label>_vs_budget_compute_percent` as (Actual − Budget) ÷ Budget × 100, where Budget is the Budget KPI of the same name, period and date. It SHALL be "N/A" when either figure is missing or Budget is zero. The existing `<label>_vs_budget_percent` (Actual ÷ Budget × 100) SHALL be unchanged.

#### Scenario: Actual below Budget
- **WHEN** the YTD Actual is 92 and the YTD Budget is 100
- **THEN** `ytd_06_26_actual_vs_budget_compute_percent` is −8 and `ytd_06_26_actual_vs_budget_percent` is still 92

#### Scenario: Actual above Budget
- **WHEN** the quarter Actual is 75 and the quarter Budget is 60
- **THEN** `quarter_06_26_actual_vs_budget_compute_percent` is 25

#### Scenario: No Budget
- **WHEN** there is no Budget for the period
- **THEN** the compute percent is "N/A"

#### Scenario: Zero Budget
- **WHEN** the Budget is 0
- **THEN** the compute percent is "N/A"

### Requirement: Reports that do not use the new fields are unchanged
Adding these fields SHALL NOT change any existing field's value or any report whose template does not use them.

#### Scenario: Existing consolidated template
- **WHEN** a template that reads only name, currency, fmv, cost_of_investment, irr and moic is generated
- **THEN** the output is the same as before this change
