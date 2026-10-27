# Spec Delta

## Purpose

Lets a portfolio report be marked as consolidated, so that its Word template receives every selected portfolio company in one document, without using report sections or extracts.

## ADDED Requirements

### Requirement: A portfolio report can be marked consolidated
The portfolio report form SHALL offer a **Consolidated** checkbox. It SHALL be unticked for new reports and for every report that existed before this capability. A consolidated report SHALL be shown with "(Consolidated)" after its name wherever reports are chosen in the legacy bulk generate flow.

#### Scenario: Tick Consolidated and save
- **WHEN** a user with access to portfolio reports creates or edits a report, ticks **Consolidated** and saves
- **THEN** the report is saved as consolidated and the checkbox is ticked when the report is edited again

#### Scenario: Existing reports are not consolidated
- **WHEN** a report that existed before this capability is opened
- **THEN** **Consolidated** is unticked and the report generates exactly as before

#### Scenario: Consolidated label in report choices
- **WHEN** the options step of the legacy bulk generate flow lists the entity's reports and one of them is consolidated
- **THEN** that report's name is followed by "(Consolidated)" and the others are not

### Requirement: A report needs no section
Sections SHALL be optional for every report. A report SHALL be saved without any section: the blank section row the form shows by default is ignored, while a section that is filled in is validated and kept. A report SHALL count as ready, and be offered when generating, once it has a template, with or without sections. Generating a report's extract SHALL NOT call the LLM when the report has no sections. For a consolidated report the form SHALL also hide the Sections block, including **Add Section**, while **Consolidated** is ticked, and show it again when unticked.

#### Scenario: Tick Consolidated and the sections go away
- **WHEN** a user ticks **Consolidated** on the report form
- **THEN** the Sections block and **Add Section** are hidden, and shown again when the box is unticked

#### Scenario: Save a consolidated report with no section
- **WHEN** a user ticks **Consolidated**, gives the report a name and saves
- **THEN** the report is saved with no sections

#### Scenario: A normal report is saved without a section
- **WHEN** a user leaves **Consolidated** unticked, leaves the section blank and saves
- **THEN** the report is saved with no section

#### Scenario: A report without sections is ready
- **WHEN** a report has a template but no section
- **THEN** the reports list shows it as ready and it is offered when generating

### Requirement: A consolidated template receives every selected company
When a consolidated report's template is generated, the system SHALL make all selected portfolio companies available to the template as a list, ordered alphabetically by company name, each company once. Inside the list, each company SHALL expose a small set of merge fields: the company, its latest and earliest portfolio investment, its funds (each with name, currency, FMV, cost of investment, IRR, MOIC and a list of ratios) and its logo when it has one. A consolidated template SHALL NOT receive a normal template's other fields (KPIs, cap table, investments list, fund-named keys, extract data). The current date and the fund totals (next requirement) SHALL be available outside the list.

#### Scenario: All selected companies listed alphabetically
- **WHEN** a consolidated template that lists its companies is generated for Gamma Corp, Ace Limited and Beta Corp (selected in that order)
- **THEN** the document lists Ace Limited, then Beta Corp, then Gamma Corp, each once

#### Scenario: Each company shows its own fund ratios
- **WHEN** a consolidated template loops the companies, then each company's funds, then each fund's ratios
- **THEN** each company shows its own IRR and MOIC in each fund it invested in: the latest stored Default-scenario run on or before the end date, or "N/A" when the ratio was never run

#### Scenario: Company without investments or logo still listed
- **WHEN** one selected company has no investments and no logo
- **THEN** it is still listed, with no funds, and the document is generated

### Requirement: A consolidated template receives fund totals
When a consolidated report's template is generated, the system SHALL also make a list `fund_totals` available outside the company list, with one entry for each fund that at least one selected company has an investment in on or before the end date. Each entry SHALL expose the fund's `name` and `currency`, its `fmv` and `cost_of_investment` (each the sum over the selected companies' lines for that fund), and `custom_fields`: for every numeric custom field of the selected companies (number and money fields, found from the companies' form types), the sum of that field over the selected companies that have an investment in the fund. A company whose field is blank counts as zero. The totals SHALL be computed once from all selected companies, not per company, and SHALL NOT add anything to a company's own fields.

#### Scenario: Fund totals across the selected companies
- **WHEN** a consolidated template with a fund-totals row is generated for three companies that each invested in the same fund
- **THEN** the row shows that fund's FMV and cost of investment as the sum of the three companies' figures, and the sum of the three companies' `investment_commitment`

#### Scenario: One entry per fund, companies of that fund only
- **WHEN** two selected companies invested in fund Alpha and a third only in fund Beta
- **THEN** `fund_totals` lists Alpha, summed over the two companies, and Beta, summed over the third alone

#### Scenario: Blank and non-numeric custom fields
- **WHEN** one of the companies has no value for a numeric custom field, and the companies also have text custom fields
- **THEN** the blank counts as zero in that field's total, and no total is offered for the text fields

### Requirement: A consolidated report does not use extracts
Generating a consolidated report's template SHALL NOT read, create or require a report extract for any company, whether or not "Generate missing report extracts" is selected.

#### Scenario: No extract read or created
- **WHEN** a consolidated template is generated for three companies that have no extracts
- **THEN** the document is generated and no extract exists for any of the companies afterwards
