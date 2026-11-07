# ui/dashboard-widgets Specification

## Purpose

Defines how dashboard widgets are chosen for a page and listed in its menu, how the Dashboard Widgets setup form names, explains and validates each setting, and how individual widgets honour their settings. Gives admins one predictable rule for what a page shows and ensures every setting offered on the form works.

## Requirements

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

### Requirement: Stats card fields are picked from a list in order
On the setup form of the "Portfolio Stats" widget (Portfolio Company Dashboard and Portfolio Dashboard) and the "Fund Portfolio Stats" widget (Fund Dashboard), the Fields setting SHALL be a multi-select offering exactly Bought Amount, Sold Amount, FMV, Cost Of Remaining, Income and Sold + FMV. The saved value SHALL list the picked cards, comma-separated, in the order they were picked. Reopening the form SHALL show the saved cards selected in their saved order. A saved name that is not one of the six cards SHALL NOT be offered and SHALL be dropped when the form is saved. The Field names setting SHALL show the hint "List the names in the same order as the Fields you picked, separated by commas. E.g. Bought Amount, Sold Amount, FMV → Buy, Sell, Fair value".

#### Scenario: Cards are saved in the order picked
- **WHEN** an admin picks FMV, then Bought Amount, in Fields on a Portfolio Stats widget and saves
- **THEN** the saved settings contain `fields: 'FMV, Bought Amount'`

#### Scenario: Saved cards reopen in their saved order
- **WHEN** an admin opens the setup form of a Portfolio Stats widget saved with `fields: 'Sold Amount, Bought Amount'`
- **THEN** Fields shows Sold Amount then Bought Amount selected

#### Scenario: Field names hint
- **WHEN** an admin opens the setup form of a Fund Portfolio Stats widget
- **THEN** the Field names setting shows helper text containing "same order as the Fields you picked"

### Requirement: Stats card fields match leniently and never empty the widget
The stats widgets SHALL match each saved field to a card ignoring letter case and surrounding spaces. When Fields is set but none of its entries matches a card, the widget SHALL show all its default cards. Field names SHALL relabel the shown cards by position; extra names SHALL be ignored and cards without a name SHALL keep their own name.

#### Scenario: Lower-case field names match
- **WHEN** a Portfolio Stats widget on the Portfolio Company Dashboard is saved with `fields: 'fmv, sold amount'`
- **THEN** the widget shows the FMV card then the Sold Amount card

#### Scenario: No field matches
- **WHEN** a Portfolio Stats widget is saved with `fields: 'Total FMV'`
- **THEN** the widget shows all its default cards

#### Scenario: Fewer names than cards
- **WHEN** a widget shows Bought Amount, Sold Amount and FMV with `field_names: 'Buy'`
- **THEN** the cards read Buy, Sold Amount and FMV

### Requirement: Stats widget setting changes show on the next load
A change to any setting that alters what a stats widget shows (Fields, Field names, Units, Decimals, Cards per row, Tracking currency, Show currency filter, Default currency) SHALL be visible the next time the page is loaded. Two widgets or pages that show the same company's or fund's stats with different settings SHALL NOT show each other's cards.

#### Scenario: Renamed label shows at once
- **WHEN** an admin changes Field names on a Portfolio Company Dashboard Portfolio Stats widget from "Buy" to "Invested" and reloads the dashboard
- **THEN** the card reads "Invested"

#### Scenario: Decimals change shows at once
- **WHEN** an admin changes Decimals on a Portfolio Stats widget from 2 to 0 and reloads the dashboard
- **THEN** the amounts show no decimal places

#### Scenario: Fund widget and Portfolio Investments page do not share cards
- **WHEN** the fund's Portfolio Stats widget is saved with `fields: 'FMV'` and a user opens the fund's Portfolio Investments page
- **THEN** the Portfolio Investments page shows its five default cards

### Requirement: Fund-level stats widgets honour the stats settings
The "Portfolio Stats" widget on the Portfolio Dashboard and the "Fund Portfolio Stats" widget on the Fund Dashboard SHALL honour Fields, Field names, Units, Decimals and Cards per row as the company widget does. Their cards SHALL be Bought Amount, Sold Amount, FMV, Cost Of Remaining and Income, plus Sold + FMV (Sold Amount plus FMV) only when picked in Fields. With no settings saved they SHALL show the same cards, units and decimals as before this change. The stats cards on the fund's Portfolio Investments page SHALL be unchanged. Under an Allocated LP portfolio view an LP's Portfolio Dashboard SHALL keep hiding the stats widget, whatever its settings, and the LP's folio totals on the Portfolio Investments page SHALL be unchanged. Amounts SHALL stay in the fund's currency.

#### Scenario: No settings, unchanged
- **WHEN** a user opens a fund's Portfolio Dashboard whose Portfolio Stats widget has no settings
- **THEN** the widget shows Bought Amount, Sold Amount, FMV, Cost Of Remaining and Income in the fund's default units with 2 decimals

#### Scenario: Picked fields and names
- **WHEN** the fund's Portfolio Stats widget is saved with `fields: 'FMV, Sold + FMV'` and `field_names: 'Value, Total value'`, with Sold Amount ₹40.00 Cr and FMV ₹310.00 Cr
- **THEN** the widget shows "Value" ₹310.00 Cr and "Total value" ₹350.00 Cr, in that order

#### Scenario: Units and decimals
- **WHEN** a Fund Portfolio Stats widget on the Fund Dashboard is saved with `force_units: 'Lakhs'` and `decimals: 0`
- **THEN** the amounts show in lakhs with no decimal places

#### Scenario: Cards per row
- **WHEN** the fund's Portfolio Stats widget is saved with `per_row: 2` and shows five cards
- **THEN** the cards are laid out two per row, the last card filling its row

#### Scenario: LP folio totals
- **WHEN** an LP under an Allocated LP portfolio view opens the fund's Portfolio Dashboard whose Portfolio Stats widget is saved with `fields: 'FMV'`
- **THEN** the dashboard shows the holdings list and no stats widget
- **AND** the LP's Portfolio Investments page shows the FMV total of the holdings allocated to their folio only

### Requirement: Stats and Data Card widgets offer only settings that work
The setup form of a new widget SHALL NOT offer:
- Data Card: Cols or Field names
- Portfolio Stats on the Portfolio Dashboard, and Fund Portfolio Stats on the Fund Dashboard: Currency, Tracking currency or Show currency filter

The Data Card offered to a new LP layout SHALL NOT carry a Cols setting.

#### Scenario: Data Card settings
- **WHEN** an admin adds a Data Card widget on the Portfolio Company Dashboard
- **THEN** the form offers Fields and Title
- **AND** there is no field for "cols" or "field_names"

#### Scenario: Fund stats settings
- **WHEN** an admin adds a Fund Portfolio Stats widget on the Fund Dashboard
- **THEN** there is no field for "currency", "tracking_currency" or "show_currency_filter"

#### Scenario: Company stats settings
- **WHEN** an admin adds a Portfolio Stats widget on the Portfolio Company Dashboard
- **THEN** the form offers Tracking currency, Show currency filter and Default currency
- **AND** Default currency is a pick-list of the firm's currency and the currencies it has exchange rates for
- **AND** Default currency shows the helper text "Order: picked on page > Tracking currency (if ON) > Default currency > firm's currency"

### Requirement: Company stats open in the default currency
The "Portfolio Stats" widget on the Portfolio Company Dashboard SHALL show its amounts in the first of: the currency the viewer picked in the widget's currency drop-down; the firm's tracking currency when Tracking currency is ON and the firm has one; the widget's Default currency (saved as `currency`) when it is the firm's currency or one it has exchange rates for; otherwise the firm's own currency. When the currency drop-down is shown, it SHALL list the currency in use and start on it. A saved Default currency the firm has no rates for SHALL be ignored without an error.

#### Scenario: Default currency used
- **WHEN** the firm's currency is INR, it has USD rates, Tracking currency is off, the widget is saved with `currency: 'USD'` and nothing is picked on the page
- **THEN** the cards show amounts in USD
- **AND** the currency drop-down, when shown, has USD selected

#### Scenario: Picked currency wins
- **WHEN** the widget is saved with `currency: 'USD'` and the viewer picks INR in the drop-down
- **THEN** the cards show amounts in INR

#### Scenario: Drop-down lists the firm's currencies
- **WHEN** the firm is in INR with SGD exchange rates and the widget shows the currency drop-down
- **THEN** the drop-down lists INR, SGD and any other currency the firm has rates for, the same currencies the metadata editor offers
- **AND** picking SGD shows the cards in SGD

#### Scenario: Tracking currency wins over the default
- **WHEN** the firm's tracking currency is USD, Tracking currency is ON and the widget is saved with `currency: 'INR'`
- **THEN** the cards show amounts in USD

#### Scenario: Default currency without rates
- **WHEN** the widget is saved with `currency: 'SGD'` and the firm has no SGD rates
- **THEN** the cards show amounts in the firm's own currency
- **AND** no error is shown

### Requirement: Data Card Fields shows lasting format help
The Data Card's Fields setting SHALL show, below the input and visible while typing, helper text explaining the `Label:field` format for standard fields and the `custom_fields.` prefix for custom fields, with the examples `Category:category`, `Sector:sector`, `City:city` and `KPI Currency:custom_fields.kpi_currency`.

#### Scenario: Help stays while typing
- **WHEN** an admin types "Category:" into the Data Card's Fields setting
- **THEN** helper text containing "custom_fields." is still shown below the input

### Requirement: Widget settings icon on fund-manager dashboards
Every widget rendered on a fund-manager dashboard (fund, portfolio, aggregated portfolio, portfolio company,
investor, ops and the fund-manager home page) SHALL carry a settings icon at the top-right of its card when the
viewer is allowed to edit the dashboard's widgets. The icon SHALL NOT be shown to a user acting as an investor,
on an LP layout, or on the LP company dashboard. The icon SHALL become visible when the pointer or keyboard
focus enters the widget and SHALL carry the tooltip "Change this widget's settings".

#### Scenario: A firm user sees the icon
- **WHEN** a Demo Capital employee opens the Portfolio tab of Fund 1
- **THEN** each widget shows a settings icon at its top-right when pointed at

#### Scenario: An LP never sees the icon
- **WHEN** a user acting as an investor opens any dashboard
- **THEN** no widget shows a settings icon

### Requirement: Settings popup
Clicking the settings icon SHALL open a popup over the dashboard titled "<widget name> settings" that shows the
same setting fields, labels and helper text as the widget's edit page, with the widget's current values, plus
the widget's Size. The popup SHALL state that changes apply to everyone in the firm who uses that layout of
that dashboard, and SHALL link to the widget's full edit page. A widget without settings of its own SHALL show
"This widget has no settings of its own" and Size only. Cancel, the close button and Esc SHALL close the popup
without saving.

#### Scenario: Popup shows current values
- **WHEN** Meera opens the settings of Valuation Freshness saved with `{current_days: 90, due_days: 180, limit: 15}`
- **THEN** the popup shows Current up to (days) 90, Due up to (days) 180, Rows to show 15 and the current Size

#### Scenario: Cancel changes nothing
- **WHEN** Meera changes Rows to show to 5 and clicks Cancel
- **THEN** the popup closes and the widget still shows 15 rows

### Requirement: Save and refresh in place
Save and refresh SHALL save the settings and Size with the same checks as the edit page. On success the popup
SHALL close and only that widget SHALL be reloaded with the saved settings, without reloading the rest of the
page or changing the scroll position; a size change SHALL take effect in the same refresh; a message
"<widget name> updated" SHALL be shown briefly. On a refused save the popup SHALL stay open, show the reason,
and nothing SHALL change on the page.

#### Scenario: Only the changed widget reloads
- **WHEN** Meera sets Rows to show to 5 on Valuation Freshness and clicks Save and refresh
- **THEN** Valuation Freshness shows 5 rows, the other widgets are not reloaded, and "Valuation Freshness updated" is shown

#### Scenario: A setting that is not a plain value is refused
- **WHEN** the settings hold an expression instead of a plain value and Meera clicks Save and refresh
- **THEN** the popup stays open with the reason and the widget is unchanged

### Requirement: First save on a dashboard showing its defaults
When the dashboard shows its default widgets because none is saved for that layout, the first Save and refresh
SHALL first save every widget the page shows, in the order shown and with their default size and display
options, and then apply the change to the chosen widget; the page SHALL then refresh in place and show the same
widgets in the same order.

#### Scenario: Ops Dashboard defaults are kept
- **WHEN** the Ops Dashboard of Demo Capital shows its 4 default widgets and Meera saves a change to My Tasks
- **THEN** 4 widgets are saved in the same order, My Tasks carries the change, and the page shows the same 4 widgets

### Requirement: Access to widget settings
Opening or saving a widget's settings SHALL be allowed only to users who may edit that widget on the widget edit
page, and SHALL be refused for a widget of another firm and for a user acting as an investor.

#### Scenario: Another firm's widget is refused
- **WHEN** a Demo Capital employee requests the settings of a widget that belongs to Other Capital
- **THEN** the request is refused and nothing is shown or saved

### Requirement: Motion
The icon, popup, in-place refresh and saved message SHALL animate briefly (fade, rise, shimmer, highlight) using
the theme's colours, and SHALL NOT animate when the user's system asks for reduced motion.

#### Scenario: Reduced motion
- **WHEN** a user with the reduced-motion system setting saves a widget's settings
- **THEN** the widget refreshes with the same result and no animation
