# Spec Delta

## Purpose

Defines how Quarter, YTD and Year figures are calculated for cumulate and forward-fill KPIs from monthly and quarterly
data, when they are not produced, when previously calculated figures are removed, and how the percentage change on a
YTD figure is measured.

## ADDED Requirements

### Requirement: Fiscal year definition
The system SHALL determine the fiscal year of every KPI figure from one shared fiscal-year start month, resolved in this
order: the portfolio company's own setting, then the fund's setting, then the regional default (April for India,
January for US). Quarters SHALL be fiscal quarters counted from that start month.

#### Scenario: India default
- **WHEN** neither the portfolio company nor the fund sets a fiscal-year start and the region is India
- **THEN** the fiscal year runs April to March and Q1 is April to June

#### Scenario: Entity setting
- **WHEN** the portfolio company sets nothing, the entity setting starts the fiscal year in January and the region is India
- **THEN** the company's figures are grouped into January to December fiscal years

#### Scenario: Portfolio company override
- **WHEN** the portfolio company sets a January fiscal-year start while the fund uses April
- **THEN** the company's figures are grouped into January to December fiscal years and Q1 is January to March

### Requirement: Calculated Quarter needs a complete quarter
For a cumulate KPI, the system SHALL calculate a Quarter figure as the sum of its 3 approved monthly Actual figures
only when all 3 months exist for the same tag. It SHALL NOT treat a missing month as zero.

#### Scenario: Complete quarter
- **WHEN** July, August and September are approved
- **THEN** a Quarter figure dated 30 September equals their sum

#### Scenario: Incomplete quarter
- **WHEN** July and August are approved but September is not
- **THEN** no Quarter figure dated 30 September is calculated

### Requirement: Uploaded Quarter figures are authoritative
The system SHALL NOT overwrite or remove a Quarter, YTD or Year figure that was uploaded or entered by a person. Only
figures the system calculated SHALL be recalculated or removed. A figure a person uploads or enters over a calculated
figure SHALL become an uploaded figure.

#### Scenario: Uploaded quarter with all months present
- **WHEN** an uploaded Quarter figure exists and all 3 months of that quarter are approved with a different total
- **THEN** the uploaded Quarter figure keeps its value

#### Scenario: Uploaded figure replaces a calculated one
- **WHEN** a calculated September Quarter figure exists and a person uploads a September Quarter figure and approves it
- **THEN** the Quarter figure holds the uploaded value and later recomputations neither recalculate nor remove it

### Requirement: YTD walks the fiscal year
For a cumulate KPI, the system SHALL calculate YTD at each period end as the total from the start of the fiscal year,
walking the fiscal quarters in order. Within a quarter, months SHALL be used while they are contiguous from the start
of the quarter. At the end of a quarter the total SHALL be the base plus the 3 months when all exist, otherwise the base
plus the Quarter figure when one exists. When neither exists, the system SHALL NOT calculate any further YTD for that
fiscal year.

#### Scenario: Quarter then months
- **WHEN** Q1 is uploaded as a Quarter figure of 8,588,635.53 and July is 4,682,642.64 and August is 3,021,951.86
- **THEN** June YTD is 8,588,635.53, July YTD is 13,271,278.17 and August YTD is 16,293,230.03

#### Scenario: Gap stops YTD
- **WHEN** Q1 is uploaded, July and September are approved and August is missing
- **THEN** June YTD and July YTD are calculated, and no YTD is calculated for August or September

#### Scenario: Quarter figure bridges a missing month
- **WHEN** Q1 and Q2 are uploaded as Quarter figures, October and December are approved, November is missing and a Q3 Quarter figure dated 31 December is uploaded
- **THEN** October YTD is Q1 plus Q2 plus October, no YTD is calculated for November, and December YTD is Q1 plus Q2 plus Q3 (the December month is not added on top)

#### Scenario: Uploaded quarter bridges a gap
- **WHEN** Q1 and Q2 are uploaded as Quarter figures and no months exist
- **THEN** June YTD equals Q1 and September YTD equals Q1 plus Q2

#### Scenario: Partial months with an uploaded quarter are not double counted
- **WHEN** Q1 is 100, July is 10, and an uploaded Q2 of 40 exists with no other Q2 months
- **THEN** July YTD is 110 and September YTD is 140

#### Scenario: Months take priority over a disagreeing uploaded quarter
- **WHEN** Q1 is 100, July, August and September total 45 and an uploaded Q2 of 40 exists
- **THEN** September YTD is 145 and the Q2 Quarter figure stays 40

#### Scenario: Gap does not leak into the next fiscal year
- **WHEN** a month is missing in one fiscal year and the next fiscal year has complete data
- **THEN** the next fiscal year's YTD is calculated from its own start

### Requirement: Year needs the whole fiscal year
For a cumulate KPI, the system SHALL calculate a Year figure, dated the last day of the fiscal year, only when all 4
fiscal quarters are covered by uploaded Quarter figures, calculated Quarter figures or complete months, as the total
of the 4 quarters.

#### Scenario: Year from months
- **WHEN** all 12 monthly figures of a fiscal year are approved
- **THEN** a Year figure equals their sum

#### Scenario: Year from mixed data
- **WHEN** Q1 and Q2 are uploaded as quarters and Q3 and Q4 are complete months
- **THEN** a Year figure equals the sum of the four quarters

#### Scenario: Year is not produced for three quarters
- **WHEN** only Q1 to Q3 are covered
- **THEN** no Year figure is calculated

### Requirement: Forward-fill KPIs carry balances
For a forward-fill KPI, the system SHALL calculate a Quarter figure equal to the last month's value only when all 3
months of the quarter exist, SHALL calculate a YTD figure equal to the balance at each month that has one (and, at a
quarter end covered only by a Quarter figure, equal to that figure) whether or not earlier months exist, and SHALL
calculate a Year figure equal to the Q4 value only when all 4 quarters are covered.

#### Scenario: Gap does not stop forward-fill YTD
- **WHEN** balances exist for April, May, June, August and September but not July
- **THEN** the YTD for each of those five months equals that month's balance, the Q1 Quarter equals the June balance
  and no Q2 Quarter figure is calculated

#### Scenario: Incomplete quarter balance
- **WHEN** July and August balances exist but September does not
- **THEN** no Quarter figure is calculated and July YTD and August YTD equal the July and August balances

#### Scenario: Quarter then month balance
- **WHEN** a Q1 balance is uploaded as a Quarter figure and July has a balance
- **THEN** June YTD equals the Q1 balance and July YTD equals the July balance

#### Scenario: Later quarter balance without a month
- **WHEN** Q1 and Q2 balances are uploaded as Quarter figures and no month figures exist
- **THEN** June YTD equals the Q1 balance and September YTD equals the Q2 balance, not the sum of the two

### Requirement: Stale calculated figures are removed
When a recomputation shows that a previously calculated Quarter, YTD or Year figure no longer qualifies, the system
SHALL remove that calculated figure. Figures that were not calculated by the system SHALL NOT be removed.

#### Scenario: Month un-approved
- **WHEN** a calculated Q2 exists and one of its months is later un-approved and the KPI is recomputed
- **THEN** the calculated Q2 and any YTD that depended on it are removed

#### Scenario: Previously wrong partial quarter
- **WHEN** a calculated September Quarter figure was built earlier from only July and August
- **THEN** it is removed on the next recomputation

#### Scenario: Uploaded figure survives
- **WHEN** an uploaded Quarter figure sits where the rules would not calculate one
- **THEN** it is not removed

#### Scenario: Status judged against a removed figure refreshes
- **WHEN** a calculated Budget YTD figure is removed and an Actual YTD figure had its red, amber or green status judged
  against it
- **THEN** the Actual YTD figure's status is evaluated again without the removed figure

### Requirement: Future-dated Actual figures
The system SHALL NOT calculate Actual Quarter, YTD or Year figures dated after today. Budget and IC figures MAY be
future-dated.

#### Scenario: Budget quarter in the future
- **WHEN** all 3 months of a future quarter exist for Budget
- **THEN** the Quarter figure is calculated

#### Scenario: Actual quarter in the future
- **WHEN** all 3 months of a future quarter exist for Actual
- **THEN** no Quarter figure is calculated

### Requirement: Approval and recompute trigger
The system SHALL run these rules whenever KPIs are approved and whenever "Recompute Auto-Fill" is used, for the
affected portfolio company, KPI and tag only.

#### Scenario: Approval triggers calculation
- **WHEN** a fund manager approves the August figures
- **THEN** the YTD for the affected fiscal year is recalculated under these rules

### Requirement: One cumulation run per company at a time
The system SHALL NOT run two cumulations for the same portfolio company at the same time. A run requested while another
is in progress SHALL wait for it and then run on the data as it then stands.

#### Scenario: Company busy
- **WHEN** a cumulation is requested for a company whose cumulation is still running
- **THEN** the second run starts only after the first has finished and changes no figure before then

### Requirement: YTD percentage change is year over year
The system SHALL calculate the percentage change of a YTD figure against the YTD figure of the same KPI, tag and owner
dated exactly one year earlier, where a month-end date is matched to the month end one year earlier. The change SHALL
be empty when that figure does not exist or is zero. The system SHALL NOT fall back to any other figure.

#### Scenario: YTD compared with a year earlier
- **WHEN** the June 2026 YTD is 8,588,636 and the June 2025 YTD is 7,000,000 for the same KPI and tag
- **THEN** the June 2026 YTD percentage change is 22.69

#### Scenario: No YTD a year earlier
- **WHEN** a July 2026 YTD exists, a June 2026 YTD exists, and no July 2025 YTD exists
- **THEN** the July 2026 YTD percentage change is empty

#### Scenario: Year-earlier YTD is zero
- **WHEN** the year-earlier YTD figure is zero
- **THEN** the percentage change is empty

#### Scenario: Year-earlier month end differs
- **WHEN** the YTD is dated 28 February 2025 and the year-earlier YTD is dated 29 February 2024
- **THEN** the two are compared

#### Scenario: YTD change too large to store
- **WHEN** the year-over-year change of a YTD figure, rounded to two decimal places, is above 9,999.99 in absolute value
- **THEN** its percentage change is empty and the other YTD figures are still compared

#### Scenario: Tags compare separately
- **WHEN** Actual and Budget YTD figures exist for two consecutive years
- **THEN** each tag's percentage change is measured against its own tag a year earlier

#### Scenario: Owners compare separately
- **WHEN** YTD figures of two owners exist for the same KPI and tag in two consecutive years
- **THEN** each owner's percentage change is measured against that owner's own figure a year earlier

#### Scenario: Year-earlier figure removed
- **WHEN** a calculated YTD figure that a later YTD was compared with is removed and the percentage change is recomputed
- **THEN** the later YTD percentage change becomes empty

### Requirement: Other periods compare with the previous figure
The system SHALL keep calculating the percentage change of Month, Quarter and Year figures against the previous figure
of the same KPI, period, tag and owner.

#### Scenario: Month, Quarter and Year unchanged
- **WHEN** consecutive Month, Quarter and Year figures exist
- **THEN** each percentage change is measured against the previous figure of its own period

### Requirement: An empty percentage change is displayed safely
The KPI grid, the KPI page and the KPI list SHALL show "-" for an empty percentage change, and SHALL NOT apply a
red or green threshold colour to it or fail when the KPI mapping has thresholds.

#### Scenario: Empty change with thresholds set
- **WHEN** a YTD figure has an empty percentage change and its KPI mapping has a lower or upper threshold
- **THEN** the grid shows "-" with no colour and no error

### Requirement: Recompute corrects stored YTD changes
The existing percentage-change recompute SHALL replace previously stored YTD percentage changes with the year-over-year
values, and SHALL run after every cumulation started by an approval or by "Recompute Auto-Fill", so newly written or
removed YTD figures are compared correctly.

#### Scenario: Recompute corrects a previously stored YTD change
- **WHEN** a YTD figure holds a percentage change measured against the previous month and the recompute runs
- **THEN** its percentage change is measured against the YTD one year earlier

#### Scenario: Recompute Auto-Fill refreshes YTD changes
- **WHEN** a person uses "Recompute Auto-Fill" and the cumulation adds or removes YTD figures
- **THEN** the YTD percentage changes are recomputed afterwards without a separate "Recompute Percentages"
