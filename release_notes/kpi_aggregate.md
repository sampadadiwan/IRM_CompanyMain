# PR: KPI Aggregation

**1. Overview**

This PR introduces a new feature to automatically cumulate monthly KPI values into quarterly and year-to-date (YTD) reports.

**2. Motivation**

To provide users with aggregated KPI data over different time periods without requiring manual calculations, improving data analysis capabilities.

**3. What Changed**

- **Model:** Added a `cumulate` boolean attribute to the `InvestorKpiMapping` model to flag KPIs that should be aggregated.
- **Background Job:** Created a new `KpiCumulateJob` to handle the asynchronous aggregation of KPI data.
- **Core Logic:** Implemented the `cumulate` method in the `Kpi` model, which calculates and stores the quarterly and YTD sums.
- **Service Integration:** The `KpiWorkbookReader` service now enqueues the `KpiCumulateJob` after successfully importing KPI data.
- **UI:** Updated the `InvestorKpiMapping` form and views to include the new `cumulate` option.
- **Testing:** Added a new feature spec (`kpi_cumulate.feature`) to test the end-to-end cumulation functionality.

**4. Refactoring / Behavior Changes**

- This change introduces a new background job that runs after KPI data is imported. This will result in new background processing activity on the server.

**5. Testing**

- Added a new feature test to cover the KPI cumulation logic.
- Manual testing was performed by uploading a KPI workbook and verifying that the quarterly and YTD data was generated correctly.

**6. Impact**

- **Performance:** The introduction of a new background job may slightly increase system load during KPI imports.
- **Database:** A new column (`cumulate`) has been added to the `investor_kpi_mappings` table.

**7. Review Focus**

- Please review the `cumulate` method in the `Kpi` model for the correctness of the aggregation logic.
- Please review the `KpiCumulateJob` to ensure it is triggered correctly and handles potential errors.