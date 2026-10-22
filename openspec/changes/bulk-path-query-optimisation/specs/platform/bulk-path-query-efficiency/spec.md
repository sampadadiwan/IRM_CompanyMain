# Spec Delta

## Purpose
Bulk jobs that process many records — capital call generation, KPI cumulation and upload, fund formula
import, portfolio re-valuation, and document checks on save — read shared data once per batch while
producing exactly the same results, failures and order of work as processing each record on its own.

## ADDED Requirements

### Requirement: Identical results from bulk jobs
Every bulk job covered by this capability SHALL produce the same records, values, ordering, audit
entries for records it saves, notifications and error messages as before this change, for the same input.

#### Scenario: Capital call generation produces the same remittances
- **WHEN** a capital call is generated for a fund with N commitments
- **THEN** exactly N remittances exist with the same call amounts, fees, statuses and payment dates as before the change

#### Scenario: A failing record fails the same way
- **WHEN** a record inside a bulk job fails validation
- **THEN** the job reports the same error for that record and records saved before it stay saved

### Requirement: Shared data read once per batch
A bulk job SHALL NOT re-read, for each record, data that is the same for every record in the batch or
that it already holds; it SHALL read such data at most once per batch of up to 1,000 records.

#### Scenario: Remittance follow-up saves load related records per batch
- **WHEN** remittances of a capital call are re-saved after generation
- **THEN** each remittance's investor, commitment, fund, entity and documents are read once per batch, not once per remittance

#### Scenario: Portfolio re-valuation totals per batch
- **WHEN** a re-valuation job processes M portfolio investments
- **THEN** the bought-unit and converted-unit totals are read once per batch, not once per investment

### Requirement: Rows created mid-job are visible to the rest of the job
When a bulk job creates a record that a later step of the same job would previously have found by
asking the database, the later step SHALL see that record.

#### Scenario: A cumulative report created for one period is reused
- **WHEN** KPI cumulation creates a Quarter report for a period and a later step needs the same period's report
- **THEN** the later step uses the created report and no duplicate report is created

#### Scenario: A repeated workbook cell updates the KPI it created
- **WHEN** a KPI workbook contains the same KPI twice for one period with the same value
- **THEN** the second cell updates the KPI created by the first, as today, and no duplicate KPI is created

### Requirement: Edge cases keep the original path
Where a shortcut could change an edge-case outcome, the job SHALL use the original per-record behaviour
for that case.

#### Scenario: Formula placed before existing formulas still shifts them
- **WHEN** an imported formula's sequence is at or below an existing formula's sequence in the same fund
- **THEN** the existing formulas are shifted down exactly as today

#### Scenario: Blank KPI tag keeps the live lookup
- **WHEN** a KPI being cumulated has no report tag
- **THEN** the target report is looked up exactly as today (without a tag filter)

#### Scenario: Documents are still validated on save
- **WHEN** a record with attached documents is saved by a bulk job and one document is invalid
- **THEN** the save fails exactly as today

### Requirement: No answer outlives the job that read it
Data read once for a batch SHALL be held only for the duration of that job or method call and SHALL NOT
be shared across requests, jobs or threads.

#### Scenario: A rule changed between two jobs is seen by the second
- **WHEN** a KPI mapping is edited after one cumulation job finishes and before the next starts
- **THEN** the next job uses the edited mapping
