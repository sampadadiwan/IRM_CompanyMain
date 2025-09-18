**Overview**: This PR introduces enhancements to table rendering, KPI display, dashboard widgets, and adds a new tracking currency feature, along with various minor improvements and bug fixes.

**Motivation**: The changes aim to improve the user experience by providing more flexible table column alignment, better KPI visualization, and enhanced dashboard customization. The introduction of a tracking currency allows for more precise financial reporting.

**What Changed**:
*   **Table Rendering**:
    *   Introduced `numberTable` CSS class for right-aligned numerical data in tables.
    *   `RansackTable` and `RansackTableHeader` components now support dynamic CSS classes for columns and conditional rendering of the actions column.
    *   `row_toggle_controller.js` updated expand/collapse symbols from `+` to `>`.
*   **KPI Display**:
    *   KPI values in `_grid_view_simple_table.html.erb` are now rounded to one decimal place and negative values are displayed in parentheses with `text-danger` styling.
    *   `_budget_view_table.html.erb` now filters KPI mappings by category.
    *   `PerformanceTableService` now uses `@metric_names` for fetching KPIs.
*   **Dashboard Widgets**:
    *   "Fund Ratios" widget now supports a `title` metadata.
    *   "Portfolio Stats" widget now includes `tracking_currency` metadata.
*   **Tracking Currency**:
    *   Added `tracking_currency` field to `EntityDashboard` and displayed it in `entities/show.html.erb`.
    *   `_stats_for_portfolio_company.html.erb` now prioritizes `tracking_currency` for `target_currency` calculation.
*   **Grid View Preferences**:
    *   Added `alignment` attribute to `GridViewPreference` model, controller, and views, allowing users to specify text alignment for grid view columns.
    *   `WithGridViewPreferences` concern now uses `name_with_alignment` and `key_with_alignment` for column mapping.
*   **Minor Improvements**:
    *   Changed `puts` statements to `Rails.logger.debug` in `agent_chart.rb`.
    *   `KycDocGenerator` now explicitly checks for "Yes" for `master_fund` custom field.
    *   Removed `prefix: "$"` from chart options in `investment_statistics_helper.rb`.
    *   Removed an unused `result` variable in `kpis_helper.rb`.

**Refactoring / Behavior Changes**:
*   The table rendering components (`RansackTable`, `RansackTableHeader`, `RansackTableRow`) have been refactored to allow more dynamic control over column presentation and actions, including the ability to specify CSS classes directly in column definitions and conditionally show/hide the actions column.
*   The KPI display logic has been refined for better readability and visual representation of negative values.
*   The `GridViewPreference` system now supports column alignment, providing more customization options for users.
*   The `FundRatioSearch` service now includes filtering by `end_date` based on a specified number of months.

**Testing**:
*   Manual testing was performed to verify the new table alignment, KPI display, and dashboard widget configurations.
*   The tracking currency functionality was tested by configuring entities with a tracking currency and observing its impact on portfolio statistics.
*   Grid view preference alignment was tested through the UI to ensure correct application of CSS classes.

**Impact**:
*   **User Interface**: Improved readability of tables, especially for numerical data, and more flexible dashboard layouts.
*   **Financial Reporting**: Enhanced accuracy in financial reporting with the introduction of tracking currency.
*   **Customization**: Increased customization options for grid views with column alignment.
*   **Logging**: More consistent logging practices in `agent_chart.rb`.

**Review Focus**:
*   Review the changes to `RansackTable` and `RansackTableHeader` components to ensure the new `actions_column` and dynamic CSS class handling are robust and do not introduce regressions.
*   Verify the logic for `tracking_currency` in `_stats_for_portfolio_company.html.erb` and `_stats.html.erb`.
*   Examine the `GridViewPreference` changes, particularly the `alignment` attribute and its integration into column mapping.
*   Confirm the display of negative KPI values and rounding in `_grid_view_simple_table.html.erb`.