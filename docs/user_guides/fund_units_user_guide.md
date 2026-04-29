# Fund Units User Guide

This guide explains how CapHive models investor ownership through fund units — from initial setup of unit classes, through issuance on capital calls and redemption on distributions, to secondary transfers between investors.

---

## Table of Contents

1. [What Are Fund Units?](#what-are-fund-units)
2. [Concepts and Terminology](#concepts-and-terminology)
3. [Fund Unit Settings — Defining Unit Classes](#fund-unit-settings--defining-unit-classes)
4. [Assigning Unit Types to Investors](#assigning-unit-types-to-investors)
5. [Setting Unit Prices on Capital Calls](#setting-unit-prices-on-capital-calls)
6. [Setting Unit Prices on Distributions](#setting-unit-prices-on-distributions)
7. [Generating Units from a Capital Call](#generating-units-from-a-capital-call)
8. [Redeeming Units from a Distribution](#redeeming-units-from-a-distribution)
9. [The Full Unit Lifecycle](#the-full-unit-lifecycle)
10. [Fund Unit Transfers](#fund-unit-transfers)
11. [What a Transfer Does Under the Hood](#what-a-transfer-does-under-the-hood)
12. [Counter Caches and Cap Table Rollups](#counter-caches-and-cap-table-rollups)
13. [Viewing and Filtering Fund Units](#viewing-and-filtering-fund-units)
14. [Importing Unit Settings from a Spreadsheet](#importing-unit-settings-from-a-spreadsheet)
15. [Importing Fund Units from a Spreadsheet](#importing-fund-units-from-a-spreadsheet)
16. [Frequently Asked Questions](#frequently-asked-questions)

---

## What Are Fund Units?

Fund units represent an investor's **proportional ownership stake** in a fund. When an investor pays into a capital call, they receive units. When a distribution returns capital, some units are redeemed. The total units held by each investor at any point reflects their current ownership in the fund.

CapHive automates this process:

```
Capital Call → Investor Pays → Units Issued  (+quantity)
Distribution → Capital Returned → Units Redeemed (−quantity)
Transfer → Investor Sells Stake → Units Move Between Folios
```

The unit count provides an auditable, per-investor cap table that links every unit back to the underlying cash transaction that created or destroyed it.

---

## Concepts and Terminology

| Term | Meaning |
|------|---------|
| **Unit Type / Class / Series** | The category of unit (e.g. "Class A", "Series I"). Each fund can have multiple classes with different fee structures. |
| **Unit Price** | The base price per unit set on a capital call or distribution. |
| **Premium** | An additional amount per unit charged over the base price (common in some fund structures). |
| **Amount** | `Quantity × (Price + Premium)` — the total monetary value represented by a unit record. |
| **Issue Date** | The date the units were issued. For call-based units: the later of the payment date and the call due date. |
| **GP Units** | Units held by the General Partner rather than limited partners. Flagged separately on the setting. |
| **Transfer Ratio** | The percentage of an investor's units being moved to another investor in a secondary transfer. |
| **Folio** | An investor's capital commitment record within a fund. Each folio has one unit type. |

---

## Fund Unit Settings — Defining Unit Classes

Before any units can be issued, you must define the **unit classes** available in the fund. Each unit class is a **FundUnitSetting**.

### Where to find them

Navigate to **Fund → Unit Settings**.

### Fields

| Field | Required | Description |
|-------|----------|-------------|
| **Class/Series Name** | Yes | The name of the unit class (e.g. "Class A", "Series I"). Must match one of the unit types configured on the fund. Unique per fund. Max 40 characters. |
| **Management Fee %** | No | Management fee percentage associated with this class. Informational — used for display and reporting; not automatically applied to calculations. |
| **Setup Fee %** | No | One-time setup fee percentage. Informational. |
| **Carry %** | No | Carried interest percentage for this class. Informational — used for display and carry computation references. |
| **ISIN** | No | The International Securities Identification Number for this unit class, if applicable. |
| **GP Units** | No | Tick this if units of this class are held by the General Partner rather than limited partners. |

> **Important:** The **Class/Series Name** must exactly match one of the unit type values defined in the fund's configuration (`fund.unit_types`). If a name is entered that is not in the fund's allowed list, the setting will not save.

### Validation rules

- Name must be unique within the fund.
- Name must be one of the fund's allowed unit types.

---

## Assigning Unit Types to Investors

Each capital commitment (folio) must have a **unit type** assigned before units can be issued. This tells CapHive which class of units to issue when that investor pays a call.

Set the unit type on the **Capital Commitment** record (the folio). The unit type must match one of the fund's unit settings.

---

## Setting Unit Prices on Capital Calls

When you create or edit a capital call, you can set **unit prices** — the price and premium per unit for each unit class. These prices are stored on the call and used during unit allocation.

Unit prices are set as a JSON structure on the call, keyed by unit type:

```
{
  "Class A": { "price": 1000, "premium": 50 },
  "Class B": { "price": 800,  "premium": 0  }
}
```

> If a unit type has no entry in the call's unit prices, no units will be issued for investors of that type, even if they are verified and paid.

---

## Setting Unit Prices on Distributions

Similarly, capital distributions can have unit prices defined for redemptions. The price here is used to calculate how many units to redeem per unit of capital returned.

```
{
  "Class A": 1050,
  "Class B": 850
}
```

(Distributions use a single price value per class, not price + premium.)

---

## Generating Units from a Capital Call

Once a capital call is approved and remittances are verified, you trigger unit allocation from the call.

### Prerequisites (all must be true for a remittance to receive units)

| Condition | What it checks |
|-----------|---------------|
| Remittance is **verified** | The payment has been confirmed |
| Collected amount is **positive** | Money was actually received |
| Capital call has **unit prices** configured | Price and premium exist for the investor's unit type |
| Capital commitment has a **unit type** assigned | The folio knows which class to issue |
| Units have **not already been allocated** for this remittance | Prevents double-issuance (idempotent) |

### Quantity formula

```
Quantity = Collected Amount ÷ (Price + Premium)
```

If Price + Premium = 0, no units are issued (division by zero is prevented).

### Issue date rule

```
Issue Date = max(Payment Date, Call Due Date)
```

This ensures that units are never backdated before the call was due, even if the investor paid early.

### What gets created

For each qualifying remittance, one **FundUnit** record is created:

| Field | Value |
|-------|-------|
| `unit_type` | The folio's unit type |
| `quantity` | Positive number (issuance) |
| `price` | From the call's unit prices |
| `premium` | From the call's unit prices |
| `amount` | `quantity × (price + premium)` |
| `total_premium` | `premium × quantity` |
| `issue_date` | `max(payment_date, due_date)` |
| `owner` | The capital remittance that triggered it |
| `reason` | Descriptive label (defaults to the call name) |

### Notifications

After allocation runs, you receive a success notification. If any remittances fail (e.g. missing unit type), you receive an error notification and a detailed error report is emailed to your entity.

---

## Redeeming Units from a Distribution

When a capital distribution is completed and payments are marked as such, you trigger unit **redemption**.

### Prerequisites

| Condition | What it checks |
|-----------|---------------|
| Distribution payment is **completed** | Payment has been processed |
| `cost_of_investment_with_fees` is **positive** | There is a cost basis to redeem against |
| Distribution has **unit prices** configured | Price exists for the investor's unit type |
| Capital commitment has a **unit type** assigned | The folio knows which class to redeem |
| Units have **not already been redeemed** for this payment | Prevents double-redemption (idempotent) |

### Quantity formula

```
Quantity = −(Cost of Investment with Fees ÷ Price)
```

The quantity is **negative** — redemptions reduce the investor's unit balance.

### Issue date

The issue date on redemption units is set to the distribution payment's `payment_date`.

### What gets created

| Field | Value |
|-------|-------|
| `unit_type` | The folio's unit type |
| `quantity` | Negative number (redemption) |
| `price` | From the distribution's unit prices |
| `amount` | `quantity × price` (negative) |
| `issue_date` | `payment_date` |
| `owner` | The capital distribution payment |

---

## The Full Unit Lifecycle

```
1. Setup
   ├── Define unit classes (FundUnitSetting): name, fees, carry, ISIN
   ├── Assign unit_type to each capital commitment (folio)
   └── Configure fund.unit_types with allowed class names

2. Capital Call
   ├── Set unit prices on the call (price + premium per class)
   ├── Investors pay → remittances verified
   └── Generate Units → one FundUnit per verified remittance
       quantity = amount ÷ (price + premium)   [positive]
       issue_date = max(payment_date, due_date)

3. Distribution
   ├── Set unit prices on the distribution (price per class)
   ├── Distribution payments marked completed
   └── Redeem Units → one FundUnit per completed payment
       quantity = −(cost_of_investment_with_fees ÷ price)  [negative]
       issue_date = payment_date

4. Secondary Transfer (optional)
   └── Move a % of units from one folio to another
       (see Fund Unit Transfers section)

5. Reporting
   └── total_fund_units_quantity on each folio = net units held
       = sum of all positive and negative FundUnit records
```

---

## Fund Unit Transfers

A **Fund Unit Transfer** moves some or all of one investor's units to another investor within the same fund. This is used for secondary market transactions — when an LP sells (or gifts) part of their stake to another party.

### Accessing the transfer form

Navigate to **Capital Commitment (Folio) → Transfer Fund Units**.

### Transfer fields

| Field | Required | Description |
|-------|----------|-------------|
| **From Folio** | Auto-filled | The selling investor's folio (pre-filled from the commitment you navigated from) |
| **To Folio** | Yes | The buying investor's folio — must be in the same fund |
| **Transfer Ratio** | Yes | What percentage of the from-folio's units are being transferred (0–100) |
| **Transfer Date** | Yes | The effective date of the transfer |
| **Price** | Yes | Price per unit at the time of transfer |
| **Premium** | Yes | Premium per unit at the time of transfer (0 if none) |
| **Transfer Account Entries** | No | Tick to also transfer the proportional share of the from-folio's account entries to the to-folio |
| **Account Entries Not Pro-Rated** | No | Comma-separated list of account entry names that should be **copied in full** to the to-folio rather than pro-rated by the transfer ratio |

### Transfer validations

The system checks these conditions before proceeding:

| Condition | Rule |
|-----------|------|
| Same fund | Both the from-folio and to-folio must belong to the same fund |
| Same unit type | Both folios must have the same unit type assigned |
| Sufficient units | The from-folio must hold at least as many units as the transfer quantity |
| Commitment date order | The to-commitment's commitment date must be **on or before** the from-commitment's commitment date. This is required because the transfer creates adjustments backdated to the from-commitment's commitment date — the to-commitment must already exist at that date. |

If any validation fails, the transfer is marked as **Failed** and the error is recorded.

---

## What a Transfer Does Under the Hood

A transfer is a multi-step operation that touches several records simultaneously. All steps run inside database transactions where possible.

### Step 1 — Issue transfer unit records

Two FundUnit records are created:

```
From-folio:  quantity = −(from_folio.total_units × transfer_ratio)
             transfer = "out"
             price    = transfer price
             premium  = transfer premium
             issue_date = transfer_date

To-folio:    quantity = +(same as above)
             transfer = "in"
             price    = transfer price
             premium  = transfer premium
             issue_date = transfer_date
```

### Step 2 — Transfer account entries (if requested)

For every account entry on the from-folio:

```
Standard entries:
  From-folio entry amount  ×= (1 − transfer_ratio)   [reduced]
  New to-folio entry amount = original × transfer_ratio [created]

Excluded entries (listed in "Account Entries Not Pro-Rated"):
  From-folio entry is unchanged
  New to-folio entry = full original amount (not pro-rated)
```

Each entry records a `transfer_id` (a unique UUID for this transfer run) and the original amount so the change can be audited.

### Step 3 — Transfer remittances

Every capital remittance on the from-folio is split:

```
From-folio remittance:
  call_amount      ×= (1 − transfer_ratio)
  collected_amount ×= (1 − transfer_ratio)
  committed_amount ×= (1 − transfer_ratio)
  (+ all folio/fee/tracking variants)

New to-folio remittance (copy):
  call_amount      = original × transfer_ratio
  collected_amount = original × transfer_ratio
  committed_amount = original × transfer_ratio
  (+ all folio/fee/tracking variants)
```

Each remittance's payments are also split by the same ratio.

### Step 4 — Transfer distribution payments

Every distribution payment on the from-folio is split by the same transfer_ratio / retained_ratio logic:

```
gross_payable, net_payable, income, cost_of_investment, reinvestment,
units_quantity, folio_amount — all scaled by transfer_ratio for the new record
                              and by (1 − transfer_ratio) for the original
```

### Step 5 — Commitment adjustments

Two `CommitmentAdjustment` records are created:

```
To-folio adjustment:   +folio_committed_amount × transfer_ratio
                        (as_of = from_commitment.commitment_date)

From-folio adjustment: −folio_committed_amount × transfer_ratio
                        (as_of = from_commitment.commitment_date)
```

These adjustments update the committed capital figures for both folios to reflect the transfer.

### Step 6 — Counter culture recalculation

After all records are created and updated, CapHive recalculates all counter caches for the fund to ensure totals are accurate:
- Remittance payment totals
- Remittance collected amounts
- Distribution payment amounts
- Fund unit quantities
- Commitment totals
- Commitment adjustment totals

### Transfer status

The FundUnitTransfer record is updated to `completed` on success, or `Failed: <reason>` if any validation or step fails.

---

## Counter Caches and Cap Table Rollups

Every FundUnit record automatically rolls up to:

| Target | Field | What it tracks |
|--------|-------|----------------|
| **Capital Commitment** | `total_fund_units_quantity` | Net units held by this investor (sum of all +/− quantities) |
| **Capital Commitment** | `total_units_premium_cents` | Total premium paid for units by this investor |
| **Capital Commitment** | `total_units_amount_cents` | Total amount of positive unit records only (issuances, not redemptions) |
| **Fund** | `total_units_premium_cents` | Total premium across all investors in the fund |

The `total_fund_units_quantity` on each folio is the live unit balance — updated automatically whenever a unit is issued, redeemed, or transferred.

---

## Viewing and Filtering Fund Units

### Opening the unit list

Navigate to **Fund → Fund Units** to see all unit records for a fund.

### Available filters

| Filter | Description |
|--------|-------------|
| `fund_id` | Restrict to a specific fund |
| `capital_commitment_id` | Show only units for one folio |
| `investor_id` | Show only units for one investor |
| `import_upload_id` | Show units from a specific import batch |
| `owner_id` / `owner_type` | Filter by the transaction that created the units (e.g. `CapitalRemittance`, `CapitalDistributionPayment`) |

### Ransack column filters

| Attribute | Filter options |
|-----------|---------------|
| `unit_type` | Partial match |
| `quantity` | Numeric comparison |
| `price` | Numeric comparison |
| `premium` | Numeric comparison |
| `issue_date` | Date range |
| `reason` | Partial match |

### Reading the list

- **Positive quantity** = units issued (from a capital call payment)
- **Negative quantity** = units redeemed (from a distribution payment)
- **transfer = "in"** = received via secondary transfer
- **transfer = "out"** = sent via secondary transfer

The sum of all quantity values for a folio equals the current `total_fund_units_quantity` shown on the commitment.

---

## Importing Unit Settings from a Spreadsheet

To create or update unit class definitions in bulk, use the FundUnitSetting import.

### Spreadsheet columns

| Column | Required | Description |
|--------|----------|-------------|
| **Fund** | Yes | Fund name — must match exactly |
| **Class/Series** | Yes | Unit class name (must match fund's allowed unit types) |
| **Management Fee %** | No | Percentage value (e.g. `2.0`) |
| **Setup Fee %** | No | Percentage value |
| **Carry %** | No | Percentage value |
| **Gp Units** | No | `Yes` if these are GP-held units |
| **Isin** | No | ISIN code |
| **Update Only** | No | `Yes` = update existing record; fail if not found. Leave blank = create new; fail if already exists. |

### Duplicate handling

- If **Update Only** is blank and a setting with the same name already exists for that fund, the row is skipped with an error.
- If **Update Only** is `Yes` and no existing setting is found, the row is skipped with an error.

---

## Importing Fund Units from a Spreadsheet

To create unit records in bulk (e.g. for migrating historical data), use the FundUnit import.

### Spreadsheet columns

| Column | Required | Description |
|--------|----------|-------------|
| **Fund** | Yes | Fund name |
| **Folio No** | Yes | Investor's folio ID within the fund |
| **Call / Distribution Name** | Yes | Name of the capital call (for positive quantities) or title of the distribution (for negative quantities) |
| **Unit Type** | Yes | Must match the folio's assigned unit type |
| **Quantity** | Yes | Positive = issuance; negative = redemption |
| **Price** | Yes | Price per unit |
| **Premium** | No | Premium per unit (defaults to 0) |
| **Reason** | No | Description of why these units were issued/redeemed |
| **Issue Date** | Yes | Date the units were issued |
| **Update Only** | No | `Yes` = update existing record; blank = create new |

### Owner resolution

- **Positive quantity** → the import looks up a **CapitalRemittance** matching the folio + call name.
- **Negative quantity** → the import looks up a **CapitalDistributionPayment** matching the folio + distribution title.

The found remittance or payment becomes the `owner` of the new FundUnit.

### Duplicate handling

- If a unit already exists for the same owner and the same issue date, the row is skipped.
- If **Update Only** is `Yes`, it updates the existing unit.

---

## Frequently Asked Questions

**What happens if I generate units twice for the same capital call?**
CapHive checks whether a FundUnit already exists for each remittance. If units are already allocated, the remittance is skipped. Generating again is safe — it only fills in any remittances that were not yet processed.

**Why did some investors not receive units even though they paid?**
Check the following on the investor's folio and the capital call:
1. Is the remittance **verified**? Units are only issued for verified remittances.
2. Does the folio have a **unit type** assigned?
3. Does the capital call have **unit prices** for that unit type?

All three must be true.

**Can I manually adjust a unit record?**
Yes — navigate to the unit record and edit it. However, changing the quantity or price will also update the counter caches on the folio automatically.

**What if the transfer ratio is 100%? Does the from-folio end up with zero units?**
Yes. A 100% transfer moves all units, all remittances, all distribution payments, and all account entries (if selected) to the to-folio. The from-folio's net unit balance will be zero after the transfer.

**Can I transfer between investors in different funds?**
No. The from-folio and to-folio must both belong to the same fund.

**Can I transfer between investors with different unit types?**
No. The unit type must match on both folios. If the two investors hold different classes, the transfer will fail validation.

**Why does the to-commitment's date matter for a transfer?**
The transfer creates backdated commitment adjustments as of the from-commitment's original commitment date. The to-commitment must already exist at that date — meaning its commitment date must be on or before the from-commitment's date. If the to-commitment is newer, the adjustment would be backdated before the to-commitment's start date, which is not allowed.

**Do unit transfers affect XIRR and distribution calculations?**
Yes. Because the transfer splits the underlying remittances and distribution payments proportionally, the to-folio's XIRR and DPI/RVPI/TVPI calculations will include the transferred history going forward. Regenerate fund ratios after a transfer to see updated performance metrics.

**Where can I see the history of a transfer?**
Each FundUnit created by a transfer has `transfer = "in"` or `transfer = "out"` on it. The remittances and account entries modified by the transfer contain a `transfer_id` in their JSON fields, along with the original amounts and notes, providing a full audit trail.

**Why are unit prices not automatically pulled from FundUnitSettings?**
The fee percentages on FundUnitSettings (management fee, carry, etc.) are informational — they are used for display and reporting. The actual **price and premium per unit** must be set on each capital call individually, since the NAV and unit price can change with each drawdown.
