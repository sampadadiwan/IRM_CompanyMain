# Tracking Currency Calculation Guide

The **Tracking Currency Job** ensures that all financial data in a Fund is available in its designated "Tracking Currency" (e.g., USD or EUR) in addition to its Base Currency. This allows for consistent reporting across different funds.

## 1. What is Computed?
The job converts various financial records from the **Fund Base Currency** to the **Tracking Currency**. The following fields are calculated:

| Category | Computed Field(s) | Business Meaning |
| :--- | :--- | :--- |
| **Account Entries** | `tracking_amount` | The value of the entry in tracking currency. |
| **Remittance Payments** | `tracking_amount` | The actual amount received from an investor in tracking currency. |
| **Remittances (Calls)** | `tracking_call_amount` | The total amount requested in the capital call. |
| | `tracking_collected_amount` | The total amount actually collected (sum of payments). |
| **Distributions** | `tracking_net_payable` | The net amount paid out to the investor. |
| | `tracking_gross_payable` | The total distribution before deductions. |
| | `tracking_reinvestment_with_fees` | Amount reinvested including associated fees. |
| **Commitment Adjustments** | `tracking_amount` | Any adjustments to investor commitments. |
| **Capital Commitments** | `tracking_committed_amount` | The current total committed amount. |
| | `tracking_orig_committed_amount` | The original amount committed by the investor. |
| **Portfolio Investments** | `tracking_amount` | The original investment cost. |
| | `tracking_fmv` | The current Fair Market Value (FMV) of the investment. |

---

## 2. Which Dates are Used?
The system uses specific "Exchange Rate Dates" to ensure the conversion reflects the market conditions at the time of the transaction:

*   **Account Entries:** Uses the `reporting_date`.
*   **Remittance Payments:** Uses the `payment_date` (when the money was actually received).
*   **Remittances (Calls):** Uses the `remittance_date` (the original date of the call).
*   **Distributions:** Uses the specific `payment_date` of the distribution.
*   **Commitment Adjustments:** Uses the `as_of` date of the adjustment.
*   **Capital Commitments:** Uses the `commitment_date` (when the agreement was signed/effective).
*   **Portfolio Investments:**
    *   For **Investment Cost**: Uses the `investment_date`.
    *   For **Fair Market Value (FMV)**: Uses the `valuation_date` of the *latest* available valuation.

---

## 3. Important Rules & Logic
*   **Daily Updates:** The job typically runs daily for all funds where the tracking currency differs from the base currency.
*   **Percentage Exception:** Entries representing a percentage (e.g., "Ownership %") are **not** converted. They maintain a 1:1 ratio because percentages are currency-neutral.
*   **Dynamic FMV Refresh:** Unlike original investment costs which are usually set once, the **Tracking FMV** is refreshed every time the job runs. This ensures it always reflects the most recent valuation and the latest exchange rates for that valuation date.
*   **Error Handling:** If an exchange rate is missing for a specific date, the system skips that record and notifies administrators so the missing rate can be added.
*   **Retroactive Corrections:** Administrators can "force" a recalculation. This is useful if historical exchange rates were corrected and the tracking amounts need to be updated to match.
