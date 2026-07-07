# Deal: README

## Purpose

This README is a quick entry point for deal configuration behavior and links to the full guides.

Use it when you need a short operational summary; use the full guides for field-level and lifecycle details.

---

## What Changed

### 1) Deal Investor Statuses are deal-level and required

- Field: `deal_investor_status`
- Stored directly on `deals` table
- Deal cannot be saved with an empty status list

### 2) Notifications are deal-level and toggleable

- Field: `enable_notifications`
- Default: `true`
- When disabled, stage-move notifications are skipped for that deal

### 3) Deal Investor status options come from the deal

- In Deal Investors UI, Status dropdown values are sourced from the parent deal configuration
- This lets each deal maintain its own status vocabulary

### 4) Deal Investors table size/shape is per-deal

- Controlled via `Grid Columns` in Edit Deal
- Add/remove rows to control visible configurable columns
- Use `position` to place columns at start/end

---

## Quick Admin Setup

1. Open Deal -> Edit.
2. Enter Deal Investor Statuses (comma-separated).
3. Confirm Enable Notifications toggle.
4. Configure Grid Columns for desired table layout.
5. Save and validate from Deal Investors table.

---

## Where To Read More

- Full deal guide: `docs/product/deal_user_guide.md`
- Deal step templates and investor activity flow: `docs/product/deal_steps_user_guide.md`
- End-user deals management guide: `docs/user_guides/deals_management_user_guide.md`
