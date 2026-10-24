# Spec Delta

## Purpose

Makes portfolio report extracts more useful on their own: they can be built for companies that have no documents, the dashboard widget shows the latest extract that actually has data, and an extract can be deleted from its details page.

## ADDED Requirements

### Requirement: Extracts are generated for companies without documents
When extract generation finds no source documents for a company and period, the system SHALL still build the extract from the company's notes for that period and the KPIs of its latest KPI report in that period (the same "latest wins" rule as for documents), and SHALL warn the user that no documents were found. The KPIs SHALL be used only in this case; an extract built from documents SHALL be built exactly as before. When the company has no documents, no notes and no KPIs for the period, the system SHALL NOT call the language model, SHALL leave the extract empty, and SHALL report the company as it does today.

#### Scenario: Notes and KPIs stand in for missing documents
- **WHEN** extracts are generated for a company that has notes and KPIs in the period but no documents
- **THEN** the extract is built from the notes and the KPIs, it records no source documents, and a warning says no documents were found and the extract was built from notes and KPIs

#### Scenario: A bulk run warns once
- **WHEN** extracts are generated in one bulk run for several companies without documents
- **THEN** the user gets one warning at the end that lists every such company, not one per company

#### Scenario: KPIs alone are enough
- **WHEN** extracts are generated for a company that has KPIs in the period but no documents and no notes
- **THEN** the extract is built from the KPIs

#### Scenario: Extracts built from documents are unchanged
- **WHEN** extracts are generated for a company that has source documents
- **THEN** the KPIs are not added to what the language model receives and no warning is shown

#### Scenario: Nothing at all leaves the extract empty
- **WHEN** extracts are generated for a company with no documents, no notes and no KPIs in the period
- **THEN** the language model is not called, the extract is created empty, and the company is reported as having nothing to extract from

### Requirement: The dashboard widget shows the latest extract that has data
The portfolio report widget SHALL show, for the company and the configured report, the latest extract whose data is not blank. Extracts are ordered by end date, then by creation order. An extract whose data is blank SHALL be skipped in favour of the previous one. When no extract of the company and report has data, the widget SHALL stay hidden.

#### Scenario: A blank latest extract is skipped
- **WHEN** a company's latest extract for the report has no data and the one before it has data
- **THEN** the widget shows the earlier extract's data

#### Scenario: The latest extract with data wins
- **WHEN** a company has two extracts with data for the report
- **THEN** the widget shows the one with the later end date

#### Scenario: Only blank extracts hide the widget
- **WHEN** every extract of the company for the report has no data
- **THEN** the widget is not shown

### Requirement: An extract can be deleted from its details page
Only company admins may delete extracts. The details page of an extract SHALL offer a **Delete** button to users who may delete extracts. The button SHALL ask for confirmation. Confirming SHALL delete the extract and return the user to the list of extracts of that report with a confirmation message. Users without permission SHALL NOT see the button, and a request to delete an extract of another entity SHALL be refused.

#### Scenario: Delete with confirmation
- **WHEN** a permitted user opens an extract's details, clicks **Delete** and confirms
- **THEN** the extract is deleted and the user sees the list of extracts of that report with a confirmation message

#### Scenario: Cancelling keeps the extract
- **WHEN** the user clicks **Delete** and cancels the confirmation
- **THEN** the extract still exists

#### Scenario: Only company admins may delete
- **WHEN** a user who is not a company admin sends a request to delete an extract
- **THEN** the request is refused, the extract remains, and the policy does not allow deletion for that user

#### Scenario: Another entity's extract cannot be deleted
- **WHEN** a request names an extract that belongs to a different entity
- **THEN** nothing is deleted and the extract is treated as not found

#### Scenario: A deleted extract is regenerated when asked
- **WHEN** an extract has been deleted and a report is generated for that company and period with "Generate missing report extracts" on
- **THEN** a new extract is generated; with it off, the report shows "No data available" for that company
