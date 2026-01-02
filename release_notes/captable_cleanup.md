# PR: Captable Cleanup and Ownership Enhancements

## Overview
This PR introduces a horizontal cap table view, ownership trend analysis, and improved investment form handling to enhance how equity and convertibles are tracked for portfolio companies.

## Motivation
The changes aim to provide better visualization of equity dilution over multiple funding rounds and to streamline the capture of convertible instrument details.

## What Changed
- **Cap Table Visualizations**:
    - Introduced a new **Horizontal Cap Table** (`app/packs/startups/investments/views/investments/_horizontal_captable.html.erb`) that shows stake percentage across multiple funding rounds side-by-side.
    - Added an **Ownership Trend Line Chart** (`app/packs/startups/investments/helpers/investment_statistics_helper.rb`) to track "Self" ownership percentage over time.
- **Investment Management**:
    - Added a Stimulus controller (`investment_form_controller.js`) to dynamically show/hide convertible instrument fields based on the selected investment type.
    - Expanded the `Investment` model and params to support `instrument_name` and `instrument_quantity`.
    - Updated `InvestmentsController` to handle `portfolio_company` context more explicitly.
- **UI Improvements**:
    - Updated the investor show page to include a direct link to the detailed CapTable view with a `show_cap_table` parameter.
    - Refined investment listing to display the portfolio company name when the category is set to "Self".
    - Added edit links directly to the investment rows for quicker access.

## Refactoring / Behavior Changes
- **Logic Consolidation**: The `Investment.generate_cap_table` method was updated to handle display name logic for "Self" categories, ensuring consistency between tables and charts.
- **Dynamic UI**: Shifted form field toggling from static server-side logic (or lack thereof) to a client-side Stimulus controller.

## Testing
- **Manual Verification**: Verified the horizontal cap table correctly aggregates data across rounds A, B, and C.
- **Charts**: Confirmed the ownership trend line chart correctly reflects fully diluted percentages from the generated cap table rows.
- **Forms**: Tested the Stimulus controller's toggle behavior with Select2 integrated dropdowns.

## Impact
- **User Experience**: Significant improvement in how investors can visualize their stake dilution over time.
- **Data Integrity**: Better capture of specific instrument names and quantities for convertible notes.

## Review Focus
- **Performance**: The `generate_horizontal_cap_table` method calls `generate_cap_table` in a loop over funding rounds. While acceptable for typical round counts (3-10), ensure it doesn't cause bottlenecks for companies with many rounds.
- **UI Consistency**: Ensure the "Self" category mapping to the portfolio company's entity name is clear to users across all views.
