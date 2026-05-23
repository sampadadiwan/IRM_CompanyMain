# Design: Harmonize Modal Introduction Headers (Option C)

## Overview
Update the introductory line in three key modals (Single KPI Reminder, Bulk KPI Reminder, and KYC Request Updates) to use a more polished "Bordered Banner" style (Option C). This improves the visual hierarchy and professionalism of the information boxes.

## User Experience
- **Structured Layout**: Replaces plain paragraphs with a bold, bordered header.
- **Visual Accent**: Uses the primary blue color for a vertical accent line, consistent with IRM design patterns.
- **Clarity**: Clearly separates the "What happens next" context from the actionable step boxes.

## Proposed Changes

### 1. Header Component Pattern
All three modals will use the following structure for the first line:
```html
<div class="border-start border-4 border-primary ps-3 py-1 mb-3">
  <div class="fw-bold text-dark small">[Context Title]</div>
  <div class="text-muted small">[Detailed instruction]</div>
</div>
```

### 2. Implementation Locations

#### A. Single KPI Reminder (`_grid_view.html.erb`)
- **Title**: `Immediate Actions`
- **Text**: `The following will happen immediately when you click **Send Reminder**:`

#### B. Bulk KPI Reminder (`new_notification.html.erb`)
- **Title**: `What Happens Next`
- **Text**: `The following will occur for each selected company when you click **Send Reminders**:`

#### C. KYC Request Updates (`investor_kycs/show.html.erb`)
- **Title**: `Immediate Actions`
- **Text**: `The following will happen immediately when you click **Send Update Request**:`

## Verification Plan
- **Visual Inspection**: Open all three modals and verify they share the same bordered header style.
- **Content Accuracy**: Ensure the bold button names in the text match the actual buttons in the modal footers.
