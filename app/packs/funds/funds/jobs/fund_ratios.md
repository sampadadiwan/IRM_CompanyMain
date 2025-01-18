Here’s a detailed breakdown of the fund ratios computed by the provided code and the steps/cashflows used to calculate each ratio. This is formatted for a financial analyst.

---

### Fund Ratios and Their Computation Steps

#### **1. XIRR (Extended Internal Rate of Return)**
   - **Steps:**
     1. Collect buy cashflows:
        - All capital remittances (negative cashflows).
     2. Collect sell cashflows:
        - All capital distributions (positive gross payable cashflows minus reinvestment amounts).
     3. Add the fund's **Fair Market Value (FMV)** at the end date.
     4. Include cash balances:
        - Add cash in hand and net current assets.
     5. Adjust for carry if calculating net IRR:
        - Subtract estimated carry (if `net_irr` is true).
     6. Compute XIRR using the accumulated cashflows.
   - **Outputs:**
     - XIRR percentage.
     - Associated cashflows (optional).

---

#### **2. DPI (Distributed to Paid-In Capital)**
   - **Steps:**
     1. Calculate total distributions:
        - Sum gross payable capital distributions minus reinvestment amounts.
     2. Calculate total collected capital:
        - Sum all verified capital remittances.
     3. Compute DPI:
        \[
        DPI = \frac{\text{Distributions}}{\text{Collected Capital}}
        \]
   - **Outputs:**
     - DPI value as a multiple (e.g., "1.5x").

---

#### **3. RVPI (Residual Value to Paid-In Capital)**
   - **Steps:**
     1. Calculate the residual value:
        - Sum FMV, net current assets, and cash in hand.
     2. Divide by collected capital:
        \[
        RVPI = \frac{\text{Residual Value}}{\text{Collected Capital}}
        \]
   - **Outputs:**
     - RVPI value as a multiple (e.g., "1.2x").

---

#### **4. TVPI (Total Value to Paid-In Capital)**
   - **Steps:**
     1. Add DPI and RVPI:
        \[
        TVPI = DPI + RVPI
        \]
   - **Outputs:**
     - TVPI value as a multiple (e.g., "2.7x").

---

#### **5. Fund Utilization**
   - **Steps:**
     1. Calculate total invested capital:
        - Sum the cost of all portfolio investments.
     2. Calculate committed capital:
        - Sum all committed amounts.
     3. Compute utilization:
        \[
        \text{Utilization} = \frac{\text{Total Investment Costs}}{\text{Committed Capital}}
        \]
   - **Outputs:**
     - Fund utilization as a percentage (e.g., "85%").

---

#### **6. Portfolio Value to Cost**
   - **Steps:**
     1. Calculate total FMV:
        - Sum the FMV of all portfolio investments.
     2. Calculate total investment cost:
        - Sum the cost of all portfolio investments.
     3. Compute value to cost:
        \[
        \text{Value to Cost} = \frac{\text{FMV}}{\text{Total Investment Costs}}
        \]
   - **Outputs:**
     - Portfolio value to cost as a multiple (e.g., "1.3x").

---

#### **7. Paid-In to Committed Capital**
   - **Steps:**
     1. Calculate total paid-in capital:
        - Sum all verified capital remittances.
     2. Divide by total committed capital:
        \[
        \text{Paid-In to Committed Capital} = \frac{\text{Collected Capital}}{\text{Committed Capital}}
        \]
   - **Outputs:**
     - Ratio as a multiple (e.g., "0.9x").

---

#### **8. Gross Portfolio IRR**
   - **Steps:**
     1. Collect buy cashflows:
        - Sum all portfolio investment costs (negative cashflows).
     2. Collect sell cashflows:
        - Sum all portfolio investment sales (positive cashflows).
     3. Add the FMV of the portfolio at the end date.
     4. Compute IRR using these cashflows.
   - **Outputs:**
     - Gross portfolio IRR as a percentage (e.g., "12.5%").

---

#### **9. Portfolio Company IRR**
   - **Steps:**
     1. For each portfolio company:
        - Collect cashflows specific to the company:
          - Buys (negative cashflows).
          - Sells (positive cashflows).
          - FMV of the company at the end date.
        - Compute XIRR for these cashflows.
   - **Outputs:**
     - XIRR for each portfolio company as a percentage.

---

#### **10. Portfolio Company Value to Cost**
   - **Steps:**
     1. For each portfolio company:
        - Calculate total FMV.
        - Calculate total cost of portfolio investments.
        - Compute value to cost:
        \[
        \text{Value to Cost} = \frac{\text{FMV}}{\text{Total Investment Costs}}
        \]
   - **Outputs:**
     - Value to cost for each portfolio company as a multiple.

---

#### **11. Aggregate Portfolio IRR**
   - **Steps:**
     1. For each Aggregate Portfolio Investment (API):
        - Collect cashflows specific to the API:
          - Buys (negative cashflows).
          - Sells (positive cashflows).
          - FMV at the end date.
        - Compute XIRR for these cashflows.
   - **Outputs:**
     - XIRR for each API as a percentage.

---

#### **12. Aggregate Portfolio Value to Cost**
   - **Steps:**
     1. For each API:
        - Calculate total FMV.
        - Calculate total cost of portfolio investments.
        - Compute value to cost:
        \[
        \text{Value to Cost} = \frac{\text{FMV}}{\text{Total Investment Costs}}
        \]
   - **Outputs:**
     - Value to cost for each API as a multiple.

---

This breakdown provides a step-by-step understanding of the computed fund ratios, making it easier for a financial analyst to interpret the calculations and assess their financial significance. Let me know if you need further clarification on any specific computation!