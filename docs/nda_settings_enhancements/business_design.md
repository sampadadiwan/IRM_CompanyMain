# NDA Settings Enhancements — Business Design

## Purpose

A set of usability and correctness improvements to the NDA settings workflow in the Data Room. These changes address four issues that GPs encounter when managing NDAs across folder hierarchies: an invisible actions menu, missing resign control on inherited NDA overrides, lack of expiry visibility, and inability to edit expired NDAs.

## Issues Addressed

### 1. Actions Dropdown Clipped on Single-Investor Row

**Problem:** On the NDA Status dashboard, when only one investor row exists in the table, the kebab (three-dot) Actions menu is clipped and invisible. The dropdown renders behind the table boundary because the table's CSS enforces `overflow: hidden`.

**Expected behavior:** The dropdown renders fully visible regardless of row count, overlapping the table boundary if needed.

### 2. Resign Checkbox When Overriding an Inherited NDA

**Problem:** When a parent folder has an active NDA that a child folder inherits, and LPs have already accepted that inherited NDA on the child folder, clicking "Set Own NDA" on the child treats it as a brand-new NDA with no history. The GP has no way to decide whether those LPs should re-sign or keep their existing acceptance.

**Expected behavior:** The NDA settings form shows a resign checkbox with the count of LPs who have already signed the inherited NDA. The GP can:
- **Check the box** — require all LPs to re-sign the new NDA (fresh start)
- **Leave unchecked** (default) — carry forward their existing acceptance so they retain access without re-signing

**User story:**
**As a** GP setting up a folder-specific NDA on a child folder that previously inherited its parent's NDA,
**I want to** choose whether existing signatories must re-sign,
**so that** I don't unnecessarily block LP access when only the NDA scope changed (not the terms).

### 3. Validity Type Locking and Expiry Summary

**Problem (locking):** After LPs have accepted an NDA, the GP can freely switch the validity type (e.g., from "Until Revoked" to "Fixed Period"). This retroactively changes how expiry is computed for existing acceptances, potentially blocking LPs who were told their acceptance was permanent.

**Expected behavior:** Once any LP has accepted, the validity type radio buttons are locked. The GP can still extend within the same type (longer period, later date) but cannot switch types. To change type, the GP must upload a new NDA version with re-sign required.

**Problem (expiry summary):** When editing an NDA with "Fixed Period" or "Specific Date" validity, the GP sees the type label but has no context on when existing acceptances actually expire.

**Expected behavior:**
- **Fixed period:** Shows "Earliest expiry: [date] · Latest expiry: [date]" below the period dropdown. Each LP's expiry is their `accepted_at + validity_days`, so the range helps the GP understand the window.
- **Specific date:** Shows "All NDAs expire on: [date]" since all LPs share the same expiry.

### 4. Expired NDA Cannot Be Edited

**Problem:** When an NDA with "Specific Date" validity has expired (the date is in the past), clicking "Save Settings" does nothing — no error message, no server response. The GP cannot extend the expiry or change any other settings. This is because a hidden date input fails the browser's built-in validation (value < min), but since the input is not focusable, the browser cannot show the error tooltip.

**Expected behavior:** The form submits successfully. If the GP changes the date, it must be in the future. If the GP is editing other fields without touching the date, the save goes through regardless of the expired date.

## UI Behavior Summary

| Scenario | What GP Sees |
|---|---|
| NDA Status with 1 investor row | Actions dropdown renders fully, not clipped |
| Set Own NDA on child with signed inherited NDA | Info banner: "X investors have already signed the inherited NDA" + resign checkbox |
| Edit NDA after LPs accepted | Validity type radios disabled with lock icon and explanation |
| Edit NDA with fixed_period validity | Earliest/latest expiry dates shown below the period dropdown |
| Edit NDA with specific_date validity | "All NDAs expire on: [date]" shown below the date field |
| Edit NDA with expired specific_date | Form submits; date field min is set to tomorrow for renewal |

## Benefits

- **Reduced LP friction:** GPs can override inherited NDAs without unnecessarily forcing re-sign
- **Data integrity:** Validity type cannot be changed retroactively after acceptances exist
- **Better decision-making:** Expiry summaries give GPs the context to time NDA revisions
- **Unblocked workflow:** Expired NDAs can be edited and renewed instead of being stuck
