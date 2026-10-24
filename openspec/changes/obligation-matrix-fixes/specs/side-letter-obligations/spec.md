# Spec Delta

## MODIFIED Requirements

### Requirement: LP Obligation Matrix view
The system SHALL provide a single obligation matrix listing obligations across all LPs and portfolio investments with columns for investor, type, obligation title, legal category, owner, next due date, and status, filterable by obligation type, owner team, due date range, review status, legal category, fund, and stakeholder. The page title SHALL always be "LP Obligation Matrix" regardless of applied filters. The legal category dropdown filter SHALL be the primary scoping mechanism — selecting a value filters obligations to that type. Agents SHALL link to the matrix with the relevant `legal_category_eq` Ransack filter value pre-selected. The legal category column SHALL always be visible. The matrix table SHALL support client-side column sorting.

#### Scenario: Matrix shows armed and dated obligations
- **WHEN** a fund has approved calendar-driven, one-time, and event-triggered obligations
- **THEN** dated obligations show their next due date and event-triggered obligations show as armed with no due date

#### Scenario: Filter by review status
- **WHEN** a user filters the matrix by `pending_review`
- **THEN** only unreviewed obligations are shown

#### Scenario: Filter by legal category — Condition Precedent
- **WHEN** a user selects "Condition Precedent" in the legal category filter
- **THEN** only condition precedent obligations are shown

#### Scenario: Filter by legal category — Side Letter Obligation
- **WHEN** a user selects "Side Letter Obligation" in the legal category filter
- **THEN** only side letter obligations are shown

#### Scenario: No filter shows all obligations
- **WHEN** a user opens the matrix without any filter applied
- **THEN** all obligation types are shown, the title reads "LP Obligation Matrix", and all columns and filter options are visible

#### Scenario: Agent link pre-selects legal category filter
- **WHEN** a user clicks "Open Obligation Matrix" from the CP/CS agent page
- **THEN** the matrix opens with `legal_category_eq` pre-selected to Condition Precedent via Ransack query params

#### Scenario: Client-side sorting
- **WHEN** a user clicks a column header on the matrix table
- **THEN** the table rows are sorted by that column without a page reload

### Requirement: Stakeholder filter scoped by legal category
The stakeholder dropdown on the obligation matrix SHALL show different stakeholder options depending on the selected legal category filter. When the legal category is condition precedent or condition subsequent, the dropdown SHALL show portfolio companies (investors linked via portfolio investments). When the legal category is side letter obligation, the dropdown SHALL show LPs/investors (linked via capital commitments and side letters). When no legal category is selected, the dropdown SHALL show all stakeholders.

#### Scenario: CP/CS filter — stakeholder shows portfolio companies
- **WHEN** a user selects "Condition Precedent" in the legal category filter and clicks Filter
- **THEN** the stakeholder dropdown shows only portfolio companies that have CP/CS obligations

#### Scenario: SLO filter — stakeholder shows LPs
- **WHEN** a user selects "Side Letter Obligation" in the legal category filter and clicks Filter
- **THEN** the stakeholder dropdown shows only LPs/investors that have SLO obligations

#### Scenario: No filter — stakeholder shows all
- **WHEN** no legal category filter is selected
- **THEN** the stakeholder dropdown shows all stakeholders (both portfolio companies and LPs)

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

### Requirement: Breadcrumb does not mislead
The obligation matrix breadcrumb SHALL link back to the matrix. The breadcrumb SHALL NOT include a misleading "Side Letters" link when viewing obligations that are sourced from portfolio investments.

#### Scenario: Breadcrumb links to matrix
- **WHEN** a user is viewing the obligation matrix
- **THEN** the breadcrumb link goes to the matrix page

#### Scenario: No side letters link for portfolio-sourced obligations
- **WHEN** a user is viewing an obligation sourced from a portfolio investment
- **THEN** the breadcrumb does not contain a "Side Letters" link

### Requirement: Run SLO Agent from capital commitment page
The system SHALL display a "Run SLO Agent" button on each capital commitment's show page when the SLO agent is enabled for the entity. Clicking the button SHALL trigger SLO extraction for that single capital commitment and display a step-by-step progress panel. After completion, the "Open Obligation Matrix" link SHALL open the matrix with `legal_category_eq` pre-selected to Side Letter Obligation.

#### Scenario: SLO button visible when agent is enabled
- **WHEN** the SLO agent is enabled for the entity and a user views a capital commitment page
- **THEN** a "Run SLO Agent" button is visible

#### Scenario: SLO button hidden when agent is disabled
- **WHEN** the SLO agent is not enabled for the entity
- **THEN** no "Run SLO Agent" button appears on the commitment page

#### Scenario: Running SLO agent from commitment page shows progress
- **WHEN** a user clicks "Run SLO Agent" on a capital commitment page
- **THEN** a progress panel appears showing step indicators (Initialize, Locate Side Letter, Extract Obligations, Save For Review, Generate Report)

#### Scenario: SLO agent completion links to matrix with pre-selected filter
- **WHEN** the SLO agent completes for a commitment
- **THEN** the "Open Obligation Matrix" link opens the matrix with `legal_category_eq=2` (Side Letter Obligation) pre-selected
