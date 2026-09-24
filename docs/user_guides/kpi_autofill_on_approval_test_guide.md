# KPI Autofill on Approval — QA Test Guide

This guide walks through the steps to verify the **KPI Autofill on Approval** feature. The fix ensures that when a fund manager approves monthly KPIs, the system automatically recomputes Quarterly, YTD, and Annual cumulative values — no manual "Recompute Cumulative" needed.

> **Branch:** `feature/kpi-autofill-on-approval`
> **What changed:** Three files — `KpiApproveService`, `KpiCumulateJob`, and the `KpiCumulative` concern.

---

## Table of Contents

1. [Background — What Was the Bug?](#1-background--what-was-the-bug)
2. [Prerequisites](#2-prerequisites)
3. [Test on Current Staging (Before Deployment)](#3-test-on-current-staging-before-deployment)
4. [Test After Branch Deployment](#4-test-after-branch-deployment)
5. [Regression Checks](#5-regression-checks)
6. [Expected Results Summary](#6-expected-results-summary)
7. [Glossary](#7-glossary)

---

## 1. Background — What Was the Bug?

**Before the fix:**
- Upload monthly KPIs for a portfolio company (e.g., Jan, Feb, Mar 2025 Revenue).
- Approve the KPIs.
- Refresh the page.
- **Quarter (Q1) and YTD columns show "N/A"** — the cumulative values are not computed.
- The fund manager must manually go to **Actions → Recompute Cumulative** to populate them.

**After the fix:**
- Approve the KPIs.
- Wait 5–10 seconds for the background job to finish.
- Refresh the page.
- **Quarter, YTD, and Year columns are automatically populated** — no manual recompute needed.

The "Recompute Cumulative" button still works as a fallback, but should no longer be necessary after approval.

---

## 2. Prerequisites

Before starting, ensure you have:

| Requirement | Details |
| :--- | :--- |
| **Login** | A fund admin account with the **approver** or **company_admin** role |
| **KPI Mappings** | At least one KPI mapping with **Autofill = Cumulate** (e.g., Revenue under Income Statement) for the test portfolio company |
| **Monthly data** | At least 3 months of data in the same quarter (e.g., Jan, Feb, Mar) for a "cumulate" KPI |
| **Sidekiq running** | On staging, Sidekiq processes background jobs; ensure it is running |

### How to check KPI Mapping setup

1. Go to **Stakeholders → View Stakeholders** → select the portfolio company.
2. Open the **Kpi Mapping** tab.
3. Look for a KPI (e.g., Revenue) where the **Autofill** column says **Cumulate**.
4. If no mapping has Autofill = Cumulate, edit one and set it — or create a new test mapping.

### How to check Autofill value for a KPI mapping

The **Autofill** column in the KPI Mapping grid shows one of:
- **Cumulate** — sums monthly values into Quarter/YTD/Year (this is what we are testing)
- **Forward Fill** — carries the latest value forward
- **Compute** — applies a formula
- **NA** — no autofill (manual entry only)

---

## 3. Test on Current Staging (Before Deployment)

> **Purpose:** Confirm the bug exists on staging so you have a "before" baseline.

### Test A: Confirm Bug — Approve Does NOT Auto-Populate Cumulative

1. **Pick or create a test portfolio company** on staging.
   - Ensure it has a KPI mapping with **Autofill = Cumulate** (e.g., Revenue).

2. **Upload monthly KPIs** for 3 months in the same quarter.
   - Example: upload Jan 2025, Feb 2025, Mar 2025 Revenue values.
   - Go to the portfolio company → **KPI Reports** → create/edit a report → upload the workbook.

3. **Approve the KPIs.**
   - Open the Grid View → **Actions → View Including Staged**.
   - Click **Approve All Staged** (or approve individually).

4. **Wait 10 seconds and refresh the page.**

5. **Check the Grid View:**
   - Look at the **Q1 2025** column for Revenue.
   - Look at the **YTD** and **Year** columns.
   - **Expected (bug):** These columns should show **N/A** or be empty.

6. **Now click Actions → Recompute Cumulative.**

7. **Wait 10 seconds and refresh again.**

8. **Check the Grid View again:**
   - **Expected:** Q1, YTD, and Year columns should now show calculated values.
   - This confirms the manual recompute still works, but approval alone did not trigger it.

**Screenshot this result** — it serves as the "before" baseline.

### Test B: Confirm Non-Autofill KPIs Are Unaffected

1. Find a KPI where **Autofill = NA** (e.g., Employee Count, if configured that way).
2. Upload and approve monthly values for it.
3. **Expected:** No Quarter/YTD/Year row should be created for this KPI — same as before.

---

## 4. Test After Branch Deployment

> **Purpose:** Verify the fix works — approval should now auto-populate cumulative values.

### Test 1: First-Time Upload and Approval

1. **Create a new test portfolio company** (or use a clean one with no existing KPI data).
   - Ensure at least one KPI mapping has **Autofill = Cumulate**.

2. **Upload monthly KPIs** for 3 months in the same quarter (e.g., Apr, May, Jun 2025).

3. **Approve all the KPIs** (Approve All Staged or individually).

4. **Wait 5–10 seconds, then hard refresh the page** (Ctrl+Shift+R / Cmd+Shift+R).

5. **Check the Grid View:**

   | Column | Expected |
   | :--- | :--- |
   | Apr 2025 | The value you uploaded |
   | May 2025 | The value you uploaded |
   | Jun 2025 | The value you uploaded |
   | **Q2 2025** | **Sum of Apr + May + Jun** (auto-populated) |
   | **YTD** | **Sum of all approved months in the year so far** (auto-populated) |
   | **Year** | **Same as YTD if only these months exist** (auto-populated) |

6. **Pass criteria:** Quarter, YTD, and Year values appear **without** clicking Recompute Cumulative.

### Test 2: Value Change and Re-Approval

This tests that updating a monthly value and re-approving propagates correctly to cumulative columns.

1. **Using the same portfolio company** from Test 1 (cumulative values already visible).

2. **Edit one monthly KPI value.**
   - In the Grid View, click on a cell (e.g., Jun 2025 Revenue), change the value.
   - Example: change Jun Revenue from 30,000,000 to 50,000,000.
   - The cell should show as **Pending** (unapproved staged value).

3. **Approve the changed value.**

4. **Wait 5–10 seconds, then hard refresh.**

5. **Check:**

   | What to verify | Expected |
   | :--- | :--- |
   | Jun 2025 | Updated to the new value (50,000,000) |
   | Q2 2025 | Updated (Apr + May + new Jun) |
   | YTD | Updated to reflect the new Jun value |
   | Percentage change (MoM) | Recalculated based on the new value |

6. **Pass criteria:** All cumulative and percentage-change values update after approval + refresh — no Recompute needed.

### Test 3: Bulk Approval (Approve All)

1. Upload KPIs for **multiple months and multiple KPI metrics** (e.g., Revenue + EBITDA for Jul, Aug, Sep).
2. Use **Actions → Approve All Staged**.
3. Wait 5–10 seconds, then hard refresh.
4. **Check:** Quarter, YTD, and Year values appear for **all** KPI metrics that have Autofill = Cumulate.

### Test 4: Mark Reviewed Path

1. Upload KPIs for a portfolio company.
2. On the KPI Report page, click **Mark Reviewed** (if available on the report).
3. Wait 5–10 seconds, then hard refresh.
4. **Check:** Cumulative values should auto-populate, same as Approve All.

### Test 5: Non-Autofill KPIs (No Side Effects)

1. Find or create a KPI with **Autofill = NA** (e.g., Employee Count).
2. Upload and approve monthly values.
3. **Expected:** No Quarter/YTD/Year values should be created for this KPI.
4. **Pass criteria:** Only KPIs with Autofill = Cumulate get cumulative values.

### Test 6: Recompute Cumulative Still Works

1. After running Tests 1–5, go to **Actions → Recompute Cumulative** on any portfolio company.
2. **Expected:** Existing cumulative values remain correct (not duplicated or wiped). No errors.
3. **Pass criteria:** The button is still functional as a fallback.

---

## 5. Regression Checks

These verify that the fix did not break existing functionality.

| Area | What to check | Expected |
| :--- | :--- | :--- |
| **Upload workflow** | Upload a new KPI workbook → Submit → values staged | Works as before |
| **Approval** | Approve individual KPI, Approve All Staged, reject | Works as before |
| **Dashboards** | After approval, check the portfolio dashboard for the KPI charts | Values reflect approved data |
| **Percentage changes** | MoM and YoY columns in the grid | Calculated correctly after approval |
| **Forward Fill KPIs** | Approve a KPI with Autofill = Forward Fill | Latest value carried forward to Quarter/YTD |
| **Unapprove** | Unapprove a KPI → cumulative values should NOT revert | Cumulative stays (same behavior as before) |
| **AI agents / reports** | If applicable, verify the portfolio assistant still reads correct KPI data | Shows latest approved values |

---

## 6. Expected Results Summary

| Scenario | Before Fix (Current Staging) | After Fix (New Branch) |
| :--- | :--- | :--- |
| Approve monthly KPIs → refresh | Quarter/YTD/Year = **N/A** | Quarter/YTD/Year = **auto-populated** |
| Change value + re-approve → refresh | Quarter/YTD/Year = **stale or N/A** | Quarter/YTD/Year = **updated** |
| Recompute Cumulative button | Works (populates values) | Still works (no change) |
| Non-autofill KPIs (Autofill = NA) | No cumulative values created | No cumulative values created (same) |
| Percentage changes after approval | May need Recompute | **Auto-calculated** on approval |

---

## 7. Glossary

| Term | Meaning |
| :--- | :--- |
| **KPI** | Key Performance Indicator — a tracked metric (e.g., Revenue, EBITDA) |
| **KPI Report** | A container for KPI data for a portfolio company for a specific period (e.g., "Mar 2025 Actuals") |
| **KPI Mapping** | Configuration that defines which KPIs a portfolio company should report, including the Autofill type |
| **Autofill** | Automatic calculation of cumulative values: Cumulate (sum), Forward Fill (carry forward), Compute (formula), or NA (none) |
| **Staged / Unapproved** | KPI data that has been uploaded but not yet approved — shown in orange with a Pending badge |
| **Approved** | KPI data promoted by an approver — used by dashboards, charts, and reports |
| **Cumulate** | Autofill mode that sums monthly values into Quarter/YTD/Year totals |
| **Quarter** | Sum of the 3 months in that quarter (e.g., Q1 = Jan + Feb + Mar) |
| **YTD (Year to Date)** | Running total of all approved months from the start of the fiscal year to the current month |
| **Year** | Full-year total — same as YTD once all 12 months are in |
| **MoM** | Month-over-Month percentage change |
| **YoY** | Year-over-Year percentage change |
| **Recompute Cumulative** | Manual button under Actions that recalculates all cumulative values for a portfolio company |
| **Hard Refresh** | Ctrl+Shift+R (Windows/Linux) or Cmd+Shift+R (Mac) — reloads the page bypassing browser cache |

---

> **Note:** After approval, the page needs a manual refresh (F5 or Ctrl+R) to show the updated cumulative values. This is the existing behavior for all background jobs in the system — the approval triggers an async job that runs in a few seconds. A future enhancement may add auto-refresh, but for now the expected flow is: **Approve → wait 5–10 seconds → refresh → values appear**.
