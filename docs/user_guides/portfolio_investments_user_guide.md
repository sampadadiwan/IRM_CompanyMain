# Portfolio Investments User Guide

This guide covers everything about recording, tracking, and computing returns on portfolio investments — including buy/sell transactions, FMV computation, FIFO and weighted-average cost attribution, aggregate views, stock conversions, splits, adjustments, portfolio cashflows, and scenarios.

---

## Table of Contents

1. [Overview](#overview)
2. [Key Concepts and Data Model](#key-concepts-and-data-model)
3. [Portfolio Investment Lifecycle](#portfolio-investment-lifecycle)
4. [Investment Instruments](#investment-instruments)
5. [Creating a Portfolio Investment (Buy)](#creating-a-portfolio-investment-buy)
6. [Recording a Sale (Sell)](#recording-a-sale-sell)
7. [Attribution — FIFO vs Weighted Average](#attribution--fifo-vs-weighted-average)
8. [FMV Computation](#fmv-computation)
9. [Aggregate Portfolio Investment](#aggregate-portfolio-investment)
10. [Key Computed Fields](#key-computed-fields)
11. [Stock Conversions](#stock-conversions)
12. [Stock Splits](#stock-splits)
13. [Stock Adjustments](#stock-adjustments)
14. [Portfolio Cashflows (Income)](#portfolio-cashflows-income)
15. [Proforma Investments](#proforma-investments)
16. [Excused Investors](#excused-investors)
17. [Portfolio Scenarios](#portfolio-scenarios)
18. [Multi-Currency Support](#multi-currency-support)
19. [Importing Data](#importing-data)
20. [Key Computations Reference](#key-computations-reference)
21. [Frequently Asked Questions](#frequently-asked-questions)

---

## Overview

CapHive's portfolio module tracks a fund's direct investments in portfolio companies — recording purchases (buys), sales (sells), current fair market value (FMV), and computing unrealised and realised gains. Each transaction belongs to a **Portfolio Company** and is denominated in a specific **Investment Instrument** (e.g. equity shares, debentures, CCDs).

```
  Fund
    │
    ├── Portfolio Company A
    │       ├── Investment Instrument: Series A Equity
    │       │       ├── Aggregate Portfolio Investment (rolled-up view)
    │       │       │       ├── Portfolio Investment: Buy 1,000 shares @ ₹100 (2021-03-01)
    │       │       │       ├── Portfolio Investment: Buy 500 shares @ ₹150 (2022-06-15)
    │       │       │       └── Portfolio Investment: Sell 600 shares @ ₹200 (2023-09-01)
    │       │       │               └── Portfolio Attributions (FIFO links to the buys)
    │       │       └── Valuations (per-share price history)
    │       └── Investment Instrument: CCDs
    │               └── Aggregate Portfolio Investment
    └── Portfolio Company B
            └── ...
```

---

## Key Concepts and Data Model

| Term | Meaning |
|------|---------|
| **Portfolio Company** | The investee company (stored as an Investor with type = Portfolio Company) |
| **Investment Instrument** | The specific security (e.g. equity, debenture, CCD, preference share). Each instrument belongs to one portfolio company and has a fixed currency. |
| **Portfolio Investment (PI)** | A single buy or sell transaction. Positive quantity = Buy; Negative quantity = Sell. |
| **Aggregate Portfolio Investment (API)** | A rolled-up summary of all buys and sells for one fund × portfolio company × instrument combination. One API per unique (fund, portfolio company, instrument) triplet. |
| **Portfolio Attribution** | The link between a sell transaction and the specific buy lot(s) it consumed. Carries cost_of_sold, gain, and sale_amount per link. |
| **Valuation** | A per-share price on a specific date, used to compute FMV of current holdings. |
| **FMV** | Fair Market Value: current quantity held × latest per-share price. |
| **Cost of Remaining** | The book cost of unsold holdings: net_quantity × cost_per_share. |
| **Unrealised Gain** | FMV − Cost of Remaining. |
| **Realised Gain** | Sale proceeds − Cost of the shares sold (from attribution). |
| **FIFO** | First-In First-Out: oldest buys are sold first. |
| **WTD_AVG** | Weighted Average: sell quantity is allocated proportionally across all open buy lots. |

---

## Portfolio Investment Lifecycle

```
  1. RECORD BUY
     ↓
     - Create PortfolioInvestment (quantity > 0)
     - Create/update Investment Instrument
     - Auto-create AggregatePortfolioInvestment if first buy
     - Create initial Valuation at buy price
     - Compute amount_cents (with FX conversion if needed)
     - Compute cost_of_remaining, FMV, unrealized_gain
     ↓
  2. VALUATIONS UPDATED PERIODICALLY
     ↓
     - Add new Valuation records (per-share price on date)
     - FMV recomputes = net_quantity × latest valuation
     - Unrealised gain updates automatically
     ↓
  3. RECORD SELL
     ↓
     - Create PortfolioInvestment (quantity < 0)
     - Validate sell quantity ≤ net available quantity
     - Compute gain_cents (sale price − buy price per attribution)
     - Attribution job runs (FIFO or WTD_AVG):
         links each sold share to a specific buy lot
         computes cost_of_sold and gain per attribution
     - Update net_quantity on the buy lot(s)
     ↓
  4. AGGREGATE METRICS UPDATED
     ↓
     - API.quantity, bought_amount, sold_amount, gain, fmv, cost_of_sold
       all auto-updated via counter caches
     - avg_cost recomputed
```

---

## Investment Instruments

An Investment Instrument is the type of security in which the fund has invested. It must be created before recording any transactions.

### Required Fields

| Field | Description |
|-------|-------------|
| **Name** | Instrument name (e.g. "Series A Equity", "10% NCD", "CCDs"). Must be unique within a portfolio company. |
| **Currency** | The denomination currency of this instrument. This determines whether FX conversion is needed when recording investments. Once set, the currency **cannot be changed**. |

### Optional Fields

| Field | Description |
|-------|-------------|
| **Sector** | The industry sector of the portfolio company. |
| **Category / Sub-Category** | Custom classification of the instrument. |
| **Investment Domicile** | "Domestic" or foreign. Automatically sets "Offshore Investment" flag accordingly. |
| **SEBI Reporting Fields** | Type of investee company, type of security, ISIN, registration number, associate/AIF flags. Used for regulatory reporting. |

### Business Rules

- An instrument's **currency cannot be changed** after it is created. This protects the integrity of existing investment amount calculations.
- Each instrument is linked to one portfolio company (they are not shared across companies).
- Valuations are stored per instrument (not per portfolio investment).

---

## Creating a Portfolio Investment (Buy)

A Buy records money deployed into a portfolio company.

### Required Fields

| Field | Description |
|-------|-------------|
| **Portfolio Company** | The investee company. |
| **Investment Instrument** | The security type being purchased. |
| **Investment Date** | The date of the investment. |
| **Quantity** | Number of shares/units purchased. Must be positive. |
| **Amount (Excluding Expenses)** | The investment amount in the instrument's currency, before expenses. |

### Optional Fields

| Field | Description |
|-------|-------------|
| **Notes** | Internal notes. |
| **Excused Folio IDs** | Commitments whose investors are excused from contributing to this investment. They will not receive a share of the gain or distribution. |
| **Proforma** | If Yes, this investment is for modelling purposes only and is excluded from all live calculations (FMV, gain, counter caches). |
| **Ref ID** | An external reference number (used to prevent duplicate imports). |

### What Happens on Save

1. **Expenses are added** — Any form custom fields tagged as "Expense" are summed and added to the base amount.
2. **Amount is converted** — If the instrument currency differs from the fund currency, the amount is converted using the exchange rate on the investment date. The exchange rate used is stored on the record.
3. **Aggregate is set up** — If no Aggregate Portfolio Investment exists yet for this (fund, company, instrument) combination, one is created automatically.
4. **Initial valuation created** — A valuation is created (or updated) for the instrument on the investment date, using the buy's cost per share. This ensures FMV can be computed from day one.
5. **All metrics computed** — cost_of_remaining, FMV, unrealised gain are calculated.
6. **quantity_as_of_date computed** — The cumulative quantity held as of the investment date is computed and stored.

### Duplicate Prevention

CapHive prevents duplicate imports by matching on: portfolio_company_name + investment_date + ex_expenses_base_amount + quantity + instrument + fund + ref_id. If all match, the import is rejected.

---

## Recording a Sale (Sell)

A Sell records the disposal of shares.

### Required Fields

Same as a Buy, but **quantity must be negative** (e.g. −500 to sell 500 shares).

### Sell Validation

Before saving, CapHive checks:
```
total net_quantity available across all open buy lots
  = sum of (buy.quantity + buy.sold_quantity − buy.transfer_quantity)
    for allocatable buys

If |sell quantity| > available quantity → rejected with error
```

"Allocatable buys" are buy lots for the same portfolio company and instrument with `net_quantity > 0`, ordered by investment date.

### Attribution

After the sell is saved, a background job (or immediate execution during import) runs the **AttributionService** to link the sell to its buy lot(s):

- **FIFO:** oldest lots first, exhausted before moving to newer ones.
- **WTD_AVG:** each lot contributes proportionally to its share of total available quantity.

Attribution only runs **once** per sell — if attributions already exist, the sell is not re-attributed.

### What Gets Computed on a Sell

| Field | Value |
|-------|-------|
| `gain_cents` | (sale_price_per_share − buy_price_per_share) × quantity |
| `cost_of_sold_cents` | buy_price_per_share × quantity sold |
| `sale_amount_cents` | sale_price_per_share × quantity |
| `fmv_cents` | 0 (sells have no FMV) |
| `unrealized_gain_cents` | 0 |
| `cost_of_remaining_cents` | 0 |

---

## Attribution — FIFO vs Weighted Average

Attribution is the process of linking a sell transaction to the specific buy lot(s) it consumed. This determines the cost basis and realised gain for each sale.

### FIFO (First-In First-Out)

```
Example:
  Buy Lot 1: 1,000 shares @ ₹100 on 2021-03-01  (net_qty=1,000)
  Buy Lot 2:   500 shares @ ₹150 on 2022-06-15  (net_qty=500)

  Sell: 1,200 shares @ ₹200 on 2023-09-01

FIFO attribution:
  Attribution 1: Sell → Lot 1 (1,000 shares)
    cost_of_sold = 1,000 × ₹100 = ₹1,00,000
    gain         = 1,000 × (₹200 − ₹100) = ₹1,00,000
    sale_amount  = 1,000 × ₹200 = ₹2,00,000

  Attribution 2: Sell → Lot 2 (200 shares)
    cost_of_sold = 200 × ₹150 = ₹30,000
    gain         = 200 × (₹200 − ₹150) = ₹10,000
    sale_amount  = 200 × ₹200 = ₹40,000

Total gain = ₹1,10,000
```

**When to use:** FIFO is the default for most regulatory and tax reporting frameworks.

### Weighted Average (WTD_AVG)

```
Example (same lots as above):
  Total available: 1,500 shares (Lot 1: 1,000, Lot 2: 500)
  Sell: 1,200 shares

  Lot 1 proportion = 1,000 / 1,500 = 66.67%
  Lot 2 proportion =   500 / 1,500 = 33.33%

WTD_AVG attribution:
  Attribution 1: Sell → Lot 1 (1,200 × 66.67% = 800 shares)
    cost_of_sold = 800 × ₹100 = ₹80,000
    gain         = 800 × (₹200 − ₹100) = ₹80,000

  Attribution 2: Sell → Lot 2 (1,200 × 33.33% = 400 shares)
    cost_of_sold = 400 × ₹150 = ₹60,000
    gain         = 400 × (₹200 − ₹150) = ₹20,000

Total gain = ₹1,00,000
```

**When to use:** Weighted average gives a smoothed cost basis across all lots, commonly used in certain accounting standards.

### Choosing the Cost Method

The cost method is set per fund via the `portfolio_cost_type` field:
- `FIFO` — first-in first-out
- `WTD_AVG` — weighted average

Once attributions have been created for a sell, they are not automatically re-run even if the cost method changes. To re-run attribution, existing attributions must be deleted first.

### Effect on Buy Lots

When a sell is attributed to a buy lot:
- The buy lot's `sold_quantity` counter increases by the attributed quantity.
- The buy lot's `net_quantity` = original_quantity + sold_quantity − transfer_quantity decreases accordingly.
- The buy lot's `cost_of_remaining` = net_quantity × cost_per_share is updated.

---

## FMV Computation

FMV (Fair Market Value) is the estimated current value of unsold holdings, based on the latest available share price.

### Valuation Records

FMV is computed from **Valuation** records stored against each investment instrument:

| Field | Description |
|-------|-------------|
| **Investment Instrument** | The instrument this valuation applies to |
| **Valuation Date** | The date this price is valid |
| **Per Share Value (cents)** | The price per share in the instrument's base currency |

When a Buy is created, CapHive automatically creates a Valuation at the buy price (if one doesn't already exist for that instrument on that date).

### FMV Computation Formula

```
FMV (fund currency) = net_quantity × latest_valuation.per_share_value_in(fund_currency, date)

where:
  net_quantity = quantity (buy) + sold_quantity − transfer_quantity
               = shares still held (not sold, not converted)

  latest_valuation = most recent Valuation for this instrument
                     with valuation_date ≤ computation date

  per_share_value_in(fund_currency, date) =
    IF instrument.currency == fund.currency:
      per_share_value_cents (no conversion)
    ELSE:
      per_share_value_cents × exchange_rate(instrument_currency → fund_currency, on date)
```

**If no valuation is found** on or before the date, FMV raises an error — you must ensure valuations exist. Zero net_quantity also returns zero FMV (avoiding the lookup).

### Updating FMV

FMV is recomputed whenever:
- A valuation is added or updated.
- A buy or sell is saved (triggers `compute_all_numbers`).
- An attribution is created or deleted (triggers `PortfolioInvestmentUpdate` on the buy lot).
- The `recompute_fees` job runs on the fund.

### FMV in Two Currencies

Each buy PI stores FMV in both the fund currency and the instrument's base currency:

| Field | Currency |
|-------|----------|
| `fmv_cents` | Fund currency |
| `instrument_currency_fmv_cents` | Instrument's base currency (raw, no FX) |
| `tracking_fmv_cents` | Tracking currency (for cross-fund dashboards) |

---

## Aggregate Portfolio Investment

The **Aggregate Portfolio Investment (API)** is an automatically maintained rollup record. There is exactly one API per (fund × portfolio company × investment instrument) combination, regardless of how many individual buy/sell transactions have been recorded.

### Auto-Creation

An API is created automatically when the first buy transaction is saved for a given (fund, company, instrument) triplet.

### What It Aggregates

| API Field | Source |
|-----------|--------|
| `quantity` | Sum of `net_quantity` across all non-proforma buy PIs |
| `bought_quantity` | Sum of quantity across all non-proforma buy PIs |
| `sold_quantity` | Sum of quantity across all non-proforma sell PIs |
| `bought_amount_cents` | Sum of amount_cents across all non-proforma buy PIs |
| `sold_amount_cents` | Sum of amount_cents across all non-proforma sell PIs |
| `cost_of_sold_cents` | Sum of cost_of_sold_cents across all sell PIs |
| `cost_of_remaining_cents` | Sum of cost_of_remaining_cents across all buy PIs |
| `gain_cents` | Sum of gain_cents across all sell PIs |
| `fmv_cents` | Sum of fmv_cents across all buy PIs |
| `unrealized_gain_cents` | Sum of unrealized_gain_cents across all buy PIs |
| `avg_cost_cents` | `bought_amount_cents / bought_quantity` |
| `portfolio_income_cents` | Sum of all "Actual" portfolio cashflows |

### as_of(date) Temporal Query

The `as_of(date)` method returns a **snapshot copy** of the API as of a historical date — without modifying the stored record:

```
API.as_of(2022-12-31):
  1. Collects all PIs with investment_date ≤ 2022-12-31
  2. Runs pi.as_of(2022-12-31) on each (same for PIs)
  3. Re-computes all rolled-up fields from those PIs
  4. Looks up FMV on that date using valuations ≤ 2022-12-31
  5. Returns a frozen (read-only) copy with historical values
```

This is used extensively in reports, XIRR calculations, and the portfolio report generator.

### avg_cost (Average Cost Per Share)

```
avg_cost_cents = total_bought_amount_cents / total_bought_quantity
               (only updated when bought_quantity > 0)
```

Average cost is the blended cost per share across all buy transactions, regardless of when they were made.

---

## Key Computed Fields

### For Buy Transactions

```
  cost_per_share_cents   = amount_cents / quantity

  sold_quantity          = sum of attribution quantities linked to this buy
  transfer_quantity      = sum of stock_conversions from this buy

  net_quantity           = quantity + sold_quantity − transfer_quantity
                         (shares still held)

  net_bought_quantity    = quantity − transfer_quantity
                         (shares bought and not yet converted away)

  cost_of_remaining      = net_quantity × cost_per_share
                         (book value of unsold holding)

  fmv                    = net_quantity × latest_valuation_price
                         (current market value)

  unrealized_gain        = fmv − cost_of_remaining
```

### For Sell Transactions

```
  gain_cents             = amount_cents.abs + cost_of_sold_cents
                         (note: cost_of_sold is negative, gain adds them)

  cost_of_sold_cents     = sum across all attributions (bought_pi.price × qty)

  sale_price_per_share   = amount_cents / |quantity|

  cost_of_sold_per_share = cost_of_sold_cents / |quantity|
```

### For the Aggregate (API)

```
  cost_of_remaining  = bought_amount + cost_of_sold + transfer_amount
                     (i.e. cost of all buys minus cost of what was sold)

  unrealized_gain    = fmv − cost_of_remaining

  gain               = sold_amount + cost_of_sold
                     (realized gain from all sells combined)
```

---

## Stock Conversions

A Stock Conversion records the transformation of one instrument type into another — for example, when Compulsorily Convertible Debentures (CCDs) convert into equity shares.

### How It Works

1. The conversion records:
   - **From instrument:** The instrument being surrendered
   - **From PI:** The specific buy lot being converted
   - **From quantity:** How many units are converted out
   - **To instrument:** The new instrument type
   - **To quantity:** How many units are received in exchange
   - **Conversion date:** When the conversion occurs

2. On save, CapHive:
   - Adds `from_quantity` to the source PI's `transfer_quantity`
   - Creates a **new buy PI** for the destination instrument, dated to the original investment date, with the cost converted using the exchange rate on that date
   - Updates the source API and creates/updates the destination API
   - Marks the `conversion_date` on both PIs

3. The source PI's `net_quantity` decreases by `from_quantity`. It is no longer available for sale or further conversion.

### Business Rules

- From and To instruments must be **different**.
- `from_quantity` cannot exceed the source PI's current `net_quantity`.
- If the two instruments are in different currencies, an exchange rate for the conversion date must exist.
- Converted quantities are excluded from FMV calculations for the source instrument (the `before()` scope filters by `conversion_date`).

### Effect on XIRR

In Gross Portfolio IRR calculations, stock conversions are removed from the buy cash flows to avoid double-counting — the converted cost is "transferred" to the new instrument, not treated as a new investment.

---

## Stock Splits

A stock split adjusts the quantity of shares held without changing the total invested amount.

### What Changes

When a split by ratio `R` is applied to a buy PI:
- `quantity *= R` (more shares)
- All attribution quantities are also multiplied by `R`
- `compute_all_numbers` is re-run to update cost_per_share, FMV, etc.
- A note is appended: "Stock adjusted by factor R on [date]"

### Effect on Cost

After a 2:1 split: if you held 1,000 shares at ₹100 each, you now hold 2,000 shares at ₹50 each. The total invested value is unchanged.

### How to Apply

Stock splits are applied through the **Stock Adjustments** feature or directly from the portfolio investment record. The split is applied at the individual PI level; the aggregate automatically recalculates.

---

## Stock Adjustments

A Stock Adjustment records a correction to the quantity of shares without creating a full buy or sell transaction — typically used for bonus shares, rights issues, or data corrections.

### How It Works

1. Create a StockAdjustment with:
   - Portfolio company, investment instrument
   - Adjustment value (positive = add shares, negative = remove shares)
2. On save, a background job applies the adjustment to all buy PIs for this company and instrument.

---

## Portfolio Cashflows (Income)

Portfolio Cashflows record income received from a portfolio company investment — such as dividends, interest, or partial distributions.

### Fields

| Field | Description |
|-------|-------------|
| **Portfolio Company** | The investee company |
| **Investment Instrument** | The instrument generating income |
| **Payment Date** | When the income was received |
| **Amount** | Amount in the fund's currency |
| **Tag** | "Actual" (real income) or other tags (projections, budgets) |

### Effect on Metrics

Only cashflows tagged **"Actual"** roll up to the API's `portfolio_income_cents` field (via counter cache).

In performance calculations:
- **Gross Portfolio IRR** includes actual portfolio cashflows as positive cash flows on their payment date.
- `portfolio_income_cents` on the API shows cumulative actual income received.

---

## Proforma Investments

Proforma investments are **what-if** transaction records used for modelling and scenario analysis. They do not affect any live metrics.

### Business Rules

- Proforma PIs are **excluded** from all counter caches (no rollup to the API).
- They are excluded from FMV, gain, and attribution computations by default.
- The default scope (`where(proforma: false)`) automatically excludes them.
- To include proforma records in a query, use `.include_proforma`.
- Attribution is not run for proforma sells.

### Use Cases

- Modelling a proposed investment before committing.
- Scenario analysis for hypothetical exits.
- Historical backdating for portfolio scenarios.

---

## Excused Investors

When a portfolio company receives investment from the fund, specific LP investors may be **excused** from participating (e.g. conflict of interest, investor restriction).

### How Excused Investors Work

A Buy PI can have a list of `excused_folio_ids` — the capital commitment IDs of investors who do not participate in this investment.

When computing an investor's **allocation of gains** from a sell, the investor's account entry percentage (Investable Capital Percentage) is looked up at the buy date. If they were excused from that buy, they were not invested, so they do not participate in the gain.

This is used in the `allocation_of_realized_gain_cents` method to compute each LP's share of gains.

---

## Portfolio Scenarios

Portfolio Scenarios let you model "what if" exits at different valuations to estimate returns.

### What a Scenario Contains

- A name and description
- A set of **Scenario Investments** (hypothetical sells at specified prices)
- Computed XIRR, MOIC, DPI, etc. for the scenario

Scenarios use the same attribution and computation logic as actual investments, but applied to the scenario's hypothetical transactions.

---

## Multi-Currency Support

### Investment Amount

If the instrument currency differs from the fund currency:
1. `ex_expenses_base_amount_cents` stores the amount in instrument currency.
2. `amount_cents` is the FX-converted equivalent in fund currency.
3. The exchange rate used is stored as `exchange_rate_id`.
4. Expenses (if any) are added in instrument currency before conversion.

### FMV

```
fmv_cents (fund currency) = net_quantity × valuation.per_share_value_cents
                             × exchange_rate(instrument → fund, on computation date)

instrument_currency_fmv_cents = net_quantity × valuation.per_share_value_cents
                                (raw, no conversion)
```

### Tracking Currency

For cross-fund dashboards and XIRR in tracking currency:
```
tracking_amount_cents = amount_cents × exchange_rate(fund → tracking, on investment_date)
tracking_fmv_cents    = fmv_cents × exchange_rate(fund → tracking, on today)
```

### Validation

If no exchange rate exists between the instrument currency and fund currency on the investment date, the PI creation is **rejected with an error**. Exchange rates must be set up before recording foreign-currency investments.

---

## Importing Data

### Importing Portfolio Investments

**Required columns:**

| Column | Description |
|--------|-------------|
| Fund | Fund name |
| Portfolio Company Name | Must match an existing portfolio company (investor) |
| Investment Date | Date of the transaction |
| Amount (Excluding Expenses) | Amount in instrument's currency, before expenses |
| Quantity | Positive = Buy, Negative = Sell |
| Instrument | Name of the investment instrument |
| Currency | Instrument's denomination currency |

**Optional columns:**

| Column | Description |
|--------|-------------|
| Investment Domicile | "Domestic" or foreign |
| Notes | Internal notes |
| Excused Folio Ids | Comma-separated folio IDs of excused investors |
| Proforma | "Yes" for scenario/modelling investments |
| Ref Id | External reference number (prevents duplicates) |
| SEBI reporting fields | Type of investee, type of security, ISIN, etc. |

**Business Rules:**
- Portfolio Company must already exist as an investor with `portfolio_company = true`.
- If the Instrument doesn't exist, it is **created** from the import data.
- A Ref Id helps prevent duplicate import of the same transaction.
- Attributions for sells are run immediately during import (not in a background job) to ensure correct ordering.
- After import, all Aggregate Portfolio Investments are saved to recalculate avg_cost.

### Importing Portfolio Cashflows

| Column | Description |
|--------|-------------|
| Fund | Fund name |
| Portfolio Company | Portfolio company name |
| Instrument | Investment instrument name |
| Payment Date | Date of income receipt |
| Amount | Amount in fund currency |
| Tag | "Actual" or custom tag |

### Importing Investment Instruments

| Column | Description |
|--------|-------------|
| Portfolio Company Name | Parent company |
| Name | Instrument name |
| Currency | Denomination currency |
| Sector, Category, ISIN, etc. | Optional attributes |

---

## Key Computations Reference

### Buy PI Computation Flow

```
1. base_amount_cents = ex_expenses_base_amount_cents + expense_cents

2. IF instrument.currency == fund.currency:
     amount_cents = base_amount_cents
   ELSE:
     amount_cents = convert(instrument_currency → fund_currency, base_amount_cents, investment_date)

3. cost_per_share_cents = amount_cents / quantity

4. sold_quantity = sum of portfolio_attribution.quantity where bought_pi = this PI
   transfer_quantity = sum of stock_conversion.from_quantity where from_PI = this PI

   net_quantity = quantity + sold_quantity − transfer_quantity
   net_bought_quantity = quantity − transfer_quantity

5. cost_of_remaining_cents = net_quantity × cost_per_share_cents

6. fmv_cents = net_quantity × latest_valuation.per_share_value_in(fund_currency, date)

7. unrealized_gain_cents = fmv_cents − cost_of_remaining_cents
```

### Sell PI Computation Flow

```
1. amount_cents = |quantity| × sale_price_per_share_cents
   (same FX logic as buy)

2. After Attribution:
   cost_of_sold_cents = sum(attributed quantity × bought_pi.cost_per_share)
                       [negative value — represents cost outflow]

   gain_cents = amount_cents.abs + cost_of_sold_cents
              = (sale proceeds) − (cost of shares sold)
```

### Attribution: FIFO

```
For each buy lot (sorted by investment_date ASC):
  attribution_quantity = min(buy.net_quantity, remaining_sell_quantity)

  PortfolioAttribution {
    bought_pi = buy,
    sold_pi   = sell,
    quantity  = −attribution_quantity,
    cost_of_sold = attribution_quantity × buy.price_per_share,
    gain         = (sell.price_per_share − buy.price_per_share) × attribution_quantity,
    sale_amount  = sell.price_per_share × attribution_quantity
  }

  remaining_sell_quantity -= attribution_quantity
  STOP when remaining_sell_quantity = 0
```

### Attribution: Weighted Average

```
total_buy_quantity = sum of net_quantity across all allocatable buys

For each buy lot:
  proportion = buy.net_quantity / total_buy_quantity
  attribution_quantity = sell_quantity × proportion  [rounded to 6 dp]

  PortfolioAttribution {
    quantity     = −attribution_quantity,
    cost_of_sold = attribution_quantity × buy.price_per_share,
    gain         = (sell.price_per_share − buy.price_per_share) × attribution_quantity,
    sale_amount  = sell.price_per_share × attribution_quantity
  }
```

### API Metrics

```
avg_cost_cents          = bought_amount_cents / bought_quantity
                         (recomputed whenever bought_quantity > 0)

cost_of_remaining       = bought_amount + cost_of_sold + transfer_amount
                         (cost basis of unsold holdings)

unrealized_gain         = fmv − cost_of_remaining

gain (realized)         = sold_amount + cost_of_sold
                         (proceeds minus cost of sold shares)
```

### Counter Caches on API (Auto-Updated)

| API Counter | Source |
|-------------|--------|
| `quantity` | Sum of `net_quantity` of non-proforma buy PIs |
| `bought_amount_cents` | Sum of `amount_cents` of non-proforma buy PIs |
| `sold_amount_cents` | Sum of `amount_cents` of non-proforma sell PIs |
| `fmv_cents` | Sum of `fmv_cents` of non-proforma buy PIs |
| `gain_cents` | Sum of `gain_cents` of non-proforma PIs (all types) |
| `cost_of_sold_cents` | Sum of `cost_of_sold_cents` of non-proforma sell PIs |
| `cost_of_remaining_cents` | Sum of `cost_of_remaining_cents` of non-proforma buy PIs |
| `unrealized_gain_cents` | Sum of `unrealized_gain_cents` of non-proforma buy PIs |
| `portfolio_income_cents` | Sum of `amount_cents` of "Actual" cashflows |
| `tracking_bought_amount_cents` | Sum of `tracking_amount_cents` of non-proforma buy PIs |
| `tracking_sold_amount_cents` | Sum of `tracking_amount_cents` of non-proforma sell PIs |

---

## Frequently Asked Questions

**Q: What is the difference between `amount` and `ex_expenses_amount` on a buy?**
`ex_expenses_amount` is the investment amount before any expense add-ons (the amount you actually wire to the portfolio company). `amount` includes expenses (fees, transaction costs) added to arrive at the total deployment amount. Both are stored in the fund currency.

**Q: Can I change the FIFO/WTD_AVG method after sells have been recorded?**
The cost method is set per fund. Changing it does not retroactively re-run attributions. Existing attributions remain as-is. If you need to switch, existing attributions for affected sells must be deleted, and the attribution job re-run.

**Q: Why does my sell show a different gain than expected?**
Gain is computed per attribution: (sell price per share − buy price per share) × quantity. Under FIFO, older lots have older (potentially lower) prices, which can produce larger gains. Under WTD_AVG, gains are smoothed. Check the Portfolio Attributions tab on the sell PI to see the breakdown.

**Q: What happens if I delete a buy that has been partially sold?**
CapHive will prevent or warn about this — the sell's attributions reference the buy. To delete the buy, you must first delete any sells that were attributed to it (and their attributions).

**Q: Why is FMV zero for a holding even though I have shares?**
There are two reasons: (a) no Valuation exists for the instrument on or before today — add one; or (b) the net_quantity is zero (all shares sold or converted). Check the valuations list for the instrument.

**Q: What does `quantity_as_of_date` mean?**
It records the cumulative net quantity across all PIs for this (fund, company, instrument) as of the PI's own investment_date. This is a snapshot used in historical reporting.

**Q: How are stock conversions different from sells?**
A stock conversion is a tax-neutral instrument change (e.g. CCD → Equity). The cost basis is preserved and transferred to the new instrument. A sell realizes the gain. A conversion does not generate gain or reduce the portfolio's cost of remaining — it just changes the instrument type.

**Q: What does `excused_folio_ids` do exactly?**
It lists commitments whose investors chose not to participate in a specific investment. When computing each LP's share of realized gain from a sell, the commitment's Investable Capital Percentage at the buy date is used. If an investor was excused from a buy, they have no ICP for that buy and receive zero allocation of gain from that sale.

**Q: Can I have the same instrument invested across two different funds?**
Yes. Each (fund × portfolio company × instrument) combination gets its own Aggregate Portfolio Investment. Transactions are fund-specific and do not mix across funds.

**Q: What is a proforma investment?**
Proforma investments are modelling tools — they do not affect live metrics (FMV, gain, IRR, counter caches). Use them to model scenarios before committing a real investment, or to run what-if exit analyses.
