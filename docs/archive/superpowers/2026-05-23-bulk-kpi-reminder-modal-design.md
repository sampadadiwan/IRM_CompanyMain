# Design: Harmonize Bulk KPI Report Reminder Modal

## Overview
Update the bulk "Send KPI Report Reminder" modal (`new_notification.html.erb`) to match the visual style and informative 4-step format of the single-investor reminder and KYC update modals. This ensures a unified experience when requesting data from one or many portfolio companies.

## User Experience
- **Unified Visual Language**: Uses the same colorful step boxes and icons as other reminder workflows.
- **Clearer Process**: Replaces the generic numeric "How it works" with specific platform actions (emailing links, creating shells, updating status).

## Proposed Changes

### 1. View: `app/packs/startups/kpis/views/kpi_reports/new_notification.html.erb`
- Remove the existing "How it works" section (lines 16-50).
- Insert the 4-step vertical box stack:
    1. **Fresh link emailed to portfolio companies** (Blue/`ti-mail`): "Each selected company receives a secure magic link — no login required."
    2. **KPI Report shells created** (Green/`ti-file-plus`): "New report entries are automatically created for the specified period to house incoming data."
    3. **Status updated to Link Sent** (Amber/`ti-refresh`): "Report statuses are updated to track requests — you can monitor progress in the KPI dashboard."
    4. **You'll be notified on submission** (Purple/`ti-bell-check`): "You'll receive email notifications as each company submits; mark them as Reviewed when done."
- Restyle the form labels and helper text for better spacing and consistency.
- Maintain the "Re-sending is safe" tip at the bottom.

## Verification Plan
- **Visual Inspection**: Open the bulk KPI Reminder modal (Actions > New Notification) and verify the 4-step layout matches the single reminder modal.
- **Functional Check**: Verify the `select2` for portfolio companies, date field, and period selector still work correctly.
- **Bulk Submission**: Ensure submitting the form correctly triggers `SendPortcoNotificationJob` for all selected companies.
