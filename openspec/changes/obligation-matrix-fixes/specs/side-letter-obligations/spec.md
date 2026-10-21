# Spec Delta

## MODIFIED Requirements

### Requirement: LP Obligation Matrix view
The system SHALL provide an obligation matrix listing obligations across all LPs with columns for investor, type, obligation title, owner, next due date, and status, filterable by obligation type, owner team, due date range, review status, legal category, fund, and stakeholder. The matrix SHALL support a `context` parameter that scopes the view: `cp_cs` shows only condition precedent and condition subsequent obligations, `side_letter` shows only side letter obligations, and no context shows all. The page title, informational banner, filter options, and column visibility SHALL adapt to the selected context. The `context` parameter SHALL be preserved across filter submissions and breadcrumb navigation. The matrix table SHALL support client-side column sorting.

#### Scenario: Matrix shows armed and dated obligations
- **WHEN** a fund has approved calendar-driven, one-time, and event-triggered obligations
- **THEN** dated obligations show their next due date and event-triggered obligations show as armed with no due date

#### Scenario: Filter by review status
- **WHEN** a user filters the matrix by `pending_review`
- **THEN** only unreviewed obligations are shown

#### Scenario: CP/CS context scopes to CP and CS only
- **WHEN** a user opens the matrix with context `cp_cs`
- **THEN** only condition precedent and condition subsequent obligations are shown, the title reads "CP/CS Obligation Matrix", and the legal category filter excludes the "Side Letter Obligation" option

#### Scenario: Side letter context scopes to SLO only
- **WHEN** a user opens the matrix with context `side_letter`
- **THEN** only side letter obligations are shown, the title reads "Side Letter Obligation Matrix", and the legal category column is hidden

#### Scenario: No context shows all obligations
- **WHEN** a user opens the matrix without a context parameter
- **THEN** all obligation types are shown, the title reads "LP Obligation Matrix", and all columns and filter options are visible

#### Scenario: Context preserved across filter submission
- **WHEN** a user is viewing the matrix in CP/CS context and applies a filter
- **THEN** the filtered results remain scoped to CP/CS obligations and the context is not lost

#### Scenario: Client-side sorting
- **WHEN** a user clicks a column header on the matrix table
- **THEN** the table rows are sorted by that column without a page reload

## ADDED Requirements

### Requirement: Legal category form submission uses string keys
The obligation edit forms (both the full form and the inline edit row) SHALL submit legal category values as string enum keys (e.g. "condition_precedent") rather than integer enum values. The Ransack filter dropdown on the matrix index page SHALL continue to use integer enum values for correct database-level comparison.

#### Scenario: Edit form saves legal category without error
- **WHEN** a user changes an obligation's legal category from "Condition Precedent" to "Condition Subsequent" on the edit form
- **THEN** the form submits with value "condition_subsequent" and the obligation is saved successfully

#### Scenario: Inline edit saves legal category without error
- **WHEN** a user changes an obligation's legal category on the inline edit row
- **THEN** the form submits with a string key and the obligation is saved successfully

#### Scenario: Ransack filter uses integer values
- **WHEN** a user selects "Condition Precedent" in the legal category filter on the matrix page
- **THEN** the filter query uses the integer enum value and returns matching obligations

### Requirement: Edit form scoping for CP/CS obligations
When editing a CP/CS obligation (legal category is condition precedent or condition subsequent), the form SHALL hide the MFN relevance checkbox and SHALL exclude the "Side Letter Obligation" option from the legal category dropdown, since those fields apply only to commitment-sourced obligations.

#### Scenario: MFN checkbox hidden for CP obligation
- **WHEN** a user edits an obligation with legal category "condition_precedent"
- **THEN** the MFN relevance checkbox is not visible on the form

#### Scenario: SLO excluded from category dropdown for CS obligation
- **WHEN** a user edits an obligation with legal category "condition_subsequent"
- **THEN** the legal category dropdown shows only "Condition Precedent" and "Condition Subsequent", not "Side Letter Obligation"

#### Scenario: Full form shown for SLO obligation
- **WHEN** a user edits an obligation with legal category "side_letter_obligation"
- **THEN** the MFN checkbox is visible and all legal category options are available

### Requirement: Breadcrumb reflects obligation context
The obligation matrix breadcrumb SHALL link back to the matrix preserving the current context parameter. The breadcrumb SHALL NOT include a misleading "Side Letters" link when viewing obligations that are not sourced from side letters.

#### Scenario: CP/CS matrix breadcrumb preserves context
- **WHEN** a user is viewing the CP/CS obligation matrix
- **THEN** the breadcrumb link includes `context=cp_cs` so clicking it returns to the CP/CS-scoped view

#### Scenario: No side letters link in CP/CS context
- **WHEN** a user is viewing the CP/CS obligation matrix
- **THEN** the breadcrumb does not contain a "Side Letters" link
