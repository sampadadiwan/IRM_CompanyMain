## Purpose

Every disaster-recovery run (drill or real recovery) leaves a self-explaining report — HTML and Markdown — that a manager, auditor or client can read without the engineer: the answer first, problems with their fix, and every step and check explained.

## ADDED Requirements

### Requirement: Answer first
The report SHALL open with the result (Passed or Failed), what was recovered where, and four figures: rebuild time, database restore time, checks passed out of checks run, and the age of the newest restored record.

#### Scenario: A passed drill opens with its answer
- **WHEN** a staging drill into ap-south-2 passes in 12:04 with a 1:59 database restore, 44 of 46 checks passed and data 0.4 h old
- **THEN** the report's first section shows "Passed", "12:04", "1:59", "44 / 46" and "0.4 h"

#### Scenario: A failed run names where it stopped
- **WHEN** a run fails during step 5, "Install the app on both servers"
- **THEN** the report shows "Failed" and names step 5 and its plain name as where the recovery stopped

### Requirement: Recovery objectives against client promises
The report SHALL state the recovery point achieved (the backup the database was restored to, and the minutes between it and the start of the recovery) and the recovery time achieved (from the recovery command to a verified stack), compare each with what CapHive promises clients, and mark each as met, not met or not reached. A missed promise SHALL appear under Needs attention.

#### Scenario: Recovery point not met, recovery time met
- **WHEN** a drill starting 07:47:56 UTC restores backup 2026-11-08_070001-incr and is verified 8:36 later, against promises of 30 minutes (RPO) and about 10 minutes (RTO)
- **THEN** the report shows the recovery point as not met with "48 min of changes lost", the recovery time as met with "8:36", and lists "Recovery point (RPO) not met" under Needs attention

#### Scenario: A failed run does not claim a recovery time
- **WHEN** a run stops at step 5
- **THEN** the recovery time is shown as not reached, naming step 5

### Requirement: Plain-words summary
The report SHALL include an "In plain words" section that states, without technical terms, what was rebuilt, what was proven, how much data a real recovery would have lost, and whether the run was a drill (live site untouched) or a real recovery.

#### Scenario: A drill says it was a drill
- **WHEN** the run was a drill
- **THEN** the summary states the live site was not touched

#### Scenario: A real recovery does not claim to be a drill
- **WHEN** the run was a real recovery
- **THEN** the summary describes it as a real recovery and does not say the servers were deleted afterwards

### Requirement: Needs attention
The report SHALL list every check that did not pass and, for a failed run, the step that stopped it, before any detail section. Each item SHALL say what it means and what to do. Failures SHALL come before warnings. A check with the same result on several servers SHALL appear once, naming the servers.

#### Scenario: One warning seen on both servers is listed once
- **WHEN** "Primary backup schedule" is a warning on both app servers
- **THEN** Needs attention lists it once, "seen on both servers", with what it means and what to do

#### Scenario: Failures before warnings
- **WHEN** a run has one failed check and one warning
- **THEN** the failed check is listed first

#### Scenario: Nothing needs attention
- **WHEN** every check passed
- **THEN** the report says nothing needs attention

### Requirement: Explained steps
The report SHALL list every step of the run in order, with its plain name, start time and duration drawn to scale, and a "What this does" explanation that includes what to check if it fails.

#### Scenario: Every step is explained
- **WHEN** a run completes its 9 steps
- **THEN** each step shows a plain name and a "What this does" explanation

### Requirement: Grouped, explained checks
The report SHALL show each check once, grouped by the layer it proves (app servers, requests through the app, data, database servers, backups), with one result column per server and a "What it proves" explanation. A check the report does not recognise SHALL still be shown, under "Other checks".

#### Scenario: Checks appear once with a column per server
- **WHEN** two servers each report the same 23 checks
- **THEN** the report shows 23 rows, each with one result per server

#### Scenario: An unknown check is not dropped
- **WHEN** a server reports a check the report does not recognise
- **THEN** it appears under "Other checks" with its own name and result

#### Scenario: A run that never reached verification
- **WHEN** the run stopped before the checks ran
- **THEN** the checks section says verification was not reached

### Requirement: Light, self-contained, safe
The HTML report SHALL render in a light theme regardless of the reader's operating-system theme, SHALL open without network access, and SHALL show any text taken from the run's output as text, never as markup.

#### Scenario: Dark-mode reader still sees a light report
- **WHEN** the report is opened on a computer set to dark mode
- **THEN** it renders light

#### Scenario: Run output cannot inject markup
- **WHEN** a check's detail contains `<script>`
- **THEN** the report shows the characters `<script>` as text

### Requirement: Markdown copy matches
The Markdown report SHALL contain the same sections in the same order as the HTML report.

#### Scenario: Same sections in both
- **WHEN** a run's reports are written
- **THEN** the Markdown and HTML reports list the same section headings in the same order

### Requirement: Evidence and scope
The report SHALL state what the rebuild time includes and excludes, and SHALL list each claim with a record held outside the repository and how to check it.

#### Scenario: Scope is stated
- **WHEN** a run's report is written
- **THEN** it states that detection, the decision to recover and the DNS switch are not included in the rebuild time
