# Spec Delta

## MODIFIED Requirements

### Requirement: The action column collapses last
When a responsive table is too wide for its container, data columns SHALL fold into the
expandable child row before the action column does — except a table's first column (the record's
name), which SHALL keep the same top priority as the action column, so that at the narrowest widths
the name stays visible and the actions fold behind the ▶ toggle instead. An action column header
that already sets `data-priority` SHALL keep its own priority.

#### Scenario: Table slightly too wide
- **WHEN** the investments index is shown at 110% zoom and does not fit its container
- **THEN** data columns other than the first are folded behind the ▶ toggle
- **AND** the Show / Edit buttons stay visible on each row

#### Scenario: Phone width
- **WHEN** the Funds list is shown on a phone-width screen
- **THEN** each row shows the fund's name, and its actions open from the ▶ toggle
