# Spec Delta

## ADDED Requirements

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
