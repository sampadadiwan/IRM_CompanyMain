# Spec Delta

## Purpose

Fills a connected portfolio company's periodic KPI report from its Xero organisation, through
the same KPI mapping and approval as uploaded workbooks, so the fund team reviews figures
instead of chasing uploads.

## ADDED Requirements

### Requirement: Periodic KPI pull
The system SHALL, each night, pull the two most recently finished periods (by the entity's KPI
reporting frequency) from each connected portfolio company's profit-and-loss and balance
sheet into that period's actuals KPI report, creating the report when it does not exist.

#### Scenario: Month finished
- **WHEN** the nightly pull runs on 02/09/2026 for a monthly-reporting entity
- **THEN** the August 2026 and July 2026 actuals KPI reports for each connected company are filled from Xero

#### Scenario: Report missing
- **WHEN** no actuals KPI report exists for August 2026
- **THEN** one is created and filled

### Requirement: Labels matched through the KPI mapping
The system SHALL turn a Xero report line into a KPI only when its label equals a reported
name in the company's KPI mapping, and SHALL list labels that matched nothing on the
company's Xero panel.

#### Scenario: Matched label
- **WHEN** the company's mapping has reported name "Total Income" for standard KPI "Revenue" and Xero shows Total Income 250,000.00
- **THEN** the report gets a Revenue KPI of 250,000.00

#### Scenario: Unmatched label
- **WHEN** Xero shows "Total Cost of Sales" and no mapping has that reported name
- **THEN** no KPI is created and "Total Cost of Sales" is listed under "Labels with no KPI mapping"

### Requirement: Pulled KPIs await approval
The system SHALL store pulled figures as KPIs awaiting approval with source "Xero", SHALL NOT
create a new value when it equals the approved value, and SHALL replace an earlier awaiting
value for the same KPI and period. Approval SHALL be the existing KPI approval.

#### Scenario: New figure
- **WHEN** Revenue 250,000.00 is pulled and no approved Revenue exists for August 2026
- **THEN** a Revenue KPI awaiting approval, source Xero, is created and does not appear in dashboards

#### Scenario: Same as approved
- **WHEN** approved Revenue for August 2026 is 250,000.00 and the pull returns 250,000.00
- **THEN** nothing new is created

#### Scenario: Correction before approval
- **WHEN** Revenue awaiting approval is 250,000.00 and the next pull returns 255,000.00
- **THEN** there is one Revenue value awaiting approval, of 255,000.00

#### Scenario: Approval
- **WHEN** a fund user approves the August 2026 report's Xero KPIs
- **THEN** they become approved and appear in dashboards as uploaded KPIs do

### Requirement: No upload reminder once filled
The system SHALL mark a report filled from Xero as submitted and SHALL NOT send the KPI upload
reminder for that report.

#### Scenario: Reminder skipped
- **WHEN** the August 2026 report was filled from Xero and the reminder run happens
- **THEN** no upload reminder is sent to that company for August 2026

#### Scenario: Connected company with no matching labels
- **WHEN** a pull for a connected company produces no KPIs because no label matched
- **THEN** the report is not marked submitted and the normal upload reminder still applies
