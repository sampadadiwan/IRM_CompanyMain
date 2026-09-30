## Purpose

Keeps the row action buttons of tables managed by the `datatable` Stimulus controller visible
and on one line, whatever the browser zoom and however quickly the page's fonts and styles load.

## ADDED Requirements

### Requirement: Action buttons stay on one line
A table's action column (`td.action-col`) SHALL NOT wrap its buttons onto more than one line.

#### Scenario: First load before layout settles
- **WHEN** the investments index is opened with a cold cache
- **THEN** each row's Show / Edit buttons sit side by side on one line

### Requirement: The action column collapses last
When a responsive table is too wide for its container, data columns SHALL fold into the
expandable child row before the action column does. An action column header that already sets
`data-priority` SHALL keep its own priority.

#### Scenario: Table slightly too wide
- **WHEN** the investments index is shown at 110% zoom and does not fit its container
- **THEN** data columns are folded behind the ▶ toggle
- **AND** the Show / Edit buttons stay visible on each row

### Requirement: Fractional zoom does not collapse a table that fits
At a fractional `devicePixelRatio`, the check for which columns to collapse SHALL allow each
column 2px of rounding slack. At a whole-number ratio, the check SHALL be unchanged.

#### Scenario: Windows at 90% zoom
- **WHEN** a table that fits its container is shown at 90% zoom
- **THEN** no column, including the action column, is folded into the child row

#### Scenario: 100% zoom
- **WHEN** a table is shown at 100% zoom
- **THEN** its columns collapse exactly as they did before this change

### Requirement: Layout is re-measured once the page settles
After initialising a table, the controller SHALL recalculate its column widths and responsive
columns:
- once layout has settled (next frame, web fonts ready, window load)
- whenever the table container's width changes

It SHALL stop observing size changes when the controller disconnects.

#### Scenario: Sidebar toggled
- **WHEN** the sidebar is collapsed or expanded, changing the table container's width
- **THEN** the table recalculates which columns fit without a page reload

#### Scenario: Navigating away
- **WHEN** the page holding the table is left via Turbo navigation
- **THEN** the controller's resize observer is disconnected
