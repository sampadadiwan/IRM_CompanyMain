# PR: Add Denomination Support for KPI Mappings

1. **Overview**: This PR introduces support for different denominations in KPI mappings, enabling automatic value scaling during Excel workbook imports.

2. **Motivation**: Startups report financial data in various units (Millions, Crores, Lakhs, Thousands). To ensure consistency in the central database, imported values must be normalized to their base units based on the configured denomination for each KPI.

3. **What Changed**:
    - **Added Denomination Column**: Created a migration to add `denomination` (string) to the `investor_kpi_mappings` table.
    - **Model Enum**: Defined `denomination` enum in [`InvestorKpiMapping`](app/packs/startups/kpis/models/investor_kpi_mapping.rb) with options: `millions`, `crores`, `lakhs`, and `thousands`.
    - **Controller Integration**: Permitted `denomination` in `InvestorKpiMappingsController` and updated the `show` view ([`investor_kpi_mappings/show.html.erb`](app/packs/startups/kpis/views/investor_kpi_mappings/show.html.erb)).
    - **Form Update**: Added a select field to the KPI mapping form ([`investor_kpi_mappings/_form.html.erb`](app/packs/startups/kpis/views/investor_kpi_mappings/_form.html.erb)).
    - **Workbook Reader Logic**: Updated [`KpiWorkbookReader`](app/packs/startups/kpis/services/kpi_workbook_reader.rb) to apply a multiplier based on the mapping's denomination before saving values.

4. **Refactoring / Behavior Changes**:
    - Values extracted from Excel workbooks are now automatically scaled. For example, a value of `10.0` with a "Millions" denomination is stored as `10,000,000.0`.

5. **Testing**:
    - **Integration Tests**: Added a new cucumber scenario to [`kpi_workbook_reading.feature`](features/startup/kpi_workbook_reading.feature) verifying that different denominations are correctly scaled during import.
    - **Step Definitions**: Added new steps to [`kpi_workbook_steps.rb`](features/step_definitions/kpi_workbook_steps.rb) to support denomination-aware testing.
    - **Test Data**: Generated a sample Excel file `public/sample_uploads/kpi_extraction/denomination_test.xlsx` for the new test case.

6. **Impact**:
    - Improved data accuracy and consistency during high-volume KPI imports.
    - No impact on existing mappings as the default denomination is `nil`/`NA`.

7. **Review Focus**:
    - Scaling factors in `KpiWorkbookReader` (Millions: 1M, Crores: 10M, Lakhs: 100k, Thousands: 1k).
    - UI integration in the KPI mapping form.
