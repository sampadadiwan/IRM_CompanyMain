# Tracking Currency Implementation & Conversion Logic

This document summarizes the technical implementation and conversion logic for the `TrackingCurrencyJob`.

## 1. Job Overview
The [`TrackingCurrencyJob`](app/packs/funds/funds/jobs/tracking_currency_job.rb) is a background job responsible for updating "tracking currency" amounts across various financial entities within a Fund. It handles conversions for account entries, remittances, distributions, commitments, and portfolio investments.

### Job Triggering Logic
The job can be invoked in four ways:
1. **Specific Fund (`fund_id`):** Updates a single fund.
2. **Specific Entity (`entity_id`):** Updates all funds for an entity (e.g., when exchange rates change).
3. **Global/Daily:** Updates all funds where `tracking_currency <> currency`.
4. **Retroactive Force (`force: true`):** Recalculates all tracking amounts even if they were previously set.

### Technical Implementation Details
- **Batch Processing:** Records are grouped by date (e.g., `reporting_date`, `payment_date`) to minimize exchange rate lookups and allow for high-performance `update_all` operations.
- **Resilience:** Errors (such as missing exchange rates) are caught at the date-group level. This allows the job to continue processing other records even if one conversion fails.
- **Audit Logging:** Wrapped in `Audited.audit_class.as_user("TrackingCurrencyJob")`.
- **Chewy Strategy:** Uses `Chewy.strategy(:sidekiq)` for async search index updates.

---

## 2. Conversion Logic Summary

| Entity (Table) | Fields Converted | Conversion Basis (Date) | Exchange Rate Calculation |
| :--- | :--- | :--- | :--- |
| **Account Entries** | `amount_cents` | `reporting_date` | `amount_cents * rate` (unless "Percentage" in name) |
| **Remittance Payments** | `amount_cents` | `payment_date` | `amount_cents * rate` |
| **Remittances** | `call_amount_cents`, `collected_amount_cents` | `remittance_date` | `call_amount_cents * rate`, `collected_amount_cents` = sum of tracking payments (Includes unverified) |
| **Distribution Payments** | `net_payable_cents`, `gross_payable_cents`, `reinvestment_with_fees_cents` | `payment_date` | `[Field] * rate` |
| **Commitment Adjustments** | `amount_cents` | `as_of` | `amount_cents * rate` |
| **Capital Commitments** | `committed_amount_cents`, `orig_committed_amount_cents` | `commitment_date` | `[Field] * rate` |
| **Portfolio Investments** | `amount_cents` (Investment), `fmv_cents` (FMV) | `investment_date` (Amt), `valuation_date` (FMV) | `[Field] * rate`. FMV is refreshed on every run. |

### Key Technical Rules:
- **Exchange Rate Source:** Rate between **Fund's base currency** and **Tracking currency** on the "Conversion Basis" date.
- **Account Entry Exception:** If the name includes **"Percentage"**, the tracking amount is kept 1:1 with the base amount.
- **Portfolio FMV:** Always refreshed to the latest valuation available to ensure real-time accuracy in tracking currency.
- **Error Reporting:** Missing exchange rates are collected into a `missing_rates` list and reported in the final error notification.
- **Precision:** Conversions are performed on "cents" (integers).
