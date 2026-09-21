# Design: Harmonize KPI Report Reminder Modal with KYC Request Updates

## Overview
Update the "Send KPI Report Reminder" modal in the KPI reports grid view to match the visual style and informative "next steps" format of the "Request KYC Updates" modal. This improves consistency across the IRM platform and provides better feedback to users about what happens when a reminder is sent.

## User Experience
- **Visual Consistency**: The modal will use the same layout as the KYC request updates modal, including colorful step boxes with icons.
- **Informative Flow**: Users will see exactly what actions are triggered (link sent, shell created, status update, notification setup).

## Proposed Changes

### 1. View: `app/packs/startups/kpis/views/kpi_reports/_grid_view.html.erb`
Modify the `sendReminderModal` structure:
- Add a text header: "The following will happen immediately when you click **Send Reminder**:"
- Implement 4 step boxes:
    1. **Fresh link emailed to portfolio company** (Blue/`ti-mail`): Explains the magic link.
    2. **KPI Report shell created** (Green/`ti-file-plus`): Explains the automatic report creation.
    3. **Status updated to Link Sent** (Amber/`ti-refresh`): Explains the status tracking.
    4. **You'll be notified on submission** (Purple/`ti-bell-check`): Explains the feedback loop.
- Re-style existing form fields (Date and Period) to be consistent with the new layout.
- Use standard Bootstrap 5 classes and IRM-specific utility classes (like `rounded-3`, `gap-3`, etc.).

## Verification Plan
- **Visual Inspection**: Open the KPI Report Reminder modal and compare it with the KYC Request Updates modal to ensure identical styling and layout.
- **Functional Check**: Ensure the date field and period selector still function correctly and the form submits to the correct endpoint (`send_portco_notification_kpi_reports_path`).
- **Regression**: Verify that other elements in the KPI grid view remain unaffected.
