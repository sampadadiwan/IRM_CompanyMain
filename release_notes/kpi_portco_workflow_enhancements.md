# KPI Portco Workflow Enhancements

## Overview
This PR hardens the end-to-end KPI self-reporting workflow for Portfolio Companies, adds a combined approve-and-review action for Fund Admins on the report show page, and fixes a client-side XLSX validation bug that prevented the submit guard from working.

## Motivation
- **Fund Admin review flow**: The previous "Mark as Reviewed" button was on the edit form, but fund admins typically review from the show page. It also only changed the report status without approving the underlying staged KPIs, requiring two separate actions.
- **XLSX submit guard**: Portco users uploading a workbook with structural errors (e.g. no date column headers) were not being blocked from submitting because the client-side validator was silently failing.
- **Test coverage**: The full portco submission lifecycle (shell → link sent → draft → submitted → reviewed) lacked end-to-end Cucumber coverage.

## What Changed

### Fund Admin: Approve All KPIs & Mark as Reviewed (Show Page)
- **Removed** the standalone "Mark as Reviewed" button from `_form.html.erb` — it did not approve staged KPIs and was only visible inside the edit view.
- **Added** an "Approve All KPIs & Mark as Reviewed" button to `show.html.erb`, guarded by:
  - `policy(@kpi_report).mark_reviewed?` — fund admin only
  - `@kpi_report.status_submitted?` — only visible for submitted reports
  - `Kpi.unapproved.where(kpi_report_id: ...).exists?` — hides if no unapproved KPIs remain
- **Updated** `KpiReportsController#mark_reviewed` to call `KpiApproveService` on all unapproved KPIs scoped to the specific report before setting `status: 'reviewed'`. This replaces the previous single-step status update.
- The button uses the existing `confirm#popup` Stimulus action (opens `#confirmModal` with a "Proceed" button), consistent with other destructive actions in the app.

### XLSX Submit Guard Fix
- **Bug**: `kpi_xlsx_report_controller.js` computed `targetId` using `event.target?.closest("[id]")`. When the `upload:complete` event is dispatched on `document`, `event.target` is `document`, which does not have a `closest` method. Optional chaining (`?.`) only protects against a null/undefined target, not against `closest` being absent on the object — so `document.closest(...)` threw a `TypeError` that silently killed the handler before `FileReader.readAsArrayBuffer` was ever called.
- **Fix**: Changed to `event.target?.closest?.("[id]")` — the second `?.` makes the method call itself optional, returning `undefined` instead of throwing when `closest` is not available.
- **Safety net**: Wrapped `reader.onload` in a try-catch so that any future parsing failure in `XLSXLib.read` renders a visible "Please fix these errors before submitting" error and activates the submit guard, rather than silently dropping the exception.

### Cucumber Test Coverage
Added `features/startup/portco_kpi_workflow.feature` with 15 scenarios covering the full lifecycle:

| # | Tag | Scenario |
|---|-----|----------|
| 1 | `@kpi_status` | New shell shows `Shell Created` status badge |
| 2 | `@kpi_notification` | Sending notification advances status to `link_sent` and emails expiry date |
| 3 | `@kpi_validation` | Invalid date on notification form shows inline error, no email sent |
| 4 | `@kpi_dashboard` | Portco pending dashboard lists outstanding reports |
| 5 | `@kpi_draft` | Save Draft advances status to `draft_saved`, fund not notified |
| 6 | `@kpi_submit` | Submit Report advances to `submitted`, fund admin notified by email |
| 7 | `@kpi_locked` | Submitted report shows locked UI, Save/Submit buttons hidden |
| 8 | `@kpi_bulk_send` | Bulk send skips already-submitted portcos |
| 9 | `@kpi_periodic` | Periodic reminder job skips already-submitted portcos |
| 10 | `@kpi_reviewed` | Fund admin approves all KPIs and marks report as reviewed from show page |
| 11 | `@kpi_contact` | Only users tagged "Kpi" receive the reminder email |
| 12 | `@kpi_expired_link` | Expired magic link shows friendly error |
| 13 | `@kpi_magic_link` | Portco user submits via magic link (unauthenticated) |
| 14 | `@kpi_submit_guard` | Invalid XLSX (no date headers) disables Save Draft and Submit Report |
| 15 | `@kpi_submit_guard` | Uploading a corrected XLSX re-enables both buttons |

Step definitions in `features/step_definitions/portco_kpi_workflow_steps.rb` include:
- XLSX generation helpers (`kpi_xlsx_base64`, `dispatch_kpi_upload`) that build real XLSX files in memory via caxlsx and dispatch them as `File` objects to the Stimulus controller.
- Magic link session isolation using a named Capybara session (`:magic_link`) with teardown via an `After('@kpi_magic_link')` hook.
- Polling via `eventually` before dispatching XLSX events to handle Stimulus's async importmap loading.

## Behavior Changes
- Fund admins clicking "Approve All KPIs & Mark as Reviewed" now atomically approves all staged KPIs for that report (triggering `KpiPercentageChangeJob` and `KpiCumulateJob` per `KpiApproveService`) and marks the report `reviewed` in one action.
- The button disappears after use (no unapproved KPIs remain and status is no longer `submitted`).

## Impact
- **Data integrity**: KPIs are guaranteed to be approved before a report is marked reviewed — no more reports stuck in `submitted` with unapproved KPI data.
- **UX**: The review action is now on the show page where fund admins naturally land after a portco submits.
- **Reliability**: XLSX structural errors are now surfaced to portco users and block submission, preventing corrupt imports.

## Review Focus
- `KpiReportsController#mark_reviewed`: confirm `KpiApproveService` side effects (percentage change and cumulate jobs) are acceptable to trigger synchronously from a web request, or consider moving to a background job for large KPI sets.
- `kpi_xlsx_report_controller.js`: the `idMatches` / `fallbackMatches` guard assumes the `data-upload-id` on the controller element matches the one in the event detail — verify this holds for the production file upload component.
