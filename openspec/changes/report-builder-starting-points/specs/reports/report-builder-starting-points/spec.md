# Spec Delta

## Purpose

Defines how a Report Builder report is started: the single New report entry, the starter templates and creating a report from one (with the fund it needs), the automatic check of every template, duplicating a report, and the names used for the builder and the guided setup.

## ADDED Requirements

### Requirement: One New report entry
The Reports page SHALL show users who can create reports a single **New report** menu with the choices **From a template** and **Guided setup**. It SHALL NOT show separate "New Custom Report" or "Builder Report" buttons. The list of standard (non-builder) reports SHALL be unchanged.

#### Scenario: One New report menu
- **WHEN** a user who can create reports opens the Reports page
- **THEN** one New report menu offers From a template and Guided setup, and no other builder button is shown

### Requirement: One name everywhere
The editor SHALL be called "Report builder" and the step-by-step flow "Guided setup" in menus, buttons and page titles. The words "Guided Wizard", "Advanced builder" and "Custom report" SHALL NOT appear.

#### Scenario: One name everywhere
- **WHEN** a user opens a builder report's card menu, the guided setup and the builder
- **THEN** they read "Guided setup" and "Duplicate", and none of the retired names

### Requirement: Templates grouped by area
The template page SHALL list the starter templates the company can use, grouped by area (Investors, Capital calls, Distributions, Fund overview, Portfolio, Compliance). A template SHALL be listed only when every table it uses belongs to a feature the company has.

#### Scenario: Templates grouped by area
- **WHEN** a user of a company with the Funds and Deals features opens the template page
- **THEN** all ten templates are listed under their areas

#### Scenario: Templates follow the company's features
- **WHEN** a company without the Funds feature opens the template page
- **THEN** templates that use fund, call, distribution or portfolio tables are not listed, and creating one directly is refused with "That template isn't available"

#### Scenario: Card says what the template answers
- **WHEN** the user reads a template card
- **THEN** it shows the template's name, the question it answers, the table it starts from, what it includes and whether it needs a fund

### Requirement: Create a report from a template
Using a template SHALL always create a new report; it SHALL NOT change an existing report. The new report SHALL have the template's columns (labels, totals, order including formula and pivot positions), related data, filters, formulas, pivots, sort and Excel grouping, and SHALL open in the builder with the message "Created from <template>". The name SHALL be the one typed; left as the template name or blank, it SHALL be the template name followed by " — <fund>" when a fund is chosen. A template whose definition is no longer valid SHALL create nothing.

#### Scenario: Create from a template with a fund
- **WHEN** a user creates *LP Capital Account Summary* for Growth Fund II
- **THEN** a new report "LP Capital Account Summary — Growth Fund II" opens in the builder with its columns, formulas, Category filter, the commitments limited to Growth Fund II and the sort by Unpaid

#### Scenario: Template without a fund
- **WHEN** a user uses a template that needs no fund
- **THEN** the popup has no Fund field and the report is created directly

#### Scenario: Template with a pivot
- **WHEN** a user creates a template with a pivot
- **THEN** the report shows one column per category value in the pivot's place

#### Scenario: Name typed by the user
- **WHEN** the user types their own name before creating
- **THEN** the report has exactly that name

#### Scenario: Blank name
- **WHEN** the user clears the name and creates
- **THEN** the report is named after the template and the chosen fund

#### Scenario: Unknown template
- **WHEN** a create request names a template that doesn't exist
- **THEN** "That template isn't available" is shown and nothing is created

#### Scenario: Broken template creates nothing
- **WHEN** a template refers to a column that no longer exists
- **THEN** "That template can't be used right now" is shown and no report or column is left behind

#### Scenario: Templates never change an existing report
- **WHEN** a user opens an existing report in the builder
- **THEN** there is no Templates button, and the old apply-template address no longer exists

### Requirement: The fund a template needs
A template that adds up amounts across funds SHALL require one fund and SHALL NOT offer "All funds". A template marked fund-optional SHALL offer "All funds" first. A template at fund level SHALL ask for no fund. The fund list SHALL contain only the company's funds. The fund SHALL limit the report's own rows when they have a fund, otherwise each related data whose rows have one.

#### Scenario: Required fund
- **WHEN** a user creates a fund-requiring template without choosing a fund
- **THEN** "Choose a fund — this template adds up amounts" is shown and nothing is created

#### Scenario: Optional fund
- **WHEN** a user creates a fund-optional template with All funds
- **THEN** the report has no fund filter

#### Scenario: Optional fund warns on mixed currencies
- **WHEN** a fund-optional report sums amounts from funds in different currencies
- **THEN** the report check warns that the amounts mix currencies

#### Scenario: Fund list
- **WHEN** the user opens the Fund list
- **THEN** only the company's own funds are listed

#### Scenario: Fund of another company
- **WHEN** a create request names another company's fund
- **THEN** it is refused (access denied) and nothing is created

### Requirement: Rows that are funds
When every row of a report is a fund, the report check SHALL NOT warn that a row mixes currencies; it SHALL note that the totals row adds funds in different currencies.

#### Scenario: Fund rows
- **WHEN** a report of funds in INR and USD sums commitments
- **THEN** the report check shows the note "The totals row adds funds in INR and USD" and no warning

### Requirement: Templates are checked
Every starter template SHALL be checked automatically: its table, related data, columns, totals, filter fields, formula columns, pivot fields and sort column SHALL exist, and it SHALL run. A failure SHALL name the template and the problem.

#### Scenario: Templates are checked
- **WHEN** the template check runs on the shipped templates
- **THEN** every template passes

#### Scenario: Check names template and column
- **WHEN** a template refers to a column that doesn't exist
- **THEN** the check fails naming the template and the column

### Requirement: Duplicate a report
A user who can create reports SHALL be able to duplicate a builder report of their company from its card menu and its report page. The copy SHALL be named "Copy of <name>", with " (2)", " (3)"… added while a report of the company has that name, and SHALL open in the builder with the message "Copied from <name>". It SHALL have the same columns (labels, totals, order including formula and pivot positions), related data, filters, formulas, pivots, sort, Excel grouping and display currency. It SHALL NOT copy the email schedule or a pending Undo. The original SHALL be unchanged.

#### Scenario: Duplicate copies the set-up
- **WHEN** a user duplicates a report
- **THEN** "Copy of <name>" opens in the builder with the same set-up

#### Scenario: The original is unchanged
- **WHEN** the user changes the copy
- **THEN** the original report is unchanged

#### Scenario: Copy name is unique
- **WHEN** "Copy of LPs" already exists and "LPs" is duplicated
- **THEN** the copy is named "Copy of LPs (2)"

#### Scenario: What isn't copied
- **WHEN** a scheduled report with a pending Undo is duplicated
- **THEN** the copy has no schedule and no Undo, and the original keeps both

#### Scenario: Duplicate across companies
- **WHEN** a user of another company asks to duplicate the report
- **THEN** the request is refused and nothing is created
