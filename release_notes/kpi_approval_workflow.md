# PR: KPI Approval Workflow and Recomputation Enhancements

## Overview
This PR introduces a KPI approval workflow, allowing users to stage and verify KPI data before it becomes official, along with enhanced recomputation and error reporting for cumulative KPIs.

## Motivation
Previously, KPI data imported via workbooks or services was immediately "live." This change provides a staging area (unapproved status) to prevent data corruption from erroneous imports. It also addresses the need to force recomputations when formulas or underlying data change.

## What Changed
- **KPI Approval Workflow**:
    - Added `status` (unapproved/approved) to the `Kpi` model.
    - Updated `ImportKpi` and `KpiWorkbookReader` to save new or changed data as `unapproved`.
    - Introduced `KpiApproveService` to handle the transition from unapproved to approved, including merging data into existing approved records.
    - Added `approve` and `approve_all` actions to `KpisController`.
- **Enhanced Recomputation**:
    - Added `recompute_cumulative` action to `KpiReportsController`.
    - Updated `KpiCumulateJob` and `KpiCumulative` concern to support a `force` mode for overwriting existing values.
- **Improved Monitoring & Feedback**:
    - Updated `KpiCumulateJob` to send real-time notifications via Stimulus/ActionCable and email error reports to the user upon failure.
- **UI Enhancements**:
    - Added "View Including Staged" toggle and "Approve" buttons to the KPI Grid View.
    - Added "Recompute Cumulative" action to the KPI Grid View menu.

## Refactoring / Behavior Changes
- `Kpi` model now defaults to `approved` for legacy data but `ImportKpi` and `KpiWorkbookReader` explicitly create `unapproved` records.
- Authorization: Added `approve?` and `recompute_cumulative?` policies.
- Scoping: Multiple services and models were updated to default to `.approved` KPIs for calculations and display.

## Testing
- Added `features/startup/kpi_approval.feature` for integration testing of the approval workflow.
- Updated existing KPI step definitions to handle the new status and grid view parameters.
- Manual verification of the "Approve All" and "Recompute Cumulative" flows in the development environment.

## Impact
- **Data Integrity**: Significant improvement by providing a verification step for imported data.
- **Visibility**: Improved feedback loop for background job failures.
- **Database**: New columns `status`, `approved_by_user_id`, and `approved_at` added to the `kpis` table (implied by model changes).

## Review Focus
- Inspect the logic in `KpiApproveService` for potential race conditions during record merging.
- Verify the `force` parameter propagation in `KpiCumulative` logic.
- Ensure the UI status badges and toggles are clear and intuitive.
