# Spec Delta

## Purpose

Defines how Report Builder results are presented and handled: value formatting in the preview, on the report page and in Excel, the totals row, sorting by header, opening a report from the list, save feedback, template confirmation and the preview's row count.

## ADDED Requirements

### Requirement: One formatting rule set for preview, report page and Excel
Values SHALL be formatted by column type, identically in the preview and on the report page: amounts and numbers with thousands separators and two decimals, right-aligned, with the report's currency label on amounts when one is set; dates and times in the user's date format; yes/no as Yes or No; empty values as blank. In Excel, amounts and numbers SHALL be number cells with a number format, dates SHALL be date cells, and yes/no SHALL be Yes or No.

#### Scenario: Same values in preview and report page
- **WHEN** a report with an amount, a date and a yes/no column is previewed and then opened on the report page
- **THEN** each value is displayed identically in both, amounts right-aligned

#### Scenario: Amounts not named "amount" are formatted
- **WHEN** a report includes Net Payable, FMV and Quantity
- **THEN** they are formatted as numbers with separators like any other amount

#### Scenario: Currency label only on amounts
- **WHEN** the report's display currency is set
- **THEN** amount columns carry the currency label and plain number columns such as Quantity do not

#### Scenario: Excel cell types
- **WHEN** the report is exported
- **THEN** amounts are number cells, dates are date cells and yes/no values read Yes or No

#### Scenario: Unknown type falls back to text
- **WHEN** a column's type cannot be determined
- **THEN** its value is shown as text and the report and export still complete

### Requirement: Totals row
A totals row SHALL appear when the report has at least one totalable column: plain amount or number columns of the report's own rows, related columns totalled with Sum or Count, and Sum or Count pivot columns. Average, Minimum, Maximum, Latest and List columns SHALL be blank in the totals row. Formula columns SHALL be recalculated from the totals row's values, not summed. On screen the row SHALL be labelled "Total" when all rows are shown, "Total (this page)" on a paged report page and "Total (these N rows)" in a preview showing fewer than all rows. Excel SHALL show one bold totals row as the last row of the Data sheet, covering every exported row, and SHALL NOT have a separate Totals sheet.

#### Scenario: Sum column totalled
- **WHEN** a Growth Fund II report has Committed of 5,00,00,000, 2,50,00,000 and 1,00,00,000
- **THEN** the totals row shows 8,50,00,000 under Committed

#### Scenario: Ratio formula recalculated
- **WHEN** the same report has Called totalling 3,40,00,000 and a Called % formula
- **THEN** the totals row shows Called % as 40.00, not the sum of the rows' percentages

#### Scenario: Non-summing totals left blank
- **WHEN** a column uses Average, Latest, Minimum, Maximum or List
- **THEN** its totals cell is blank

#### Scenario: Paged report label
- **WHEN** the report page shows 100 of 1,284 rows
- **THEN** the totals row is labelled "Total (this page)" and sums only those 100 rows

#### Scenario: No totalable columns
- **WHEN** a report has no totalable columns
- **THEN** no totals row is shown

#### Scenario: Excel totals
- **WHEN** the report is exported
- **THEN** the last row of the Data sheet is a bold totals row over every row and there is no Totals sheet

### Requirement: Sort by column header
On the report page each column header SHALL sort the rows by that column: lowest first on the first click, highest first on the next, with the current direction shown. The sort SHALL last for the visit and across pages, SHALL NOT change the report's saved sort, and a sort naming a column not in the report SHALL be ignored. Sorting by a related, pivot or formula column on a report with more than 20,000 rows SHALL say "Sorted within the first 20,000 rows".

#### Scenario: Sort by an amount
- **WHEN** a reader clicks the Committed header twice
- **THEN** rows are ordered highest committed first and the header shows the descending arrow

#### Scenario: Saved sort unchanged
- **WHEN** the reader leaves and another user opens the report
- **THEN** the report shows its saved sort

#### Scenario: Sort kept across pages
- **WHEN** a sorted report spans several pages and the reader moves to the next page
- **THEN** the next page continues in the same sort order

#### Scenario: Unknown sort column ignored
- **WHEN** the page is requested with a sort naming a column not in the report
- **THEN** the report is shown in its saved order without an error

#### Scenario: Large report computed sort
- **WHEN** a reader sorts a 25,000-row report by a related total
- **THEN** the note "Sorted within the first 20,000 rows" is shown

#### Scenario: Another entity's report
- **WHEN** a user requests the report page of another entity's report with a sort
- **THEN** access is refused as it is today

### Requirement: Report name opens the report page
On the Reports list, the name of a Report Builder report SHALL open its report page; Edit SHALL open the builder. Other reports SHALL keep their current links.

#### Scenario: Builder report
- **WHEN** a user clicks a Report Builder report's name on the Reports list
- **THEN** the report page opens

#### Scenario: Other report
- **WHEN** a user clicks a non-builder report's name
- **THEN** it opens as it does today

### Requirement: Truthful save feedback
A setting changed in the builder SHALL show a success message only after the server confirms the save. When the server refuses the change or cannot be reached, the user SHALL see an error message naming the setting and the reason, and the control SHALL return to its saved value.

#### Scenario: Saved
- **WHEN** a user changes the sort and the server confirms
- **THEN** a green "Sort saved" message appears

#### Scenario: Refused
- **WHEN** the server refuses the change
- **THEN** a red "Sort wasn't saved" message with the reason appears, no green message appears, and the control shows its saved value

#### Scenario: Network error
- **WHEN** the request fails to reach the server
- **THEN** a red message says the change wasn't saved

### Requirement: Applying a template asks first
Applying a template in the builder SHALL first show the Immediate Actions popup, stating that the report's columns, related data and formulas are replaced and that this cannot be undone. Cancelling SHALL change nothing.

#### Scenario: Confirm
- **WHEN** a user clicks Apply Template and confirms
- **THEN** the template replaces the report's set-up

#### Scenario: Cancel
- **WHEN** a user clicks Apply Template and cancels
- **THEN** the report is unchanged

### Requirement: Preview states its row count
The preview SHALL show up to 20 rows and say so. It SHALL state "N of M rows" when the report has more rows than shown and "All N rows" otherwise.

#### Scenario: More rows than shown
- **WHEN** a report with 1,284 rows is previewed
- **THEN** the preview says "20 of 1,284 rows"

#### Scenario: Fewer than 20 rows
- **WHEN** a report with 7 rows is previewed
- **THEN** the preview says "All 7 rows"

### Requirement: Wizard Summarize shows the saved total
The guided wizard's Summarize step SHALL show, for each related column, the total actually saved for it, and changing it SHALL save the new total.

#### Scenario: Newly added column
- **WHEN** a user adds Committed on the Summarize step
- **THEN** its dropdown shows Sum and Sum is saved

#### Scenario: Changed total
- **WHEN** the user changes it to Count
- **THEN** Count is saved and shown after the page reloads
