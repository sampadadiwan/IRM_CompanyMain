# Carry Computations & Performance Ratios User Guide

This guide explains how CapHive computes fund performance metrics — XIRR (net and gross IRR), DPI, RVPI, TVPI, MOIC, PIC, and Estimated Carry — and how these metrics are used at both the fund level and the individual investor (folio) level.

---

## Table of Contents

1. [Overview](#overview)
2. [Key Terms](#key-terms)
3. [Cash Flow Inputs](#cash-flow-inputs)
4. [Performance Metrics](#performance-metrics)
   - [DPI — Distributions to Paid-In](#dpi--distributions-to-paid-in)
   - [RVPI — Residual Value to Paid-In](#rvpi--residual-value-to-paid-in)
   - [TVPI — Total Value to Paid-In](#tvpi--total-value-to-paid-in)
   - [XIRR — Net IRR and Gross IRR](#xirr--net-irr-and-gross-irr)
   - [MOIC — Multiple on Invested Capital](#moic--multiple-on-invested-capital)
   - [PIC — Paid-In to Committed Capital](#pic--paid-in-to-committed-capital)
   - [Gross Portfolio IRR](#gross-portfolio-irr)
5. [Carry in FundUnitSettings](#carry-in-fundunitsettings)
6. [Estimated Carry Account Entry](#estimated-carry-account-entry)
7. [Net IRR vs Gross IRR](#net-irr-vs-gross-irr)
8. [Ratio Formulas — Customising Metrics](#ratio-formulas--customising-metrics)
9. [Tracking Currency Support](#tracking-currency-support)
10. [Computation Levels: Fund vs Folio](#computation-levels-fund-vs-folio)
11. [Key Computations Reference](#key-computations-reference)
12. [Frequently Asked Questions](#frequently-asked-questions)

---

## Overview

CapHive computes performance metrics using actual cash flow data stored in the system:
- **Capital calls** (money in from investors)
- **Capital distributions** (money back to investors)
- **Portfolio FMV** (current value of unrealised investments)
- **Cash in hand and net current assets** (liquid fund balances)
- **Estimated carry** (the GP's expected profit share from future exits)

Metrics can be computed at two levels:
- **Fund level** — aggregate across all investors
- **Folio level** — per individual investor commitment

---

## Key Terms

| Term | Meaning |
|------|---------|
| **Paid-In Capital** | The total amount investors have actually transferred to the fund (sum of verified capital remittance collected amounts) |
| **Distributions** | The total net payable actually sent back to investors (sum of completed distribution payments) |
| **FMV** | Fair Market Value of the fund's unrealised portfolio holdings (from "Portfolio FMV" account entry) |
| **Cash In Hand** | Liquid cash held by the fund (from "Cash In Hand" account entry) |
| **Net Current Assets** | Fund's net current assets balance (from "Net Current Assets" account entry) |
| **Estimated Carry** | The GP's estimated profit share (from "Estimated Carry" account entry). Used only when computing Net IRR. |
| **Carry %** | The percentage of profits the GP earns per unit class, configured in Fund Unit Settings |
| **End Date** | The date as of which metrics are calculated. All account entries and transactions up to and including this date are included. |

---

## Cash Flow Inputs

### For Net IRR / XIRR Calculations

| Cash Flow | Sign | Source |
|-----------|------|--------|
| Capital remittance payments | **Negative** (money out from investor) | `capital_remittance_payments.amount_cents` on `payment_date` |
| Distribution payments — gross payable | **Positive** (money back to investor) | `capital_distribution_payments.gross_payable_cents` on `payment_date` |
| Distribution payments — reinvestment | **Negative** (re-invested, not received) | `capital_distribution_payments.reinvestment_with_fees_cents` on `payment_date` |
| Portfolio FMV (terminal value) | **Positive** | "Portfolio FMV" account entry, as of end date |
| Cash In Hand | **Positive** | "Cash In Hand" account entry, as of end date |
| Net Current Assets | **Positive** | "Net Current Assets" account entry, as of end date |
| Estimated Carry | **Negative** (GP's share, reduces investor return) | "Estimated Carry" account entry — **only** when computing Net IRR |
| Custom ratio formula adjustments | **Positive or Negative** | Account entries specified via Ratio Formulas |

> **Reinvestment is treated as a cost** in XIRR because it represents money the investor is effectively putting back in (even though it came from a distribution), not money they have received.

### For DPI / RVPI / TVPI Calculations

| Component | Source |
|-----------|--------|
| **Paid-In (denominator)** | Sum of `collected_amount_cents` on **verified** capital remittances up to end date |
| **Distributions (DPI numerator)** | Sum of `net_payable_cents` on **completed** distribution payments up to end date |
| **Residual Value (RVPI numerator)** | `Portfolio FMV + Cash In Hand + Net Current Assets` |

---

## Performance Metrics

### DPI — Distributions to Paid-In

**What it measures:** How much cash has been returned to investors relative to how much they put in.

```
DPI = Total Distributions / Total Paid-In Capital

where:
  Total Distributions  = sum of net_payable_cents of COMPLETED distribution payments
                         (up to end date)
  Total Paid-In Capital = sum of collected_amount_cents of VERIFIED capital remittances
                          (up to end date)

DPI = 0  if Paid-In Capital is zero
```

- A DPI of 1.0x means investors have received back exactly what they put in.
- A DPI above 1.0x means the fund has returned more than was called.
- DPI only counts **completed** distributions and **verified** remittances, so unrecorded receipts or pending distributions do not appear here.

**Fund level:** Uses all fund remittances and distribution payments.
**Folio level:** Uses only the specific commitment's remittances and distribution payments.

---

### RVPI — Residual Value to Paid-In

**What it measures:** The current estimated value of unrealised investments relative to paid-in capital.

```
RVPI = (Portfolio FMV + Cash In Hand + Net Current Assets) / Total Paid-In Capital

RVPI = 0  if Paid-In Capital is zero
```

- A high RVPI indicates significant unrealised value still in the portfolio.
- FMV, Cash In Hand, and Net Current Assets are read from their most recent account entries on or before the end date.

**Fund level:** Uses fund-level account entries (not tied to any commitment).
**Folio level:** Uses the commitment's own account entries (e.g. investor's share of FMV).

---

### TVPI — Total Value to Paid-In

**What it measures:** The combined return — both what has been distributed and what remains in the portfolio.

```
TVPI = (Total Distributions + Residual Value) / Total Paid-In Capital

     = DPI + RVPI
```

- TVPI is the most commonly quoted performance multiple.
- A TVPI of 2.0x means investors have (or expect) to receive twice what they put in.

---

### XIRR — Net IRR and Gross IRR

**What it measures:** The internal rate of return of all cash flows, accounting for the timing of each payment.

#### Net IRR (Investor's perspective)

Net IRR uses the investor's actual cash flows:

```
Cash Flows In:   Capital remittance payments (negative)
                 Reinvestment portions of distributions (negative)
                 [Custom outflow formula entries]

Cash Flows Out:  Gross distribution payments (positive)
                 Portfolio FMV (positive, on end date)
                 Cash In Hand (positive, on end date)
                 Net Current Assets (positive, on end date)
                 [Custom inflow formula entries]

Adjustment:      Estimated Carry (negative, on end date) ← only when net_irr=true
```

When `net_irr = true`, the **Estimated Carry** account entry is subtracted from the terminal value. This reduces the investor's apparent return to reflect that the GP will take a share of future profits — giving a more conservative, LP-perspective return figure.

#### Gross IRR (Fund's perspective)

Gross IRR is calculated without the Estimated Carry deduction (i.e., `net_irr = false`). It represents the overall fund return before the GP's carry is taken.

```
Gross IRR = same as Net IRR, but Estimated Carry is NOT subtracted
```

The result is expressed as a **percentage, rounded to 2 decimal places** (e.g. 18.45%).

---

### MOIC — Multiple on Invested Capital

**What it measures:** The ratio of total realised and unrealised value from portfolio investments to the total invested capital. MOIC is computed from **portfolio investment transactions** (buys and sells), not from capital calls and distributions.

```
MOIC = (Total Sold Amount + Current FMV) / Total Bought Amount

where:
  Total Bought Amount = sum of portfolio investment buy amounts
  Total Sold Amount   = sum of portfolio investment sell amounts
  Current FMV         = sum of current FMV of remaining portfolio investments
```

- A MOIC of 2.0x means every rupee/dollar invested in portfolio companies has generated 2x in return.
- Stock conversions are removed from the numerator/denominator to avoid double-counting when a position has been converted.

---

### PIC — Paid-In to Committed Capital

**What it measures:** The proportion of total investor commitments that has actually been called.

```
PIC = Total Paid-In Capital / Total Committed Capital

where:
  Total Paid-In Capital  = sum of collected_amount_cents of VERIFIED remittances
  Total Committed Capital = sum of committed_amount_cents of all capital commitments
```

- A PIC of 0.60 means 60% of the committed capital has been drawn down.

---

### Gross Portfolio IRR

**What it measures:** The IRR of the portfolio company investments themselves — how well the fund has performed on its direct investments, independent of the fund's fee and carry structure.

```
Cash Flows:
  Portfolio investment buys  → Negative (money deployed)
  Portfolio investment sells → Positive (proceeds received)
  Portfolio income cashflows → Positive (dividends/distributions from portfolio companies)
  Current FMV               → Positive (terminal value, on end date)
  [Stock conversions adjusted out]
```

This is a fund-level metric only (not computed per folio).

---

## Carry in FundUnitSettings

Each unit class or series in a fund can have a **Carry %** configured in the **Fund Unit Settings**.

| Field | Description |
|-------|-------------|
| **Carry %** | The percentage of profits the GP earns on distributions from this unit class. E.g. 20% means the GP takes 20 cents for every 1 rupee/dollar of profit. |
| **Management Fee %** | Annual management fee percentage for this unit class. |
| **Setup Fee %** | One-time setup/placement fee percentage. |

The Carry % stored in FundUnitSetting is a **reference/informational field** used in distribution notices and reports. It is not automatically applied to calculated carry in XIRR/DPI computations — those use the "Estimated Carry" account entry instead.

### Setting Carry %

1. Navigate to the Fund.
2. Go to **Fund Unit Settings** (via the Actions menu).
3. Create or edit a unit class.
4. Enter the **Carry %** (e.g. 20 for 20%).

### Importing Fund Unit Settings

Fund unit settings (including carry %) can be imported via spreadsheet:

| Column | Description |
|--------|-------------|
| Fund | Fund name |
| Class/Series | Unit class name (must match a unit type already defined in the fund) |
| Management Fee % | Annual management fee |
| Setup Fee % | One-time setup fee |
| Carry % | Carry percentage for this class |
| Gp Units | Yes/No — whether these are GP units |
| ISIN | Securities identifier |
| Update Only | Yes/No — update existing only |

---

## Estimated Carry Account Entry

The **"Estimated Carry"** account entry is the mechanism through which carry is factored into XIRR calculations.

### What It Is

- A non-cumulative account entry with name = **"Estimated Carry"** recorded against a fund or commitment.
- It represents the GP's estimated share of future profits that will be paid out of the portfolio's unrealised value.
- It is used **only** in Net IRR calculations, where it is subtracted from the terminal value to show investors their expected return net of carry.

### How to Record It

The "Estimated Carry" account entry is typically generated by a **fund formula** in CapHive rather than entered manually. The formula computes the estimated carry based on:
- Current FMV
- Total distributions to date
- Hurdle rate (if applicable)
- Carry percentage from Fund Unit Settings

### Effect on Net IRR

```
Without Estimated Carry:  Gross IRR — returns the fund's full return
With Estimated Carry:     Net IRR  — subtracts GP's share from terminal value
                                     giving LP's actual expected return
```

Example:
- Current FMV = 500
- Estimated Carry = 80 (GP's expected 20% of unrealised profit)
- Net IRR terminal value = 500 − 80 = **420** (LP's share)
- Gross IRR terminal value = 500

---

## Net IRR vs Gross IRR

```
              GROSS IRR                     NET IRR (LP Perspective)
              ─────────                     ────────────────────────
Cash In:      Capital calls (negative)      Capital calls (negative)
              Reinvestment (negative)        Reinvestment (negative)

Cash Out:     Distributions (positive)      Distributions (positive)
              FMV (positive)                FMV (positive)
              Cash In Hand (positive)        Cash In Hand (positive)
              Net Current Assets (positive)  Net Current Assets (positive)
                                             Estimated Carry (NEGATIVE ← subtracted)

Result:       Full fund return              Investor's return after GP carry
```

Both are expressed as an annualised percentage return.

---

## Ratio Formulas — Customising Metrics

CapHive allows funds to customise how performance ratios are computed by adding **Ratio Formulas**. These define account entries that should modify the standard computation.

For full documentation, see the [Ratio Formulas User Guide](ratio_formulas_user_guide.md).

### Summary of Actions

| Action | Effect |
|--------|--------|
| `add_cashflow` | Adds the account entry as a positive cash flow in XIRR |
| `reduce_cashflow` | Adds the account entry as a negative cash flow in XIRR |
| `add_numerator` | Adds to the top of DPI / RVPI / TVPI / MOIC / PIC |
| `reduce_numerator` | Subtracts from the top |
| `add_denominator` | Adds to the bottom |
| `reduce_denominator` | Subtracts from the bottom |

### Formula Levels

| Level | Scope |
|-------|-------|
| **Fund** | Only applies to fund-level account entries (not tied to any commitment) |
| **Folio** | Only applies to entries tied to a specific investor commitment |
| **PortfolioCompany** | Only applies to entries tied to a portfolio company context |

### Period Options

| Period | Behaviour |
|--------|-----------|
| **As-on** | Takes only the single most recent non-cumulative entry on or before the end date |
| **All** | Sums all non-cumulative entries from the beginning up to the end date |

---

## Tracking Currency Support

All metrics can optionally be computed in the fund's **tracking currency** rather than its base currency.

When `use_tracking_currency = true`:
- Each capital remittance payment's `tracking_amount_cents` is used instead of `amount_cents`.
- Each distribution payment's `tracking_gross_payable_cents` / `tracking_net_payable_cents` are used.
- Account entry values (FMV, Cash In Hand, etc.) are converted to the tracking currency using the exchange rate on the end date.
- An exchange rate for the fund's base currency → tracking currency on the end date **must exist** in the system; otherwise the computation raises an error.

---

## Computation Levels: Fund vs Folio

```
  FUND LEVEL                          FOLIO LEVEL
  ──────────                          ───────────
  Uses all fund remittances           Uses only this commitment's remittances
  Uses all fund distribution payments Uses only this commitment's distribution payments
  FMV from fund-level AEs             FMV from commitment-level AEs
  Cash In Hand from fund-level AEs    Cash In Hand from commitment-level AEs
  Net Current Assets from fund AEs    Net Current Assets from commitment AEs
  Estimated Carry from fund AEs       Estimated Carry from commitment AEs
  All ratio formulas at Fund level    Ratio formulas at Folio level

  Class: FundPortfolioCalcs           Class: CapitalCommitmentCalcs
```

Both levels compute DPI, RVPI, TVPI, XIRR (gross and net). MOIC and Gross Portfolio IRR are fund-level only.

---

## Key Computations Reference

### DPI (Fund and Folio)

```
Paid-In = sum of collected_amount_cents WHERE verified=true AND payment_date ≤ end_date

Fund:    Distributions = sum of net_payable_cents WHERE completed=true AND payment_date ≤ end_date
                         (fund-level capital_distribution_payments)
Folio:   Distributions = sum of net_payable_cents WHERE completed=true AND payment_date ≤ end_date
                         (commitment's capital_distribution_payments)

DPI = Distributions / Paid-In
      [± ratio formula adjustments to numerator/denominator]
```

### RVPI (Fund and Folio)

```
Residual Value = FMV + Cash In Hand + Net Current Assets
                 (from account entries as of end_date)

RVPI = Residual Value / Paid-In
       [± ratio formula adjustments]
```

### TVPI (Fund and Folio)

```
TVPI = (Distributions + Residual Value) / Paid-In
       [± ratio formula adjustments]
     = DPI + RVPI  (approximately, before formula adjustments)
```

### XIRR

```
Cash flows:
  Each capital remittance payment:     (−amount) on payment_date
  Each distribution payment:           (+gross_payable) on payment_date
  Each reinvestment:                   (−reinvestment_with_fees) on payment_date
  Terminal: FMV                        (+) on end_date
  Terminal: Cash In Hand               (+) on end_date
  Terminal: Net Current Assets         (+) on end_date
  Terminal: Estimated Carry (net IRR)  (−) on end_date
  ± ratio formula cashflow entries

Result: annualised IRR as a percentage, rounded to 2 decimal places
```

### MOIC (Fund level)

```
For each portfolio investment buy (quantity > 0):
  total_bought += amount_cents

For each portfolio investment sell (quantity < 0):
  total_sold += |amount_cents|

Current FMV = sum of FMV of remaining positions

MOIC = (total_sold + Current FMV) / total_bought
       [± ratio formula adjustments]
```

### PIC

```
PIC = Total Paid-In Capital / Total Committed Capital

where:
  Total Committed Capital = sum of committed_amount_cents of all capital commitments
  Total Paid-In Capital   = sum of verified remittance collected amounts
```

### Gross Portfolio IRR

```
Cash flows:
  Buy portfolio investments  → (−amount_cents) on investment_date
  Sell portfolio investments → (+amount_cents) on investment_date
  Portfolio income cashflows → (+amount_cents) on payment_date
  Current FMV               → (+) on end_date

  [Stock conversion adjustments to remove double-counting]
  [Ratio formula cashflow entries for "Gross Portfolio IRR"]
```

---

## Frequently Asked Questions

**Q: What's the difference between DPI and TVPI?**
DPI only counts what has actually been distributed (paid out in cash). TVPI includes both distributions and the estimated remaining value (FMV + cash). TVPI = DPI + RVPI.

**Q: Why does Net IRR differ from Gross IRR?**
Net IRR subtracts the "Estimated Carry" account entry from the terminal FMV before computing the IRR. This reflects the GP's expected profit share, giving investors a more accurate picture of their own expected return after carry.

**Q: Where does the Estimated Carry figure come from?**
It comes from an account entry named exactly "Estimated Carry" recorded against the fund (for fund-level XIRR) or against the investor commitment (for folio-level XIRR). This entry is typically generated by a fund formula and updated periodically.

**Q: Is carry automatically deducted from distributions?**
No. The Carry % on Fund Unit Settings is informational and used in reports and notices. It is not automatically subtracted from distribution payments. Actual carry paid to the GP is recorded as a separate portfolio transaction or distribution. The "Estimated Carry" account entry is the only mechanism that affects computed metrics.

**Q: Why would DPI be negative?**
This would indicate that distributions have been recorded as negative amounts, or that paid-in capital is negative (rare). Check for any negative remittance payments or distribution payments.

**Q: Can RVPI be computed without FMV data?**
Yes — if no "Portfolio FMV" account entry exists, FMV defaults to zero. RVPI will then only reflect Cash In Hand and Net Current Assets. The result will typically be lower than the fund's true residual value.

**Q: What does the Carry % in Fund Unit Settings actually do?**
It is a reference number stored per unit class and displayed in reports and distribution notices. It does not automatically compute or deduct carry from XIRR or distribution calculations. To reflect carry in Net IRR, record an "Estimated Carry" account entry.

**Q: How is a fund's total paid-in capital different from a commitment's paid-in capital?**
At the fund level, paid-in = sum across ALL investor commitments' collected amounts (verified remittances). At the folio level, paid-in = only the specific commitment's collected amounts. This is why DPI and XIRR differ between fund-level and folio-level views for the same fund.

**Q: What happens to XIRR if no terminal value (FMV) is available?**
XIRR is still computed but the terminal value cash flows are zero. The result reflects only realised cash flows (distributions against capital calls). For a fund with no exits, this typically produces a negative XIRR.

**Q: Can Ratio Formulas override the standard account entries like Cash In Hand?**
No — Ratio Formulas are **additive** on top of the standard components. They cannot remove or replace the standard cash flows. If you need to exclude the default Cash In Hand, contact your system administrator.
