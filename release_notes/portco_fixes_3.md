# PR Description: KPI Reporting and Notification Enhancements

## Overview
This PR introduces significant improvements to the KPI reporting workflow, including bulk notifications for Portfolio Companies (PortCos), multi-year KPI cumulation (adding 'Year' period), and stricter 'Actual' data validation by preventing future-dated imports.

## Motivation
- **Bulk Notifications**: Users needed a way to trigger reminders for multiple companies at once for specific reporting periods.
- **Improved Cumulation**: The existing system lacked support for 'Year' period records and had limitations in multi-year tracking.
- **Data Integrity**: Preventing future 'Actual' KPIs ensures data quality and aligns with financial reporting standards.

## What Changed
### KPI Notifications & Workflow
- **Bulk Notification Support**: Refactored `KpiReportsController#send_portco_notification` to handle multiple IDs and integrated `SendPortcoNotificationJob` for asynchronous processing.
- **New Notification Modal**: Added a dedicated `new_notification` view and Stimulus `modal_controller.js` for a streamlined multi-select reminder interface.
- **Job-based Notifications**: Implemented `SendPortcoNotificationJob` with intelligent report shell creation (targeting current/previous quarter ends) and error reporting via email.

### KPI Cumulation (Domain Logic)
- **Year Period Support**: Updated `KpiCumulative` concern to automatically generate 'Year' period records when 12 months of 'Actual' data exist within a fiscal year.
- **Fiscal Year Flexibility**: Enhanced `fiscal_year_key` to better handle entity-specific financial year starts.
- **Improved YTD/Quarterly Processing**: Refined the cumulation logic to ensure accurate progress tracking.

### KPI Workbook Reader
- **Future Date Validation**: Added a check in `KpiWorkbookReader` to skip 'Actual' KPIs with dates in the future.

### UI & UX
- **Grid View Enhancements**: Integrated a date-specific reminder modal in the KPI grid view and added a remote modal frame for asynchronous alerts.
- **Mailer Improvements**: Updated `send_reminder` email template with better date formatting and a call-to-action button.

## Refactoring / Behavior Changes
- Shifted KPI notification triggering from a synchronous controller action to a background job (`SendPortcoNotificationJob`).
- Changed the `send_portco_notification` route to support collection-level POST requests.

## Testing
- **New Cucumber Features**: Added `kpi_cumulate_multi_year.feature` to verify multi-year cumulation and 'Year' record generation.
- **Updated Features**: Enhanced `kpi_reminder_email.feature` and `kpi_cumulate.feature` to cover new modal interactions and 12-month validation logic.
- **Step Definitions**: Added new steps for modal interaction and database verification in `kpi_workbook_steps.rb` and `kpi_steps.rb`.

## Impact
- **Performance**: Notifications are now handled in the background, improving UI responsiveness for bulk actions.
- **Data Accuracy**: Improved cumulation logic provides better year-over-year reporting.
- **User Experience**: Clearer feedback via Turbo Stream alerts and more flexible reminder options.

## Review Focus
- **Notification Logic**: Inspect the intelligent shell creation in `SendPortcoNotificationJob#find_or_create_kpi_report_shell`.
- **Cumulation Logic**: Verify the 12-month check in `KpiCumulative#process_yearly_cumulatives`.
- **Authorization**: Ensure the per-PortCo authorization check in the controller and job is sufficient.
