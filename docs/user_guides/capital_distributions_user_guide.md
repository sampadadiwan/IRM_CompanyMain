# Capital Distributions User Guide

This guide explains how to create and manage capital distributions, track per-investor distribution payments, apply account-entry-based fee adjustments, and send investor notifications. No technical knowledge is required.

---

## Table of Contents

1. [Overview](#overview)
2. [Key Concepts](#key-concepts)
3. [Capital Distribution Lifecycle](#capital-distribution-lifecycle)
4. [Creating a Capital Distribution](#creating-a-capital-distribution)
5. [Distribution Basis — How Amounts Are Allocated](#distribution-basis--how-amounts-are-allocated)
6. [Distribution Fees — Account Entry Adjustments](#distribution-fees--account-entry-adjustments)
7. [Generating Distribution Payments](#generating-distribution-payments)
8. [Approving a Capital Distribution](#approving-a-capital-distribution)
9. [Capital Distribution Payments](#capital-distribution-payments)
10. [How Net Payable and Gross Payable Are Computed](#how-net-payable-and-gross-payable-are-computed)
11. [Completing Payments](#completing-payments)
12. [Multi-Currency Support](#multi-currency-support)
13. [Notifications](#notifications)
14. [Document Generation](#document-generation)
15. [Unit Redemption](#unit-redemption)
16. [Recomputing Fees](#recomputing-fees)
17. [Linking Portfolio Investment Sales](#linking-portfolio-investment-sales)
18. [Importing Data](#importing-data)
19. [Key Computations Reference](#key-computations-reference)
20. [Frequently Asked Questions](#frequently-asked-questions)

---

## Overview

A **Capital Distribution** is a payment from a fund to its investors. It records how much income (e.g. from a portfolio company sale) or return of capital (Face Value for Redemption) is being paid out, and generates one **Capital Distribution Payment** per investor commitment that specifies each investor's share.

```
Fund declares Capital Distribution
        │
        ▼
System generates one Distribution Payment per investor commitment
        │
        ▼
Distribution fees (taxes, expenses, additional income) applied per investor
        │
        ▼
Net Payable and Gross Payable computed for each investor
        │
        ▼
Approve the distribution
        │
        ▼
Mark individual payments as Completed
        │
        ▼
Investor notification emails sent (if enabled)
```

---

## Key Concepts

| Term | Meaning |
|------|---------|
| **Capital Distribution** | The fund-level record declaring a distribution event |
| **Capital Distribution Payment** | The per-investor record showing how much that investor receives |
| **Distribution Fee** | An account-entry adjustment (income addition, tax deduction, expense, reinvestment, etc.) applied to each investor's payment |
| **Income** | Gain or income component of the distribution (e.g. from a portfolio sale) |
| **Face Value For Redemption (FVR)** | The cost-of-investment component being returned to investors (principal repayment) |
| **Reinvestment** | A portion of the distribution that is reinvested rather than paid out |
| **Gross Payable** | The total outgoing before tax/expense deductions: Income + FVR adjustments |
| **Net Payable** | The investor's actual take-home: Gross adjusted for taxes, expenses, and reinvestment |
| **Completed** | The fund team's confirmation that the payment has been made to the investor |
| **Distribution Basis** | The method used to allocate the total distribution among investors |

---

## Capital Distribution Lifecycle

```
  ┌──────────────────────────────────────────────────────────┐
  │               CAPITAL DISTRIBUTION                        │
  │                                                          │
  │  1. CREATE                                               │
  │     Set title, date, income, FV for Redemption,          │
  │     reinvestment, distribution basis, distribution fees  │
  │                    │                                     │
  │                    ▼                                     │
  │  2. GENERATE PAYMENTS (automatic on create)              │
  │     One payment created per commitment                   │
  │     Each payment's amounts computed via distribution     │
  │     percentage × total fund amounts                      │
  │     Distribution fees applied per investor               │
  │                    │                                     │
  │                    ▼                                     │
  │  3. APPROVE                                              │
  │     Fund manager approves the distribution               │
  │                    │                                     │
  │                    ▼                                     │
  │  4. MARK PAYMENTS AS COMPLETED                           │
  │     Fund confirms money sent to each investor            │
  │     "Mark All Completed" bulk action available           │
  │                    │                                     │
  │                    ▼                                     │
  │  5. SEND NOTIFICATIONS                                   │
  │     Emails sent to investors once completed+approved     │
  └──────────────────────────────────────────────────────────┘
```

---

## Creating a Capital Distribution

Navigate to a **Fund** and click **New Capital Distribution**.

### Required Fields

| Field | Description |
|-------|-------------|
| **Title** | A unique name for this distribution within the fund. Spaces are trimmed; duplicates are not allowed. |
| **Distribution Date** | The date of the distribution. Defaults to today. Used for payment dates and account entry lookups. |
| **Distribution Basis** | How to allocate the total among investors (see [Distribution Basis](#distribution-basis--how-amounts-are-allocated)). |

### Amount Fields

| Field | Description |
|-------|-------------|
| **Income** | The income/gain portion being distributed (e.g. profit from a portfolio company sale). |
| **Face Value For Redemption** | The cost-of-investment or principal portion being returned to investors. |
| **Reinvestment** | Amount of the distribution that is being reinvested rather than paid out in cash. Deducted from Net Payable. |

> **Note:** All three amounts are at the **fund level** — they represent the total amounts to distribute across all investors. Each investor's share is computed from these totals based on their distribution percentage.

### Optional Fields

| Field | Description |
|-------|-------------|
| **Notes** | Internal notes about this distribution. |
| **Generate Payments** | Whether to auto-generate payments for all commitments on save. Defaults to **Yes**. |
| **Payments Paid** | If enabled, generated payments are automatically marked as **Completed**. Useful for recording historical distributions. |
| **Send Notification on Complete** | Whether to email investors when their payment is marked Completed. Defaults to **Yes**. |
| **Distribution Fees** | Account-entry-based adjustments (taxes, income additions, expenses) — see [Distribution Fees](#distribution-fees--account-entry-adjustments). |
| **Portfolio Investments** | Optionally link portfolio investment sales that generated the income. |
| **Unit Prices** | Per-unit-type price for unit redemption. |

### Business Rules

- Title must be **unique within the fund**.
- Distribution Date is required.
- When a distribution is linked to portfolio investments, the income and FVR amounts are pre-filled from the gain and cost of those investments.
- If distribution_basis is "Upload", no payments are generated automatically — they must be uploaded.

---

## Distribution Basis — How Amounts Are Allocated

The Distribution Basis determines each investor's **percentage share** of the total distribution.

### Option 1: Commitment Percentage

```
Investor's Share (%) = Investor Commitment Percentage
                       (the "percentage" field on the capital commitment)

Investor Income = Total Fund Income × Investor Percentage / 100
Investor FVR    = Total Fund FVR    × Investor Percentage / 100
Investor Reinvest = Total Fund Reinvestment × Investor Percentage / 100
```

- Each commitment has a stored `percentage` (e.g. 5.25% of the fund).
- CapHive multiplies the fund totals by each commitment's percentage.
- This is the standard method for most closed-ended funds.

### Option 2: Investable Capital Percentage

```
Investor's Share (%) = most recent "Investable Capital Percentage" account entry
                       on or before the Distribution Date

Fallback: if no account entry exists → uses Commitment Percentage
```

- Looks up each commitment's "Investable Capital Percentage" account entry (the most recent entry dated on or before the distribution date).
- Used when investors have different percentages based on their investable capital allocation rather than their raw commitment size.

### Option 3: Upload

- No automatic payment generation.
- Each payment's income, FVR, and reinvestment amounts are provided explicitly via spreadsheet import.
- Use when payment amounts are determined externally.

---

## Distribution Fees — Account Entry Adjustments

Distribution Fees are adjustments applied to each investor's payment based on account entries already recorded against their commitment. Despite the name "fees", these are not charges — they are **account entry bucketing rules** that modify income and FVR components.

### Fee Types and Their Effect

| Fee Type | Effect on Investor Payment |
|----------|---------------------------|
| **Income** | Adds the account entry amount to `income_with_fees`. Increases Net Payable and Gross Payable. |
| **FV For Redemption** | Adds the account entry amount to `cost_of_investment_with_fees`. Increases Net Payable and Gross Payable. |
| **Tax** | Subtracts the account entry amount from `income_with_fees`. Decreases Net Payable but **not** Gross Payable. |
| **Expense** | Subtracts the account entry amount from `income_with_fees`. Decreases Net Payable but **not** Gross Payable. |
| **Reinvestment** | Adds the account entry amount to `reinvestment_with_fees`. **Decreases Net Payable** but **not** Gross Payable. |
| **Display Only** | Shows in the audit trail / distribution notice. **No effect** on any computed amount. |

> **Key distinction:** Taxes and expenses reduce Net Payable (what the investor actually receives) but do not reduce Gross Payable (what the fund distributes before deductions). This distinction matters for DPI, TVPI, and fund-level reporting.

### How Distribution Fees Are Configured

1. On the Capital Distribution form, click **Add Distribution Fee**.
2. Set:

| Field | Description |
|-------|-------------|
| **Name** | Must match an account entry name recorded on the investor's commitment. |
| **Start Date** | Beginning of the date range to search for account entries. |
| **End Date** | End of the date range. |
| **Fee Type** | Income, FV For Redemption, Tax, Expense, Reinvestment, or Display Only. |
| **Notes** | Internal notes. For support users, can contain a formula expression. |

3. Multiple distribution fees can be added. They are processed in **alphabetical order by fee type**.

### Audit Trail

For every distribution payment, CapHive stores a detailed JSON audit (in `ae_audit`) showing every account entry that contributed to every fee, including the name, date, and amount. This audit is used in distribution notices.

---

## Generating Distribution Payments

When a Capital Distribution is saved with **Generate Payments = Yes**, CapHive automatically queues a background job to create one payment per commitment.

### What Happens

1. For each commitment in the fund, CapHive computes the distribution percentage.
2. Income, FVR, and Reinvestment are each multiplied by the percentage.
3. Distribution fees are applied (account entries looked up and summed).
4. Net Payable and Gross Payable are calculated.
5. A payment record is created for each commitment.
6. If **Payments Paid = Yes**, payments are created as Completed.

### Idempotency

Generation is **idempotent** — if a payment already exists for a given distribution + commitment pair, it is skipped. Running the job a second time will not create duplicates.

### Skipping Generation

If **Generate Payments = No**, payments must be added manually (one at a time from the distribution page) or via bulk import.

---

## Approving a Capital Distribution

Approval is a formal confirmation step.

1. Open the Capital Distribution.
2. Click **Approve**.
3. The distribution's `approved` flag is set and the `approved_by_user` is recorded.
4. Notifications can only be sent to investors once the distribution is approved.

---

## Capital Distribution Payments

A Capital Distribution Payment is the per-investor record. It holds the base amounts, fee-adjusted amounts, and the Completed status.

### Key Fields

| Field | Description |
|-------|-------------|
| **Folio ID** | The investor's commitment identifier. Must be unique within a distribution. |
| **Income** | The investor's share of the fund's income (before fee adjustments). |
| **Face Value For Redemption (FVR)** | The investor's share of the fund's FVR (cost_of_investment, before adjustments). |
| **Reinvestment** | The investor's share of the reinvestment amount (before adjustments). |
| **Income With Fees** | Income after adding Income-type AEs and subtracting Tax/Expense AEs. |
| **FVR With Fees** | FVR after adding FV For Redemption-type AEs. |
| **Reinvestment With Fees** | Reinvestment after adding Reinvestment-type AEs. |
| **Net Of Account Entries** | The net sum of all AE adjustments (positive AEs minus Tax/Expense/Reinvestment AEs). |
| **Gross Of Account Entries** | The gross sum of AE adjustments (positive AEs only, ignoring deductions). |
| **Net Payable** | The investor's actual payment (see [computation](#how-net-payable-and-gross-payable-are-computed)). |
| **Gross Payable** | The payment before deductions. Used for fund-level totals and DPI/TVPI. |
| **Folio Amount** | Net Payable converted to the investor's folio currency. |
| **Payment Date** | Date of payment. Defaults to the distribution date. |
| **Percentage** | The investor's distribution percentage (from commitment percentage or ICP account entry). |
| **Completed** | Whether the fund has confirmed the money has been sent to this investor. |
| **Notification Sent** | Whether the notification email has been sent. |

---

## How Net Payable and Gross Payable Are Computed

```
Step 1 — Apply Distribution Fees

  For each DistributionFee on the Capital Distribution:
    → sum all non-cumulative account entries for that fee name
       within [start_date, end_date] on this investor's commitment

  Categorise each sum:
    Income AEs        → net_ae += amount; gross_ae += amount
                        income_with_fees += amount
    FVR AEs           → net_ae += amount; gross_ae += amount
                        cost_of_investment_with_fees += amount
    Tax AEs           → net_ae -= amount  (NOT gross_ae)
                        income_with_fees -= amount
    Expense AEs       → net_ae -= amount  (NOT gross_ae)
                        income_with_fees -= amount
    Reinvestment AEs  → net_ae -= amount  (NOT gross_ae)
                        reinvestment_with_fees += amount
    Display Only AEs  → audit only, no computation

Step 2 — Compute Net Payable and Gross Payable

  net_payable = income + net_ae + cost_of_investment - reinvestment

  gross_payable = income + gross_ae + cost_of_investment
```

### Illustrated Example

Suppose an investor has:
- Income = 1,000
- FVR = 500
- Reinvestment = 200
- Account entries: Tax 100, Management Fee Income 50

| Step | Calculation | Result |
|------|-------------|--------|
| Start | income=1000, fvr=500, reinvest=200 | net_ae=0, gross_ae=0 |
| Tax (Expense type) | net_ae -= 100 | net_ae=−100, gross_ae=0 |
| Mgmt Fee (Income type) | net_ae += 50, gross_ae += 50 | net_ae=−50, gross_ae=50 |
| **Net Payable** | 1000 + (−50) + 500 − 200 | **1,250** |
| **Gross Payable** | 1000 + 50 + 500 | **1,550** |

---

## Completing Payments

"Completing" a payment is the fund team's confirmation that cash has been sent to the investor.

### Completing a Single Payment

1. Open the Capital Distribution Payment.
2. Click **Mark Completed**.

### Completing All Payments at Once

1. Open the Capital Distribution.
2. Click **Mark All Payments Completed**.
3. CapHive marks all payments on this distribution as Completed in sequence and reports how many succeeded.

### Effect of Completion

- The payment's `completed` flag is set to `true`.
- The `completed_distribution_amount_cents` counter on the Capital Distribution is updated.
- If notifications are enabled, the investor is sent a distribution notification email.

---

## Multi-Currency Support

```
  Fund Currency (Net Payable, Gross Payable, Income, FVR)
          │
          │  Exchange rate on payment_date
          ▼
  Folio Currency (folio_amount = converted net_payable)
          │
          │  Exchange rate on payment_date (for tracking)
          ▼
  Tracking Currency (tracking_net_payable, tracking_gross_payable)
```

- All fund-level amount fields (`income`, `net_payable`, `gross_payable`) are in the **fund currency**.
- `folio_amount` is the net_payable converted to the investor's **folio currency** using the payment date exchange rate.
- `tracking_net_payable` and `tracking_gross_payable` are used for cross-fund reporting in the **tracking currency**.
- Fund-level counter caches use `gross_payable_cents` for `distribution_amount_cents`, and `tracking_net_payable_cents` for `tracking_distribution_amount_cents` (completed only).

---

## Notifications

### When Notifications Are Sent

A distribution notification is sent to an investor's notification users when **all** of the following conditions are met:

| Condition | Where It Is Configured |
|-----------|----------------------|
| The payment is **Completed** | Completion flag on the payment |
| The Capital Distribution is **Approved** | Approval action on the distribution |
| **Send Notification on Complete** = Yes | Field on the Capital Distribution |
| Generation is **not manual** | `manual_generation = false` on the distribution |
| The commitment does **not have Skip Call Notice = Yes** | Commitment settings |
| Notification has **not already been sent** (unless force-sent) | `notification_sent` flag on the payment |

### Sending Notifications

**Automatically:** Each time a payment is marked Completed (via the button), the notification is sent if all conditions above are met.

**Bulk send from the distribution:** Click **Send Notifications** on the Capital Distribution page. This queues a background job that:
1. Iterates all payments on the distribution.
2. Sends notifications to investors who have not yet received one.
3. Reports success/failure counts upon completion.
4. Errors are emailed to the triggering user.

**Force-send on individual payment:** From the payment page, click **Send Notification**. This sends regardless of whether a notification was already sent.

### Email Contents

- **Subject:** "Capital Distribution: [Fund Name]"
- Any generated and approved distribution notices attached.
- Any manually uploaded documents attached.
- Custom notification template (subject/body) supported if configured on the distribution.
- CC addresses from the commitment's `cc` field are included.

### Notification Deduplication

Once a notification is sent, `notification_sent = true` is set on the payment. Subsequent sends are skipped unless forced.

### Skip Call Notice

If an investor's commitment has **Skip Call Notice = Yes**, no distribution notice will be generated and no notification email will be sent for that commitment. This setting is shared with capital call notices.

---

## Document Generation

CapHive can generate a personalised distribution notice document for each payment.

### For All Payments

1. Open the Capital Distribution.
2. Click **Generate Docs**.
3. CapHive queues a background job using the **"Distribution Template"** at the fund or commitment level.

### For a Single Payment

1. Open the Capital Distribution Payment.
2. Click **Generate Docs**.
3. Note: If the commitment has **Skip Call Notice = Yes**, document generation is blocked with an alert.

### Per-KYC Mode

If the fund's `call_notice_on` setting is "kyc", a single consolidated document is generated per KYC record (combining all folios of the same KYC). This avoids sending multiple separate notices to the same investor.

### Required Conditions

- A **"Distribution Template"** (document template tagged accordingly) must exist at the fund or commitment level.
- The investor must have a verified **KYC record**.
- Documents must be approved before notifications can be sent (approved documents are attached to the notification email).

---

## Unit Redemption

When a distribution represents a partial or full redemption of fund units:

1. Open the Capital Distribution.
2. Click **Redeem Units**.
3. CapHive queues a background job that allocates negative fund units (redemptions) against each payment.

Unit prices per unit type can be configured on the Capital Distribution (as a JSON map of unit type to price/premium).

---

## Recomputing Fees

If account entries are added or corrected after distribution payments have been generated, use **Recompute Fees** to refresh all payments.

1. Open the Capital Distribution.
2. Click **Recompute Fees**.
3. CapHive queues a background job that:
   - Re-reads all account entries for each distribution fee.
   - Recalculates income_with_fees, cost_of_investment_with_fees, reinvestment_with_fees.
   - Recomputes net_payable and gross_payable for every payment.
4. Errors are reported by email to the triggering user.

---

## Linking Portfolio Investment Sales

A Capital Distribution can be linked to one or more **Portfolio Investment** sale records. This is used to record that the distribution income comes from the proceeds of a portfolio company exit.

### When Creating a Distribution

- On the new distribution form, select the portfolio investment sells to include.
- CapHive automatically:
  - Sets `income` = sum of gains from selected portfolio investments.
  - Sets `cost_of_investment` = sum of costs of selected portfolio investments.
- The selected portfolio investments are tagged with this distribution's ID.

### On Deletion

When a Capital Distribution is deleted, the linked portfolio investments are **unlinked** (their `capital_distribution_id` is cleared) and the distribution and all its payments are destroyed.

---

## Importing Data

### Importing Capital Distributions

**Required columns:**

| Column | Description |
|--------|-------------|
| Fund | Fund name (must match exactly) |
| Title | Distribution title (must be unique within the fund) |
| Income | Total income amount at fund level |
| Date | Distribution date |
| Generate Payments | Yes/No |
| Payments Paid | Yes/No — whether to mark generated payments as Completed |
| Reinvestment | Total reinvestment amount |
| Folio No | (Optional — not used in generation) |
| Distribution Basis | "Commitment Percentage", "Investable Capital Percentage", or "Upload" |
| Face Value For Redemption | Total FVR amount |
| Send Notification | Yes/No |

**Business Rules:**
- A distribution with the same title in the same fund is rejected as a duplicate.
- Exchange rates can be provided via a "From Currency" column to handle multi-currency setups.
- When importing, `manual_generation = true` is set, which suppresses notification sending even if send_notification_on_complete = true.

### Importing Capital Distribution Payments

**Required columns:**

| Column | Description |
|--------|-------------|
| Stakeholder | Investor name |
| Fund | Fund name |
| Capital Distribution | Distribution title |
| Income | Payment-level income amount (in fund currency) |
| Payment Date | Date of payment |
| Completed | Yes/No |
| Folio No | Investor's folio ID |
| Face Value For Redemption | Payment-level FVR amount |
| Reinvestment | Payment-level reinvestment amount |

**Business Rules:**
- The investor must have a commitment in the specified fund with the specified folio number.
- The investor's commitment percentage is captured at import time.
- Distribution fees are applied automatically after the amounts are set.
- Each folio ID must be unique within a distribution.

---

## Key Computations Reference

### Per-Investor Base Amounts (Generated Payments)

```
investor_percentage = distribution_percentage(commitment)
                    = commitment.percentage            (Commitment Percentage basis)
                    = last ICP account entry / 100     (Investable Capital Percentage basis)

income_cents              = round(fund.income_cents × investor_percentage / 100, 2)
cost_of_investment_cents  = round(fund.cost_of_investment_cents × investor_percentage / 100, 2)
reinvestment_cents        = round(fund.reinvestment_cents × investor_percentage / 100, 2)
```

### Fee Application

```
For each DistributionFee (ordered by fee_type asc):
  ae_cents = sum of commitment account entries
             WHERE name = fee.name
             AND reporting_date BETWEEN fee.start_date AND fee.end_date
             AND cumulative = false

  Income:        income_with_fees += ae_cents; net_ae += ae_cents; gross_ae += ae_cents
  FVR:           cost_of_investment_with_fees += ae_cents; net_ae += ae_cents; gross_ae += ae_cents
  Tax/Expense:   income_with_fees -= ae_cents; net_ae -= ae_cents
  Reinvestment:  reinvestment_with_fees += ae_cents; net_ae -= ae_cents
  Display Only:  (no computation, audit only)

net_of_account_entries   = net_ae
gross_of_account_entries = gross_ae
```

### Net Payable and Gross Payable

```
net_payable   = income + net_of_account_entries + cost_of_investment - reinvestment

gross_payable = income + gross_of_account_entries + cost_of_investment
```

### Folio Amount (Currency Conversion)

```
folio_amount = convert(net_payable, fund_currency → folio_currency, on payment_date)
```

### Counter Caches (Auto-Aggregated)

| Counter | Aggregates From |
|---------|----------------|
| `capital_distribution.distribution_amount_cents` | Sum of all payments' `net_payable_cents` |
| `capital_distribution.gross_amount_cents` | Sum of all payments' `gross_payable_cents` |
| `capital_distribution.completed_distribution_amount_cents` | Sum of **completed** payments' `net_payable_cents` |
| `fund.distribution_amount_cents` | Sum of all payments' `gross_payable_cents` |
| `fund.tracking_distribution_amount_cents` | Sum of **completed** payments' `tracking_net_payable_cents` |
| `capital_commitment.distribution_amount_cents` | Sum of commitment payments' `gross_payable_cents` |
| `capital_commitment.tracking_distribution_amount_cents` | Sum of commitment payments' `tracking_net_payable_cents` |

---

## Frequently Asked Questions

**Q: Can I add a payment manually for an investor who was missed?**
Yes. From the distribution's Payments tab, click **New Payment** and select the investor's commitment. Enter the income, FVR, and reinvestment amounts manually. Distribution fees are applied automatically on save.

**Q: What is the difference between Gross Payable and Net Payable?**
Gross Payable is the total amount going out before investor-level deductions (taxes, expenses, reinvestments). Net Payable is what the investor actually receives in cash. Fund-level distribution totals and DPI/TVPI ratios use Gross Payable; the actual investor payment and folio_amount use Net Payable.

**Q: What does "Reinvestment" do exactly?**
Reinvestment is an amount that the investor technically "earns" from the distribution but which is immediately re-invested rather than paid out. It reduces Net Payable (so the investor receives less cash) but it also shows in the notification as a separate line item. Reinvestment AEs are tracked in `reinvestment_with_fees`.

**Q: Can I delete a distribution after payments have been sent?**
Yes, but deleting a distribution deletes all its payments as well. Any linked portfolio investments are unlinked (not deleted). If unit redemptions have been recorded, those should be reviewed before deletion.

**Q: Why would Gross Payable be higher than Net Payable?**
Because taxes and expenses reduce Net Payable but not Gross Payable. The spread represents the amount withheld from the investor (tax, expense deductions). In the fund's own books and performance metrics, the gross amount is used to reflect the full value distributed.

**Q: What is Display Only fee type used for?**
Display Only fees appear in the distribution notice document for transparency (e.g. showing the investor a breakdown of management fee accruals) but do not affect any amount. They are purely informational.

**Q: Can two investors receive different percentages in the same distribution?**
Yes. Under "Investable Capital Percentage" basis, each investor's percentage comes from their own "Investable Capital Percentage" account entry. Investors who haven't reached the hurdle may have lower ICP percentages than their commitment percentages, while others may have higher.

**Q: When is "Payments Paid" useful?**
When loading historical data. Setting Payments Paid = Yes (via import or when creating the distribution) marks all generated payments as Completed immediately, so you don't need to manually complete them one by one.

**Q: Does approving a distribution trigger notifications?**
Not automatically — notifications are triggered when payments are marked **Completed**, not at approval. Approval is just a prerequisite for notifications to be sent.
