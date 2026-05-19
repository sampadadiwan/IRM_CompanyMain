# Fund Ratios User Guide

This guide explains how CapHive computes, generates, and manages fund performance ratios — including fund-level, folio-level, cross-fund, and cross-portfolio-company ratios — and how to filter and find them.

---

## Table of Contents

1. [What Are Fund Ratios?](#what-are-fund-ratios)
2. [Standard Ratios Reference](#standard-ratios-reference)
3. [How Each Ratio Is Computed](#how-each-ratio-is-computed)
4. [Generating Fund Ratios](#generating-fund-ratios)
5. [Cross-Fund Ratios](#cross-fund-ratios)
6. [Cross-Portfolio-Company Ratios](#cross-portfolio-company-ratios)
7. [Folio-Specific Ratios](#folio-specific-ratios)
8. [Portfolio Company and Instrument Ratios](#portfolio-company-and-instrument-ratios)
9. [Tracking Currency Variants](#tracking-currency-variants)
10. [Customising Ratios with Ratio Formulas](#customising-ratios-with-ratio-formulas)
11. [Run Records — FundRatioRun](#run-records)
12. [Scenarios](#scenarios)
13. [Ratio Run Templates — Saving and Reusing Configurations](#ratio-run-templates)
14. [Filtering and Finding Ratios](#filtering-and-finding-ratios)
15. [Importing Ratios from a Spreadsheet](#importing-ratios-from-a-spreadsheet)
16. [Cash Flow Documents](#cash-flow-documents)
17. [Pivot View](#pivot-view)
18. [Frequently Asked Questions](#frequently-asked-questions)

---

## What Are Fund Ratios?

Fund ratios are point-in-time performance metrics stored against a fund as of a specific **end date**. They answer questions such as:

- How much have we returned to investors relative to what they put in? (DPI / TVPI)
- What is the annualised return of the fund? (XIRR)
- How is each portfolio company performing relative to its cost? (IRR / MOIC per company)
- How does performance look if you combine several funds together? (Cross-fund ratios)

Ratios are **stored records**, not live calculations. You generate them on demand — CapHive runs the computation in the background and saves the results so they can be viewed, exported, and compared over time.

---

## Standard Ratios Reference

| Ratio | Unit | Computed For |
|-------|------|--------------|
| **XIRR** | % | Fund, Folio |
| **Net IRR** | % | Fund, Folio |
| **DPI** | x | Fund, Folio, Cross-fund |
| **RVPI** | x | Fund, Folio, Cross-fund |
| **TVPI** | x | Fund, Folio, Cross-fund |
| **MOIC** | x | Fund, Portfolio Company, Instrument (API), Cross-fund |
| **Gross Portfolio IRR** | % | Fund, Cross-fund, Cross-portfolio |
| **Portfolio Value to Cost** | x | Fund, Cross-fund |
| **Paid-In to Committed Capital (PIC)** | x | Fund, Cross-fund |
| **IRR** | % | Portfolio Company, Instrument (API) |
| **Value to Cost** | x | Portfolio Company, Instrument (API) |

---

## How Each Ratio Is Computed

### XIRR (Extended Internal Rate of Return)

XIRR is the annualised rate of return that makes the net present value of all cash flows equal to zero.

**Cash flows used:**

```
(–) Capital remittance payments  ← money invested by LP
(+) Gross distribution payments  ← money returned to LP
(–) Reinvestment amounts         ← distributions put back in
(+) FMV at end date              ← residual value
(+) Cash in hand                 ← cash account balance
(+) Net current assets           ← fund's working capital
```

For **Net IRR**, the estimated carry is also subtracted from the terminal value, reflecting the GP's share of remaining value.

Custom account entries can be added to or removed from the XIRR cash flows using **Ratio Formulas** (see Section 10).

---

### DPI — Distributed to Paid-In Capital

```
DPI = Total Distributions ÷ Total Collected Capital

Distributions = sum of gross distribution payments
                − sum of reinvestment amounts
Collected Capital = sum of all verified remittance payments
```

A DPI of 1.5x means LPs have received 1.5 times their invested capital back in cash.

---

### RVPI — Residual Value to Paid-In Capital

```
RVPI = Residual Value ÷ Collected Capital

Residual Value = FMV + Cash in Hand + Net Current Assets
```

RVPI represents the unrealised portion of value relative to what investors put in.

---

### TVPI — Total Value to Paid-In Capital

```
TVPI = DPI + RVPI
     = (Distributions + Residual Value) ÷ Collected Capital
```

TVPI is the total value multiple — realised plus unrealised — relative to paid-in capital.

---

### MOIC — Multiple on Invested Capital

```
MOIC = (FMV + Total Sold) ÷ Total Bought

Total Bought = sum of portfolio investment purchase amounts
Total Sold   = sum of portfolio investment sale amounts
FMV          = fair market value of remaining holdings
```

MOIC focuses on portfolio investments (not LP cash flows), making it a pure investment performance measure.

---

### Gross Portfolio IRR

The Gross Portfolio IRR is the annualised return on portfolio investments, **before** fund-level fees and carry.

**Cash flows used:**

```
(–) Portfolio investment purchases (buys)
(+) Portfolio investment sales (sells)
(+) Portfolio cashflows / income (e.g. dividends)
(+) FMV at end date
```

Stock conversions are handled: if shares in Company A were converted into Company B, the original cost is reversed from the A buy and re-dated at the same investment date.

---

### Portfolio Value to Cost

```
Portfolio Value to Cost = FMV ÷ Cost of Remaining Holdings
```

This is the mark-to-market multiple on unrealised holdings.

---

### Paid-In to Committed Capital (PIC)

```
PIC = Collected Capital ÷ Total Committed Capital
```

A PIC of 0.8x means 80% of the total fund commitment has been drawn down.

---

## Generating Fund Ratios

### Fund-Level Generation

1. Navigate to the **Fund** you want to compute ratios for.
2. Click **Generate Fund Ratios**.
3. Select the **Fund** tab.
4. Choose the **end date** (defaults to today).
5. Optionally tick **Generate For Each Folio** to also produce per-investor ratios.
6. Click **Generate**.

CapHive runs the computation in the background. You will receive a notification with links to the generated ratios when it is complete.

**What gets generated (fund level):**
- XIRR, DPI, RVPI, TVPI, MOIC, Gross Portfolio IRR, Portfolio Value to Cost, PIC
- IRR per portfolio company
- IRR per instrument (Aggregate Portfolio Investment)
- MOIC per portfolio company
- MOIC per instrument

> **Idempotent:** Generating ratios for the same fund and end date **replaces** the previous results for that date. It is safe to regenerate.

---

## Cross-Fund Ratios

A cross-fund ratio aggregates performance **across multiple funds**, converting all values to a single base currency before combining.

### When to use

Use cross-fund ratios when you want a consolidated view across a subset of funds — for example, all funds in a particular vintage year, or all funds investing in a single geography.

### How to generate

1. Navigate to any fund and click **Generate Fund Ratios**, or go to **Funds → Cross-Fund Ratios** from the Funds index.
2. Select the **Cross Fund** tab.
3. Select the **funds** to include in the analysis.
4. Choose the **end date**.
5. Click **Generate**.

The run is identified automatically by a fingerprint derived from the selected funds and date — no scenario name is required. A notification with links to the results is sent when the job completes.

**Ratios produced:**
- XIRR (aggregated across selected funds)
- MOIC
- DPI, RVPI, TVPI
- Gross Portfolio IRR
- Portfolio Value to Cost
- PIC

### How aggregation works

Each fund's numerator and denominator components are computed **in that fund's currency**, then converted to the base currency using the exchange rate on the relevant date. The converted components are summed and the ratio is computed from the totals.

```
Cross-fund DPI example:

Fund A (USD):  Distributions = $500,000 / Collected = $400,000
Fund B (EUR):  Distributions = €300,000 / Collected = €200,000
               at 1.10 USD/EUR = $330,000 / $220,000

Aggregate:     Total Distributions = $830,000
               Total Collected     = $620,000
               Cross-fund DPI      = 830,000 / 620,000 = 1.34x
```

Cross-fund DPI, RVPI, and TVPI respect each fund's **Ratio Formulas**, applying adjustments before aggregating.

### Re-running and idempotency

Generating cross-fund ratios for the same set of funds and the same end date reuses the existing run record and recalculates the ratios in place — no duplicate records are created. The run is identified by a SHA-256 fingerprint of the fund IDs and date, not by a user-supplied name.

---

## Cross-Portfolio-Company Ratios

A cross-portfolio-company analysis computes IRR and value metrics **per portfolio company**, aggregated across multiple funds or filtered by company tags.

### When to use

Use this when you want to understand the performance of a **specific company** (e.g. "what is the IRR for Company X across all funds combined?"), or benchmark a subset of companies.

### How to generate

1. Navigate to any fund and click **Generate Fund Ratios**, or go to **Investors → Cross-Portfolio Ratios** from the Investors index.
2. Select the **Cross Portfolio** tab.
3. Optionally select specific **funds** to limit the calculation to. Leave blank to span all entity funds.
4. Optionally select specific **portfolio companies**, enter **tags** (comma-separated), or choose **sectors** to filter which companies are included. At least one filter is recommended; leaving all blank includes every portfolio company in the entity.
5. Choose the **end date**.
6. Click **Generate**.

**Ratios produced per portfolio company:**
- IRR
- MOIC
- Value to Cost

**Summary ratios produced:**
- Gross Portfolio IRR (for the combined selection)

### Re-running and idempotency

Like cross-fund runs, each cross-portfolio run is identified by a fingerprint of the selected company IDs, tags, and sectors. Re-running the same selection and date recalculates in place.

---

## Folio-Specific Ratios

When you tick **Generate For Each Folio** on fund-level generation, CapHive computes the same ratios independently for each investor (capital commitment / folio).

**Ratios per folio:**
- XIRR
- DPI, RVPI, TVPI

**How folio ratios differ from fund ratios:**

| Component | Fund Ratio | Folio Ratio |
|-----------|------------|-------------|
| Capital flows | All remittances and distributions for the fund | Only the remittances and distributions for that investor's commitment |
| FMV | Total fund FMV | Folio-level FMV (based on folio's share of holdings) |
| Ratio Formulas at `Folio` level | Not applied | Applied — account entries are filtered to the folio |

Folio-specific ratio formulas use account entries scoped to the investor's folio ID, not the whole fund.

---

## Portfolio Company and Instrument Ratios

As part of regular fund ratio generation, CapHive automatically computes per-company and per-instrument metrics:

### Portfolio Company Ratios

For each portfolio company invested in by the fund:

| Ratio | Formula |
|-------|---------|
| **IRR** | XIRR of: (−) buys, (+) sells, (+) portfolio income, (+) FMV at end date — all for that company |
| **MOIC** | (FMV + Total Sold) ÷ Total Bought — for that company |
| **Value to Cost** | FMV ÷ Cost of Remaining — for that company |

### Instrument (Aggregate Portfolio Investment) Ratios

For each fund-company-instrument combination:

| Ratio | Formula |
|-------|---------|
| **IRR** | Same as portfolio company but scoped to one instrument |
| **MOIC** | Same as portfolio company but scoped to one instrument |
| **Value to Cost** | FMV ÷ Cost of Remaining — for that instrument position |

> The instrument-level view is useful when a fund holds multiple instruments (equity, preference shares, compulsory convertible debentures) in the same company.

---

## Tracking Currency Variants

If a fund has a **tracking currency** configured, CapHive automatically generates an additional variant of each ratio denominated in that currency.

**Variants generated (examples):**

| Ratio | Standard | With Tracking Currency |
|-------|----------|----------------------|
| XIRR | 18.5 % | XIRR (USD): 16.2 % |
| DPI | 1.4x | DPI (USD): 1.4x |
| MOIC | 2.1x | MOIC (USD): 2.0x |

All monetary components (remittances, distributions, FMV) are converted using exchange rates on their respective transaction dates before computing tracking-currency ratios.

---

## Customising Ratios with Ratio Formulas

**Ratio Formulas** let you adjust how standard ratios are computed by injecting or removing account entry values. This handles cases such as:

- Adding management fee rebates to the XIRR numerator
- Adjusting DPI to exclude certain distributions
- Including a special reserve account in the TVPI denominator

### Where to set them up

Navigate to **Fund → Ratio Formulas** to manage formulas for a specific fund.

### Ratio Formula Fields

| Field | What it controls |
|-------|-----------------|
| **Ratios** | Which ratio(s) this formula applies to (e.g. `XIRR`, `DPI`, `MOIC`, `IRR`) |
| **Action** | What to do with the value (see table below) |
| **Level** | Scope of account entries to use: `Fund`, `Folio`, or `PortfolioCompany` |
| **Period** | `as_on` = use the most recent entry on or before the end date; `all` = use all entries up to the end date |
| **Account Entry Names** | Which named account entries to pull the values from |

### Actions

| Action | Effect |
|--------|--------|
| **add_cashflow** | Adds each account entry as a positive cash flow in the XIRR computation |
| **reduce_cashflow** | Adds each account entry as a negative cash flow in the XIRR computation |
| **add_numerator** | Adds the account entry amount to the ratio's numerator |
| **reduce_numerator** | Subtracts the account entry amount from the ratio's numerator |
| **add_denominator** | Adds the account entry amount to the ratio's denominator |
| **reduce_denominator** | Subtracts the account entry amount from the ratio's denominator |

### Example: Adjusting DPI

If you have an account entry called "Fee Rebate" that should be included in DPI's numerator:

- **Ratios:** `DPI`
- **Action:** `add_numerator`
- **Level:** `Fund`
- **Period:** `all`
- **Account Entry Names:** `Fee Rebate`

After saving, the next time you generate ratios, the Fee Rebate balance will be added to the distribution amount before dividing by collected capital.

### Level scoping

| Level | When applied |
|-------|-------------|
| **Fund** | Only when computing a fund-level ratio (entries with no capital commitment) |
| **Folio** | Only when computing a folio-level ratio; entries are filtered to that investor's folio |
| **PortfolioCompany** | Only when computing a per-company ratio; entries are filtered to the company |

---

## Run Records — FundRatioRun {#run-records}

Every cross-fund or cross-portfolio generation creates (or reuses) a **FundRatioRun** record. This run record stores the exact filter inputs used for that calculation and links to all the `FundRatio` rows it produced.

### What a run stores

| Field | Description |
|-------|-------------|
| **Run type** | `cross-fund` or `cross-portfolio` |
| **End date** | The date the calculation was run for |
| **Source funds** | The fund IDs that fed the calculation |
| **Portfolio companies** | Explicit company IDs included (cross-portfolio only) |
| **Tag filter** | Portfolio company tags used as a filter |
| **Sector filter** | Portfolio company sectors used as a filter |
| **Anchor fund** | The fund used for document storage |
| **Fingerprint** | SHA-256 hash of the filter inputs — used as the unique run identifier |
| **Run by** | The user who triggered the calculation |
| **Created at** | When the run was created |

### Fingerprint and idempotency

The fingerprint is computed from the sorted filter inputs (fund IDs, company IDs, tag string, sectors). Two runs with identical inputs on the same date produce the same fingerprint and share a single run record — ratios are recalculated in place rather than duplicated.

### Viewing a run

From any `FundRatio` detail page, click **View Run Inputs** to open the run record and see exactly which funds, companies, tags, and sectors fed the calculation. From the run page you can also navigate to all ratios linked to that run.

---

## Scenarios

Every fund ratio has a **scenario** field. For cross-fund and cross-portfolio ratios, this is automatically populated from the first 40 characters of the run's fingerprint — it is not a user-supplied label.

For **fund-level ratios** (not cross-fund), the scenario is always `Default`.

When viewing ratios you can filter by scenario, but for cross-fund and cross-portfolio results it is more reliable to filter by **FundRatioRun** (using the run detail page or the computation context filter) rather than by scenario text.

---

## Ratio Run Templates — Saving and Reusing Configurations {#ratio-run-templates}

If you run the same cross-fund or cross-portfolio calculation repeatedly (e.g. monthly or quarterly), **Ratio Run Templates** let you save the filter configuration once and trigger it for any new date with a single click.

### What you can do with templates

- **Save** a named set of filters (funds, portfolio companies, tags, sectors, anchor fund)
- **Tag** templates to group them (e.g. `monthly`, `quarterly`, `board-reporting`)
- **Trigger one** template for a given date
- **Trigger all** entity templates at once for a date
- **Trigger by tag** — run only templates with a specific tag
- **View past runs** — see the history of FundRatioRun records a template has produced

### Quick-start

1. Go to **Funds → Ratio Templates** in the sidebar, or click **Manage Templates** next to the Generate button on any ratio generation page.
2. Click **New Template**, fill in the filters and a name, and save.
3. From the index, click **Run** next to any template, enter an end date, and submit.

### Idempotency with templates

Triggering a template twice for the same date reuses the existing FundRatioRun (same fingerprint) and recalculates ratios in place — no duplicates are created.

> See the **[Ratio Run Templates User Guide](fund_ratio_run_templates_user_guide)** for full details on creating, tagging, triggering, and managing templates.

---

## Filtering and Finding Ratios

### Opening the Ratios list

From a fund page, click **Fund Ratios** in the navigation. By default this shows all ratios for the fund, sorted by end date descending.

### Quick filters

| Filter | How to use |
|--------|-----------|
| **Fund** | Pass `fund_id` to see only ratios for one fund |
| **Folio** | Pass `capital_commitment_id` to see only one investor's ratios |
| **Owner type** | Filter by `Fund`, `Investor` (portfolio company), or `AggregatePortfolioInvestment` |
| **Scenario** | Filter by scenario name; pass comma-separated names to see multiple |
| **End date** | Pass `end_date` to see ratios for a specific date |
| **Recent months** | Pass `months=6` to see ratios from the last 6 months |
| **Latest only** | Pass `latest=true` to see only the most recent ratio for each name/owner combination |
| **Fund ratios only** | Pass `fund_ratios_only` to exclude folio-level ratios from the list |
| **By run** | Filter `computation_context_id` + `computation_context_type=FundRatioRun` to see all ratios from one run |

### Full-text search

Use the **search box** to find ratios by any of:
- Ratio name (e.g. "XIRR", "DPI", "Gross Portfolio IRR")
- Fund name
- Scenario name
- Portfolio scenario name
- Label
- End date

The search uses a prefix match — typing "Gross" will match "Gross Portfolio IRR".

### Ransack / column filters

Standard column filters are available for:
- `name` — exact or partial match on ratio name
- `owner_type` — `Fund`, `Investor`, or `AggregatePortfolioInvestment`
- `end_date` — on/before/after filters
- `scenario` — exact match
- `latest` — true/false

### Finding cross-fund and cross-portfolio ratios

After a cross-fund or cross-portfolio job completes, CapHive sends you a notification with direct links to the generated ratios filtered by that run. You can also navigate to the **FundRatioRun** record (linked from any ratio's detail page via **View Run Inputs**) and click through to the filtered ratio list from there.

---

## Importing Ratios from a Spreadsheet

You can upload fund ratios in bulk via a CSV or Excel file.

### Spreadsheet columns

| Column | Required | Description |
|--------|----------|-------------|
| **Fund** | Yes | Fund name — must match exactly |
| **Folio No** | No | Investor folio number — use to assign the ratio to a specific investor |
| **Portfolio Company** | No | Company name — use for company-level ratios |
| **Instrument** | No | Instrument name within the company — use for instrument-level ratios |
| **Ratio Name** | Yes | Name of the ratio (e.g. "XIRR", "DPI", "Custom KPI") |
| **Value** | Yes | Numeric value (will be stored and displayed) |
| **End Date** | Yes | The date this ratio applies to |
| **Label** | No | Short display label (max 50 characters) |
| **Note** | No | Internal note visible to your team |
| **Update Only** | No | Set to `yes` to update an existing ratio instead of creating a new one |
| **Scenario** | No | Scenario name; defaults to `Default` if blank |

### Owner resolution rules

The import determines who "owns" each ratio based on the columns you fill in:

```
Folio No present              → ratio belongs to that investor (CapitalCommitment)
Portfolio Company + Instrument → ratio belongs to that instrument (AggregatePortfolioInvestment)
Portfolio Company only         → ratio belongs to that company (Investor / PortfolioCompany)
None of the above              → ratio belongs to the fund
```

> **Note:** You cannot set both Folio No and Portfolio Company in the same row.

### Display value formatting

CapHive auto-formats the displayed value:
- Ratios named `XIRR`, `Gross Portfolio IRR`, or any name containing `IRR` → displayed as `X.XX %`
- All other ratios → displayed as `X.XX x`

---

## Cash Flow Documents

When generating ratios, you can optionally request the **underlying cash flows** to be saved as CSV documents. This is available in **debug mode** (append `?debug=1` to the generate page URL).

For each ratio where cash flows were requested, CapHive creates a CSV document in a `FundRatios` folder within the fund, named:

```
Cash Flows - <Ratio Name> - <End Date>.csv
```

The CSV lists each transaction date, amount, and a description (e.g. "Remittance 123", "FMV", "Sold Amount").

This is useful for auditing why XIRR or Gross Portfolio IRR came out at a specific value.

---

## Pivot View

The pivot view groups ratios into a cross-tab by period (month or quarter) and owner/name, making it easy to track trends over time.

To use it, request the `pivot` view from the Fund Ratios list. Periods can be grouped by:
- **Month** — e.g. "Jan 2025", "Feb 2025"
- **Quarter** — e.g. "Q1 2025", "Q2 2025"

The pivot is sorted chronologically so the most recent periods appear last.

---

## Frequently Asked Questions

**How do I generate ratios for a single folio without regenerating for the whole fund?**
Go to **Generate Fund Ratios → Fund** tab, select the end date, leave **Generate For Each Folio** unchecked, and generate for just the fund. To generate for a single folio, use the capital commitment page directly if that link is available, or run the full fund generation with the folio checkbox.

**Why do XIRR results differ from my own spreadsheet?**
Check whether Ratio Formulas are adjusting the cash flows — go to **Fund → Ratio Formulas** to see any customisations. Also confirm that the end date matches. Cash flow documents (debug mode) will show exactly what went into the calculation.

**Can I generate ratios for a historical date?**
Yes. Set any past date as the end date when generating. CapHive will use only transactions and valuations that existed on or before that date.

**What currency are cross-fund ratios denominated in?**
The base currency of your entity by default. You can override this by specifying a currency when triggering the generation programmatically; the UI uses the entity currency.

**Can I have different XIRR formulas for different funds?**
Yes. Ratio Formulas are **fund-specific**. Each fund can have its own set of adjustments independently.

**The IRR shows 0% even though we have investments. Why?**
XIRR cannot be computed if the cash flows are all in one direction (e.g. only outflows, no inflows or terminal value). This usually means FMV is zero and no distributions have been made yet. Once a valuation record exists for the portfolio company, FMV will be included in the terminal cash flow and XIRR will compute correctly.

**How do I compare Q1 results vs Q2 results for the same fund?**
Generate ratios at both dates. Then use the **Pivot View** on the Fund Ratios list, or filter by the fund and review the rows sorted by end date.

**What does "latest" mean on a ratio?**
After generating ratios, CapHive marks the most recent ratio for each name/owner combination as `latest = true`. This flag lets you quickly show only the current snapshot rather than the full history.

**Can I manually enter a ratio that CapHive does not compute automatically?**
Yes. Use the import spreadsheet to upload any custom ratio name (e.g. "Revenue Multiple", "Cash Yield"). CapHive will store and display it alongside the computed ratios.

**I need to run the same cross-fund or cross-portfolio calculation every month. Is there a faster way?**
Yes — use **Ratio Run Templates**. Save the filter configuration once, then trigger it for each new date from the Templates index with a single click, or use the Trigger by Tag feature to run a whole group at once. See the [Ratio Run Templates User Guide](fund_ratio_run_templates_user_guide).

**What is a FundRatioRun?**
A FundRatioRun is the record that captures exactly which filters were used for a cross-fund or cross-portfolio calculation. Every ratio produced by such a run is linked back to it. You can view a run's inputs by clicking **View Run Inputs** on any cross-fund ratio's detail page.
