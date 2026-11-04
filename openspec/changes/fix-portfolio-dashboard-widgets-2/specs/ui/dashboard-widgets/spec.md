# Spec Delta

## Purpose

Defines how dashboard widgets are chosen for a page and listed in its menu, how the Dashboard Widgets setup form names, explains and validates each setting, and how individual widgets honour their settings. Gives admins one predictable rule for what a page shows and ensures every setting offered on the form works.

## ADDED Requirements

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
