# Capital Calls User Guide

This guide explains everything you need to know about issuing capital calls, tracking investor remittances, recording payments, and understanding how amounts and fees are computed. No technical knowledge is required.

---

## Table of Contents

1. [Overview](#overview)
2. [Key Concepts](#key-concepts)
3. [Capital Call Lifecycle](#capital-call-lifecycle)
4. [Creating a Capital Call](#creating-a-capital-call)
5. [Call Basis — How Amounts Are Calculated](#call-basis--how-amounts-are-calculated)
6. [Fund Closes and Close Percentages](#fund-closes-and-close-percentages)
7. [Call Fees](#call-fees)
8. [Generating Remittances](#generating-remittances)
9. [Approving a Capital Call](#approving-a-capital-call)
10. [Capital Remittances](#capital-remittances)
11. [Remittance Status Lifecycle](#remittance-status-lifecycle)
12. [Verifying a Remittance](#verifying-a-remittance)
13. [Capital Remittance Payments](#capital-remittance-payments)
14. [Multi-Currency Support](#multi-currency-support)
15. [Notifications](#notifications)
16. [Document Generation](#document-generation)
17. [Unit Allocation](#unit-allocation)
18. [Recomputing Fees](#recomputing-fees)
19. [Importing Data](#importing-data)
20. [Key Computations Reference](#key-computations-reference)
21. [Frequently Asked Questions](#frequently-asked-questions)

---

## Overview

A **Capital Call** is a request from a fund to its investors asking them to transfer a portion of their committed capital. CapHive manages the entire lifecycle — from issuing the call and computing each investor's share, to tracking payments and sending notifications.

```
Fund issues Capital Call
        │
        ▼
System generates one Capital Remittance per investor commitment
        │
        ▼
Investors receive notification email with their due amount
        │
        ▼
Investors transfer funds → recorded as Capital Remittance Payments
        │
        ▼
Team verifies receipt → Remittance marked Paid
        │
        ▼
(Optional) Fund units allocated to investors
```

---

## Key Concepts

| Term | Meaning |
|------|---------|
| **Capital Call** | The fund-level instruction to call a percentage or amount from investors |
| **Capital Remittance** | The per-investor record showing how much is owed for a given capital call |
| **Capital Remittance Payment** | A single payment made by an investor against their remittance |
| **Call Fee** | A fee (management fee, upfront fee, etc.) that is bundled into or alongside the call amount |
| **Folio ID** | A unique identifier for each investor-commitment combination |
| **Fund Close** | A closing tranche of the fund (e.g. First Close, Second Close) |
| **Call Basis** | The method used to calculate each investor's call amount |
| **Verified** | A flag set by the fund team to confirm that the remittance amount has been validated/received |

---

## Capital Call Lifecycle

```
  ┌─────────────────────────────────────────────────────────┐
  │                    CAPITAL CALL                          │
  │                                                         │
  │  1. CREATE                                              │
  │     Set name, dates, call basis, fund closes, fees      │
  │                    │                                    │
  │                    ▼                                    │
  │  2. GENERATE REMITTANCES (automatic or manual)          │
  │     One remittance created per eligible commitment      │
  │                    │                                    │
  │                    ▼                                    │
  │  3. GENERATE & APPROVE CALL NOTICE DOCUMENTS            │
  │     Generate personalised notices per remittance        │
  │     Approve each document before proceeding             │
  │     ─ Call is LOCKED for edits after approval ─         │
  │                    │                                    │
  │                    ▼                                    │
  │  4. APPROVE                                             │
  │     Fund manager approves the call                      │
  │     ─ Validates all generated documents are approved    │
  │     ─ Triggers notification emails (if enabled)         │
  │     ─ Call, edit, and recompute actions disabled        │
  │                    │                                    │
  │                    ▼                                    │
  │  5. INVESTORS PAY                                       │
  │     Payments recorded as Remittance Payments            │
  │                    │                                    │
  │                    ▼                                    │
  │  6. VERIFY REMITTANCES                                  │
  │     Team marks each remittance as Verified              │
  │     Status changes to Paid / Overdue / Overpaid         │
  │                    │                                    │
  │                    ▼                                    │
  │  7. CLOSE (optional)                                    │
  │     Allocate fund units; send payment notifications     │
  └─────────────────────────────────────────────────────────┘
```

---

## Creating a Capital Call

Navigate to a **Fund** and click **New Capital Call**.

### Required Fields

| Field | Description |
|-------|-------------|
| **Name** | A unique name for this call within the fund. Spaces are trimmed and duplicates are not allowed. |
| **Call Date** | The date the call is issued. Defaults to today. |
| **Due Date** | The deadline by which investors must pay. Defaults to two weeks from today. |
| **Call Basis** | How each investor's amount is calculated (see [Call Basis](#call-basis--how-amounts-are-calculated)). |
| **Fund Closes** | Which closing tranches this call applies to. Must be specified unless Call Basis is "Upload". |
| **Percentage Called** | For "Percentage of Commitment" basis, the percentage of each investor's commitment to call. Cannot exceed 100%. |

### Optional Fields

| Field | Description |
|-------|-------------|
| **Notes** | Internal notes about this call. |
| **Send Call Notice** | Whether to email investors when the call is approved. Defaults to **Yes**. |
| **Send Payment Notification** | Whether to notify investors when a payment is received and verified. Defaults to **Yes**. |
| **Generate Remittances** | Whether to auto-generate one remittance per commitment. Defaults to **Yes**. |
| **Remittances Verified** | If enabled, generated remittances are automatically marked as verified and paid. Useful for recording historical data. |
| **Call Fees** | Fee entries to be included in the call computation (see [Call Fees](#call-fees)). |
| **Unit Prices** | Per-unit-type price and premium for unit allocation. |

### Business Rules

- The call **name must be unique** within the fund.
- **Due Date and Call Date are both required.**
- **Percentage Called** must be ≤ 100.
- Fund Closes must be specified for all call basis types except "Upload".
- Once saved, if the call basis is not "Upload", CapHive will automatically queue generation of remittances if the percentage or amount changes.

---

## Call Basis — How Amounts Are Calculated

The Call Basis determines how CapHive computes each investor's individual call amount.

### Option 1: Percentage of Commitment

```
Investor Call Amount = (Percentage Called / 100) × Investor's Committed Amount
                       + Capital Fees + Investment Amount
```

- You set a **Percentage Called** (e.g. 25%).
- CapHive multiplies each investor's commitment by that percentage.
- If different fund closes are called at different percentages, each close gets its own percentage (see [Fund Closes and Close Percentages](#fund-closes-and-close-percentages)).
- Fees (if configured) are added on top of the base call amount.

### Option 2: Investable Capital Percentage (or custom account-entry basis)

```
Investor Call Amount = (Investor's Investable Capital %) × Total Amount To Be Called
                       + Capital Fees + Investment Amount
```

- You set a **Total Amount To Be Called** at the fund level.
- Each investor's share is determined by their "Investable Capital Percentage" account entry (the most recent entry up to the due date).
- If no such entry exists for an investor, their call amount is zero.

### Option 3: Upload

- No automatic computation.
- You upload a spreadsheet with each investor's exact call amount (in folio currency and/or fund currency).
- Call amounts, capital fees, other fees, and investment amounts are all taken directly from the file.
- Use this when amounts are determined externally (e.g. from a fund administrator's file).

---

## Fund Closes and Close Percentages

A fund may have multiple closing tranches. Capital calls can target **specific closes** or **all closes**.

- When you select fund closes, only investors whose commitment belongs to one of the selected closes will receive a remittance.
- You can specify a **different percentage for each close**. For example, First Close investors might be called at 25% while Second Close investors are called at 10%.

```
Example:
  First Close  → 25%
  Second Close → 10%
  Third Close  → excluded from this call
```

- Selecting **"All"** applies the call to every commitment in the fund at the same percentage.

---

## Call Fees

Call Fees let you bundle additional charges into a capital call. They are attached to a specific call and computed per investor.

### Fee Types

| Fee Type | Effect |
|----------|--------|
| **Fees Part Of Capital** | Added to the investor's call amount (capital_fee). Included in the total amount the investor must transfer. |
| **Other Fees** | Charged separately on top of the call amount. Shown as a distinct line item. |
| **Investment Amount** | Treated as an investment sub-component within the call. Added to the call amount alongside capital fees. |

### How Fee Amounts Are Determined

**Standard (Account Entry) Method:**
- You specify a fee **name** (must match an account entry name in the commitment), a **start date**, and an **end date**.
- CapHive sums all non-cumulative account entries with that name whose reporting date falls within the start-to-end date range.
- This is the standard method for management fees, upfront fees, etc.

**Formula Method (support users only):**
- A custom formula (Ruby expression) can be written in the notes field of the call fee.
- The formula has access to `capital_call`, `capital_commitment`, and `capital_remittance` objects.
- A convenience method `management_fees_days(start_date, end_date)` is available for day-count calculations.

### Fee Audit

For every remittance, CapHive stores a detailed audit trail in JSON showing exactly which account entries contributed to each fee amount, including the name, date, and amount of each entry.

---

## Generating Remittances

When a capital call is saved (or when the percentage/amount changes), CapHive automatically generates one **Capital Remittance** for each eligible commitment.

### What "Eligible" Means

A commitment is eligible if:
- Its **fund close** is included in the capital call's selected fund closes.
- No remittance already exists for this commitment + capital call combination (generation is **idempotent** — it never creates duplicates).

### Generation Options

| Setting | Behaviour |
|---------|-----------|
| **Generate Remittances = Yes** | CapHive auto-generates remittances when the call is saved (default). |
| **Generate Remittances = No** | You can still add remittances manually or via upload. |
| **Remittances Verified = Yes** | Generated remittances are created pre-verified with status "Paid". A payment record is also created automatically. |

> **Tip:** After generation completes (which runs as a background job), refresh the capital call page to see the remittances list.

---

## Approving a Capital Call

Approval is a formal, one-way step that triggers notifications and locks the call against further changes.

### Pre-Approval Checklist

Before clicking Approve, complete these steps in order:

1. **Generate Documents** — use the Generate Documents action to create personalised call notices for each remittance.
2. **Review and approve notices** — open each remittance's Documents tab and approve the generated call notice. Unapproved notices block approval.
3. Confirm the due date, call amount, and investor list are correct. These cannot be changed after approval.

### Approval Steps

1. Open the capital call.
2. Click **Actions → Approve**.
3. The system checks that **all generated documents are approved** (any unapproved call notice on a remittance will block approval with an error).
4. Once approved, the capital call is locked and the `Approved By` user is recorded.

### What Happens After Approval

- If **Send Call Notice** is enabled, notification emails are sent to all investors with pending remittances (whose commitments do not have "Skip Call Notice" set).
- Approved call notice documents are attached to the email.
- The approved status is visible to investors in their portal.
- **Edit, Delete, Recompute Fees, and Generate Documents actions are all disabled** on an approved call. Unit Allocation remains available.

### Business Rule: Approval Cannot Proceed If

- Any generated document attached to a remittance of this call has not yet been approved.
- You must approve (or delete) those documents first.

---

## Capital Remittances

A Capital Remittance is the per-investor record for a capital call. It shows:

- How much the investor owes (`call_amount` = base call + capital fees + investment amount)
- Any other fees owed separately (`other_fee`)
- How much has been collected (`collected_amount`)
- The outstanding balance (`due_amount` = call_amount + other_fee − collected_amount)
- The current status (Pending, Paid, Overdue, Overpaid)

### Key Fields

| Field | Description |
|-------|-------------|
| **Folio ID** | The investor's commitment identifier. Must be unique within a capital call. |
| **Call Amount** | Total amount to be transferred (base + capital fees + investment amount). |
| **Capital Fee** | The portion of the call amount that represents fees. |
| **Other Fee** | Fees charged in addition to the call amount (e.g. penalty). |
| **Investment Amount** | Sub-component of the call treated as a pure investment. |
| **Collected Amount** | Running total of all received payments. |
| **Due Amount** | `Call Amount + Other Fee − Collected Amount` |
| **Committed Amount** | The investor's total committed amount at the time the remittance was created (snapshot). |
| **Remittance Date** | The date used for exchange rate lookups (defaults to the call date). |
| **Payment Date** | The date of the last received payment. Auto-set from payments. |
| **Verified** | Whether the fund team has confirmed the remittance. |
| **Notification Sent** | Whether the call notice email has been sent to this investor. |
| **Arrear Amount** | Any amount carried forward from a previous call. |
| **Percentage** | The effective percentage of commitment being called for this investor. |

### Folio Currency vs Fund Currency

Every remittance stores amounts in **two currencies**:
- **Folio Currency** (`folio_*` fields): The investor's denomination currency (from their commitment). This is the currency investors actually pay in.
- **Fund Currency** (`call_amount`, `collected_amount`, etc.): The fund's base currency. Amounts are converted using exchange rates on the remittance date.

---

## Remittance Status Lifecycle

```
  New Remittance Created
          │
          ▼
      ┌───────┐
      │PENDING│  ◄── Due date in the future
      └───────┘
          │
          │  Due date passes with unpaid balance
          ▼
      ┌───────┐
      │OVERDUE│  ◄── Checked daily by background job
      └───────┘

  When team verifies the remittance:
          │
          ├──── Folio Due Amount ≤ ±10 ──────────► ┌────┐
          │                                         │PAID│
          │                                         └────┘
          │
          ├──── Folio Due Amount < -10 ────────────► ┌─────────┐
          │                                           │OVERPAID │
          │                                           └─────────┘
          │
          └──── Folio Due Amount > 10 ──────────────► PENDING or OVERDUE
                                                      (based on due date)
```

### Status Rules

| Status | Condition |
|--------|-----------|
| **Pending** | Remittance is not verified. Due date is today or in the future. |
| **Overdue** | Remittance is not verified. Due date has passed. |
| **Paid** | Remittance is verified. Folio due amount is within ±10 (currency tolerance for rounding). |
| **Overpaid** | Remittance is verified. Folio due amount is less than −10 (more has been paid than owed). |

> **Tolerance:** A ±10 cent tolerance is applied when determining Paid vs outstanding, to account for rounding differences.

### Daily Status Update

A background job runs every day and automatically changes **Pending** remittances to **Overdue** when their capital call's due date has passed.

---

## Verifying a Remittance

Verification is the fund team's confirmation that the investor's payment has been received and validated.

### How to Verify

1. Open a Capital Remittance.
2. Click **Verify** (or use the verify action from the remittances list).
3. The system:
   - Recomputes call fees.
   - Recalculates the call amount.
   - Toggles the `verified` flag.
   - Recalculates the status (Paid / Overdue / Overpaid).
   - Updates the payment date.
   - Sends **payment received notifications** to the investor (if enabled and conditions are met — see [Notifications](#notifications)).
4. Clicking Verify again **un-verifies** the remittance (toggle behaviour).

### Business Rule: Unverify on New Payment

When a new payment is added to a remittance, the remittance is automatically **unverified**. The team must re-verify it after reviewing the new payment. This ensures the collected amount is always recalculated before final confirmation.

---

## Capital Remittance Payments

A Capital Remittance Payment records an actual money transfer from an investor.

### Creating a Payment

1. Open a Capital Remittance.
2. Click **New Payment**.
3. Fill in:

| Field | Description |
|-------|-------------|
| **Amount (Folio Currency)** | The amount received in the investor's currency. This is the primary amount. |
| **Payment Date** | The date the payment was received. |
| **Reference No** | Bank reference or transaction ID. Must be unique within the fund (if provided). |
| **Notes** | Optional internal notes. |
| **Payment Proof** | Upload a proof document (bank statement, screenshot, etc.). |

### Currency Conversion

- Payments are always entered in the **folio currency** (the investor's denomination).
- CapHive automatically converts the amount to the **fund currency** using the exchange rate for the payment date.
- If you provide both folio and fund currency amounts explicitly (e.g. via import), automatic conversion is skipped.

### Effect on Collected Amount

When a payment is saved, the remittance's `collected_amount` (and `folio_collected_amount`) are updated automatically via counter cache — no manual recalculation needed.

The **payment date on the remittance** is always updated to match the most recently dated payment.

### Deleting a Payment

A payment **cannot be deleted** if fund units have already been allocated based on that payment. You must adjust or remove the unit allocations first.

### Reference No Uniqueness

Reference numbers must be **unique within the fund**. Duplicate reference numbers are rejected.

---

## Multi-Currency Support

CapHive fully supports funds with investors in multiple currencies.

```
  Investor's Commitment Currency (Folio Currency)
          │
          │  Exchange rate on remittance date
          ▼
  Fund's Base Currency
          │
          │  Exchange rate on payment date (for tracking currency)
          ▼
  Tracking Currency (optional, for reporting)
```

- **Folio Currency**: Set at the commitment level. All investor-facing amounts use this currency.
- **Fund Currency**: The fund's base currency. Used for fund-level totals (call_amount, collected_amount on the Capital Call).
- **Tracking Currency**: An optional reporting currency used for cross-fund dashboards.

Amounts are always stored and displayed in all three currencies where applicable.

---

## Notifications

CapHive can send automated email notifications at several points in the capital call lifecycle.

### 1. Call Notice (to Investors)

**When sent:** When a capital call is **approved**, if "Send Call Notice" is enabled on the call.

**Who receives it:** The notification users of each investor associated with a pending remittance — provided:
- "Send Call Notice" flag is **Yes** on the capital call, AND
- The investor's commitment does not have **Skip Call Notice** set to Yes.

**What it contains:**
- Fund name and capital call name as subject.
- Any approved, generated documents attached to the remittance (e.g. call notice letter).
- Any manually uploaded documents attached to the remittance.
- If a custom notification template is configured for the call, the custom subject and body are used.

**Sending a Reminder:**
- Click **Send Reminder** on the capital call page.
- This re-sends the call notice email (with "Reminder:" prefix in the subject) to all investors whose remittances are still Pending or Overdue.
- Individual remittance reminders can also be triggered from the remittance detail page.
- If a notification was previously sent to an investor, subsequent sends are treated as reminders automatically.

### 2. Payment Received Notification (to Investors)

**When sent:** When a remittance is **verified** (or when a payment is added and the remittance is already verified).

**Who receives it:** The notification users of the investor.

**Conditions for sending:**
- "Send Payment Notification" flag is **Yes** on the capital call, AND
- The remittance is **verified**, AND
- The payment amount is positive, AND
- The payment notification has not already been sent for this payment.

**Subject:** "Remittance payment received by [Fund Name] for [Capital Call Name]"

**Deduplication:** Once a payment notification is sent, it is marked `payment_notification_sent = true` and will not be sent again.

### 3. Call Notice Skipping

Set **Skip Call Notice = Yes** on a capital commitment to permanently exclude that investor from all call notice and reminder emails for that commitment.

### Notification Summary Table

| Event | Trigger | Recipient | Controlled By |
|-------|---------|-----------|---------------|
| Call issued | Capital call approved | Investors with pending remittances | "Send Call Notice" on call + "Skip Call Notice" on commitment |
| Reminder | Manual click on "Send Reminder" | Investors with Pending/Overdue remittances | Same as above |
| Individual reminder | Manual from remittance page | Single investor | Same as above |
| Payment received | Remittance verified | Investor | "Send Payment Notification" on call |

---

## Document Generation

CapHive can automatically generate a personalised call notice document for each remittance. Document generation must be completed **before** the capital call is approved — the Generate Documents action is disabled on an approved call.

### How to Generate Documents

**For all remittances in a call:**
1. Open the Capital Call.
2. Click **Actions → Generate Documents**.
3. CapHive queues a background job that creates a document for each remittance using the **"Call Template"** template.
4. Refresh the page after a few minutes and review the generated documents on each remittance.

**For a single remittance:**
1. Open the Capital Remittance.
2. Click **Generate Docs**.
3. A document is generated for that remittance only.

### Prerequisites

- A template tagged **"Call Template"** must exist (either at the fund level or the commitment level).
- The investor must have a verified **KYC record**.

### Document Generation Per KYC

If the fund's `call_notice_on` setting is "kyc", a single document is generated per KYC (rather than per folio). This is useful when one investor has multiple commitments but should receive a single combined notice.

### Approving Generated Documents

After generation, each document must be individually **approved** before the capital call itself can be approved. Unapproved generated documents block the capital call approval step.

1. Open a Capital Remittance.
2. Click the **Documents** tab.
3. Review the generated call notice and click **Approve**.
4. Repeat for every remittance. Once all notices are approved, the capital call's Approve action will proceed.

> **Why this matters:** Only approved documents are attached to the investor notification email. Requiring explicit approval ensures the fund team has reviewed every notice before it reaches investors.

### No Re-Generation After Approval

Once a capital call is approved, the Generate Documents action is permanently disabled for that call. If a notice needs to be corrected after approval, the correction must be handled outside CapHive (e.g. a separate communication to the investor).

---

## Unit Allocation

If the fund issues units to investors based on their capital contributions:

### For All Remittances in a Call

1. Open the Capital Call.
2. Click **Allocate Units**.
3. CapHive queues a background job that allocates fund units to each remittance.

### For a Single Remittance

1. Open the Capital Remittance.
2. Click **Allocate Units**.

### Unit Allocation Logic

- If `collected_amount ≥ call_amount`: units are allocated for the **call amount** (capped at what was called).
- If `collected_amount < call_amount`: units are allocated for the **collected amount**.
- The amount already allocated is tracked, so partial allocations can be made progressively.

### Blocking Payment Deletion

If units have already been allocated for a payment, that payment **cannot be deleted** until the unit allocation is adjusted. The remittance itself also cannot be deleted while any of its payments have units allocated.

---

## Recomputing Fees

If fee account entries are updated after a capital call's remittances have already been generated, fees can go stale. Use **Recompute Fees** to refresh all remittances.

1. Open the Capital Call.
2. Click **Recompute Fees** (or **Recompute Call** button).
3. CapHive queues a background job that:
   - Recomputes call fees for every remittance.
   - Recalculates call amounts.
   - Updates statuses.
4. Any errors during recomputation are reported by email to the triggering user.

> **Note:** Recompute replaces computed amounts. If investors have already been notified of their amounts, consider whether re-notification is needed.

---

## Importing Data

### Importing Capital Calls

Use the **Import** feature to create multiple capital calls from a spreadsheet.

**Required columns:**

| Column | Description |
|--------|-------------|
| Fund | Fund name (must match exactly) |
| Name | Capital call name (must be unique within the fund) |
| Percentage Called | Percentage(s) — comma-separated for multiple closes |
| Due Date | Payment deadline |
| Call Date | Date the call is issued |
| Fund Closes | Comma-separated close names, or leave blank for "All" |
| Generate Remittances | Yes/No |
| Remittances Verified | Yes/No |
| Call Basis | "Percentage of Commitment", "Upload", or custom |
| Unit Price/Premium | Optional — format: `UnitType:Price:Premium,UnitType2:...` |
| Send Call Notice | Yes/No |
| Send Payment Notification | Yes/No |

**Business Rules:**
- A capital call with the same name in the same fund is rejected as a duplicate.
- If a "Fund Closes" column is provided with multiple closes, and "Percentage Called" contains comma-separated values, they are paired in order (First Close → first percentage, etc.).
- An "Exchange Rates" sheet may be included in the Excel file to set exchange rates for multi-currency funds.

### Importing Capital Remittances

**Required columns:**

| Column | Description |
|--------|-------------|
| Stakeholder | Investor name |
| Fund | Fund name |
| Capital Call | Capital call name |
| Call Amount (Inclusive Of Capital Fees, Folio Currency) | Total folio amount to call |
| Capital Fees (Folio Currency) | Fees in folio currency |
| Other Fees (Folio Currency) | Other fees in folio currency |
| Call Amount (Inclusive Of Capital Fees, Fund Currency) | Optional override in fund currency |
| Capital Fees (Fund Currency) | Optional |
| Other Fees (Fund Currency) | Optional |
| Investment Amount (Fund Currency) | Optional |
| Remittance Date | Date for FX rate lookups |
| Verified | Yes/No |
| Folio No | Investor's folio ID |

**Business Rules:**
- The investor must exist and have a commitment in the specified fund with the specified folio number.
- Import creates remittances with `call_basis = "Upload"`.

### Importing Capital Remittance Payments

**Required columns:**

| Column | Description |
|--------|-------------|
| Stakeholder | Investor name |
| Fund | Fund name |
| Capital Call | Capital call name |
| Amount (Folio Currency) | Payment amount in investor's currency |
| Currency | Folio currency code — must match commitment currency |
| Amount (Fund Currency) | Optional — if provided, disables auto conversion |
| Folio No | Investor's folio ID (or use Virtual Bank Account) |
| Virtual Bank Account | Alternative to Folio No |
| Verified | Yes/No — whether to verify the remittance after payment |
| Reference No | Bank transaction reference |
| Payment Date | Date of payment |
| Notes | Optional |
| Update Only | Yes/No — if Yes, only updates an existing matching payment |

**Business Rules:**
- Either Folio No or Virtual Bank Account must be provided.
- Currency must match the commitment's folio currency.
- Reference numbers must be unique within the fund.
- If `Update Only = Yes` and no matching payment exists, the row is skipped.
- If a payment already exists with matching fund, remittance, amount, reference, and date, a new one will not be created (unless `Update Only = Yes` to force an update).
- After all rows are processed, counter caches are fixed and remittances are optionally verified in bulk.

---

## Key Computations Reference

### Call Amount (Percentage of Commitment)

```
folio_call_amount = (percentage / 100) × folio_committed_amount
                  + folio_capital_fee + folio_investment_amount

call_amount = convert(folio_call_amount, folio_currency → fund_currency)
            + capital_fee + investment_amount
```

### Call Amount (Account Entry Basis)

```
percentage = investor's account entry value for the call basis name
             (most recent entry on or before due_date)

computed_amount = total_amount_to_be_called × (percentage / 100)

call_amount = computed_amount + capital_fee + investment_amount
folio_call_amount = convert(call_amount, fund_currency → folio_currency)
```

### Call Amount (Upload)

```
call_amount = convert(folio_call_amount, folio_currency → fund_currency)
              [if not already provided in fund currency]

computed_amount = call_amount − capital_fee

percentage = min(folio_call_amount / folio_committed_amount × 100, 100%)
             [capped at 100%, floored at −100%]
```

### Due Amount

```
due_amount = call_amount + other_fee − collected_amount
folio_due_amount = folio_call_amount + folio_other_fee − folio_collected_amount
```

The **folio due amount** is used for status determination (Paid/Overpaid/Pending/Overdue).

### Percentage Raised (Capital Call Level)

```
percentage_raised = (collected_amount / call_amount) × 100
```

### Status Determination

```
IF verified:
  IF |folio_due_amount| ≤ 10    → Paid
  IF folio_due_amount < −10     → Overpaid
  IF due_date > today           → Pending
  ELSE                          → Overdue
ELSE:
  → Pending
```

### Counter Caches (Auto-Aggregated)

The following totals are maintained automatically and updated whenever remittances or payments change:

| Field | Aggregated From |
|-------|----------------|
| Capital Call `call_amount` | Sum of all remittance `call_amount_cents` |
| Capital Call `collected_amount` | Sum of verified remittance `collected_amount_cents` |
| Capital Call `capital_fee` | Sum of all remittance `capital_fee_cents` |
| Capital Call `other_fee` | Sum of all remittance `other_fee_cents` |
| Fund `call_amount` | Sum of all remittance `call_amount_cents` |
| Fund `collected_amount` | Sum of verified remittance `collected_amount_cents` |
| Commitment `call_amount` | Sum of remittances for that commitment |
| Commitment `collected_amount` | Sum of verified remittances for that commitment |

---

## Frequently Asked Questions

**Q: Can I add a remittance manually for an investor who was missed in generation?**
Yes. From the capital call's Remittances tab, click **New Remittance** and select the investor and commitment. The call amount will be computed automatically based on the call basis.

**Q: What happens if I change the percentage after remittances have already been generated?**
For call basis "Percentage of Commitment", CapHive will re-queue remittance generation. Existing remittances are not updated automatically — use **Recompute Fees** to refresh existing remittances.

**Q: Can one investor have multiple remittances for the same capital call?**
No. Each folio ID can only appear once per capital call. The folio ID is unique per call.

**Q: What if an investor overpays?**
The remittance status becomes **Overpaid** (folio due amount < −10). The excess is visible in the due_amount field. You can handle this by recording a negative adjustment or carrying it forward.

**Q: Can I send the call notice without approving the call?**
No. The call notice is sent only when the capital call is approved (or when you manually trigger a reminder from the remittance page for an already-approved call).

**Q: What does "Skip Call Notice" on a commitment do?**
It permanently suppresses call notice and reminder emails for that specific commitment. This is useful for internal or fund-of-funds investors who do not need investor communications.

**Q: Can I edit a capital call after it has been approved?**
No. Once approved, the capital call is fully locked. Edit, Delete, Recompute Fees, and Generate Documents are all disabled. This protects the integrity of the amounts and notices already sent to investors. If a correction is needed after approval, contact your administrator.

**Q: Can I generate documents after the call is approved?**
No. Document generation is only available before approval. The intended workflow is: generate documents → approve each notice → then approve the capital call. Once approved, any corrections to notices must be handled outside CapHive.

**Q: What if I forget to approve the documents before approving the call?**
The system will block the approval and display an error: "There are unapproved documents for the remittances of this call. Please approve them first." Open each remittance's Documents tab, approve the notice, and try again.

**Q: Can I edit a remittance after it is verified?**
Yes, but editing will typically trigger a re-verification step (the unverify-on-change logic applies to payment changes, not manual edits). Always re-verify after making changes to ensure the status reflects the current state.

**Q: What is the difference between "Call Date" and "Due Date"?**
- **Call Date** is when the call is issued and is used as the default remittance date for FX lookups.
- **Due Date** is the payment deadline. Remittances become "Overdue" if unpaid after this date.

**Q: Can I delete a capital call?**
Only if the call has not been approved. Approved calls are locked and cannot be deleted. For unapproved calls, deletion is also blocked if any remittance has allocated fund units — remove unit allocations first.

**Q: What does "Recompute Fees" do exactly?**
It re-reads all account entries within the call fee date ranges and recalculates each investor's capital_fee, other_fee, and investment_amount. Call amounts, folio amounts, and statuses are all updated. Use this after correcting or backdating fee entries. Note: Recompute Fees is not available on an approved call.
