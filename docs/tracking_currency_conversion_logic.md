# Tracking Currency Conversion Logic Summary

This document outlines the entities processed by the `TrackingCurrencyJob`, the specific fields being converted, the date used to determine the exchange rate, and the rate applied.

| Entity (Table) | Fields Converted to Tracking Currency | Conversion Basis (Date) | Exchange Rate Calculation |
| :--- | :--- | :--- | :--- |
| **Account Entries** | `amount_cents` | `reporting_date` | `amount_cents * rate` (unless "Percentage" in name) |
| **Remittance Payments** | `amount_cents` | `payment_date` | `amount_cents * rate` |
| **Remittances** | `call_amount_cents`, `collected_amount_cents` | `remittance_date` | `[Field] * rate` |
| **Distribution Payments** | `net_payable_cents`, `gross_payable_cents`, `reinvestment_with_fees_cents` | `payment_date` | `[Field] * rate` |
| **Commitment Adjustments** | `amount_cents` | `as_of` (date) | `amount_cents * rate` |
| **Capital Commitments** | `committed_amount_cents`, `orig_committed_amount_cents` | `commitment_date` | `[Field] * rate` |
| **Portfolio Investments** | `amount_cents` (Investment Amount), `fmv_cents` (Fair Market Value) | `investment_date` (for Amount), `valuation_date` (for FMV) | `[Field] * rate` |

## Key Technical Notes for BA:
*   **Exchange Rate Source:** The "rate" is derived from the exchange rate between the **Fund's base currency** and its **Tracking currency** on the specific date listed in the "Conversion Basis" column.
*   **Account Entry Exception:** If an Account Entry name includes the word **"Percentage"**, the tracking amount is kept identical to the base amount (1:1), bypassing the exchange rate.
*   **Portfolio FMV:** The Fair Market Value (FMV) conversion uses the date of the **latest valuation** available for that investment.
*   **Precision:** All conversions are performed on "cents" (integer values) to ensure financial accuracy.
