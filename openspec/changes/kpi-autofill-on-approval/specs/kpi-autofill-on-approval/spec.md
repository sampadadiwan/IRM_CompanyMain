# Spec Delta

## Purpose

Automatically recomputes cumulative KPI values (Quarter, YTD, Year) and percentage changes (MoM/YoY) when monthly KPIs are approved, scoped to only the affected reports, eliminating the need for manual "Recompute Cumulative" action.

## ADDED Requirements

### Requirement: Approval triggers scoped cumulation

The system SHALL enqueue a cumulation job immediately after KPIs are approved, restricted to only the source reports of the approved KPIs, with forced reprocessing that bypasses any prior completion gate.

#### Scenario: Approve monthly KPIs auto-populates quarterly and YTD values

- **WHEN** a fund manager approves monthly KPIs (e.g., Jan, Feb, Mar Revenue) for a portfolio company with a cumulate-type autofill mapping
- **THEN** the Quarter, YTD, and Year columns display the cumulated sum within the background job processing window, without any manual recompute action

#### Scenario: Only affected reports are reprocessed

- **GIVEN** a portfolio company with KPI reports across multiple quarters
- **WHEN** a user approves KPIs belonging to only one quarter's monthly reports
- **THEN** the cumulation job processes only the approved reports and their downstream cumulative reports, not the entire portfolio company's report set

### Requirement: Force bypass of completion gate

The cumulation job SHALL accept a force mode that reprocesses reports regardless of whether they were previously marked as complete. Approval SHALL always invoke this force mode.

#### Scenario: Re-approval after prior cumulation updates values

- **GIVEN** a portfolio company whose Q1 cumulative KPIs were already computed from a previous approval
- **WHEN** a user corrects and re-approves a January KPI value
- **THEN** the Q1 cumulative value is recomputed with the corrected input, not skipped as already complete

### Requirement: Mapping backfill on cumulated KPIs

The cumulation process SHALL assign an investor KPI mapping to existing cumulated KPI records that lack one, using the source KPI's mapping or a fallback lookup by standard name. Records SHALL be saved when only the mapping changed, even if the numeric value is unchanged.

#### Scenario: Legacy cumulated KPI without mapping gets backfilled

- **GIVEN** a cumulated KPI record with no investor KPI mapping assigned (created before mapping inheritance was introduced)
- **WHEN** the cumulation job processes that record
- **THEN** the record's mapping is set from the source KPI's mapping or a fallback by standard name, and the KPI displays correctly in grid view instead of showing "N/A"

#### Scenario: Mapping-only change triggers save

- **GIVEN** a cumulated KPI whose numeric value matches the recomputed sum but has no mapping assigned
- **WHEN** the cumulation job runs
- **THEN** the record is saved with the backfilled mapping, not skipped as unchanged

### Requirement: Percentage changes computed after cumulation

The system SHALL compute MoM and YoY percentage changes inline after cumulation completes when triggered by approval, guaranteeing that percentage values reflect freshly cumulated data.

#### Scenario: MoM/YoY percentages update after approval

- **GIVEN** monthly KPIs for Jan and Feb with a cumulate-type autofill mapping
- **WHEN** both months are approved
- **THEN** after the cumulation job completes, MoM percentage change between the two months is computed and visible in the grid

### Requirement: Manual recompute remains available

The existing "Recompute Cumulative" action SHALL continue to function as a fallback, processing all reports for the portfolio company regardless of approval state.

#### Scenario: Manual recompute still works

- **GIVEN** a portfolio company with approved KPIs
- **WHEN** a fund manager triggers the manual "Recompute Cumulative" action
- **THEN** all cumulative values across all reports are reprocessed, matching pre-existing behavior

### Requirement: Scalar portfolio company ID in approval path

The approval service SHALL pass a single integer portfolio company ID to the cumulation job, not an array. The cumulation job's Phase 2 (Compute) SHALL wrap the portfolio company ID in `Array()` as a defensive guard against callers that might pass an array.

#### Scenario: Single KPI approval passes scalar ID

- **WHEN** a fund manager approves a single KPI for a portfolio company
- **THEN** the cumulation job receives a scalar integer `portfolio_company_id`, not an array, and Phase 2 Compute correctly queries reports for that company

#### Scenario: Array input does not break Compute phase

- **GIVEN** a caller passes an array of portfolio company IDs to the cumulation job
- **WHEN** Phase 2 (Compute) iterates over the IDs
- **THEN** each ID is unwrapped to a scalar integer via `Array()`, and `Kpi.new(portfolio_company_id: id)` receives a valid integer (not nil)

### Requirement: Forward fill quarterly fallback

The forward fill process SHALL derive YTD values from Quarter KPIs when a company reports quarterly with no monthly data. Fiscal years that already have monthly data SHALL be skipped to avoid double-processing.

#### Scenario: Quarterly-only company gets YTD values via forward fill

- **GIVEN** a portfolio company that reports quarterly (no monthly KPI reports exist) with a forward-fill-type autofill mapping
- **WHEN** the cumulation job processes that company's reports
- **THEN** YTD values are derived from the Quarter KPIs, and Year values are created from Q4 when all 4 quarters are present

#### Scenario: Mixed reporting skips quarterly fallback for months with data

- **GIVEN** a portfolio company with monthly data for FY2025 but quarterly-only data for FY2024
- **WHEN** the forward fill runs
- **THEN** FY2025 YTD is derived from monthly data (existing behavior) and FY2024 YTD is derived from quarterly data (fallback), with no double-processing

### Requirement: Approval notice informs user of background processing

The approval actions (`approve`, `approve_all`) SHALL display a notice message informing the user that cumulative values are being computed and to refresh the page in a few seconds.

#### Scenario: User sees background processing notice after approval

- **WHEN** a fund manager approves one or more KPIs
- **THEN** the page displays a notice: "Cumulative values are being computed — refresh the page in a few seconds"

### Requirement: Scoped report processing in cumulation job

The cumulation job SHALL accept an optional set of report IDs. When provided, only those reports SHALL be processed (ordered chronologically), bypassing the normal completion and recency gates. When not provided, existing gate behavior SHALL be unchanged.

#### Scenario: Job with report IDs processes only specified reports

- **GIVEN** a portfolio company with 12 monthly reports
- **WHEN** the cumulation job is invoked with 3 specific report IDs
- **THEN** only those 3 reports and their downstream cumulative reports are processed

#### Scenario: Job without report IDs preserves existing behavior

- **WHEN** the cumulation job is invoked without report IDs and without force mode
- **THEN** only reports not yet marked as complete or within the recency window are processed, matching existing behavior
