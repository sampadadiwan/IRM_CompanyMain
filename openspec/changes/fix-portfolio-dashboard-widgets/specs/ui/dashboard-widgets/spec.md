# Spec Delta

## Purpose

Defines how dashboard widgets are chosen for a page and listed in its menu, how the Dashboard Widgets setup form names, explains and validates each setting, and how the KPI Performance Table, Kpis, Key KPIs, Documents and Portfolio Investments widgets behave. Gives admins one predictable rule for what a page shows and ensures every setting offered on the form works.

## ADDED Requirements

### Requirement: Default widgets apply only when no widget is enabled
For a given dashboard, layout name and entity, the system SHALL show the dashboard's default widgets on the page and in the menu when no widget is enabled for it. A widget that exists but is disabled SHALL NOT count as enabled.

#### Scenario: No widget is configured
- **WHEN** a user opens a dashboard for which the entity has no widget rows
- **THEN** the page shows the default widgets
- **AND** the menu lists the default widgets

#### Scenario: Every configured widget is disabled
- **WHEN** a user opens a dashboard for which every widget row is disabled
- **THEN** the page shows the default widgets
- **AND** the menu lists the default widgets

### Requirement: The menu lists only widgets that are on the page and marked Show Menu
When at least one widget is enabled, the page SHALL show the enabled widgets in position order and the menu SHALL list as widget links exactly the enabled widgets that have Show Menu ticked. When no enabled widget has Show Menu ticked the menu row SHALL NOT be drawn at all, which also leaves out the Reports drop-down and the layout selector (an accepted limitation). The default widgets SHALL NOT appear on the page or in the menu while any widget is enabled. Each widget link SHALL lead to its widget on the page.

#### Scenario: Enabled widgets but none has Show Menu
- **WHEN** a user opens a dashboard where widgets are enabled and none has Show Menu ticked
- **THEN** the page shows the enabled widgets
- **AND** no menu row is drawn
- **AND** no default widget appears anywhere on the page

#### Scenario: Some enabled widgets have Show Menu
- **WHEN** a user opens a dashboard where three widgets are enabled and two have Show Menu ticked
- **THEN** the page shows all three widgets
- **AND** the menu lists only the two ticked widgets, in position order

#### Scenario: Menu links reach their widget
- **WHEN** a user clicks a widget link in the menu
- **THEN** the page moves to that widget

#### Scenario: A single enabled widget with Show Menu unticked
- **WHEN** a user opens a dashboard where only one widget is enabled and its Show Menu is unticked
- **THEN** the page shows that widget
- **AND** no menu row is drawn

#### Scenario: A disabled widget with Show Menu ticked
- **WHEN** a widget has Show Menu ticked but is disabled while another widget is enabled
- **THEN** the disabled widget appears neither on the page nor in the menu

#### Scenario: Menu row hides Reports and layout selector too
- **WHEN** a user opens a dashboard that has reports tagged for it and more than one layout, and no enabled widget has Show Menu ticked
- **THEN** no menu row is drawn, so the Reports drop-down and the layout selector are not shown either

#### Scenario: Same rules on every dashboard that has this menu
- **WHEN** a user opens the multi-portfolio dashboard or an LP company page whose enabled widgets have no Show Menu ticked
- **THEN** no menu row is drawn
- **AND** the default widgets are not added to the menu

#### Scenario: Enabled widgets all hidden by tags
- **WHEN** widgets are enabled but every one is hidden by tag filtering for the viewer
- **THEN** the page shows no widgets and the default widgets are not substituted

### Requirement: The setup form names and explains each setting from one definition
The Dashboard Widgets form SHALL show, for each setting of a widget, a human label and, where one is defined, a one-line helper text beneath the field. The wording for a setting SHALL be the same wherever the setting appears.

#### Scenario: Compound is shown as Data-only view with help
- **WHEN** an admin edits a Kpis widget
- **THEN** the setting formerly named Compound is labelled "Data-only view"
- **AND** helper text beneath it says ON groups KPIs by category as data only with chart selection off, and OFF shows the full table with a plot checkbox per KPI

#### Scenario: Show action buttons has helper text
- **WHEN** an admin edits a Kpis widget
- **THEN** the "Show action buttons" setting shows helper text saying ON shows the toolbar above the table and it is OFF by default

#### Scenario: Budget vs Actual offers only the default category
- **WHEN** an admin edits a Kpis Budget vs Actual widget
- **THEN** the form shows no Categories setting
- **AND** the "Default category" setting has one line of helper text saying it is pre-selected in the filter

#### Scenario: Saved Data-only view still applies
- **WHEN** a Kpis widget was saved earlier with Compound switched on
- **THEN** the widget still shows the grouped data-only view
- **AND** the form shows Data-only view as ON

### Requirement: Settings that have no effect are not offered
The form SHALL NOT show these settings: "Chart" on Kpis Performance Table, "Kpis" on Key Kpis, "Show table", "Show chart" and "Budget View" on Kpis, and "Entity" on Documents. A value previously saved for them SHALL be ignored when the widget renders. Clearing saved values from existing widgets is done by a one-off script outside this change.

#### Scenario: Settings with no effect are not offered
- **WHEN** an admin adds a Kpis Performance Table, Key Kpis, Kpis or Documents widget
- **THEN** the form shows none of the settings listed above for that widget

#### Scenario: Key KPIs shows the company's flagged KPIs
- **WHEN** a user opens a company page with a Key Kpis widget
- **THEN** the widget shows the KPIs flagged "show in report" for that company

### Requirement: ID settings accept whole numbers only
Settings that hold an ID (Documents "Owner ID" and "Folder ID") SHALL accept only whole numbers of 1 or more. The field SHALL not accept letters (including "e"), signs, or decimal points.

#### Scenario: Letters are refused
- **WHEN** an admin types "e12" into Folder ID
- **THEN** the field contains only "12"

#### Scenario: A whole number is saved
- **WHEN** an admin enters 42 as Folder ID and saves
- **THEN** the widget's saved settings hold folder_id 42

#### Scenario: Pasting mixed text keeps only digits
- **WHEN** an admin pastes "1.5e3" into Owner ID
- **THEN** the field contains only digits

### Requirement: Documents widget can show any folder the viewer may see
The Documents widget SHALL show the documents of the folder given by Folder ID, whichever folder it is, limited to documents the viewer is allowed to see.

#### Scenario: Folder outside the company's own folder
- **WHEN** a Documents widget has a Folder ID of a folder of the viewer's own entity that is not inside the company's folder
- **THEN** the widget lists that folder's documents the viewer may see

#### Scenario: Folder of another entity
- **WHEN** a Documents widget has a Folder ID of a folder belonging to another entity the viewer cannot access
- **THEN** the widget lists no documents and does not name the folder

#### Scenario: Folder not shared with an investor viewer
- **WHEN** an investor user opens the page and the Documents widget's Folder ID is a folder of the company that has not been shared with them
- **THEN** the widget lists no documents and does not name the folder

#### Scenario: Folder shared with an investor viewer
- **WHEN** the same folder and its documents have been shared with that investor
- **THEN** the widget lists the folder's own documents

#### Scenario: Folder viewed by an employee who is not a company admin
- **WHEN** an employee of the folder's entity without the company admin role opens the page
- **THEN** the widget lists the documents in the folder itself that the employee may see

### Requirement: KPI Performance Table lists the months that have reports
The month dropdown of the KPI Performance Table SHALL list every month for which the viewer may see a KPI report for the company, newest first, and the table SHALL open on the latest such month. Choosing any listed month SHALL show that month in one step.

#### Scenario: Dropdown lists all months with reports
- **WHEN** a company has KPI reports for Jan 2022, Oct 2025 and Mar 2026 and a user opens the table
- **THEN** the dropdown lists Mar 2026, Oct 2025 and Jan 2022 and no other month
- **AND** Mar 2026 is selected and its table is shown

#### Scenario: Reaching an old month in one step
- **WHEN** a user chooses Jan 2022 from the dropdown
- **THEN** the table shows Jan 2022
- **AND** the dropdown still lists all months

#### Scenario: Company has no KPI report
- **WHEN** a user opens the table for a company with no KPI report
- **THEN** the page says no KPI report was found
- **AND** the dropdown has no month choices

#### Scenario: Requested month has no report
- **WHEN** a user opens the table with a month that has no report and the company has reports for other months
- **THEN** the page says no report exists for that month
- **AND** offers the nearest months that do have reports

#### Scenario: Only reports the viewer may see
- **WHEN** a company has a report the viewer is not allowed to view
- **THEN** that report's month is not listed

### Requirement: The Kpis widget shows the KPI grid and has no Budget View setting
The Kpis widget SHALL always show the KPI grid. The form SHALL NOT offer Budget View on it; the Actual vs Budget table is provided by the Kpis Budget vs Actual widget. A previously saved `budget_view` value SHALL be ignored when the widget renders.

#### Scenario: Budget View is not offered
- **WHEN** an admin edits a Kpis widget
- **THEN** the form shows no Budget View setting
- **AND** Data-only view and Show action buttons are still shown

#### Scenario: Action buttons are off by default
- **WHEN** a user opens a company page with a Kpis widget that has no Show action buttons setting
- **THEN** the widget shows the KPI grid without the heading and the filter, chart and settings buttons

#### Scenario: Show action buttons shows them
- **WHEN** a user opens a company page with a Kpis widget saved with Show action buttons ON
- **THEN** the widget shows the heading and the filter, chart and settings buttons above the grid

#### Scenario: Kpis widget shows the KPI grid
- **WHEN** a user opens a company page with a Kpis widget
- **THEN** the widget shows the KPI grid

#### Scenario: Existing widget saved with Budget View
- **WHEN** a Kpis widget was saved earlier with budget_view true
- **THEN** it shows the KPI grid

### Requirement: Group by column is a choice of the grid's columns
For the Portfolio Investments widget the form SHALL offer "Group by column" as a list of the columns of the portfolio investments grid, each shown with its on-screen name, including Fund Name. A chosen column SHALL take effect whether AG Grid is ON, OFF or Default. A previously saved value SHALL be kept and shown.

#### Scenario: List shows the grid's columns
- **WHEN** an admin edits a Portfolio Investments widget
- **THEN** "Group by column" is a list whose entries are the grid's columns with their on-screen names
- **AND** the list includes "Fund Name"

#### Scenario: Grouping with AG Grid off
- **WHEN** a Portfolio Investments widget has a group column chosen and AG Grid is OFF
- **THEN** the widget shows the investments grid grouped by that column

#### Scenario: Grouping with AG Grid default
- **WHEN** a Portfolio Investments widget has a group column chosen and AG Grid is not set
- **THEN** the widget shows the investments grid grouped by that column

#### Scenario: No group column
- **WHEN** a Portfolio Investments widget has no group column and AG Grid is OFF
- **THEN** the widget shows the aggregate table as before

#### Scenario: Saved value is preserved
- **WHEN** a widget was saved with a group value that is not a single listed column, such as "fund_name, investment_instrument_name"
- **THEN** the form shows that value as the current choice
- **AND** saving the widget keeps it unchanged
