# Release Notes — Fund Unit Transfer Improvements

**Audience:** Fund Managers, Investor Relations, Fund Administrators
**Area:** Fund Units → Transfer Fund Units

---

## What Changed

This release strengthens the Fund Unit Transfer feature with improvements to reliability, data accuracy, and usability. No existing workflows have changed — all transfers work exactly as before, but the system now handles edge cases more safely and provides clearer feedback when something goes wrong.

---

## Improvements

### 1. Concurrent Transfer Protection

**What it means for you:** If two members of your team attempt to transfer units from the same investor folio at exactly the same moment, the system now safely handles the collision. The first transfer proceeds normally; the second receives a clear message — *"Another transfer is in progress for this commitment. Please try again."* — rather than producing corrupted or duplicate records.

**Before:** Simultaneous transfers on the same folio could silently overwrite each other.
**After:** Only one transfer proceeds at a time; the second is cleanly rejected with a retry prompt.

---

### 2. Clearer Validation Errors for Transfer Ratio

**What it means for you:** If you accidentally enter an invalid transfer ratio (such as 0 or a number above 100), you now see a specific, plain-English error message rather than a generic failure.

| What you enter | Error message you see |
|---|---|
| 0 (or a negative number) | *"Transfer ratio must be greater than 0."* |
| More than 100 | *"Transfer ratio must be 100 or less."* |

**Before:** An invalid ratio produced a generic error with no guidance.
**After:** The specific field and the acceptable range are called out directly.

---

### 3. More Accurate Financial Arithmetic

**What it means for you:** All amount calculations during a transfer (unit prices, premiums, capital call splits, fee splits, distribution splits) now use high-precision decimal arithmetic internally. This eliminates tiny rounding discrepancies that could appear when working with large amounts or non-round transfer ratios (e.g. transferring exactly one-third of a stake).

**Before:** Calculations used floating-point numbers, which can produce rounding errors (e.g. a split totalling 99.99 instead of 100.00).
**After:** All arithmetic uses exact decimal precision; totals balance correctly to the cent.

---

### 4. Safer Partial Failures

**What it means for you:** If the system encounters a problem partway through a transfer (for example, if unit records cannot be created due to a data issue), it now rolls back all changes from that step completely rather than leaving a partially written record in the database. The transfer is marked as failed and no partial data is committed.

**Before:** A mid-transfer error could leave the seller's unit debit recorded without the corresponding buyer credit.
**After:** Either the full transfer succeeds, or nothing is written — no partial states.

---

### 5. Running Totals Refreshed After Every Transfer

**What it means for you:** Unit balances, payment totals, and committed capital figures shown on each investor's folio are now guaranteed to be accurate immediately after a transfer completes. Previously, these summary figures could briefly lag behind the actual records.

**Before:** Counter totals (shown on the folio summary) could be stale immediately after a transfer.
**After:** Totals are recalculated as part of the transfer process itself, so figures are accurate the moment you land on the folio page.

---

### 6. "Account Entries Not Pro-Rated" — Clarified Behaviour

**What it means for you:** When you mark specific fee types as "not pro-rated" during a transfer, those entries are now explicitly documented to work as follows: the buyer receives a **full copy** of the entry at its original amount, and the seller's entry is also **kept at its original amount** — both folios show the full amount for that line item after the transfer.

This is appropriate for one-time, indivisible costs (e.g. a setup fee). All other account entries continue to be split proportionally by the transfer ratio.

**Before:** The behaviour of excluded entries was not documented and could be misunderstood.
**After:** The user guide describes this clearly, with guidance on when to use it.

---

## Updated Documentation

The **Fund Unit Transfers User Guide** (`docs/user_guides/fund_unit_transfers_user_guide.md`) has been updated to reflect all of the above, including:

- Revised pre-transfer checklist
- Transfer ratio range clarified as 1–100
- Expanded guidance on "Account Entries Not Pro-Rated"
- Complete validation error reference table (now includes ratio errors)
- FAQ updated with commitment-date behaviour explanation

---

## No Action Required

These changes are fully backward-compatible. Existing transfers, historical records, and current workflows are unaffected. No data migration is needed.

---

*Release prepared: 2026-05-18*
