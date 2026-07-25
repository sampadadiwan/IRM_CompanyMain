# Generating Account Entries for Multiple Fee Types with One Formula

**GenerateAccountEntryMultiple** is a rule type that lets one formula generate account entries for several fee types at once. Instead of maintaining one formula per fee type per period (Quarterly, YTD, Since Inception), you list all the fee types inside a single formula — the system still creates a separate account entry for each fee type on each commitment, exactly as if you had written them individually.

This guide is for fund administrators who maintain allocation formulas.

---

## Before and After

A typical reporting setup needs Quarterly, YTD, and Since Inception entries for each of five fee types — 15 formulas. With this rule type, that becomes 3:

| Name | Rule Type | Formula |
|---|---|---|
| Quarterly Reporting | GenerateAccountEntryMultiple | `capital_commitment.quarterly(["Management Fees", "Custody Fees", "Fund Administrative Costs", "Audit Fees", "Bank Charges"], nil, @start_date, @end_date)` |
| YTD Reporting | GenerateAccountEntryMultiple | `capital_commitment.year_to_date(["Management Fees", "Custody Fees", "Fund Administrative Costs", "Audit Fees", "Bank Charges"], nil, @start_date, @end_date)` |
| Since Inception Reporting | GenerateAccountEntryMultiple | `capital_commitment.since_inception(["Management Fees", "Custody Fees", "Fund Administrative Costs", "Audit Fees", "Bank Charges"], nil, @start_date, @end_date)` |

The result is unchanged: every commitment still gets its own "Quarterly Management Fees", "Quarterly Custody Fees", etc. entry with the correct amount, plus the usual fund-level totals — the same number of entries as before, from far fewer formulas.

## Setting One Up

1. Open the fund's **Formulas** page and create a new formula.
2. Choose **GenerateAccountEntryMultiple** as the Rule Type.
3. Write the formula as usual, but put the fee-type names in a **quoted, comma-separated list inside square brackets** where a single name would normally go.
4. Give the formula a descriptive batch name (e.g. "Quarterly Reporting") — the individual entries are **not** named after the formula; they are named after each fee type in the list.

## How Entries Are Named

Each generated entry is named *prefix + fee type*. The prefix comes automatically from the period used in the formula:

| Formula uses | Entries are named | Example |
|---|---|---|
| `quarterly` | Quarterly … | Quarterly Management Fees |
| `year_to_date` | YTD … | YTD Management Fees |
| `since_inception` | Since Inception … | Since Inception Management Fees |
| anything else | no prefix | Management Fees |

These are the same names the single-formula setup produced, so investor statements and templates that reference them keep working.

**Custom prefix**: add `name_prefix=My Prefix ` to the formula's meta data to override the automatic prefix. Include the trailing space — otherwise the prefix runs into the name (`My PrefixManagement Fees`).

## Things to Know

- **Same output, fewer formulas.** Per-commitment entries, fund-level totals, and per-entry explanations are all produced per fee type, just as with individual formulas.
- **The list must contain at least one quoted name.** The formula will not save otherwise.
- **Keep each entry name in only one formula** (for a given entry type). Totals are grouped by entry name, so two formulas generating the same name would sum into each other's totals — the same as it has always been for two single formulas sharing a name.
- **Duplicates in the list are ignored** — each fee type generates once.
- **The "generate YTD/Quarterly" checkbox cannot be combined** with this rule type; write separate Quarterly / YTD / Since Inception formulas instead, as in the example above.
- **Re-running a period is safe.** Entries from the previous run for the same period are replaced, not duplicated.
