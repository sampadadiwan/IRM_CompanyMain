# Deals: User Guide

## Overview

The Deals module is where you define a fundraising process for a company, track investors in that process, and manage what appears in the Deal Investors table.

This guide focuses on three recent behaviors:

1. `deal_investor_status` is a first-class deal field (required).
2. `enable_notifications` is a first-class deal field (default: enabled).
3. The Deal Investors table status options come from the parent deal.

---

## Part 1: Deal Setup Fields

When you create or edit a deal, these fields now control downstream behavior:

| Field | Required | What it controls |
|---|---|---|
| **Deal Investor Statuses** (`deal_investor_status`) | Yes | Defines the allowed status choices users can select for investors in this deal. |
| **Enable Notifications** (`enable_notifications`) | No (defaults to enabled) | Enables/disables stage-move notifications for this deal. |
| **Grid Columns** (`grid_columns`) | No | Controls which columns appear in Deal Investors table and where they are placed. |

### Deal Investor Statuses (required)

- Enter as comma-separated values in the Deal form.
- Example: `New, Interested, In Progress, Committed, Complete, Declined`
- If left blank, the deal cannot be saved.

This field is now stored directly on `deals.deal_investor_status` and no longer depends on legacy JSON storage.

### Enable Notifications (toggle)

- Enabled by default for new deals.
- If disabled, stage-move notifications are skipped for that deal.
- The toggle is saved on `deals.enable_notifications`.

This gives deal-level control over whether stage transitions should send notification emails.

---

## Part 2: Deal Investor Status Dropdown Source

In Deal Investors forms and table flows, the **Status** choices are deal-specific.

The dropdown source is:

1. `deal.deal_investor_status` (preferred)
2. Fallback to system defaults only if the deal has no configured statuses

This means each deal can run its own status taxonomy without affecting other deals.

### What users see

- If Deal A defines `New, DD, IC, Closed`, users on Deal A only see those options.
- If Deal B defines `Active, Pending, Declined`, users on Deal B only see those options.

---

## Part 3: Deal Investors Table Size and Columns

The Deal Investors table shape is controlled from **Edit Deal -> Grid Columns**.

Each configured row stores:

- `field` (data key)
- `label` (display name)
- `position` (`start` or `end`)

### Behavior

- If Grid Columns is empty: standard/default columns are shown.
- If Grid Columns is configured: the table uses your selected columns and labels.
- Position controls whether a configured column appears toward the beginning or end of the table.

This is the "table size" control point: adding/removing grid column rows increases or reduces the set of visible configurable columns.

---

## Part 4: Recommended Admin Workflow

1. Create/edit a deal.
2. Set **Deal Investor Statuses** before adding investors.
3. Confirm **Enable Notifications** based on whether stage-move emails should be active.
4. Configure **Grid Columns** to match what your team wants in the Deal Investors table.
5. Add investors and track progress with deal-specific statuses.

---

## Quick Validation Checklist

- Deal form saves only when Deal Investor Statuses is non-empty.
- Deal Investors status dropdown reflects the parent deal's status list.
- Stage moves do not send notifications when Enable Notifications is off.
- Grid column config changes are reflected in Deal Investors table layout.

---

## Related Docs

- Deal steps and activity lifecycle: `docs/modules/deals/deal_steps_user_guide.md`
- Grid configuration behavior in end-user guide: `docs/user_guides/deals_management_user_guide.md`
