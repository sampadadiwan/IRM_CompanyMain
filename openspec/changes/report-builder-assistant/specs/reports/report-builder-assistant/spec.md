# Report Builder assistant

## Purpose

Lets a fund-side user describe a Report Builder report in words and get a checked draft — explained as plain cards, with the assistant's questions, assumptions and what it couldn't do — to refine, preview with a suggested chart, and save.

## ADDED Requirements

### Requirement: Ask in words

The Reports page's New report menu SHALL offer "Describe it". It SHALL open a page with a question box, examples taken from the starter templates' questions, and the user's own drafts. "Draft" SHALL save a private draft and draft it in the background. The draft page SHALL update in place when the draft is ready, and the user SHALL also get an alert "Your draft report is ready" linking to it. While a draft is being drafted, another Draft or refinement on it SHALL NOT start a second conversation. When neither the company nor the platform has a default AI model, the page SHALL say "AI drafting isn't set up for your account", link to the templates, and SHALL NOT offer Draft.

#### Scenario: Describe page
- **WHEN** a user picks New report › Describe it
- **THEN** the page shows the question box, the template questions as examples and Draft

#### Scenario: No AI model
- **WHEN** the company has no default AI model and there is no platform default
- **THEN** the page says "AI drafting isn't set up for your account" with a link to the templates, and no Draft button

#### Scenario: Double click
- **WHEN** Draft is sent again while the draft is still being drafted
- **THEN** only one AI conversation runs

#### Scenario: Ready alert
- **WHEN** a draft finishes
- **THEN** its maker gets the alert "Your draft report is ready" linking to the draft

### Requirement: Check the draft

The draft page SHALL show the draft as cards in plain words: what each row is, the columns, what is included (filters in guided setup's words), and the order and calculations. It SHALL also show the AI's questions, its assumptions, and a "Couldn't do" list. The AI SHALL be asked in two steps: first which report table, chosen from the company's report tables; then the report, given only that table's columns and related data. The AI SHALL NOT be sent row data while drafting.

#### Scenario: A drafted report
- **WHEN** the user asks "Which LPs still owe money on calls? Biggest first."
- **THEN** the cards read one row per investor, the chosen columns, "Only include investors where Category is LP", "Sorted by Unpaid (largest first)" and "Calculates Unpaid", and the question "Which fund?" lists the company's funds

#### Scenario: Fixed dates
- **WHEN** the AI answers with an assumption about dates
- **THEN** the assumption is listed as given

### Requirement: Answer the fund question

Choosing a fund for "Which fund?" SHALL limit the report the way guided setup does: the rows if they have a fund, else each related data that has one. It SHALL NOT call the AI. The options SHALL be the company's own funds.

#### Scenario: Pick the fund
- **WHEN** the user picks Growth Fund II
- **THEN** a card reads "Only capital commitments in Growth Fund II" and no AI call is made

### Requirement: Refine in words

A refinement SHALL send the AI the current report — including changes made by hand in the builder — and the instruction, and replace the draft with the checked answer. An answer to any question other than the fund SHALL be sent the same way. A fund already chosen SHALL be kept.

#### Scenario: Refine
- **WHEN** the user refines with "also show what was distributed"
- **THEN** the AI gets the current report and the instruction, and the draft gains the Distributed column while keeping the fund limit

#### Scenario: Hand edits kept
- **WHEN** the user removed a column in the builder and then refines
- **THEN** the report sent to the AI no longer has that column

### Requirement: Couldn't do

Every part of the AI's answer SHALL be checked with the same rules as templates. A part that fails SHALL be left out and listed under "Couldn't do" with its reason:
- an unknown column: "<key> isn't a column of <table>"
- a table not in the company's reports: "<table> aren't available in reports for your account"
- a filter field that isn't offered, or a filter on the company itself
- a value that matches no row: "No <table> have <Field> <value>", with the values listed for a field with few values (never on the largest tables)

Anything the AI itself says it can't do SHALL be listed too, with its suggestion. When nothing usable remains, the page SHALL show only the Couldn't do list, with no preview and no Save. Rows SHALL always be scoped to the user's company.

#### Scenario: Not reportable
- **WHEN** the AI says IRR isn't a reportable column and suggests DPI
- **THEN** Couldn't do reads "IRR isn't a reportable column — try DPI" and the rest is drafted

#### Scenario: Value matches nothing
- **WHEN** the AI filters investors to Category "Partner"
- **THEN** that filter is left out and Couldn't do reads "No investors have Category Partner — values: Co-Investor, LP"

#### Scenario: Data not in reports
- **WHEN** the AI picks secondary sales
- **THEN** Couldn't do reads "secondary sales aren't available in reports for your account" and there is nothing to preview

#### Scenario: Nothing usable
- **WHEN** every column the AI gives is unknown
- **THEN** only Couldn't do shows; there is no preview and no Save

#### Scenario: Another company's data
- **WHEN** the AI adds a filter on the company id
- **THEN** the filter is left out and the preview shows only the user's company's rows

### Requirement: AI failures

An AI error or an answer that isn't JSON SHALL be retried once. If the retry fails too, the page SHALL say "Couldn't draft this right now — try again in a moment" and keep the question.

#### Scenario: Times out
- **WHEN** the AI raises twice
- **THEN** the page says "Couldn't draft this right now — try again in a moment" and the question stays

#### Scenario: Not JSON
- **WHEN** the AI answers prose twice
- **THEN** the page says the same

### Requirement: Suggested chart

The preview SHALL show 20 rows, the totals row and the report check. It SHALL suggest a chart by rules, with no AI call:
- a text column and an amount column → a horizontal bar of the first amount by the first text column, top 15
- a date column and an amount column → a line over the date
- a pivot → stacked bars
- otherwise "No chart suggested"

The user SHALL be able to choose No chart.

#### Scenario: Text and amount
- **WHEN** the draft has Investor and Committed
- **THEN** the suggested chart is a horizontal bar of Committed by Investor

#### Scenario: Date and amount
- **WHEN** the draft has Due date and Call amount
- **THEN** the suggested chart is a line of Call amount over Due date

#### Scenario: Nothing to chart
- **WHEN** the draft has only text columns
- **THEN** it says "No chart suggested" and still offers Describe a chart

#### Scenario: Large table
- **WHEN** the draft's rows are capital remittances
- **THEN** the preview runs and the report check gives the export row count

### Requirement: Describe a chart

"Describe a chart" SHALL send the instruction and the 20 preview rows to the company's AI model, and SHALL say so next to the button ("sends these 20 rows to your configured AI model"). The chart it returns SHALL be saved for the report.

#### Scenario: Describe a chart
- **WHEN** the user describes "pie of committed by investor"
- **THEN** the chart AI gets the 20 preview rows and the chart is saved for the report

### Requirement: Charts on the report page

A report with a chosen chart SHALL show it above the table on the report page, drawn from the page's rows for a suggested chart, with "Hide chart".

#### Scenario: Chart shown
- **WHEN** a report saved with the suggested chart is opened
- **THEN** the chart shows above the table with Hide chart

### Requirement: Save

"Save and open" SHALL clear the draft mark, set the name (a blank name keeps the suggestion), keep the question as the report's description, and open the report page. "Fine-tune in builder" SHALL save the same way and open the builder. "Discard" SHALL delete the draft and return to the Describe page.

#### Scenario: Save and open
- **WHEN** the user saves "LPs owing — GF2"
- **THEN** the report page opens, the report is no longer a draft, its description is the question, and other users of the company see it

#### Scenario: Fine-tune
- **WHEN** the user picks Fine-tune in builder
- **THEN** the report is saved and the builder opens

#### Scenario: Discard
- **WHEN** the user discards the draft
- **THEN** it is deleted and the Describe page opens

### Requirement: Private drafts

A draft SHALL be listed and openable only by its maker, with a Draft badge. Other users, of the same or another company, SHALL be refused. Drafts not changed for 7 days SHALL be deleted by a daily clean-up. Saved reports SHALL NOT be touched.

#### Scenario: Others can't see it
- **WHEN** another user of the company opens Reports or the draft's address
- **THEN** it isn't listed and the address is refused

#### Scenario: Another company
- **WHEN** a user of another company opens or refines the draft
- **THEN** it is refused

#### Scenario: Clean-up
- **WHEN** the clean-up runs with drafts 8 and 2 days old and a 30-day-old saved report
- **THEN** only the 8-day-old draft is deleted
