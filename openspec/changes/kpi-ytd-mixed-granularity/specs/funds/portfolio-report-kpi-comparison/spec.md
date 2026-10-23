# Spec Delta

## Purpose

Defines the comparison field the Word portfolio report offers for each Actual KPI column: Actual as a percentage of
another tag (Budget) for the same KPI, period and date.

## ADDED Requirements

### Requirement: Actual as a percentage of Budget
For every KPI report column tagged Actual, the portfolio report SHALL offer a field named `<label>_vs_budget_percent`
(where `<label>` is the column's existing label) equal to the Actual value divided by the Budget value of the same KPI,
same period and same date, multiplied by 100. Only approved KPIs SHALL be used, for both the Actual and the Budget side. The field SHALL be "N/A" when no approved
Budget figure exists for that KPI, period and date, when the Actual figure is not approved, or when the Budget value is
zero.

#### Scenario: YTD Actual against YTD Budget
- **WHEN** the June 2026 YTD Actual is 92 and the June 2026 YTD Budget is 100
- **THEN** the field for the June 2026 YTD Actual column is 92

#### Scenario: Quarter Actual against Quarter Budget
- **WHEN** the June 2026 Quarter Actual is 45 and the June 2026 Quarter Budget is 60
- **THEN** the field for the June 2026 Quarter Actual column is 75

#### Scenario: Budget missing
- **WHEN** an Actual column has no Budget figure for the same KPI, period and date
- **THEN** its field is "N/A"

#### Scenario: Budget is zero
- **WHEN** the Budget value is zero
- **THEN** the field is "N/A"

#### Scenario: Unapproved figures are not compared
- **WHEN** the Budget figure, or the Actual figure, is not approved
- **THEN** the field is "N/A"

#### Scenario: Tag case is ignored
- **WHEN** the Budget report is tagged "budget" rather than "Budget"
- **THEN** it is the Budget for the Actual column and the field is calculated

#### Scenario: Different period is not compared
- **WHEN** a June 2026 Month Actual exists and only a June 2026 Quarter Budget exists
- **THEN** the Month Actual field is "N/A"

#### Scenario: Budget approved later
- **WHEN** a Budget figure is approved after the Actual and the report is generated again
- **THEN** the field reflects the approved Budget

### Requirement: Only Actual columns carry the field
The portfolio report SHALL NOT offer an "against Budget" field for columns tagged Budget, IC or untagged.

#### Scenario: Budget and IC columns
- **WHEN** a Budget column and an IC column exist
- **THEN** neither has a `_vs_budget_percent` field

### Requirement: Comparator tags are a list
The portfolio report SHALL derive the field name from the comparator tag (`_vs_<tag>_percent`, tag in lower case) and
SHALL support a list of comparator tags whose only entry is Budget.

#### Scenario: Field name follows the comparator tag
- **WHEN** the comparator list contains Budget
- **THEN** the field is named with the suffix `_vs_budget_percent` and no other comparison field exists

### Requirement: The report uses approved KPIs only
The portfolio report's KPI rows (the main list, the per-category lists, and the Word export of an AI-drafted report)
SHALL use approved KPIs only. A KPI that is not approved SHALL be treated as missing, so its `<label>` and
`<label>_percent` fields show "N/A". KPI screens SHALL NOT be affected.

#### Scenario: Report uses approved KPIs only
- **WHEN** a KPI in a report column is not approved
- **THEN** its `<label>` and `<label>_percent` fields are "N/A"

### Requirement: Each KPI row carries its data type
Each KPI row of the portfolio report SHALL carry `data_type`: the KPI mapping's data type in lower case (`money`,
`numeric` or `percentage`), so a template can format a percentage KPI differently. Percentage values stay stored and
passed as fractions (0.12 for 12%).

#### Scenario: Row data type
- **WHEN** a KPI's mapping has data type percentage
- **THEN** its row has `data_type` "percentage"

### Requirement: Existing report fields are unchanged for approved figures
The portfolio report SHALL keep every existing KPI field (`<label>`, `<label>_percent`, the header and the category
lists) with the same values for the same approved, stored KPIs, and SHALL NOT store the comparison. Changes to the
stored values themselves (cumulation and the YTD percentage change) are covered by their own capabilities.

#### Scenario: Existing fields unchanged
- **WHEN** a template that does not use the new field is rendered, all KPIs are approved and the stored KPI values are
  the same as before
- **THEN** its output is the same as before this change
