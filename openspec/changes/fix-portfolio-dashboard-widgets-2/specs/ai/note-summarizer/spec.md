# Spec Delta

## Purpose

Defines what a user is told when they run the Note Summariser on a portfolio company or investor from its Notes: which notes the summary covers, where the summary is saved, and why a summary is empty.

## ADDED Requirements

### Requirement: The run window names the period covered
When a user opens the Summarise Notes window from a Notes list, the window SHALL state the dates the run will cover, as "Summarises notes dated {start} – {end} (the last completed {quarter|month})." The period SHALL be the one the summary itself uses: the last completed calendar quarter, or the last completed calendar month when the agent's summary period is Month. The period rule SHALL NOT change.

#### Scenario: Quarterly agent
- **WHEN** a user opens Summarise Notes on 03 Nov 2026 and the agent's summary period is Quarter or blank
- **THEN** the window says "Summarises notes dated Jul 01, 2026 – Sep 30, 2026 (the last completed quarter)."

#### Scenario: Monthly agent
- **WHEN** a user opens Summarise Notes on 03 Nov 2026 and the agent's summary period is Month
- **THEN** the window says "Summarises notes dated Oct 01, 2026 – Oct 31, 2026 (the last completed month)."

#### Scenario: Window and summary agree
- **WHEN** a user runs the summariser from the window on 03 Nov 2026 for a quarterly agent
- **THEN** the resulting Note Summaries entry shows the period as "Quarter (Jul 01, 2026 – Sep 30, 2026)", the same dates as the window, with the year on both dates

### Requirement: A manual run confirms where the summary goes
After a user runs the summariser from the Summarise Notes window, the page SHALL show a message naming the period and saying the summary will appear in the Notes list as a note tagged "summary" dated the period's last day, and in the Note Summaries widget.

#### Scenario: Message after run
- **WHEN** a user clicks Run Summariser on 03 Nov 2026 for a quarterly agent
- **THEN** the page shows "Summarising notes dated Jul 01, 2026 – Sep 30, 2026. The summary will appear in this Notes list as a note tagged 'summary' dated 30/09/2026, and in the Note Summaries widget."

#### Scenario: Summary appears in the Notes list
- **WHEN** a run for a period with notes finishes and the user reloads the Notes list
- **THEN** the list shows a note tagged "summary" dated the period's last day holding the summary

### Requirement: An empty summary says why
When a run's period had no notes to summarise, the Note Summaries entry SHALL show "No notes dated {start} – {end}. Notes dated after {end} will be in the next {quarter|month}'s summary." in place of an empty summary box.

#### Scenario: Notes only after the period
- **WHEN** a company's only notes are dated 27 Oct – 04 Nov 2026 and a quarterly run on 03 Nov 2026 finishes
- **THEN** the Note Summaries entry shows "Notes processed: 0"
- **AND** it shows "No notes dated Jul 01, 2026 – Sep 30, 2026. Notes dated after Sep 30, 2026 will be in the next quarter's summary."
- **AND** no empty Summary box is shown
