# Value Bridge User Guide

The **Value Bridge** (also known as a Valuation Bridge or Waterfall) is a powerful tool in IRM that allows you to decompose the change in a portfolio company's Enterprise Value between two valuation dates. It helps identify how much value was created through revenue growth, margin improvement, and multiple expansion.

---

## 1. Overview

The Value Bridge calculates the impact of specific financial metrics on the total change in Enterprise Value (EV). By default, it tracks:
- **Revenue Growth**: Impact of change in top-line revenue.
- **EBITDA Margin**: Impact of operational efficiency (margin) changes.
- **Valuation Multiple**: Impact of market sentiment or sector re-rating.

It presents these changes in a **Waterfall Chart**, showing the step-by-step transition from the "Entry" (Initial Valuation) to the "Exit" (Final Valuation).

---

## 2. Setup & Configuration

To use the Value Bridge, your environment must be configured with specific custom fields on the **Valuation** form.

### Step 1: Initialize Custom Fields
The system relies on custom fields and calculations defined on the **Valuation** form. Below is a standard configuration (as used in active projects):

| Field Name | Type | Meta Data / Formula |
| :--- | :--- | :--- |
| `revenue` | Number | (Manual Input) |
| `ebitda_margin`| Number | (Manual Input) |
| `ebitda` | Calculation | `revenue * ebitda_margin / 100` |
| `valuation_multiple` | Number | (Manual Input) |
| `fx_rate` | Calculation | Fetches latest FX rate for USD to INR |
| `enterprise_value` | Calculation | `ebitda * valuation_multiple * fx_rate` |
| `net_debt` | Number | (Manual Input) |
| `equity_value` | Calculation | `enterprise_value - net_debt` |

### Step 2: Configure Bridge Columns
You can customize which metrics appear as "steps" in the bridge.
1. Navigate to **Entity Settings**.
2. Locate the **Value Bridge Columns** setting.
3. Enter a comma-separated list of field names (e.g., `Revenue, EBITDA Margin, Valuation Multiple, FX Rate`).
   - *Note: These names must match the display names of your custom fields exactly.*

---

## 3. Real-World Example (Entity 157)

In a live environment (e.g., Entity 157), the Value Bridge is configured to handle complex scenarios including currency fluctuations.

### Advanced Formulas Used:
- **Dynamic EBITDA Lookup**: Instead of manual entry, EBITDA can be pulled directly from KPIs:
  `entity.kpis.joins(:kpi_report).where(name: "EBITDA", ...).last&.value || 0`
- **Automated FX Rates**: The `fx_rate` field automatically pulls the exchange rate as of the valuation date:
  `entity.exchange_rates.where(from: "USD", to: "INR", as_of: ..valuation_date).last&.rate || 0`
- **Total EV Calculation**:
  `(json_fields["ebitda"].to_f * json_fields["valuation_multiple"].to_f * json_fields["fx_rate"].to_f).round(2)`

This configuration allows the Value Bridge to show an **"FX Rate"** step, isolating the impact of currency movement from business performance.

---

## 4. How to Generate a Value Bridge

Once the fields are configured and data is entered:

1. **Navigate to Valuations**: Go to the portfolio company's valuation section.
2. **Select Valuations**: Choose two valuations for the same investment instrument:
   - **Initial Valuation**: Usually the entry date or start of a period.
   - **Final Valuation**: Usually the most recent valuation or exit date.
3. **Open Value Bridge**: Click on the **Value Bridge** action.
4. **View Results**:
   - **Table**: Shows the raw numbers for each step.
   - **Waterfall Chart**: Visualizes the increase (green) or decrease (orange) contributed by each metric.

---

## 5. Advanced Features

### MOIC Mode (Multiple of Invested Capital)
You can toggle the **MOIC** option when generating the bridge. This will normalize all values by the initial Enterprise Value, showing the contribution of each metric as a multiple (e.g., how many "turns" of MOIC each metric contributed).

### Custom Bridge Steps
If you have additional metrics (e.g., `Net Debt` or `Market Share`), you can add them to the **Value Bridge Columns** in settings. The service will automatically include them as intermediate steps in the calculation.

---

## 6. Troubleshooting

- **Missing Data**: Ensure both selected valuations have values for all fields used in the bridge calculations.
- **Calculation Errors**: Check the formulas in the custom field definitions. The bridge relies on `enterprise_value` being correctly calculated from the other metrics.
- **Instrument Mismatch**: The bridge can only be calculated between two valuations of the same investment instrument.
