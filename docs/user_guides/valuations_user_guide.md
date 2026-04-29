# Valuations User Guide

This guide covers how to record, manage, and analyse valuations for portfolio companies in CapHive — including how valuations flow through to FMV on portfolio investments, and how to use the Value Bridge to decompose performance drivers between two dates.

---

## Table of Contents

1. [What Is a Valuation?](#what-is-a-valuation)
2. [Key Concepts](#key-concepts)
3. [Creating a Valuation](#creating-a-valuation)
4. [Valuation Fields Reference](#valuation-fields-reference)
5. [How Valuations Drive FMV](#how-valuations-drive-fmv)
6. [Synthetic Valuations](#synthetic-valuations)
7. [Custom Fields on Valuations](#custom-fields-on-valuations)
8. [Setting Up the Value Bridge](#setting-up-the-value-bridge)
9. [Using the Value Bridge](#using-the-value-bridge)
10. [How the Value Bridge Is Computed](#how-the-value-bridge-is-computed)
11. [MOIC Mode on the Value Bridge](#moic-mode-on-the-value-bridge)
12. [Filtering and Finding Valuations](#filtering-and-finding-valuations)
13. [Importing Valuations from a Spreadsheet](#importing-valuations-from-a-spreadsheet)
14. [Validations and Business Rules](#validations-and-business-rules)
15. [Frequently Asked Questions](#frequently-asked-questions)

---

## What Is a Valuation?

A **Valuation** records the **price per share** (or per unit) of a specific instrument held in a portfolio company, as of a given date. It is the single source of truth for the **fair market value (FMV)** of every portfolio investment in that instrument.

Every time you want to mark up or mark down an investment, you create a new valuation record. CapHive uses the most recent valuation on or before any given date to calculate the current FMV of the fund's holdings.

---

## Key Concepts

| Term | Meaning |
|------|---------|
| **Portfolio Company** | The company the fund has invested in (an `Investor` record with category `Portfolio Company`) |
| **Investment Instrument** | A specific class of security in that company (e.g. "Equity Shares", "Series A Preferred", "CCD"). Each instrument has its own valuation history. |
| **Per Share Value** | The price of one unit of the instrument. Multiplied by quantity to get total FMV. |
| **Valuation Date** | The date the per-share value is effective from. |
| **Owner** | The portfolio company the valuation belongs to. A valuation is always scoped to one company and one instrument. |
| **Synthetic** | A what-if valuation used for scenario modelling. Does **not** affect live FMV. |
| **Latest Valuation** | The most recent non-synthetic valuation on or before a given end date — this is what drives FMV calculations. |

---

## Creating a Valuation

### From the portfolio company page

1. Navigate to the **Portfolio Company** (Stakeholders → the company).
2. Click the **Valuations** tab.
3. Click **New Valuation**.
4. Fill in the form and save.

### From the global Valuations list

Navigate to **Valuations** in the main menu and click **New**.

### Creating multiple instrument valuations at once

When creating a **new** valuation, you can select **multiple instruments** in a single form submission. CapHive will create a separate valuation record for each instrument selected, all with the same date and per-share value.

> This is useful at quarter-end when you want to mark all instruments in a company at the same new value simultaneously.

---

## Valuation Fields Reference

| Field | Required | Description |
|-------|----------|-------------|
| **Valuation Date** | Yes | The effective date of this valuation. Must be unique per instrument per portfolio company. |
| **Instrument** | Yes | Which instrument this valuation applies to. Instruments are specific to the portfolio company. |
| **Per Share Value** | Yes | The price per unit. Must be ≥ 0. Stored with high precision (up to 8 decimal places). |
| **Valuation** | No | Total enterprise or equity value — informational, not used in FMV calculations directly. |
| **Report** | No | Attach a PDF or document (e.g. a valuation report from a third party). |
| **Synthetic** | No | Mark as synthetic if this is a scenario/what-if record. Synthetic valuations do **not** update FMV. |
| **Custom Fields** | No | Additional fields configured by your administrator (e.g. EBITDA, Revenue, Valuation Multiple) — required for Value Bridge. |

### Currency

The currency of a valuation is determined by the **investment instrument's currency**, not the fund's currency. When FMV is computed for a fund in a different currency, the per-share value is converted using the exchange rate on the relevant date.

---

## How Valuations Drive FMV

When you save a valuation (non-synthetic, and it is the **latest** for that instrument), CapHive automatically recalculates the FMV for every portfolio investment in that instrument.

### The update chain

```
1. You save a Valuation (per_share_value changes, or date changes)
2. CapHive checks: is this the latest valuation for this instrument?
3. If yes → triggers valuation_updated on the portfolio company
4. For every portfolio investment in this instrument:
   PortfolioInvestmentUpdate runs:
   - Recomputes fmv_cents = net_quantity × per_share_value_in(fund_currency, end_date)
   - Recomputes unrealized_gain = fmv − cost_of_remaining
   - Updates all counter caches on the folio and fund
```

### FMV formula

```
FMV of a position as of a date =
  Net Quantity on Date × Latest Per Share Value on or before that date
                         (converted to fund currency at the exchange rate on that date)
```

Net Quantity accounts for buys, sells, and stock conversions. The "on or before" rule means if you enter a valuation dated March 31, all positions at any date from March 31 onwards will use that value until a newer valuation is entered.

### When a valuation is deleted

When you delete a valuation, CapHive enqueues an `UpdatePortfolioInvestmentsJob` to recompute all affected portfolio investments — ensuring no stale FMV values remain.

---

## Synthetic Valuations

A **synthetic valuation** is a what-if record used for scenario analysis and the Value Bridge. It does **not** trigger any FMV updates and is **excluded** from all live calculations by default.

### Key rules

- Synthetic valuations are hidden from all default queries (`default_scope { where(synthetic: false) }`).
- To access them, use `.with_synthetic` scope — this is done automatically by the Value Bridge and scenario tooling.
- A synthetic valuation is **never** considered "latest" for FMV purposes.
- Attribution, counter caches, and ratios are unaffected by synthetic valuations.

### When to use synthetic valuations

- Modelling a hypothetical exit valuation for scenario planning.
- Creating an "entry" snapshot for value bridge analysis without backdating real valuations.
- Stress-testing fund ratios under different FMV assumptions.

---

## Custom Fields on Valuations

Valuations support custom fields through CapHive's form builder. Your administrator can add any number of numeric, text, or calculated fields to the valuation form.

Custom fields are stored in a `json_fields` column on each valuation and are used by:
- The **Value Bridge** (see below)
- Custom reports
- KPI charts

### Built-in Value Bridge fields

CapHive includes a standard set of value bridge custom fields that can be added to the **Valuation** form type by an administrator:

| Field | Type | Description |
|-------|------|-------------|
| `revenue` | Number | Company revenue at this valuation date |
| `ebitda_margin` | Number | EBITDA margin as a percentage |
| `ebitda` | Calculated | `revenue × ebitda_margin ÷ 100` |
| `valuation_multiple` | Number | The EV/EBITDA multiple applied |
| `enterprise_value` | Calculated | `ebitda × valuation_multiple` |
| `equity_value` | Calculated | `enterprise_value − net_debt` |
| `net_debt` | Number | Net debt (debt minus cash) |
| `debt_ratio` | Calculated | `net_debt ÷ enterprise_value` |
| `equity_ratio` | Calculated | `equity_value ÷ enterprise_value` |

> **Setting up:** Ask your administrator to run the Value Bridge field setup, which adds all of the above as calculated custom fields on the Valuation form type for your entity. Once set up, these fields appear on every valuation form.

---

## Setting Up the Value Bridge

The Value Bridge analyses how enterprise value changed between two dates by isolating the contribution of each financial driver.

### Step 1 — Add custom fields

Your administrator sets up the Value Bridge custom fields on the Valuation form type. The standard drivers are:
- **Revenue** (what revenue growth contributed)
- **EBITDA Margin** (what margin expansion/contraction contributed)
- **Valuation Multiple** (what re-rating contributed)

Additional or different drivers can be configured by your administrator.

### Step 2 — Configure the bridge columns for your entity

The ordered list of drivers shown in the bridge is set in **Entity Settings → Value Bridge Columns** as a comma-separated list, e.g.:

```
Revenue, EBITDA Margin, Valuation Multiple
```

The order matters: drivers are applied **left to right**, and each step builds on the previous one.

### Step 3 — Fill in custom fields on valuations

For the Value Bridge to work, both the **entry** valuation (the start date) and the **exit** valuation (the end date) must have the custom fields filled in:
- Revenue
- EBITDA Margin
- Valuation Multiple
- Net Debt

Calculated fields (EBITDA, Enterprise Value, etc.) are computed automatically from the inputs.

---

## Using the Value Bridge

### Opening the Value Bridge

1. Navigate to the **Portfolio Company** page.
2. Click **Value Bridge** (or navigate to Valuations → Value Bridge for the company).
3. Select the **Start Point** (entry valuation) from the dropdown.
4. Select the **End Point** (exit valuation) from the dropdown.
5. The bridge renders immediately.

### What you see

The Value Bridge renders both a **data table** and a **waterfall chart**:

**Table columns:**

| Column | What it shows |
|--------|--------------|
| **Entry** | All financial metrics at the start date |
| **Revenue Impact** | EV change if only revenue moved to the exit value (all else held at entry) |
| **EBITDA Margin Impact** | EV change if margin moved next (revenue already at exit value) |
| **Valuation Multiple Impact** | EV change if the multiple moved last |
| **Exit** | All financial metrics at the end date |

**Table rows:** Each key metric (Revenue, EBITDA, Enterprise Value, Enterprise Value Change, etc.) is shown for each column, colour-coded green (improvement) or red (deterioration).

**Waterfall chart:** A visual bar chart showing the cumulative build-up from Entry EV to Exit EV, with each driver as a positive (green) or negative (red) bar.

### Selecting valuations

The dropdown only shows valuations for the same instrument. If you have a `compute_value_bridge` custom field set to `"1"` on some valuations, only those valuations will appear in the dropdown — this lets you flag specific milestone valuations (e.g. entry, Q4-2024, Q4-2025) without cluttering the dropdown with every quarterly mark.

---

## How the Value Bridge Is Computed

The bridge works by **isolating the impact of one driver at a time**, holding all others constant, and observing the resulting change in Enterprise Value.

### Algorithm

Starting from the **Entry** valuation:

```
Step 0 — Entry:
  Use all financial metrics from the entry date
  Enterprise Value = entry EBITDA × entry Multiple

Step 1 — Revenue Impact:
  Hold EBITDA Margin and Multiple at entry values
  Change Revenue → exit Revenue
  Recompute EBITDA = exit Revenue × entry EBITDA Margin ÷ 100
  Recompute Enterprise Value = new EBITDA × entry Multiple
  Revenue Impact = new EV − previous EV

Step 2 — EBITDA Margin Impact:
  Revenue is now at exit value (from Step 1)
  Change EBITDA Margin → exit Margin
  Recompute EBITDA = exit Revenue × exit Margin ÷ 100
  Recompute Enterprise Value = new EBITDA × entry Multiple
  EBITDA Margin Impact = new EV − previous EV

Step 3 — Valuation Multiple Impact:
  Revenue and Margin are now both at exit values
  Change Multiple → exit Multiple
  Recompute Enterprise Value = exit EBITDA × exit Multiple
  Multiple Impact = new EV − previous EV

Final — Exit:
  All metrics at exit values
  Enterprise Value = exit EBITDA × exit Multiple
  (Should equal the exit valuation's Enterprise Value)
```

### Example

| | Entry (2023-03-31) | Revenue Impact | EBITDA Margin Impact | Multiple Impact | Exit (2025-03-31) |
|--|--|--|--|--|--|
| Revenue | 100 | **120** | 120 | 120 | 120 |
| EBITDA Margin | 20% | 20% | **25%** | 25% | 25% |
| EBITDA | 20 | 24 | 30 | 30 | 30 |
| Multiple | 10x | 10x | 10x | **12x** | 12x |
| Enterprise Value | **200** | 240 | 300 | 360 | **360** |
| EV Change | — | **+40** | **+60** | **+60** | — |

Total change = 40 + 60 + 60 = **160** (Entry 200 → Exit 360 ✓)

### Order matters

The drivers are applied in the order configured in Entity Settings. The impact attributed to each driver depends on what has already been "applied" — revenue growth impact is measured holding margins and multiples at entry levels. This is a standard **sequential decomposition** approach.

---

## MOIC Mode on the Value Bridge

By default the Value Bridge shows **absolute values** (e.g. Enterprise Value in currency units). Switching to **MOIC mode** normalises every number by the Entry Enterprise Value.

```
MOIC = all values ÷ Entry Enterprise Value
```

This makes the bridge instrument-agnostic and comparable across companies of different sizes — a revenue impact of "+0.20x" means the revenue growth alone contributed a 0.2x multiple on entry investment.

Toggle between **Values** and **MOIC** using the "Basis" dropdown on the Value Bridge form.

---

## Filtering and Finding Valuations

### Valuation list page

Navigate to **Valuations** in the main menu to see all valuations you have access to.

### Filter by portfolio company

Pass `owner_id` (the portfolio company ID) and `owner_type=Investor` to see only valuations for one company. This is done automatically when you open the Valuations tab on a portfolio company page.

### Filter by instrument

Use the ransack column filter for `investment_instrument` to restrict to one instrument within a company.

### Filter by date

Filter by `valuation_date` — supports on/before/after comparisons.

### Filter by synthetic

By default, synthetic valuations are **hidden**. The Valuations list uses `.with_synthetic` scope, so both synthetic and real records are visible. Filter by `synthetic = true` or `synthetic = false` to separate them.

### Search

Use the ransack filter on `portfolio_company_name` to search by company name, or `per_share_value` for numeric comparison.

---

## Importing Valuations from a Spreadsheet

### Spreadsheet columns

| Column | Required | Description |
|--------|----------|-------------|
| **Instrument** | Yes | Name of the investment instrument — must already exist on the portfolio company |
| **Portfolio Company** | Yes | Company name — must match an existing Portfolio Company exactly |
| **Valuation Date** | Yes | Date of the valuation (parsed with local date format) |
| **Per Share Value** | Yes | Price per share/unit |
| **Valuation** | No | Total valuation amount (informational) |

Additional columns can be provided to populate custom fields (e.g. `revenue`, `ebitda_margin`).

### Duplicate handling

If a valuation already exists for the same instrument, portfolio company, valuation date, per-share value, and total valuation, the row is **skipped** (no update, no error raised to fail the batch — just silently de-duplicated).

### After import

After a successful import, CapHive triggers the `valuation_updated` callback for each new valuation — so FMV on all related portfolio investments is recalculated automatically.

---

## Validations and Business Rules

| Rule | Detail |
|------|--------|
| **Valuation date required** | A valuation cannot be saved without a date. |
| **Per share value ≥ 0** | A negative per-share value is not allowed. Zero is valid (e.g. write-off). |
| **Unique per instrument per date** | Only one valuation per instrument per portfolio company per date. Attempting to create a duplicate raises a validation error. |
| **Instrument required** | Every valuation must be linked to an investment instrument — it cannot float free. |
| **Latest rule for FMV** | Only the most recent non-synthetic valuation on or before the calculation date drives FMV. Older valuations are retained as history but do not retroactively change previously computed FMV snapshots. |
| **Synthetic flag is immutable after create** | The synthetic flag cannot be changed after a valuation is saved, to prevent accidental promotion of a scenario record to a live valuation. |
| **Name auto-generated** | If no name is entered, CapHive sets it to `<Instrument> - <Date>`. If there is no instrument (entity-level valuation), it uses `<Entity Name> - <Date>`. |

---

## Frequently Asked Questions

**Why hasn't my FMV updated after I saved a new valuation?**
Check that:
1. The valuation is **not** marked synthetic.
2. The valuation date is the **latest** for that instrument — if an older valuation was edited, FMV would not update.
3. The portfolio investments exist and have the correct instrument assigned.

FMV updates run synchronously (not in a background job), so the change should be visible immediately after saving.

**Can I enter a valuation in a different currency than the fund?**
Yes. The instrument has its own currency, and the valuation is always in that currency. When CapHive computes FMV for the fund, it converts per-share value to the fund's currency using exchange rates on the relevant dates.

**How do I model a write-off?**
Create a new valuation with **Per Share Value = 0**. This will set FMV to zero for all holdings in that instrument from that date onwards.

**Can I use the Value Bridge for non-EBITDA companies?**
Yes, with configuration. The Value Bridge fields are fully customisable. Your administrator can configure different drivers (e.g. Revenue Multiple for SaaS companies, P/E multiple for listed equities, ARR growth for subscription businesses). The drivers and their calculation formulas are set up in the Valuation form type's custom fields.

**What is the difference between "Valuation" and "Per Share Value" on the form?**
- **Per Share Value** is the operative number — it is multiplied by quantity to compute FMV for each portfolio investment.
- **Valuation** (total) is informational — it may represent the total enterprise value or equity value of the company, but it does not feed directly into any automated calculation unless you set up a custom field formula that references it.

**I created a valuation but do not see it in the Value Bridge dropdown. Why?**
If any of your valuations have a custom field called `compute_value_bridge` set to `"1"`, the Value Bridge dropdown filters to **only** those flagged valuations. Check whether your other valuations need this flag set, or ask your administrator whether this filtering is intentional.

**Can I bulk-update per-share values for many companies at once?**
Yes — use the import spreadsheet. List each company/instrument/date combination in separate rows. Each row creates one valuation and triggers an FMV recalculation for that instrument.

**Does deleting a valuation affect historical reporting?**
When you delete a valuation, CapHive re-runs `PortfolioInvestmentUpdate` for all affected portfolio investments. This may change reported FMV figures going back to the date of the deleted valuation. Historical snapshots stored in fund ratios are not automatically re-generated — you would need to regenerate fund ratios after a deletion if you want the stored ratios to reflect the change.
