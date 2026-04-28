# Feature: KPI Approval Workflow (Implemented)

## Status: DEPLOYED

This document outlines the design of the KPI approval mechanism. For the current technical documentation, see [`docs/kpi_import_process.md`](docs/kpi_import_process.md).

## Summary
Introduced a staging area for all imported KPIs. Data from Excel workbooks no longer automatically updates the system's official metrics. Instead, it is saved as `unapproved` and requires explicit approval from an authorized user.

## Technical Implementation Summary

### 1. Database
- Added `status` column to `kpis` table.
- Indexed `status` for performance.
- Defaulted existing records to `approved`.

### 2. Models & Services
- **[`Kpi`](app/packs/startups/kpis/models/kpi.rb)**: Added enum for status and uniqueness validations.
- **[`KpiWorkbookReader`](app/packs/startups/kpis/services/kpi_workbook_reader.rb)**: Updated to create unapproved records if values differ from approved ones.
- **[`KpiApproveService`](app/packs/startups/kpis/services/kpi_approve_service.rb)**: New service to merge unapproved values into official records.

### 3. Security
- **[`KpiPolicy`](app/packs/startups/kpis/policies/kpi_policy.rb)**: Added `approve?` permission checking for `approver`, `company_admin`, or `super` roles.

### 4. Reporting
- **[`PerformanceTableService`](app/packs/startups/kpis/services/performance_table_service.rb)**: Updated to strictly exclude `unapproved` data from standard reports.
