# Deal Investor Import README

## Overview

This document explains the Deal Investor import flow and summarizes the recent fixes made to keep imports aligned with current Deal/Note ownership behavior.

Primary implementation files:
- `app/packs/startups/deals/services/import_deal_investor_service.rb`
- `app/packs/startups/deals/services/import_deal_investor.rb`

## Workbook Structure

The importer reads a multi-sheet workbook:

1. `Deal Investors` (required)
- Creates `DealInvestor` records for the selected Deal.
- Required column: `Deal Investor`.
- Standard supported columns:
  - `Status`
  - `Tags`
  - `Source`
  - `Deal Lead`
  - `Tier`
  - `Primary Amount`
  - `Secondary Amount`
  - `Pre Money Valuation`
- Any additional columns are treated as custom fields and written into `json_fields`.

2. `Deal Steps` (optional)
- Updates activity statuses for each imported investor.
- Header format: `Deal Investor`, then one column per step title.
- Supported values (case-insensitive): `Complete`, `Incomplete`, `Skip`.

3. `Notes` (optional)
- Creates Note records for each deal investor row.
- Expected headers:
  - `Deal Investor`
  - `On`
  - `Details`
  - `Tags`
  - `Reminder Emails`
  - `Reminder Date`

## Recent Changes Applied

### 1) Notes ownership fixed to DealInvestor (critical)

Problem fixed:
- Notes import previously used legacy investor linkage.
- Notes now use polymorphic ownership (`owner_id` + `owner_type`).
- Result was missing/broken notes for imported deal investors.

Current behavior:
- Notes from the `Notes` sheet are created with:
  - `owner_type: "DealInvestor"`
  - `owner_id: deal_investor.id`
- Importer resolves the `DealInvestor` in the context of the current Deal before creating each note.
- If a matching `DealInvestor` is not found, the row is marked failed.

### 2) Deal investor status validation uses deal-level status options

Current behavior:
- If `Status` is provided, it must be one of:
  - `deal.deal_investor_status` (if configured), else
  - `DealInvestor::STATUS` fallback.
- Invalid status values fail the row with a clear message.

### 3) First-step task generation preserves actor context

Current behavior:
- After creating a new `DealInvestor`, templates generate activities.
- First-step task generation is queued with the importer user id:
  - `GenerateDealStepTasksJob.perform_later(deal_investor.id, user_id, first_step.id)`

## Row Processing and Counts

- `processed_row_count` increments on successful row processing.
- `failed_row_count` increments on rescued row errors.
- Import handles row-level failures without aborting the full workbook.

## Common Failure Reasons

- `Deal Investor` value is blank.
- Investor name does not exist in the importing entity.
- Duplicate `DealInvestor` already exists for that Deal + Investor.
- Provided `Status` is not in allowed status options.
- Notes row references an investor that does not map to a `DealInvestor` in the current Deal.

## Validation and Debugging Checklist

1. Confirm workbook sheet names exactly match:
- `Deal Investors`
- `Deal Steps`
- `Notes`

2. Confirm `Deal Investor` names match existing `Investor.investor_name` values for the same `entity_id`.

3. For notes visibility/debugging:
- Verify imported notes have:
  - `owner_type = "DealInvestor"`
  - `owner_id = <deal_investor.id>`

4. Confirm deal status config:
- If a custom deal status list is configured, uploaded `Status` values must match exactly.

## Related Code

- Import entry point:
  - `app/packs/startups/deals/services/import_deal_investor_service.rb`
- Core import logic:
  - `app/packs/startups/deals/services/import_deal_investor.rb`
- Notes model (polymorphic owner):
  - `app/packs/core/notes/models/note.rb`
- Notes controller owner handling:
  - `app/packs/core/notes/controllers/notes_controller.rb`

## Notes

This README documents behavior as currently implemented and should be updated when:
- Workbook column contracts change.
- Additional supported status values are introduced.
- Note ownership semantics change again.
