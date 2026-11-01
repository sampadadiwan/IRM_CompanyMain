# Report Builder delivery

## Purpose

How a finished Report Builder report is exported, delivered on a schedule and read: visible export progress, recent exports, a checked schedule with a named time zone, a test send, the report's filters in words, reader-only narrowing and headline totals.

## ADDED Requirements

### Requirement: Export shows its progress

Clicking Export XLSX on the report page or in the builder header SHALL turn the button into a disabled "Preparing…" state at once. When the export file has been saved, the same button SHALL become "Download", linking to the saved document, with "Export again" next to it, without a page reload. When the export fails, the button SHALL return to "Export XLSX" and the user SHALL get a red alert reading "Couldn't export <report name>: <reason>". The existing "report is ready" alert SHALL still be sent.

#### Scenario: Export from the report page
- **WHEN** a user clicks Export XLSX on the report page and the export succeeds
- **THEN** the button reads "Preparing…" and is disabled, and then reads "Download" linking to the new document, with "Export again"

#### Scenario: Export from the builder
- **WHEN** a user clicks Export XLSX in the builder header and the export succeeds
- **THEN** the header button goes through the same "Preparing…" and "Download" states

#### Scenario: Export fails
- **WHEN** the export cannot be saved
- **THEN** the button reads "Export XLSX" again and a red alert says "Couldn't export <report name>: <reason>"

### Requirement: Recent exports

The report page SHALL list the report's last 5 exports that the user may open, newest first. Each row shows the file name, who made it, when (in the locale date-time format) and a Download link. With none, it SHALL read "No exports yet — Export XLSX makes one." A finished export SHALL appear at the top of the list without a reload. Exports of other reports SHALL NOT be listed.

#### Scenario: Five newest
- **WHEN** a report has 7 exports
- **THEN** the report page lists the 5 newest, newest first, each with its maker, time and Download

#### Scenario: None yet
- **WHEN** a report has never been exported
- **THEN** Recent exports reads "No exports yet — Export XLSX makes one."

#### Scenario: Only this report
- **WHEN** another report has exports and this one has none
- **THEN** this report's Recent exports is empty

### Requirement: A checked schedule

Saving a schedule SHALL check its recipients first. Addresses may be separated by commas, semicolons, spaces or new lines. They SHALL be stored lower-case, without duplicates. Any address that is not a valid email SHALL be named under the Recipients field ("bob@ isn't an email address", or "… aren't email addresses" for several), what was typed SHALL stay, and nothing SHALL be saved. An empty list with the schedule on SHALL show "Add at least one email". A successful save SHALL say "Schedule saved — <frequency> at 09:00 <zone> to <N> people". Turning the schedule switch off SHALL save at once with "Schedule turned off" and SHALL NOT check recipients.

#### Scenario: Valid recipients inside the company
- **WHEN** an editor saves a weekly schedule in India Standard Time to two users of the company
- **THEN** no popup is shown and the message reads "Schedule saved — weekly on Monday at 09:00 IST to 2 people"

#### Scenario: Addresses tidied
- **WHEN** the recipients are "Meera@Acme.test; ravi@acme.test" and "meera@acme.test" on a new line
- **THEN** the schedule stores meera@acme.test and ravi@acme.test

#### Scenario: Invalid address
- **WHEN** the recipients include "bob@"
- **THEN** "bob@ isn't an email address" shows under the field and nothing is saved

#### Scenario: Empty list
- **WHEN** the schedule is on and the recipients are empty
- **THEN** "Add at least one email" shows and nothing is saved

#### Scenario: Turning off
- **WHEN** the editor switches a saved schedule off
- **THEN** it is saved as off at once with "Schedule turned off" and its recipients are kept

### Requirement: Recipients outside the company

Before a schedule is saved with any recipient who is not a user of the report's company (by email, ignoring case), an Immediate Actions popup SHALL name them ("Emails <N> person/people outside <company>" with the addresses). Proceed SHALL save. Cancel SHALL save nothing. A save request that includes such recipients without confirming them SHALL be refused with "Confirm sending to people outside <company> first".

#### Scenario: Proceed
- **WHEN** the recipients include lp@gmail.com and the editor clicks Proceed in the popup
- **THEN** the schedule is saved with lp@gmail.com

#### Scenario: Cancel
- **WHEN** the editor clicks Cancel in the popup
- **THEN** nothing is saved

#### Scenario: Unconfirmed request
- **WHEN** a save request includes an outside recipient without confirmation
- **THEN** it is refused with "Confirm sending to people outside Acme Capital first" and nothing is saved

### Requirement: Time zone named

The schedule SHALL have a time zone chosen from the same list as agent schedules. A new schedule SHALL default to India Standard Time. An existing schedule SHALL keep its stored time zone. The frequency choices SHALL read "Daily at 09:00", "Weekly on Monday at 09:00" and "Monthly on the 1st at 09:00".

#### Scenario: An old UTC schedule
- **WHEN** a schedule saved before this change has time zone UTC
- **THEN** the Delivery tab shows UTC and the next send in UTC, and nothing changes until it is saved

### Requirement: Send test to me

"Send test to me" SHALL email the current report, as the scheduled email would (same subject and Excel attachment), to the signed-in user only. The message SHALL read "A test is on its way to <their email>". It SHALL work whether or not a schedule is saved, and SHALL NOT change "Last sent". Only users who can edit the report SHALL be able to send a test.

#### Scenario: Test send
- **WHEN** an editor clicks Send test to me
- **THEN** one email with the Excel file goes to that editor only, and no schedule recipient gets it

#### Scenario: Another company
- **WHEN** a user of another company sends the test request for this report
- **THEN** it is refused and no email is sent

### Requirement: Last sent and next

The Delivery tab SHALL show "Last sent <date time> <zone> · Next <date time> <zone>" in the schedule's time zone and the locale date-time format, or "Not sent yet · Next …" before the first send. "Last sent" SHALL be the time a scheduled email went out.

#### Scenario: Shown in the schedule's zone
- **WHEN** a weekly IST schedule last sent at 2026-11-02 03:30 UTC
- **THEN** the tab reads "Last sent 02 Nov 2026 09:00 IST · Next 09 Nov 2026 09:00 IST"

#### Scenario: A test send is not a scheduled send
- **WHEN** the editor sends a test
- **THEN** "Last sent" is unchanged

#### Scenario: Never sent
- **WHEN** a schedule has not been sent yet
- **THEN** the tab reads "Not sent yet · Next …"

### Requirement: The report's filters in words

The report page SHALL show the report's saved filters as chips, in the same words guided setup uses ("Category is LP", "Only capital commitments in Growth Fund II"), under "This report shows only:". These chips SHALL NOT be removable on the report page. A "Change in builder" link SHALL be shown to users who can edit the report. With no saved filters, the line SHALL NOT be shown.

#### Scenario: Saved filters
- **WHEN** a report filters Category to LP and its commitments to Growth Fund II
- **THEN** the report page shows the chips "Category is LP" and "Only capital commitments in Growth Fund II"

#### Scenario: No saved filters
- **WHEN** a report has no saved filters
- **THEN** no "This report shows only" line is shown

### Requirement: Narrow down

The report page SHALL offer "Narrow down" over the report's own root filter fields, with the builder's typed inputs and plain-word operators, replacing the single search box. Each applied reader filter SHALL show as a chip with ✕, and ✕ SHALL remove it. Reader filters SHALL apply to this page visit only. They SHALL NOT change the report or its export, and the page SHALL say so. A reader filter on a field the report already filters on SHALL be dropped with "<Field> is already set by the report". A filter on a field that isn't one of the report's filter fields SHALL be ignored.

#### Scenario: Narrow to a city
- **WHEN** a reader narrows "LPs" to City is Mumbai
- **THEN** only Mumbai investors are shown, a chip "City is Mumbai" appears, and the report's saved filters are unchanged

#### Scenario: Remove the chip
- **WHEN** the reader clicks ✕ on "City is Mumbai"
- **THEN** all the report's rows are shown again

#### Scenario: Saved filter wins
- **WHEN** the page is opened with a reader filter on Category
- **THEN** the rows keep the report's Category filter and the page says "Category is already set by the report"

#### Scenario: Unknown field
- **WHEN** the page is opened with a filter on a field that isn't one of the report's filter fields
- **THEN** it is ignored and no chip is shown

### Requirement: Headline totals

The report page SHALL show up to four stats cards above the table, one for each of the first four columns, in report order, that have a total in the totals row. Each card's figure SHALL be the totals row's text for that column. On a paged report each card SHALL say "this page", as the totals row does. With no totals, there SHALL be no cards.

#### Scenario: Cards match the totals row
- **WHEN** "LPs" shows Committed and Called totals
- **THEN** two cards show 7,50,00,000.00 and 3,00,00,000.00, the totals row's text

#### Scenario: Paged
- **WHEN** the report spans several pages
- **THEN** the cards equal "Total (this page)" and each says "this page"

#### Scenario: Nothing to total
- **WHEN** no column has a total
- **THEN** no cards are shown

### Requirement: Save as View removed

The builder SHALL NOT offer View or Sharing settings, and the address that saved them SHALL no longer exist. Reports stored with the old view setting SHALL open and run as any other report.

#### Scenario: Gone
- **WHEN** a request is sent to the old view-settings address
- **THEN** it is refused as an unknown page and the report is unchanged

#### Scenario: Old view report
- **WHEN** a report once marked as a view is opened
- **THEN** it runs as any report
