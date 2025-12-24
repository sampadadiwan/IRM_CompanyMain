# KPI Self-Reporting Workflow for Portfolio Companies

## Overview
This document outlines the workflow and implementation details for allowing Portfolio Companies to self-report KPIs directly into the Fund's entity space.
Reference: [kpi_portco_upload.md](mdc:kpi_portco_upload.md)

## Requirement
Funds need a periodic way to request KPI data from their portfolio companies. Instead of the Fund manually entering data, the Portfolio Company users should receive a link to a pre-created KPI report which they can fill out and save.

## Implementation Details

### 1. Authorization Logic
Updated `KpiReportPolicy` to allow `create?`, `update?`, and `edit?` access to users whose entity matches the `investor_entity_id` of the report's `portfolio_company`.

### 2. Periodic Trigger
A background job `GeneratePeriodicKpiReportsJob` runs daily:
- It checks `EntitySetting#kpi_reminder_frequency` and `kpi_reminder_before`.
- It pre-creates empty `KpiReport` shells for each portfolio company.
- It triggers notifications to the portfolio company employees.

### 3. Audit Trail
The `user_id` on `KpiReport` is used to track the last person who filled/modified the report, providing an audit trail of whether the data was entered by the Fund or the Portfolio Company.
