# Spec Delta

## Purpose

Defines the Report Builder editing page: a live preview that updates with every change, settings in tabs, bulk column adding, per-column header menus, typed autosaving filters, a formula editor, undo for removals, a health check and a pivot preview.

## ADDED Requirements

### Requirement: Live preview
The builder SHALL show the preview when it opens, without a manual refresh. After any change to columns, totals, labels, order, related data, filters, sort, formulas or pivots, it SHALL update the settings panel, the preview and the health indicator without reloading the page, keeping the open tab. A preview error SHALL appear inside the preview area while the settings stay usable.

#### Scenario: Preview on open
- **WHEN** a user opens the builder for a report with columns
- **THEN** the preview with its rows and totals is shown without clicking Refresh Preview

#### Scenario: Change updates panel and preview
- **WHEN** the user changes a total from Sum to Count
- **THEN** the preview shows the counts and the settings panel shows Count, without a page reload

#### Scenario: Preview error contained
- **WHEN** the preview cannot be produced
- **THEN** an error message appears in the preview area and the settings tabs still work

### Requirement: Column picker with grouping and bulk add
The Columns tab SHALL list the row's own columns and each related data's stored columns, grouped by source and then by kind (Amounts, Dates, Yes/No, Names & text), with type icons. It SHALL NOT list internal identifier (`…_id`) or cents (`…_cents`) fields, and SHALL tell apart two fields with the same label. Ticking columns and choosing Add selected SHALL add every ticked column in one request, skip columns already in the report, and refuse any column that is not allowed while adding the rest.

#### Scenario: Grouped list without internal fields
- **WHEN** the user opens the Columns tab of an Investor report with capital commitments
- **THEN** the list shows "About the investor" and "From capital commitments", grouped by kind, and no field ending in _id or _cents

#### Scenario: Same label told apart
- **WHEN** a table has two fields labelled alike
- **THEN** each shows a distinguishing hint

#### Scenario: Add several at once
- **WHEN** the user ticks three columns and chooses Add selected
- **THEN** all three are added in one update and the related amounts get their default totals

#### Scenario: Already added and refused columns
- **WHEN** the selection includes a column already in the report and one that is not allowed
- **THEN** the existing one is skipped, the disallowed one is named in an error, and the others are added

#### Scenario: Nothing ticked
- **WHEN** no column is ticked
- **THEN** Add selected is disabled

### Requirement: Column header menu
Each preview column SHALL have a menu offering Rename, Total (only for many-per-row related columns, in plain words), Move left, Move right and Remove. Formula columns SHALL offer Move and Edit in Formulas; a pivot's columns SHALL move together as a block. Move SHALL be unavailable past either end. A blank rename SHALL restore the original label.

#### Scenario: Rename
- **WHEN** the user renames Committed to "Total committed"
- **THEN** the header shows "Total committed" in the preview, on the report page and in Excel

#### Scenario: Blank rename
- **WHEN** the user clears the name
- **THEN** the original label is restored

#### Scenario: Move
- **WHEN** the user moves a column right
- **THEN** it swaps with its right neighbour everywhere the report is shown

#### Scenario: No total on one-per-row columns
- **WHEN** the user opens the menu of a commitment's fund name
- **THEN** no Total choice is offered

#### Scenario: Ends
- **WHEN** the column is first
- **THEN** Move left is unavailable

### Requirement: Typed filters that save themselves
Each filter SHALL offer an input and operators matching its field: the locale date input for dates; Yes/No for yes/no fields; the entity's funds by name for a fund field; a pick-list of existing values for text fields with at most 30 distinct values on tables other than account entries, capital remittances, capital distribution payments and documents; a number box for amounts and numbers; otherwise a text box. Operators SHALL be in plain words. A filter SHALL be saved shortly after it changes; a row without a value SHALL not be saved and SHALL say it needs a value; an unreadable date SHALL be refused with an example of the expected format.

#### Scenario: Date filter
- **WHEN** the user filters Commitment date "is on or after" 01/02/2026 in the date input
- **THEN** the filter is saved and the preview shows only matching rows

#### Scenario: Pick-list and fund picker
- **WHEN** the user filters Category and the fund of capital commitments
- **THEN** Category offers the existing values and Fund offers the entity's funds by name

#### Scenario: Large table field
- **WHEN** the user filters Status on capital remittances
- **THEN** a text box is offered, without a list of values

#### Scenario: Many values
- **WHEN** a text field has more than 30 distinct values
- **THEN** a text box is offered

#### Scenario: Missing value
- **WHEN** a filter row has a field and operator but no value
- **THEN** it is not saved and the row says it needs a value

#### Scenario: Unreadable date
- **WHEN** the typed date cannot be read
- **THEN** the filter is not saved and the message shows a date in the expected format

### Requirement: Formula editor
The formula editor SHALL list the report's columns and formulas and insert a clicked one at the cursor in the expression. While the expression changes it SHALL show the result for the first five rows, or the error in plain words, and SHALL allow adding the formula only when it evaluates.

#### Scenario: Insert a column
- **WHEN** the user clicks Called in the editor
- **THEN** `[capital_commitments.call_amount]` is inserted at the cursor

#### Scenario: Sample results
- **WHEN** the expression is valid
- **THEN** the results for the first five rows are shown next to their row names

#### Scenario: Invalid expression
- **WHEN** the expression does not evaluate
- **THEN** the error is shown and Add Formula is disabled

### Requirement: Undo removal
Removing a column or related data SHALL offer Undo. Undo SHALL restore exactly what was removed — columns with their labels, totals and positions, and related data with its filters and pivot — when used within 10 minutes and before any other change to the report; otherwise it SHALL refuse with the reason. Removing related data SHALL first show an Immediate Actions confirmation listing the columns that will go.

#### Scenario: Undo a column
- **WHEN** the user removes Committed and chooses Undo
- **THEN** Committed is back in its place with its label and total

#### Scenario: Undo related data
- **WHEN** the user removes capital commitments with three columns and a filter, then chooses Undo
- **THEN** the related data, its three columns and its filter are restored

#### Scenario: Too late
- **WHEN** Undo is chosen more than 10 minutes after the removal
- **THEN** it is refused with "Too late to undo — removals can be undone for 10 minutes"

#### Scenario: Changed since
- **WHEN** another change was made after the removal
- **THEN** Undo is refused with "Too late to undo — the report has changed since"

#### Scenario: Confirmation lists columns
- **WHEN** the user removes related data
- **THEN** the confirmation lists the columns that will be removed with it

#### Scenario: Another entity
- **WHEN** a user of another entity requests an undo
- **THEN** access is refused

### Requirement: Health check
The builder SHALL show a health indicator — "All good" or the number of warnings — and a panel listing: columns that will come out blank; formulas using columns not in the report; money summed across currencies, naming them; filters matching no rows; pivots creating more than 20 columns; and, as information, an export over 50,000 rows and columns using a default total. Each item SHALL link to the tab that fixes it.

#### Scenario: All good
- **WHEN** a report has no issue
- **THEN** the indicator says "All good"

#### Scenario: Mixed currencies
- **WHEN** a related Sum column adds commitments in an INR fund and a USD fund
- **THEN** a warning names the column and both currencies

#### Scenario: Blank column
- **WHEN** a column's related-data path no longer resolves
- **THEN** a warning says the column will be blank

#### Scenario: Broken formula reference
- **WHEN** a formula uses a column that was removed
- **THEN** a warning names the formula and the missing column

#### Scenario: Filter matches nothing
- **WHEN** the report has no rows and one filter alone matches nothing
- **THEN** a warning names that filter

#### Scenario: Large pivot
- **WHEN** a pivot would create more than 20 columns
- **THEN** a warning gives the number

#### Scenario: Large export and default totals
- **WHEN** the report has more than 50,000 rows or a related column without a stored total
- **THEN** information items say so

### Requirement: Pivot preview
Before a pivot is applied, the pivot form SHALL show how many columns it will create and the first five headers, and SHALL warn when it is more than 20.

#### Scenario: Count shown
- **WHEN** the user picks Unit Type as category and Committed as value
- **THEN** the form says "This will create 2 columns: A, B"

#### Scenario: Unknown field
- **WHEN** the preview is requested for a field that is not on the related data
- **THEN** it is refused with a message and nothing is applied

### Requirement: Accessible, consistent and self-explaining page
The builder SHALL use the application's standard tables, badges, buttons and type scale; every icon-only button SHALL have a title and an accessible label; the page SHALL offer a link to the Report Builder user guide and a visible command search button; and every empty state SHALL name the next action.

#### Scenario: Labels and help
- **WHEN** the builder is opened
- **THEN** icon-only buttons have accessible labels, and a guide link and a search button are visible

#### Scenario: Empty report
- **WHEN** a report has no columns
- **THEN** the preview says to tick columns and choose Add selected
