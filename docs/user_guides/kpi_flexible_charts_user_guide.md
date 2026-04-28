# User Guide: Flexible KPI Charts in Grid View

The Flexible KPI Charting system allows you to create, customize, and save interactive visualizations directly from the KPI Grid View. This guide covers how to use manual selections, mix chart types, and manage saved configurations.

---

## 1. Accessing the Chart View
Navigate to the **KPIs** section and ensure you are in the **Grid View**. The charting interface is integrated directly into the grid, appearing above the data table whenever a selection is made.

## 2. Creating a Manual Chart
You can build a custom chart on the fly by selecting specific KPIs from the grid:

1.  **Select KPIs**: Click the checkboxes next to the KPI names in the first column of the grid table.
2.  **Chart Controls**: As soon as you select a KPI, the **Chart Controls** panel will appear.
3.  **Choose Chart Types**: In the controls panel, you can assign a specific visualization type to each selected KPI:
    *   **Line**: Best for trends over time.
    *   **Bar (Column)**: Best for comparing values across periods.
    *   **Area**: Highlights the magnitude of change over time.
    *   **Pie / Donut**: Useful for seeing the composition of a single period (best used when data points are limited).
4.  **Mixed Modes**: You can mix types in a single chart (e.g., plot "Revenue" as a Bar and "Net Profit Margin" as a Line).
5.  **Update Chart**: Click the **Update Chart** button to refresh the visualization with your choices.

## 3. Saving Chart Configurations
Once you have created a chart layout you like, you can save it for future use:

1.  In the **Chart Controls** panel, enter a name in the **Setting Name** input field.
2.  Click **Save Setting**.
3.  The configuration is now stored and linked to your user account and the current Portfolio Company.

## 4. Using Saved Charts
The **Saved Charts** dropdown (top right of the grid) allows you to quickly load previously saved visualizations.

*   **Multi-View**: You can check multiple saved charts simultaneously. Each selection will render as its own individual "card" on the page, allowing for side-by-side comparison of different KPI sets.
*   **Toggle Off**: Uncheck a setting in the dropdown to remove its card from the view.
*   **Clear All**: Use the "Clear All" link in the dropdown or the Chart Controls panel to reset all checkboxes and hide all chart cards.

## 5. Data & Filter Synchronization
The charts are strictly bound to the **Grid Filters**:

*   **Time Window**: If you filter the grid to show "Last 12 Months" or a specific date range using the `no_of_periods` and `as_of` filters, the chart will only display data for that exact window.
*   **Tags**: The chart respects the active tags (e.g., "Actual", "Budget", "Projected") selected in the grid filters.
*   **Real-time Updates**: If you change a filter in the grid (e.g., switching from Monthly to Quarterly), the charts will automatically update to reflect the new data context.

## 6. Understanding KPI Names (Standardization)
The system automatically handles the translation between technical "Reported" names and "Standard" investor names:
*   **Legends & Labels**: The chart will always display the **Standard KPI Name** defined in your investor mappings, ensuring consistency even if different portfolio companies use different naming conventions in their raw data.
*   **Cross-Category Access**: You can plot any KPI belonging to the company, even if it is not in the currently active category tab (e.g., plotting an "Income Statement" KPI while viewing the "Balance Sheet" tab).

## 7. Tips for Best Results
*   **Comparison**: Use "Line" for growth metrics and "Bar" for volume metrics to make them easy to distinguish in a mixed chart.
*   **Reseting**: If the UI becomes cluttered, the **Clear All** button in the top-right "Saved Charts" menu is the fastest way to return to a clean grid view.
