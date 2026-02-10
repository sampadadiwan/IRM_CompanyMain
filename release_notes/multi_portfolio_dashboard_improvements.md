# Multi-Portfolio Dashboard Improvements - Testing Guide

**Branch:** `multi_portfolio_dashboard_fix`
**Date:** February 6, 2026

This document outlines the improvements made to the Multi-Portfolio Dashboard and provides step-by-step testing instructions for the business team.

---

## 1. Force Units in Stats Settings

### Change Summary
Added support for force units in settings to display values in **Lakhs**, **Millions**, or **Crores** format across stats widgets.

### How to Test
1. Navigate to the dashboard settings or widget metadata
2. Set `force_units` parameter to one of the following values:
   - `'Crores'`
   - `'Lakhs'`
   - `'Millions'`
3. Refresh the dashboard
4. **Expected Result:** All stats should display values in the specified unit format

### Example Configuration
```yaml
force_units: 'Crores'
```

---

## 2. Widget/Chart Title Configuration

### Change Summary
Fixed widget titles to properly respect the `tag`  parameter if title is not provided. Previously, unsetting titles did not work correctly.

### How to Test
1. Navigate to Company charts widget metadata settings
2. **Test Case 1:** Set a custom title
   ```yaml
   {title: 'Sector Bought Amount',show_sector_wise: true, plot: 'bought_amount', show_table: true}
   ```
   - **Expected Result:** Widget displays "My Custom Chart Title"

3. **Test Case 2:** Unset or remove the title parameter
   ```yaml
   {show_sector_wise: true, plot: 'fmv', show_table: true}
   ```
   - **Expected Result:** Widget displays the title based on tags

---

## 3. Table Formatting Improvements

### Change Summary
Improved table readability below charts by:
- Centering tables horizontally
- Reducing excessive whitespace between labels and percentages
- Better visual alignment
- **UI Consistency:** Company charts now use standard card layout instead of toggle view for better page consistency

### How to Test
1. Navigate to any dashboard with sector/company breakdown charts
2. Look at the tables displayed below pie charts
3. **Expected Results:**
   - Tables are centered in their container
   - Minimal gap between sector/company names and percentage values
   - Clean, professional appearance
   - Easy to read at a glance
   - Card header with title has proper padding without background color
   - No toggle button - card always expanded for consistent UI

### Affected Views
- Sector-wise breakdown tables
- Company-wise breakdown tables
- Portfolio investment tables

---

## 4. IRR / MOIC Chart Enhancements

### Changes Summary
Multiple improvements to Fund Ratio charts:
- **Title Font:** Standardized font styling to match the rest of the page
- **IRR Labels:** Now display with `%` symbol and configurable decimal places
- **MOIC Labels:** Display in `X.Xx` format (e.g., `2.4x`, `3.2x`)

### How to Test

#### Test IRR Chart with Decimals
1. Create or edit a fund ratio widget
2. Add `decimals` parameter to metadata:
   ```yaml
   {show_table: true, show_chart: true, decimals: 3,ratio_names: ['Gross Portfolio IRR', 'Gross Portfolio MOIC'], chart_colors: ["#00c49a", "#ff8042"]}
   ```
3. View the IRR chart
4. **Expected Results:**
   - Chart labels show percentages like `136.53 %`
   - Values rounded to 2 decimal places
   - Table below chart matches the same precision

#### Test MOIC Chart Format
1. View a MOIC (Multiple on Invested Capital) chart
2. **Expected Results:**
   - Chart labels show format like `2.4x`, `3.2x`, `1.1x`
   - Values rounded to 1 decimal place
   - No decimal precision applied (whole numbers with one decimal)

#### Test Different Decimal Settings
Try different decimal values:
```yaml
decimals: 2  # For one decimal place
decimals: 3  # For three decimal places
```

---

## 5. Portfolio Investment (PI) Report - Multi-Level Grouping

### Change Summary
Enhanced AG Grid grouping functionality to support **multiple column grouping** with hierarchical levels.

### How to Test

#### Single Column Grouping (Existing Feature)
1. Navigate to Portfolio Investments report
2. Set group_by_column with a single column:
   ```yaml
   {title: "Investments", show_grouped: true, group_by_column: 'portfolio_company_name',decimals:2}
   ```
3. **Expected Result:** Rows grouped by portfolio company name

#### Multi-Level Grouping (New Feature)
1. Set group_by_column with multiple columns (comma-separated):
   ```yaml
   {title: "Investments", show_grouped: true, group_by_column: 'portfolio_company_name, investment_date',decimals:2}
   ```
2. **Expected Result:**
   - Primary grouping by Sector
   - Secondary grouping by Portfolio Company Name within each sector
   - Expandable/collapsible hierarchy

---

## 6. Company-Wise IRR and MOIC Charts (New Widget)

### Change Summary
Added a new widget called **"Company Ratio"** that provides the same IRR and MOIC charting functionality as fund ratios, but for individual portfolio companies.

**Recent Updates:**
- **Fund Filtering:** Widget now respects `fund_ids` parameter to filter companies by specific funds
- **Negative Values:** Customizable color for negative ratio values via `negative_color` parameter
- **Title Handling:** Title from metadata is used as-is without titleization
- **UI Consistency:** Changed from toggle card to standard card view for better page consistency

### How to Test

#### Adding the Widget
1. Navigate to dashboard widget configuration
2. Add a new widget with type: `Company Ratios`
3. Configure similar to fund ratio widgets:
   ```yaml
    {show_table: true, show_chart: true, ratio_names: ['IRR'], titles: ['IRR'], chart_colors: ['#00c49a'], negative_color: '#ff0000'}
   ```

#### Test Fund Filtering
1. Add `fund_ids` parameter to filter by specific funds:
   ```yaml
   {show_table: true, show_chart: true, ratio_names: ['IRR', 'MOIC'], fund_ids: [1, 2, 3]}
   ```
2. **Expected Result:** Only companies from specified funds are displayed

#### Test Negative Value Coloring
1. Set a custom color for negative ratios:
   ```yaml
   {show_table: true, show_chart: true, ratio_names: ['IRR'], negative_color: '#dc3545'}
   ```
2. **Expected Result:** Companies with negative IRR/MOIC values display in the specified color

#### Viewing Company Ratios
1. Navigate to the dashboard with the company ratio widget
2. **Expected Results:**
   - Chart displays IRR/MOIC for individual portfolio companies
   - IRR values show with `%` symbol
   - MOIC values show with `x` suffix
   - Table below chart lists companies with their ratios
   - Same formatting rules as fund ratios apply
   - Card displays without toggle button for consistent UI

#### Test Features
- **IRR Chart:** Should display company IRR with specified decimal precision
- **MOIC Chart:** Should display company MOIC in `X.Xx` format
- **Table Data:** Should match chart data exactly
- **Decimal Control:** Test with different `decimals` parameter values
- **Fund Filtering:** Verify only selected fund companies appear
- **Negative Colors:** Check negative values display in custom color

---

## General Testing Tips

### Browser Cache
- Always perform a **hard refresh** after configuration changes:
  - **Windows/Linux:** `Ctrl + Shift + R`
  - **Mac:** `Cmd + Shift + R`



### Verification Checklist
- [ ] Force units display correctly in stats
- [ ] Widget titles respect metadata settings
- [ ] Tables are centered and well-formatted
- [ ] IRR charts show percentages with correct decimals
- [ ] MOIC charts show `X.Xx` format
- [ ] Single column grouping works
- [ ] Multi-column grouping creates proper hierarchy
- [ ] Company ratio widget displays correctly
- [ ] All formatting is consistent across widgets

---

## Known Limitations

1. **Multi-level grouping:** Maximum recommended levels is 3 for optimal performance
2. **Decimal precision:** IRR supports configurable decimals; MOIC always uses 1 decimal place
3. **Group by columns:** Column names must exactly match the mapping in ag grid

---

## Troubleshooting

### Issue: Changes not reflecting
**Solution:** Clear browser cache and perform hard refresh

### Issue: Grouping not working
**Solution:**
- Verify column names are correct (case-sensitive)
- Check that columns exist in the AG Grid configuration
- Ensure comma-separated format with no extra spaces

### Issue: Charts not displaying correct format
**Solution:**
- Verify `decimals` parameter is set in metadata
- Check that ratio data exists in the database
- Ensure `ratio_names` array includes the correct ratio types

### Issue: Tables stretched or misaligned
**Solution:**
- Verify no conflicting CSS is being applied
- Check that widget container has proper width constraints

---

## Recent Updates & Additional Improvements

### Fund-Based Filtering
- **Company Ratios Widget** now respects `fund_ids` parameter for filtering data
- When multiple funds are selected, only ratios from those specific funds are included in calculations
- Ensures accurate company-level metrics when viewing multi-portfolio dashboards

### Customizable Negative Value Colors
- Added `negative_color` parameter to company ratios widget
- Allows customization of how negative ratios are displayed
- Example configuration:
  ```ruby
    {show_chart: true, ratio_names: ['IRR', 'MOIC'], titles: ['IRR', 'MOIC'], chart_colors: ['#00c49a', '#ff8042'], negative_colors: ['#ff0000', '#ff0000']}
  ```

### Title Display Enhancement
- Widget titles from metadata are now displayed as-is without automatic titleization
- Preserves custom formatting, capitalization, and abbreviations
- Provides more control over dashboard presentation

### UI Consistency - Company Charts
- Removed toggle view functionality from company/sector charts
- Changed to standard card layout with shadow for consistency
- Maintains clean padding (`p-3 pb-0`) without background color
- Improved visual alignment with other dashboard widgets

---


**Document Version:** 1.0
**Last Updated:** February 6, 2026
