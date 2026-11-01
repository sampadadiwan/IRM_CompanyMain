# Spec Delta

## Purpose

Defines the Report Builder guided wizard: five steps from choosing what each row is to saving the report, with a live sample, fund selection, suggested calculations and a check-and-save page shared with later guided flows.

## ADDED Requirements

### Requirement: Step 1 — what is each row
The wizard SHALL start with one card per reportable table, each with an icon and an example question, and SHALL create an untitled report for the chosen table without asking for a name.

#### Scenario: Cards with examples
- **WHEN** a user starts the guided wizard
- **THEN** every reportable table is shown as a card with an icon and an example question

#### Scenario: No name yet
- **WHEN** the user chooses the Investors card
- **THEN** an untitled Investor report is created and step 2 opens

#### Scenario: Unknown table
- **WHEN** a request names a table that is not reportable
- **THEN** step 1 is shown again with an error and no report is created

### Requirement: Step 2 — what to show
Step 2 SHALL list, in one picker, the row's own columns and each available related data's stored columns, grouped by source. Choosing Add selected SHALL add any related data needed and the ticked columns, saving each related column's default total, shown and changeable inline. Tables with no related data SHALL show their own columns only.

#### Scenario: Own and related columns together
- **WHEN** the user ticks Stakeholder, Committed and Called and chooses Add selected
- **THEN** capital commitments is added as related data, the three columns are added, and Committed and Called show Sum

#### Scenario: Change a total inline
- **WHEN** the user changes Called to Count
- **THEN** Count is saved and the sample shows the counts

#### Scenario: Many related sources
- **WHEN** the table has several related sources
- **THEN** its own columns are listed open first and each related source is listed closed below them

### Requirement: Live sample
From step 2 onwards, each step SHALL show beside it the first five rows of the report with its totals, formatted as in the preview.

#### Scenario: Sample beside the step
- **WHEN** the user is on step 3
- **THEN** a five-row sample with totals is shown beside it

### Requirement: Step 3 — fund and filters
When the row or any related data has a fund, step 3 SHALL offer a fund picker of the entity's funds and "All funds"; choosing a fund SHALL filter the row's own fund when it has one, otherwise each related data that has a fund; "All funds" SHALL remove that filter. Filters SHALL be added with the typed inputs of the builder and read back as sentences.

#### Scenario: Fund on related data
- **WHEN** an Investor report with capital commitments picks Growth Fund II
- **THEN** capital commitments is filtered to Growth Fund II and the summary reads "Only commitments in Growth Fund II"

#### Scenario: All funds
- **WHEN** the user picks All funds
- **THEN** the fund filter is removed

#### Scenario: No fund
- **WHEN** neither the row nor its related data has a fund
- **THEN** no fund picker is shown

#### Scenario: Sentence filters
- **WHEN** the user adds Category is LP
- **THEN** it reads "Only include investors where Category is LP"

### Requirement: Step 4 — order and suggested calculations
Step 4 SHALL set the sort and SHALL suggest calculations from pairs of picked columns of the same source — Called % (called and committed), Unpaid (called and collected), Uncalled (committed and called), DPI (distributed and collected) — each added as a formula with one click, already-added ones marked Added, and a message when none apply.

#### Scenario: Suggestions offered
- **WHEN** Committed, Called and Collected from capital commitments are picked
- **THEN** Called %, Unpaid and Uncalled are suggested with their expressions in words

#### Scenario: Add a suggestion
- **WHEN** the user adds Called %
- **THEN** a Called % formula is saved and the suggestion shows Added

#### Scenario: Nothing to suggest
- **WHEN** no pair applies
- **THEN** the step says there are no suggestions for these columns

### Requirement: Step 5 — check and save
Step 5 SHALL show a summary of the report as cards — one row per, columns with their source and total, only include, sorted by, calculations — each opening its step; the health check; the preview with totals; and a suggested name built from the table, the main columns and the fund. Save and open SHALL save the name (the suggestion when left blank) and open the report page; Fine-tune in builder SHALL open the builder.

#### Scenario: Summary and suggested name
- **WHEN** the user reaches step 5 for the Part B report
- **THEN** the cards describe it and the name box shows "Investors — Committed, Called — Growth Fund II"

#### Scenario: Card opens its step
- **WHEN** the user clicks the Only include card
- **THEN** step 3 opens

#### Scenario: Save and open
- **WHEN** the user chooses Save and open
- **THEN** the report is named and its report page opens

#### Scenario: Blank name
- **WHEN** the name box is cleared and Save and open is chosen
- **THEN** the suggested name is used

#### Scenario: Fine-tune
- **WHEN** the user chooses Fine-tune in builder
- **THEN** the builder opens for the report

### Requirement: Old wizard links
Links to the previous wizard steps SHALL open the matching new step: Columns, Related Data and Summarize open What to show; Filters opens Fund and filters; Sort opens Order and calculations; Review opens Check and save.

#### Scenario: Old link
- **WHEN** a user opens an old Summarize step link
- **THEN** the What to show step opens

### Requirement: Access
Every wizard step and action SHALL be limited to users who may edit the report.

#### Scenario: Another entity
- **WHEN** a user of another entity opens a wizard step of the report
- **THEN** access is refused
