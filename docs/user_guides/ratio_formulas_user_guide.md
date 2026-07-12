# Ratio Formulas User Guide

**Ratio formulas** let you tailor how a fund's performance ratios are calculated. Out of the box, the system computes XIRR, MOIC, DPI, TVPI and the rest from standard ingredients (capital called, distributions, fair market value, cash, and net current assets). Ratio formulas let you fold in *additional* amounts you've recorded against the fund — so a ratio reflects your fund's specific economics rather than a one-size-fits-all formula.

This guide is for fund managers and finance teams who need a ratio to account for something the standard calculation doesn't capture — for example a fee rebate, a side-pocket investment, or an expense that should reduce the return.

---

## Table of Contents

1. [What a Ratio Formula Does](#what-a-ratio-formula-does)
2. [When You'd Use One](#when-youd-use-one)
3. [Finding Ratio Formulas](#finding-ratio-formulas)
4. [Building a Rule](#building-a-rule)
5. [Choosing the Right Action](#choosing-the-right-action)
6. [Grouping Rules with Labels](#grouping-rules-with-labels)
7. [How the Rules Are Applied](#how-the-rules-are-applied)
8. [Worked Examples](#worked-examples)
9. [Using Formulas Across Multiple Funds](#using-formulas-across-multiple-funds)
10. [Frequently Asked Questions](#frequently-asked-questions)

---

## What a Ratio Formula Does

Every performance ratio is a comparison of value against capital. A ratio formula adds your own amounts to one side of that comparison.

```mermaid
flowchart LR
    A[Standard ingredients<br/>calls, distributions, FMV, cash] --> R[Ratio]
    B[Your recorded amounts<br/>fees, rebates, side investments] -->|ratio formula| R
```

The amounts come from **account entries** — the line items already stored against the fund, an investor folio, or a portfolio company. A formula tells the system: *"for this ratio, take these named amounts and add or subtract them on the value side or the capital side."*

Crucially, formulas are **additive**. They supplement the standard calculation; they don't replace it. The fund still counts FMV, cash, net current assets, and estimated carry as usual.

---

## When You'd Use One

- Make Fund XIRR **net of** certain expenses that live in account entries (legal fees, non-deal costs).
- Count a **side-pocket or sidecar investment** toward residual value in TVPI and MOIC.
- Add a **management-fee rebate** into distributions for DPI.
- Reduce an investor's folio return by a **temporary income distribution**.

---

## Finding Ratio Formulas

1. Open the **Funds** list and select a fund.
2. Click **Actions** (top right).
3. Open the **Account Entries** sub-menu.
4. Click **Ratio Formulas**.

Here you can view, create, edit, or delete the rules for that fund. Rules are defined **per fund** — each fund keeps its own set.

---

## Building a Rule

Click **New Ratio Formula** and fill in:

| Field | What it controls |
|-------|------------------|
| **Level** | Which calculation the rule affects: **Fund** (fund-wide ratios), **Folio** (an individual investor's ratios), or **Portfolio Company** (a single company's ratios). |
| **Ratios** | One or more ratios this rule applies to (e.g. XIRR, DPI, MOIC, TVPI). |
| **Action** | How the amount is used — see [Choosing the Right Action](#choosing-the-right-action). |
| **Account Entry Names** | The named line items to pull amounts from. You can choose several. |
| **Period** | **All** — total every matching entry up to the end date. **As-on** — use only the latest entry on or before the end date for *each* selected account entry name (best for valuations, where you want the most recent figure per line item, not a sum). |
| **Label** *(optional)* | Groups this rule with any other rule sharing the same label into its own, separately-named ratio. See [Grouping Rules with Labels](#grouping-rules-with-labels). |

The following advanced fields are tucked under the collapsible section next to Account Entry Names — most rules don't need them:

| Field | What it controls |
|-------|------------------|
| **Entry Type** *(optional)* | Restrict matching entries to one or more entry types (comma-separated), in addition to matching on name. Leave blank to match any entry type. |
| **Parent Type** *(optional)* | Restrict matching entries by the type of record they're attached to (comma-separated, e.g. `Investor`, `PortfolioInvestment`). Leave blank to use the default parent-type behavior for the rule's Level. |
| **Cumulative** | Whether to pull from **cumulative** account entries (running totals) instead of the default non-cumulative ones. Leave unchecked unless you specifically need cumulative entries — see [No double-counting](#how-the-rules-are-applied). |
| **Skip Portfolio FMV** *(optional, FMV-based ratios only)* | When checked, the fund's code-computed portfolio FMV is left out of this rule's ratio. For the FMV-based **multiples** — MOIC, TVPI, RVPI, Portfolio Value to Cost, and Value to Cost — it is subtracted from the numerator; for the **rate-of-return** ratios — XIRR and Gross Portfolio IRR — it is simply not added to the cash flow. Use this when the rule's own account entries already represent the FMV (e.g. feeder funds pulling FMV from the master fund via account entries instead of the API-computed value). Has **no effect** on ratios that don't include FMV, such as **DPI** and **PIC**. |

---

## Choosing the Right Action

The available actions depend on whether the ratio is a *rate of return* (XIRR/IRR) or a *multiple* (DPI, MOIC, RVPI, TVPI, PIC).

### For rate-of-return ratios (XIRR, IRR)

These work on cash flows, so you tell the system whether your amount behaves like money coming in or money going out:

| Action | Plain meaning |
|--------|---------------|
| **add_cashflow** | Treat the amount as an **inflow** (a positive return) on the reporting date. |
| **reduce_cashflow** | Treat the amount as an **outflow** (a cost) on the reporting date. |

### For multiple ratios (DPI, MOIC, RVPI, TVPI, PIC)

A multiple is value ÷ capital. You choose which side of the fraction to adjust:

| Action | Plain meaning |
|--------|---------------|
| **add_numerator** | Add to the **top** (the value side — e.g. distributions or total value). |
| **reduce_numerator** | Subtract from the top. |
| **add_denominator** | Add to the **bottom** (the capital side — e.g. paid-in capital). |
| **reduce_denominator** | Subtract from the bottom. |

```mermaid
flowchart TD
    A{Which kind of ratio?} -->|Rate of return<br/>XIRR / IRR| B[Use cash-flow actions<br/>add_cashflow / reduce_cashflow]
    A -->|Multiple<br/>DPI / MOIC / TVPI| C[Use numerator / denominator actions]
    C --> D[Value side → numerator]
    C --> E[Capital side → denominator]
```

---

## Grouping Rules with Labels

Normally, all the rules you define for a given ratio and level are combined into a single result — e.g. every Fund-level XIRR rule feeds the one "XIRR" figure.

A **Label** lets you carve out an *alternate* version of the ratio instead. Give one or more rules the same label, and when ratios are generated the system computes a **separate, additional** ratio using only the rules that share that label — stored under the label's own name rather than "XIRR" or "DPI".

```mermaid
flowchart LR
    A[Unlabeled rules] --> R1[Standard ratio<br/>e.g. XIRR]
    B[Rules labeled 'xirr outflow'] --> R2[Separate ratio<br/>named 'xirr outflow']
```

Key points:

- **Labeled rules don't feed the standard ratio.** A rule with a label only counts toward the ratio named after that label — it's excluded from the plain "XIRR"/"DPI"/etc. figure. Rules with no label continue to produce the standard ratio exactly as before.
- **Several rules can share a label.** All rules with the same label (for the same ratio and level) are combined together into that one labeled result, the same way unlabeled rules combine into the standard one.
- **Every label becomes its own ratio record.** If a fund has an unlabeled XIRR rule and a rule labeled "xirr outflow", generating ratios produces two results: "XIRR" and "xirr outflow" — both viewable, exportable, and searchable like any other ratio.
- **Tracking currency still applies.** A labeled ratio gets its own tracking-currency variant too, e.g. "xirr outflow (USD)", following the same naming pattern as the standard ratio.
- **Use it to model variants side by side** — for example an "as reported" XIRR alongside an "ex-expenses" XIRR, without losing either figure.

> Labels are limited to 30 characters and are matched by exact, case-sensitive text — use the same label spelling on every rule you want grouped together.

---

## How the Rules Are Applied

A few principles govern how formulas behave:

- **Additive, not replacing.** Formulas are applied *on top of* the standard components (FMV, cash in hand, net current assets, estimated carry). Defining a formula doesn't switch those off.
- **Sensible fallback.** If a fund has no rules for "Cash In Hand" or "Net Current Assets", the system uses its built-in defaults. As soon as you define a rule for a specific ratio, your rules take over for that ratio.
- **No double-counting.** Only **non-cumulative** account entries are picked up, so a running-total entry won't be added twice.
- **Currency-aware.** Amounts are automatically converted to the right currency (tracking or base) using the exchange rate on the entry's reporting date.

---

## Worked Examples

### Example 1 — Make Fund XIRR net of expenses

You want Fund XIRR to reflect legal and non-deal costs stored as account entries.

| Setting | Value |
|---------|-------|
| Level | Fund |
| Ratios | XIRR |
| Action | **reduce_cashflow** (treat as an outflow) |
| Account Entry Names | "Non Deal Expenses", "Legal Fees" |
| Period | All (include every expense event) |

**Effect:** every matching expense becomes a negative cash flow, lowering the XIRR to reflect the true net return.

### Example 2 — Count a sidecar investment in TVPI and MOIC

The fund holds a side investment in a mutual fund that should count toward residual value.

| Setting | Value |
|---------|-------|
| Level | Fund |
| Ratios | TVPI, MOIC |
| Action | **add_numerator** (increase the value side) |
| Account Entry Names | "Mutual Fund Investment" |
| Period | As-on (use only the latest valuation) |

**Effect — illustrative:** if standard TVPI was (Distributions 5M + Remaining 7M) ÷ Paid-in 10M = **1.20×**, and the latest sidecar valuation is 2M, the adjusted TVPI becomes (5M + 7M + 2M) ÷ 10M = **1.40×**.

### Example 3 — Reduce a folio's XIRR with a temporary distribution

Some investors received a temporary distribution that should affect their individual return.

| Setting | Value |
|---------|-------|
| Level | Folio |
| Ratios | XIRR |
| Action | **add_cashflow** (a return to the investor) |
| Account Entry Names | "Temp income distribution" |
| Period | All |

**Effect:** the temporary distribution is treated as an inflow on the investor's folio XIRR only, not at the fund level.

---

## Using Formulas Across Multiple Funds

When you calculate a ratio for an **entity** (several funds combined) or a **cross-fund scenario**, each fund's own formulas are respected:

```mermaid
flowchart TD
    A[Cross-fund / entity ratio] --> B[Fund A: apply Fund A's formulas]
    A --> C[Fund B: apply Fund B's formulas]
    B --> D[Convert to entity base currency]
    C --> D
    D --> E[Sum and compute the combined ratio]
```

So if Fund A includes expenses in its XIRR but Fund B doesn't, the combined entity XIRR correctly reflects each fund's choice.

---

## Frequently Asked Questions

**Do I have to define formulas for the standard components?**
No. FMV, cash in hand, net current assets, and estimated carry are included automatically. Use formulas only to add something extra or to override a specific ratio.

**Will a formula change every ratio?**
Only the ratios you list, at the level you choose. A Folio-level rule, for instance, affects only per-investor ratios — not the fund total.

**When should I use "As-on" versus "All"?**
Use **As-on** for things that have a current value (like a valuation), where you want only the latest figure. Use **All** for things that accumulate (like a series of expenses or distributions), where you want the total.

**Why isn't my entry being picked up?**
Check that it isn't marked cumulative (only non-cumulative entries are used), that its name exactly matches one in the rule, and that its reporting date falls on or before the ratio's end date.

**Do formulas affect previously generated ratios?**
No — they apply the next time you generate ratios. Regenerate to see the effect.
