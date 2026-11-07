# Spec Delta

## Purpose

Lets a firm's company admin choose a table's columns from the table itself, in a side panel, saving the whole
set at once and reloading only that table.

## ADDED Requirements

### Requirement: Columns icon on customisable tables
Every table of a record type that has standard columns SHALL show an always-visible columns button next to the
table's search box, or at the table's top-right when the page has no search box, when the user may change the
columns that table shows. The icon SHALL be shown only to a company admin of the firm
that owns those columns, never to a user acting as an investor, and, when the columns are a saved report's,
only to a user who may edit that report. The icon SHALL NOT cover the table's headings or sort links.

#### Scenario: Company admin sees the icon
- **WHEN** a company admin opens the Investors page
- **THEN** the columns button is visible right of the search box, without pointing at the table

#### Scenario: Page without a search box
- **WHEN** a company admin opens a table whose page hides the search box
- **THEN** the columns button is visible at the table's top-right

#### Scenario: Employee who is not a company admin
- **WHEN** an employee without the company admin role opens the Investors page
- **THEN** the table shows no columns icon

#### Scenario: User acting as an investor
- **WHEN** a user acting as an investor opens a table of the firm
- **THEN** the table shows no columns icon

#### Scenario: AG grid tables
- **WHEN** a company admin opens the Capital Commitments grid view
- **THEN** the grid shows the columns icon on its top-right corner

### Requirement: Panel shows the columns the table shows
Clicking the icon SHALL open a side panel listing, in order, the columns the table shows now, each with its
heading, its field name and its data type, without leaving the page. When the firm has no saved columns for the
record type, the list SHALL be the page's standard columns. Columns the page always adds SHALL be listed as
locked; saved columns the page hides SHALL be listed as not shown on this page. Columns added only for a
snapshot view SHALL NOT be listed.

#### Scenario: Saved columns listed in order
- **WHEN** the firm's saved Investor columns are Name, Category, City and the admin opens the panel
- **THEN** the panel lists Name, Category, City in that order with their data types

#### Scenario: Page standard columns when nothing is saved
- **WHEN** the firm has no saved Capital Call columns and the admin opens the panel on Capital Calls
- **THEN** the panel lists the columns the Capital Calls table shows, in the same order

#### Scenario: Page always adds a column
- **WHEN** the admin opens the panel on the all-funds Capital Commitments list
- **THEN** Fund Name, which the page adds itself, is listed as always shown and cannot be moved or removed, while
  Stakeholder, already one of the list's columns, is an ordinary row that saving keeps

#### Scenario: Page hides a saved column
- **WHEN** the firm's saved Commitment columns include Investor and the admin opens the panel on an investor's Commitments tab
- **THEN** Investor is listed as not shown on this page

#### Scenario: Snapshot column
- **WHEN** the admin opens the panel on a snapshot view
- **THEN** Snapshot Date is not listed

### Requirement: Edit the list without saving
In the panel the user SHALL be able to reorder columns by dragging, rename a column's heading, remove a column
and add a column from a searchable list of the record type's fields, the firm's custom fields and related
records' fields, excluding columns already listed. Nothing SHALL be saved until Save; Cancel, the close button
and the Escape key SHALL close the panel without saving.

#### Scenario: Add a custom field
- **WHEN** the admin picks "Risk rating" under Custom fields
- **THEN** Risk rating is added at the end of the list and leaves the add list

#### Scenario: Add a related record's field
- **WHEN** the admin opens the panel on Capital Commitments and picks a field of the commitment's investor
- **THEN** that field is added to the list

#### Scenario: Cancel discards
- **WHEN** the admin removes City and presses Escape
- **THEN** the panel closes and the saved columns are unchanged

### Requirement: Save stores the whole set and reloads only the table
Save SHALL store the listed columns, in order, with their headings, as the complete set for the record type in
the firm, or for the open report when the report has its own columns, replacing the previous set in one step.
After a successful save the panel SHALL close and only the table SHALL reload with the saved columns, keeping
the page's search, filters, sort and page number, followed by a confirmation message. The change SHALL apply
to every table of that record type in the firm.

#### Scenario: Reorder, rename, remove, add
- **WHEN** the admin moves Committed above City, renames Tags to Segment, removes City, adds Risk rating and saves
- **THEN** only the table reloads, showing Name, Category, Committed, Segment, Risk rating in that order, with the search still applied

#### Scenario: Firm-wide
- **WHEN** the admin saves Investor columns from the Investors page
- **THEN** another employee of the firm sees the same columns on a fund's Investors tab

#### Scenario: Table inside a tab
- **WHEN** the admin saves columns of a table inside a fund page tab
- **THEN** only that tab's table reloads and the tab stays open

#### Scenario: Double click on Save
- **WHEN** the admin clicks Save twice quickly
- **THEN** one set of columns is saved, with no duplicates

#### Scenario: Grid reloads
- **WHEN** the admin saves columns from the Capital Commitments grid view
- **THEN** only the grid reloads with the saved columns

### Requirement: First save keeps what the table showed
When the firm has no saved columns for the record type, the first save SHALL store the columns listed in the
panel, which start from the page's standard columns, so no column the table showed disappears unless the user
removed it. When the firm has no form type for the record type, the save SHALL create it.

#### Scenario: First save from standard columns
- **WHEN** the firm has no saved Capital Call columns and the admin adds one column and saves
- **THEN** the table shows the columns it showed before plus the added column, in the same order

#### Scenario: Form type created
- **WHEN** the firm has no Capital Call form type and the admin saves Capital Call columns
- **THEN** a Capital Call form type is created for the firm with the saved columns

### Requirement: Report columns
When the table is showing a saved report that has its own columns, the panel SHALL edit that report's columns,
say so in its header, and leave the firm's columns unchanged. When the report has no columns of its own, the
panel SHALL edit the firm's columns. A change to a report's columns SHALL show the next time the table is shown,
without delay.

#### Scenario: Report with its own columns
- **WHEN** the admin opens the panel on the report "LPs by city", removes City and saves
- **THEN** the report shows the new columns at once and the firm's Investor columns are unchanged

#### Scenario: Report without its own columns
- **WHEN** the admin opens the panel on a report that has no columns of its own
- **THEN** the panel header says it edits the firm's columns

### Requirement: Derived fields keep their formula
Derived fields SHALL be listed and MAY be reordered, renamed or removed in the panel; their key, data type and
alignment SHALL change only when the user edits them in the row's details.

#### Scenario: Rename a derived field
- **WHEN** the admin renames the derived field "NAV / Commitment" to "NAV ratio" and saves
- **THEN** the column shows as "NAV ratio" with the same values and data type

### Requirement: Column details and derived fields in the panel
Each listed column SHALL offer its data type (String, Number, Decimal, Date, HTML) and alignment (left, centre,
right or none) for editing, and a derived field also its key. The panel SHALL let the user add a derived field
with a label, a key and a data type. These are the settings Configure Grids offered.

#### Scenario: Change data type and alignment
- **WHEN** the admin sets Committed to Decimal, right-aligned, and saves
- **THEN** the column is stored as Decimal with right alignment and the table aligns it right

#### Scenario: Add a derived field
- **WHEN** the admin adds a derived field "RM" with key custom_fields.relationship_manager and saves
- **THEN** the table shows an RM column with each investor's relationship manager

#### Scenario: Edit a derived field's key
- **WHEN** the admin changes a derived field's key and saves
- **THEN** the column shows the values of the new key

#### Scenario: Invalid data type
- **WHEN** a save names a data type that is not offered
- **THEN** the save is refused and nothing is saved

### Requirement: Hand-built list tables offer columns
The 14 list tables that today render fixed columns (Funds, Investments, Investment Instruments, Deal Investors,
Distributions, Allocations, Approvals, Approval Responses, Expressions of Interest, Investment
Opportunities, Investor KPI Mappings, Portfolio Cashflows, Secondary Sales, Users) SHALL show the same columns
button and use the firm's saved columns. With no saved columns each SHALL show the columns it shows today, with
the same links, badges and actions. Their in-page search, sorting and paging SHALL keep working. Configure Grids
SHALL be offered on the Form Type page for every record type that has standard columns.

#### Scenario: Today's columns by default
- **WHEN** a company admin opens the Funds list and the firm has no saved Fund columns
- **THEN** the list shows the same columns, links and actions as before, and the columns button

#### Scenario: Add a column to a hand-built list
- **WHEN** the admin adds a custom field column to the Distributions list and saves
- **THEN** the list shows that column for every distribution

#### Scenario: Beside the in-page search box
- **WHEN** a hand-built list shows its in-page "Search:" box
- **THEN** the columns button sits right of that box

#### Scenario: Search and sort after customising
- **WHEN** the admin has changed the Distributions columns and then searches and sorts the list in the page
- **THEN** the list filters and sorts as before

#### Scenario: Configure Grids offered
- **WHEN** the admin opens the Capital Distribution form type page
- **THEN** it offers Configure Grids

### Requirement: Configure Grids shows the same list
The Configure Grids page (reached from the Form Types list and page, the report page and the report card, at its
existing address) SHALL show the same column list, add controls and Save as the columns panel, for that form type
or report, starting from its saved columns or, when none, the record type's standard columns. Each saved column
SHALL also offer Show, Edit and Delete as before; Delete SHALL ask for confirmation and remove the column at once.
Users not allowed to save columns SHALL be refused as before.

#### Scenario: From a form type page
- **WHEN** the admin clicks Configure Grids on the Investor form type page
- **THEN** the page shows the Investor columns in the same list as the panel, each saved column with Show, Edit and Delete

#### Scenario: Delete a column on the full page
- **WHEN** the admin clicks Delete on a saved column and confirms
- **THEN** the column is removed at once and the list shows the rest

#### Scenario: A second form type of the same record type
- **WHEN** the admin clicks Configure Grids on the "Feeder" Capital Commitment form type
- **THEN** the panel edits the Feeder form type's columns

#### Scenario: From a report page
- **WHEN** the admin clicks Configure Grids on a report with no columns of its own
- **THEN** the panel edits that report's columns, starting from the standard columns

#### Scenario: Save on the full page
- **WHEN** the admin reorders columns on the Configure Grids page and saves
- **THEN** the page refreshes in place showing the new order

#### Scenario: Another firm's Configure Grids
- **WHEN** an admin opens the Configure Grids page for another firm's form type
- **THEN** the request is refused

### Requirement: Reset to standard columns
The panel SHALL offer Reset to standard columns. Saving after a reset SHALL remove the saved columns of the
record type in the firm (or of the open report), including derived fields, so each table shows its page's
standard columns again; the panel SHALL say so before saving.

#### Scenario: Reset
- **WHEN** the admin clicks Reset to standard columns and saves
- **THEN** the firm has no saved Investor columns and the table shows the page's standard columns

### Requirement: Save validation
A save SHALL be refused, with a message in the panel and nothing changed, when the list is empty, or when it
names a column that is neither offered in the add list, nor already saved, nor shown by the table when the
panel opened. A blank heading SHALL use the column's standard name; a heading SHALL be at most 100 characters;
a column listed twice SHALL be saved once. Columns removed by someone else while the panel was open SHALL be
skipped.

#### Scenario: Empty list
- **WHEN** the admin removes every column and saves
- **THEN** the panel shows "Keep at least one column" and nothing is saved

#### Scenario: Column not offered
- **WHEN** a save names a column that is not offered, saved or shown
- **THEN** the save is refused and nothing is saved

#### Scenario: Blank heading
- **WHEN** the admin clears the heading of Category and saves
- **THEN** the column is saved with the heading "Category"

#### Scenario: Column listed twice
- **WHEN** a save lists City twice
- **THEN** City is saved once, at its first position

#### Scenario: Column removed meanwhile
- **WHEN** another admin removes City while the panel is open and the admin then saves a list containing City's row
- **THEN** the save succeeds without City

### Requirement: Access to the panel
Opening or saving the panel SHALL be refused, with nothing changed, for a user who is not a company admin of the
firm that owns the columns, for a user acting as an investor, for another firm's columns or reports, for a
report the user may not edit, for an unknown record type, and when the panel's record of what the table showed
has been altered or has expired. A save SHALL change only columns, headings and order: any other field sent
SHALL be ignored.

#### Scenario: Direct request by a non-admin
- **WHEN** an employee who is not a company admin requests the panel or saves columns directly
- **THEN** the request is refused and nothing changes

#### Scenario: Direct request acting as investor
- **WHEN** a user acting as an investor requests the panel directly
- **THEN** the request is refused

#### Scenario: Another firm
- **WHEN** an admin saves columns naming another firm's report
- **THEN** the request is refused and the other firm's columns are unchanged

#### Scenario: Report the user may not edit
- **WHEN** an admin saves columns of another user's draft report
- **THEN** the request is refused

#### Scenario: Unknown record type
- **WHEN** the panel is requested for a record type that has no standard columns
- **THEN** the request is refused as not found

#### Scenario: Altered panel record
- **WHEN** the panel's record of what the table showed is altered or expired
- **THEN** the request is refused and nothing is saved

#### Scenario: Extra fields ignored
- **WHEN** a save also sends a firm, an owner or a data type
- **THEN** only the columns, headings and order change
