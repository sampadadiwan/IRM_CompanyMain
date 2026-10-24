# Spec Delta

## Purpose

Lets the legacy bulk portfolio report flow build one Word document from an ordered list of report-and-template rows, so a cover, the per-company reports and a closing page come out as one file.

## ADDED Requirements

### Requirement: The company step guides the choice of companies
On the company step of the legacy bulk generate flow, **Next** SHALL be disabled until at least one portfolio company is chosen in the list, and SHALL be disabled again when none remains. When the user clicks **Preview** and no company matches the chosen filters, the page SHALL show the message "No portfolio companies match the selected filters."

#### Scenario: Next needs a company
- **WHEN** no company is chosen in the list
- **THEN** **Next** is disabled, and it becomes enabled as soon as a company is chosen

#### Scenario: Preview with no match says so
- **WHEN** the user clicks **Preview** and no company matches the filters
- **THEN** the message "No portfolio companies match the selected filters." is shown

### Requirement: The options step builds a list of report rows
The options step of the legacy bulk generate flow SHALL show a list of rows, each with a report and a template. It SHALL start with one row. The user SHALL be able to add rows and remove rows, but never remove the last remaining row. Each row's template choices SHALL be limited to the templates of that row's report. The order of the rows on screen SHALL be the order of the parts in the final document.

#### Scenario: Options start with one row
- **WHEN** the user arrives at the options step for three selected companies
- **THEN** exactly one row is shown, with the first report and its first template selected

#### Scenario: Add report adds a row
- **WHEN** the user clicks **Add report**
- **THEN** a new row appears below the others

#### Scenario: Remove report removes a row
- **WHEN** the list has two rows and the user clicks **Remove** on the first
- **THEN** only the second row remains

#### Scenario: The last row cannot be removed
- **WHEN** the list has one row
- **THEN** no **Remove** button is available for it

#### Scenario: Templates follow the row's report
- **WHEN** the user changes a row's report
- **THEN** that row lists only that report's templates and selects the first of them, and other rows are unchanged

### Requirement: Rows are checked in the browser before anything is sent
The options step SHALL check the rows in the browser, without contacting the server. When the user clicks **Generate Report**, the page SHALL NOT submit and SHALL show a message next to the offending row if any row has no template or if a template appears in more than one row. A row's message SHALL clear as soon as the row is fixed. When the user clicks **Generate Extracts Only** and every row is a consolidated report, the page SHALL NOT submit and SHALL show a message.

#### Scenario: Row without a template blocks the submit
- **WHEN** a row has no template and the user clicks **Generate Report**
- **THEN** nothing is sent, nothing is queued and the message "Choose a template for every report in the list." is shown next to that row

#### Scenario: Repeated template blocks the submit
- **WHEN** two rows have the same template and the user clicks **Generate Report**
- **THEN** nothing is sent, nothing is queued and the message "Each template can be used only once in a list. Remove the repeated template." is shown next to the repeated row

#### Scenario: A fixed row clears its message
- **WHEN** the user changes the repeated template to another one
- **THEN** the message next to that row disappears and **Generate Report** submits

#### Scenario: Extracts Only with consolidated reports only is blocked
- **WHEN** every row is a consolidated report and the user clicks **Generate Extracts Only**
- **THEN** nothing is sent and the message "Consolidated reports don't use extracts, so there is nothing to generate." is shown

### Requirement: The server repeats the checks as a backstop
The server SHALL NOT trust the browser. A request that reaches it with a row that has no template, a template in more than one row, a template that does not belong to its row's report, or a report that is not one of the user's entity's reports SHALL queue nothing. For the first three the user SHALL be returned to the company step with a message; the fourth is treated as not found.

#### Scenario: Posted row without a template is refused
- **WHEN** a request posts a row with no template
- **THEN** nothing is queued and the user is returned to the company step with "Choose a template for every report in the list."

#### Scenario: Posted repeated template is refused
- **WHEN** a request posts the same template in two rows
- **THEN** nothing is queued and the user is returned to the company step with "Each template can be used only once in a list. Remove the repeated template."

#### Scenario: Template from another report is refused
- **WHEN** a row's template belongs to a different report than the row's report
- **THEN** nothing is queued and the user is returned to the company step with "The selected template does not belong to the chosen report."

#### Scenario: Report from another entity is refused
- **WHEN** a request names a report that belongs to a different entity
- **THEN** nothing is queued and the report is treated as not found

#### Scenario: Companies from another entity are ignored
- **WHEN** a request names a portfolio company that belongs to a different entity
- **THEN** that company is left out and is never generated

### Requirement: The final document follows the order of the rows
The final document SHALL contain the parts in row order, with a page break between consecutive pieces. A normal report SHALL contribute one piece per selected company, ordered alphabetically by company name; a consolidated report SHALL contribute one piece for all companies. The ordering SHALL follow the on-screen order of the rows even when the submitted row numbers have gaps.

#### Scenario: Sections follow row order
- **WHEN** the rows are Cover and Summary (consolidated), Company One-Pager (normal) and Legal Disclaimer (consolidated), for Ace Limited, Beta Corp and Gamma Corp
- **THEN** the final document holds the cover, then the one-pagers for Ace, Beta and Gamma, then the disclaimer

#### Scenario: Companies alphabetical within a report
- **WHEN** a normal report is generated for companies selected as Gamma Corp, Ace Limited, Beta Corp
- **THEN** its pieces in the final document are in the order Ace, Beta, Gamma

#### Scenario: Gaps in row numbering keep the order
- **WHEN** rows are submitted numbered 0, 2 and 5
- **THEN** they are treated in the order 0, 2, 5

### Requirement: The final document takes the look of the first part
The final document SHALL use the first part's styles, page setup and running header and footer for the whole document. Later parts SHALL contribute their content only.

#### Scenario: Later parts adopt the first part's look
- **WHEN** parts built from different templates are joined
- **THEN** the combined file opens in Word without a repair prompt and shows every part's text and images

### Requirement: Only the combined document is saved as a new file
Each company's own document from a normal report SHALL be saved in that company's "Portfolio Reports" folder, as today. A consolidated part SHALL NOT be saved on its own. The combined document SHALL be saved in the entity's Portfolio Reports / Generated Portfolio Reports folder, named "<first row's template name> <start date> to <end date> - <N> companies", and carry the first row's template settings. When the list is exactly one normal report and one company, no combined document SHALL be created and that company's own document is the result.

#### Scenario: Company reports are saved as today
- **WHEN** a list with a normal report is generated for three companies
- **THEN** each company has its own one-pager in its "Portfolio Reports" folder

#### Scenario: Consolidated parts are not saved separately
- **WHEN** a list with a consolidated report is generated
- **THEN** no document exists for the consolidated part other than inside the combined document

#### Scenario: Combined file is saved and named
- **WHEN** the list of three rows is generated for three companies from 2026-01-01 to 2026-09-30
- **THEN** one document named "Cover and Summary 2026-01-01 to 2026-09-30 - 3 companies" exists in Portfolio Reports / Generated Portfolio Reports and the completion message links to it

#### Scenario: Lone company report creates no combined file
- **WHEN** the list is one normal report and one company
- **THEN** no combined document is created and the completion message links to that company's own report

#### Scenario: Consolidated-only list creates a combined file
- **WHEN** the list is a single consolidated report
- **THEN** a combined document holding just that part is saved and named as above

### Requirement: Problems in one part do not lose the others
A company with no extract SHALL still get its section (with "No data available" when "Generate missing report extracts" is off), and the completion message SHALL note the company as information, not as an error. If a company's section fails, or a consolidated part fails, the system SHALL report the failure in the completion message and error email and still join the remaining parts. If nothing could be generated, no combined document SHALL be created. If joining fails, the system SHALL report it and keep every company's own document.

#### Scenario: A company without data still gets a section
- **WHEN** Gamma Corp has no extract and "Generate missing report extracts" is off
- **THEN** its section reads "No data available" and the completion message names Gamma Corp as having no extract, without an error

#### Scenario: A failing company section does not stop the rest
- **WHEN** generating Beta Corp's one-pager fails
- **THEN** the error message names Beta Corp and the combined document still holds every other part

#### Scenario: A failing consolidated part does not stop the rest
- **WHEN** the Cover and Summary part fails
- **THEN** the error message names that part and the combined document still holds the other parts

#### Scenario: Nothing generated means no combined file
- **WHEN** every part fails
- **THEN** an error message is shown and no combined document is created

#### Scenario: Joining failure keeps company reports
- **WHEN** joining the parts fails
- **THEN** an error message is shown and each company's own document remains saved

### Requirement: Extracts are handled per normal report
"Generate Extracts Only" SHALL act on each distinct normal report in the list once, for the selected companies, and SHALL ignore consolidated reports. "Generate missing report extracts" SHALL create missing extracts for normal reports only, and an extract needed by two rows that use the same report SHALL be created once.

#### Scenario: Extracts only covers the normal reports
- **WHEN** the list has a consolidated report and a normal report and the user clicks **Generate Extracts Only**
- **THEN** extracts are generated for the normal report's companies and none for the consolidated report

#### Scenario: Posted extracts only with consolidated reports only
- **WHEN** a request posts Extracts Only with every row a consolidated report
- **THEN** nothing is queued and the user is returned to the company step with "Consolidated reports don't use extracts, so there is nothing to generate."

#### Scenario: Extracts are made once per report
- **WHEN** two rows use the same normal report with different templates and "Generate missing report extracts" is on
- **THEN** each company gets one extract for that report and both rows use it

### Requirement: Today's single-report behaviour keeps working
A request that carries one report and one template in the earlier form, and a run queued before this capability was released, SHALL behave as a list with one row.

#### Scenario: Single-report submit still works
- **WHEN** a request names one report and one template without a list of rows
- **THEN** it is treated as a list with one row

#### Scenario: Queued runs from before release still work
- **WHEN** a run queued with only a report, a template and the earlier options is performed after release
- **THEN** it generates as a list with one row

### Requirement: The flow keeps its existing access rules
Only users who may use the legacy bulk generate flow today SHALL be able to see the options step or queue a run, and every report, template and company used SHALL belong to the user's entity.

#### Scenario: Users without access are refused
- **WHEN** a user without access to portfolio reports posts to the options step
- **THEN** the request is refused and nothing is queued
