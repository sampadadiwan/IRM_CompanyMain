# User Guide: Dynamic Ratio Formulas

This guide explains how to use the **Ratio Formulas** feature to customize financial ratio calculations (XIRR, MOIC, DPI, TVPI, etc.) by incorporating specific account entries.

---

## 1. Overview
By default, the system calculates ratios using standard components (Capital Calls, Distributions, FMV, Cash in Hand, and Net Current Assets). The **Ratio Formulas** feature allows you to **supplement** these calculations by defining rules that "Add" or "Reduce" specific **Account Entry** values. These formulas are applied **in addition** to the standard components.

Rules are defined **per Fund** and can target different levels of calculation (Fund, Folio, or Portfolio Company).

---

## 2. Accessing Ratio Formulas
1.  Navigate to the **Funds** list and select a fund.
2.  Click on the **Actions** button in the top right.
3.  Select the **Account Entries** sub-menu.
4.  Click on **Ratio Formulas**.
5.  Here you can view, create, edit, or delete rules for the selected fund.

---

## 3. Creating a Rule
When you create a "New Ratio Formula," you define the following attributes:

| Field | Description |
| :--- | :--- |
| **Level** | **Fund**: Affects fund-level ratios. <br> **Folio**: Affects individual investor (Capital Commitment) ratios. <br> **PortfolioCompany**: Affects asset-level (Portfolio Company) ratios. |
| **Ratios** | Select one or more ratios this rule should affect (e.g., XIRR, DPI, MOIC). |
| **Action** | Defines how the amount is applied (see Actions section below). |
| **Account Entry Names**| Select the specific account entries to include. You can select multiple names. |
| **Period** | **All**: Aggregates all non-cumulative entries up to the end date. <br> **As-on**: Takes only the single latest non-cumulative entry as of the end date. |

### Available Actions
*   **For XIRR / IRR**:
    *   `add_cashflow`: Treats the entry as an **Inflow** (Positive cash flow) on the reporting date.
    *   `reduce_cashflow`: Treats the entry as an **Outflow** (Negative cash flow/Cost) on the reporting date.
*   **For Static Ratios (DPI, MOIC, RVPI, TVPI, PIC)**:
    *   `add_numerator`: Adds the amount to the top of the ratio (e.g., Total Value or Distributions).
    *   `reduce_numerator`: Subtracts from the top.
    *   `add_denominator`: Adds the amount to the bottom of the ratio (e.g., Total Cost or Paid-In Capital).
    *   `reduce_denominator`: Subtracts from the bottom.

---

## 4. How the Logic Works
*   **Sequential Application (Additive)**: Ratio formulas are applied **in addition** to the standard terminal value components (FMV, Cash in Hand, Net Current Assets, and Estimated Carry). Defining a formula does not disable the automatic inclusion of these components.
*   **Fallback**: If a fund has **no rules** defined for "Cash In Hand" or "Net Current Assets," the system uses the default hardcoded logic. As soon as you define a rule for a specific ratio (e.g., DPI), the system switches to your custom rules for that ratio.
*   **Filtering**: The system only picks up **non-cumulative** account entries to avoid double-counting.
*   **Currency**: Amounts are automatically converted to the appropriate currency (Tracking Currency or Base Currency) using the exchange rate on the entry's reporting date.

---

## 5. Practical Examples

### Example 1: Including "Non-Deal Expenses" in Fund XIRR
If you want your Fund XIRR to be net of certain expenses stored in account entries:
*   **Level**: Fund
*   **Ratios**: XIRR
*   **Action**: `reduce_cashflow` (Treats it as an outflow)
*   **Account Entry Names**: "Non Deal Expenses", "Legal Fees"
*   **Period**: All (Include every expense event)

### Example 2: Adding "Mutual Fund Investments" to Portfolio Value
If the fund has assets in a side-car mutual fund that should count towards the "Residual Value" in TVPI and MOIC:
*   **Level**: Fund
*   **Ratios**: TVPI, MOIC
*   **Action**: `add_numerator` (Increases the "Value" side)
*   **Account Entry Names**: "Mutual Fund Investment"
*   **Period**: As-on (Only use the latest valuation of the mutual fund)

### Example 3: Reducing Folio XIRR with "Temp Income Distribution"
If investors receive temporary distributions that should reduce their return in their individual Folio XIRR:
*   **Level**: Folio
*   **Ratios**: XIRR
*   **Action**: `add_cashflow` (Treats it as an inflow/return to the investor)
*   **Account Entry Names**: "Temp income distribution"
*   **Period**: All

---

## 6. Multi-Fund Aggregation
When calculating ratios for an **Entity** (Multi-fund) or a **Cross-fund Scenario**:
1.  The system looks at every fund included in the aggregation.
2.  It applies each fund's specific **Ratio Formulas** to that fund's entries.
3.  It converts the adjusted results into the Entity's base currency.
4.  It sums everything up to produce the final Entity-level ratio.

This ensures that if Fund A includes expenses in its XIRR but Fund B does not, the Entity-level XIRR will correctly reflect those choices.
