# compliance/compliance-monitoring Specification

## Purpose
Runs every attached pack's checks nightly and on demand, stores each result with its figures as an immutable record, and keeps a compliance register of breaches and manual duties with approvals, fix-by dates, notifications, a daily digest and exports.

## Requirements

### Requirement: Nightly and on-demand runs
The system SHALL run every applicable check of every attached pack for every monitored fund at 02:00 in the entity's time zone, and for one fund when a compliance editor presses Run now. Each fund's run SHALL read one consistent snapshot of its data. A second Run now for the same fund while one is running SHALL wait for the first and produce one result set. Closed or wound-up funds SHALL not be run.

#### Scenario: Nightly run
- **WHEN** it is 02:00 IST for Horizon Capital
- **THEN** every check of every pack attached to Horizon's monitored funds is evaluated and stored

#### Scenario: Run now twice
- **WHEN** Meera presses Run now twice on Growth Fund I
- **THEN** one result set is produced

#### Scenario: Payment recorded during a run
- **WHEN** a payment is recorded for Growth Fund I while its run is in progress
- **THEN** that run's figures either all include it or all exclude it

#### Scenario: Closed fund not run
- **WHEN** a fund is wound up
- **THEN** it is not run and its history remains viewable

### Requirement: Immutable results with the working
Each run SHALL store, per check per fund: pack and version, classification, result, every figure used, the limit (with any override and the pack's value), and the run time. Stored results MUST NOT change after the run, even if data is later corrected or backdated; past dates are never re-run. Results, register and history MUST NOT be deleted automatically (retention period: counsel). Soft-deleted records SHALL be excluded from every figure. Results SHALL be Pass, Breach, Warning, Needs review or Could not check.

#### Scenario: Concentration breach with working
- **WHEN** corpus is ₹300.00 cr, estimated expenses ₹30.00 cr and Acme Foods' cost ₹72.00 cr
- **THEN** the result is Breach with working "₹300.00 − ₹30.00 = ₹270.00 cr; 72.00 ÷ 270.00 = 26.67% > 25%"

#### Scenario: Backdated payment
- **WHEN** on 20 Nov Arjun records a sponsor payment dated 01 Nov
- **THEN** results from 02–20 Nov stay as computed and the 21 Nov run includes the payment

#### Scenario: Soft-deleted record excluded
- **WHEN** an investor's commitment is soft-deleted
- **THEN** the next run's figures exclude it

#### Scenario: Undated record counted
- **WHEN** a commitment of ₹10.00 cr has no commitment date
- **THEN** the run counts it ("Corpus = ₹310.00 cr") rather than dropping it from the figures

#### Scenario: Corrected data does not rewrite history
- **WHEN** Acme's cost is corrected to ₹65.00 cr after the 5 Nov run
- **THEN** the 5 Nov result still shows 26.67% and the next run shows 24.07%

### Requirement: Version used by each fund
On the nightly run of a version's effective date the system SHALL move funds automatically by the version's applicability: A — every fund carrying the pack; B — funds whose start date is on or after the applicability date, while older funds stay on the previous version, labelled "On v1 — grandfathered", and keep that version's checks and duties; C — every fund. A fund with no start date under B or C SHALL NOT be guessed: its checks under that pack SHALL show "Could not check — missing: fund start date". Each result SHALL record the version used.

#### Scenario: Applicability A moves every fund
- **WHEN** SEBI v2 (A) is effective 01 Jan 2027
- **THEN** the 01 Jan run of every fund carrying SEBI records v2

#### Scenario: Applicability B fund starting on the applicability date
- **WHEN** v2 (B) has applicability date 01 Jan 2027 and a fund started on 01 Jan 2027
- **THEN** that fund runs on v2 from 01 Jan

#### Scenario: Applicability B fund starting the day before
- **WHEN** v2 (B) has applicability date 01 Jan 2027 and Growth Fund I started on 31 Dec 2026
- **THEN** Growth Fund I stays on v1, labelled "On v1 — grandfathered", with v1's checks and duties

#### Scenario: Fund without a start date
- **WHEN** v2 (B) takes effect and a fund carrying SEBI has no start date
- **THEN** every SEBI check of that fund shows "Could not check — missing: fund start date"

### Requirement: Transition period warnings
Under applicability C, for funds that started before the effective date, a breach under the new version SHALL show as Warning "In transition until <transition end date>" on every run up to and including the transition end date, and as Breach from the next run; funds that started on or after the effective date SHALL get no transition.

#### Scenario: Warning on the last transition day
- **WHEN** v2 (C) is effective 01 Jan 2027 with transition end 30 Jun 2027, Growth Fund I started in 2025 and fails a new v2 check
- **THEN** the 30 Jun 2027 run shows Warning "In transition until 30 Jun 2027"

#### Scenario: Breach on the run after the transition ends
- **WHEN** the same check still fails on the 01 Jul 2027 run
- **THEN** it shows Breach and a register item opens

#### Scenario: Fund started on the effective date gets no transition
- **WHEN** a fund started on 01 Jan 2027 fails a v2 check on 02 Jan 2027
- **THEN** it shows Breach, not Warning

### Requirement: Version published ahead
A version published before its effective date SHALL show a "Coming into effect <date>" banner on every fund carrying the pack and offer a read-only preview run per fund under the new version, listing each check's preview result against today's result. Preview results MUST NOT be written to the register, the stored results or the digest. Funds staying grandfathered under B SHALL see "This version will not apply to this fund".

#### Scenario: Preview shown, nothing logged
- **WHEN** SEBI v2 is published on 01 Dec 2026, effective 01 Jan 2027, and Meera opens the preview for Growth Fund I
- **THEN** she sees "Under v2: concentration 26.67% vs 25% → ✗ Breach (unchanged); new check <name> → ✗" and no register item, result or digest line is created

#### Scenario: Grandfathered fund preview
- **WHEN** v2 (B) is published ahead and Growth Fund I started before the applicability date
- **THEN** its banner says "This version will not apply to this fund"

### Requirement: Version notifications
Compliance owners of every entity with a fund carrying the pack SHALL be notified when a version is published ahead and again exactly 7 days before its effective date.

#### Scenario: Notified on publish
- **WHEN** SEBI v2 is published on 01 Dec 2026, effective 01 Jan 2027
- **THEN** Horizon's owners are notified on 01 Dec

#### Scenario: Notified exactly 7 days before
- **WHEN** the date is 25 Dec 2026 for a 01 Jan 2027 effective date
- **THEN** owners are notified that day, and not on 24 Dec or 26 Dec

### Requirement: Register items when a version changes checks
When a new version takes effect for a fund, open register items for checks removed in that version SHALL close as "Check removed in v<n>"; items for changed checks SHALL stay open and be re-evaluated by that night's run.

#### Scenario: Removed check closes its item
- **WHEN** v2 removes a check with an open item on Growth Fund I
- **THEN** the item closes as "Check removed in v2"

#### Scenario: Changed check re-evaluated
- **WHEN** v2 raises a limit and the open item's figure now passes
- **THEN** the item closes as "Cleared by data" on the 01 Jan run

### Requirement: Never a silent pass
A check whose input is missing SHALL show "Could not check — missing: <input>"; an attachment without classification SHALL run no checks and say so; neither MAY be counted as Pass.

#### Scenario: Missing input
- **WHEN** estimated expenses are blank for a fund
- **THEN** concentration shows "Could not check — missing: estimated expenses" and is counted under could not check

### Requirement: Tested continuously or when a record is made
A check tested continuously SHALL be evaluated on every run. A check tested when a record is made SHALL evaluate each new record once, in the first run after it is created, with that day's figures, and later changes MUST NOT reopen it.

#### Scenario: Record-time check ignores later changes
- **WHEN** a concentration check is tested when a record is made and investable funds fall after the investment
- **THEN** no new breach is opened for that investment

#### Scenario: Continuous check catches a passive breach
- **WHEN** the same check is tested continuously and investable funds fall from ₹200 cr to ₹180 cr with Acme at ₹50 cr
- **THEN** the next run is Breach (50 ÷ 180 = 27.78% > 25%)

### Requirement: Currency conversion
When a figure's currency differs from the limit's, the figure SHALL be converted at CapHive's exchange rate for the run date and the working SHALL show the rate. With no rate for that date the check SHALL show Could not check naming the missing rate.

#### Scenario: USD limit on an INR figure
- **WHEN** a USD 150,000 minimum is tested on a ₹1.20 cr commitment with a run-date rate of ₹83.00 per USD
- **THEN** the working shows "₹1,20,00,000 ÷ 83.00 = USD 144,578 < USD 150,000" and the result is Breach

#### Scenario: Missing exchange rate
- **WHEN** no INR/USD rate exists for the run date
- **THEN** the check shows "Could not check — missing: INR/USD rate for <date>"

### Requirement: Grouped results list each failing group
A check over a per-investor or per-investee measure SHALL list every failing investor or investee with its figure.

#### Scenario: Investors below the minimum listed
- **WHEN** two investors have commitments of ₹90 lakh and ₹99,99,999
- **THEN** the minimum-investment breach lists both with their amounts

### Requirement: Record-level document results
A record-level document check SHALL show "N of M records OK", list each failing record with Missing, Not signed or Signed late, and count records before the "checks from" date as not checked. "Signed" SHALL be met by a completed CapHive e-signature (signed date = completion date) or by an uploaded copy marked "Signed (wet ink)" with a required, not-future signed date; the timing test SHALL use the signed date, never the upload date. Signed late SHALL be cleared only by an approved explanation. When a document is moved to another record or deleted, the record SHALL be re-evaluated (Missing) on the next run. A failing row for a soft-deleted record SHALL drop off the list as "Record deleted".

#### Scenario: IC note list
- **WHEN** 17 investments are dated on or after 1 Apr 2026, 3 lack a valid IC note and 120 are earlier
- **THEN** the result shows "14 of 17 investments OK · 3 failing · 120 earlier investments not checked"

#### Scenario: Wet ink scanned after the investment
- **WHEN** an IC note signed in wet ink on 10 Sep is uploaded on 15 Sep for a 12 Sep investment and marked signed 10 Sep
- **THEN** the investment passes (10 Sep ≤ 12 Sep)

#### Scenario: Scan not marked signed
- **WHEN** an IC note scan is uploaded but not marked signed and has no e-signature
- **THEN** the investment is listed "Not signed — mark as signed (wet ink)"

#### Scenario: E-sign completed after the investment
- **WHEN** an IC note e-signature completes on 24 Oct for a 20 Oct investment
- **THEN** the investment is listed "Signed late" and uploading again does not clear it

#### Scenario: IC note moved to another investment
- **WHEN** Orbit Health's IC note is moved to the Kite Pay investment
- **THEN** the next run lists Orbit Health as Missing

#### Scenario: Deleted investment drops off the list
- **WHEN** the failing Zen Labs investment is soft-deleted
- **THEN** the next run removes it as "Record deleted" and the count becomes "14 of 16"

#### Scenario: Future signed date refused
- **WHEN** a user marks a scan signed with a date after today
- **THEN** it is refused with "Signed date cannot be in the future"

### Requirement: Two packs, same figure
When two attached packs test the same figure with different limits, each SHALL produce its own result and its own register item.

#### Scenario: SEBI and fund agreement both fail
- **WHEN** Acme is 26.67% with SEBI ≤ 25% and the fund agreement ≤ 20%
- **THEN** two breaches are shown, one under each pack

### Requirement: Register lifecycle
A failing result SHALL open one register item per check per fund per breach episode (not one per day). The item SHALL move Open → In progress on assignment; an explanation SHALL be Pending approval until a compliance approver or company admin other than its author approves (Explained) or rejects (back to In progress); if the entity has exactly one eligible user, self-approval SHALL be allowed and labelled "Self-approved — single approver". When a user is deactivated, their assigned items and pending approvals SHALL return to the compliance owner, and the next digest SHALL say so once. An open item for a soft-deleted record SHALL close as "Record deleted". An item SHALL close as Cleared by data when the check passes again, keeping failing and passing figures; an Explained item SHALL reopen if the figure becomes worse than when approved. Approved detaching closes items as Pack detached; approved disabling closes them as Disabled.

#### Scenario: Same breach next day
- **WHEN** concentration fails on 5 Nov and again on 6 Nov
- **THEN** there is one item opened 5 Nov and no new digest line on 6 Nov

#### Scenario: Cleared by data
- **WHEN** the sponsor's top-up brings paid-in to ₹2.25 cr and the next run passes
- **THEN** the pro-rata item closes as "Cleared by data" with both runs' figures

#### Scenario: Explanation approved then worsens
- **WHEN** Rahul approves an explanation at 26.67% and a later run shows 27.50%
- **THEN** the item reopens "Worsened since approval"

#### Scenario: Author cannot approve own explanation
- **WHEN** Meera approves her own explanation, including by a direct request
- **THEN** it is refused

#### Scenario: Deactivated approver with a pending request
- **WHEN** Rahul has a pending explanation to approve and is deactivated
- **THEN** the request returns to the compliance owner Meera's queue and the next digest says "1 request from Rahul (deactivated) returned to you" once

#### Scenario: Item for a deleted record closes
- **WHEN** a breach item concerns an investor whose commitment is soft-deleted
- **THEN** the item closes as "Record deleted"

#### Scenario: Assign before explain is optional
- **WHEN** Meera writes an explanation on an Open item without assigning it
- **THEN** the item becomes Pending approval

### Requirement: Fix-by dates and escalation
Each register item SHALL have a fix-by date = first seen + the check's time to fix. After the fix-by date the item SHALL be flagged Overdue and the owner and approver emailed, and it SHALL appear in every digest until resolved.

#### Scenario: Overdue on the day after fix-by
- **WHEN** an item first seen 5 Nov has 30 days to fix and is still open on 6 Dec
- **THEN** it is flagged Overdue on 6 Dec (fix-by 5 Dec) and escalated

#### Scenario: Not overdue on the fix-by date
- **WHEN** the same item is open on 5 Dec
- **THEN** it is not yet Overdue

### Requirement: Manual duties
Manual duties SHALL be created per fund by schedule, on demand, or event ("for each new <record type>", "when a <document input> is uploaded or replaced"); records created before an event duty's from date (e.g. historic imports) SHALL create no duties; a pack attached mid-period SHALL get its first scheduled duty at the next period end, with no backfilled duties; a duty with no named owner SHALL go to the compliance owner. Duties move Scheduled → Due when the reminder window opens → Done when marked done, or Overdue after the due date. Marking done SHALL record who, when, a note and — when required — an evidence document. Late completion SHALL be recorded as late.

#### Scenario: Quarterly duty done with evidence
- **WHEN** Meera marks "Quarterly SEBI report — Q2 FY27" done and uploads the acknowledgement
- **THEN** the duty is Done with the evidence link and the Q3 duty is scheduled

#### Scenario: Evidence required
- **WHEN** a duty requiring evidence is marked done without a document
- **THEN** it is refused with "Upload the evidence"

#### Scenario: Event duty for a new investor
- **WHEN** a new investor is added to Growth Fund I and the pack has "for each new investor: due diligence, due 15 days"
- **THEN** a due-diligence duty for that investor is created, due 15 days later

#### Scenario: Import straddling the from date
- **WHEN** an import on 05 Nov creates 312 investors with commitment dates before the 01 Nov from date and 4 on or after it
- **THEN** 4 due-diligence duties are created and none for the other 312

#### Scenario: Attached mid-period
- **WHEN** the SEBI pack is attached on 20 Nov 2026 with a financial-year basis
- **THEN** the first quarterly duty covers the quarter ending 31 Dec 2026 and nothing is created for earlier quarters

#### Scenario: Duty without owner defaults
- **WHEN** an event duty is created and no owner is named for it
- **THEN** it is owned by the compliance owner

#### Scenario: Overdue duty
- **WHEN** a duty's due date passes without completion
- **THEN** it shows Overdue in red on the dashboard and in the digest

### Requirement: Run health
Every Compliance screen SHALL show the last successful run. Results older than 26 hours SHALL be marked "may be out of date" in amber. A failed run SHALL email the compliance owners and alert CapHive support. Missed runs SHALL show as gaps in run history and SHALL NOT be backfilled.

#### Scenario: Failed run
- **WHEN** the 6 Nov run fails
- **THEN** screens show "Last successful run 05 Nov 02:00 — results may be out of date" after 26 hours and owners are emailed

#### Scenario: Missed run shown as a gap
- **WHEN** no run happened on 06 Nov
- **THEN** run history shows a gap for 06 Nov and no 06 Nov results are created later

#### Scenario: Not stale at 25 hours
- **WHEN** the last successful run was 25 hours ago
- **THEN** results are not marked out of date

### Requirement: Notifications
The system SHALL notify: assignees on assignment (email and in-app); approvers on requests for explanation, override, disable or detach (email and in-app); requesters on approval or rejection (in-app); owner and approver on overdue items (email); owners and CapHive support on failed runs (email). No compliance notification SHALL ever go to investors or investor advisors.

#### Scenario: Assignment notified
- **WHEN** Meera assigns the concentration item to Arjun
- **THEN** Arjun gets an email and an in-app notification

#### Scenario: No investor notification
- **WHEN** any compliance event occurs on Growth Fund I
- **THEN** no investor or investor advisor is notified

### Requirement: Daily digest only on change
One digest per day SHALL go to the compliance owners listing new breaches, needs-review items, cleared items, attachments missing a classification, AI-read facts waiting (each with how long it has waited), duties within their reminder window (bulk-created duties grouped in one line), overdue duties and items, new pack versions with overrides to review, and queued documents, grouped by fund and pack. No digest SHALL be sent on a day with none of these.

#### Scenario: Bulk duties in one line
- **WHEN** 312 new investors created after the from date produce 312 due-diligence duties in one night
- **THEN** the digest shows one line "312 new investors — 312 due-diligence duties"

#### Scenario: Waiting facts show their age
- **WHEN** the Orbit Health IC note facts have been unconfirmed since 27 Oct and the digest is sent on 05 Nov
- **THEN** the line reads "IC note — Orbit Health: facts waiting 9 days"

#### Scenario: Quiet day
- **WHEN** nothing changed overnight and nothing is due or overdue
- **THEN** no digest is sent

#### Scenario: First run digest
- **WHEN** the first run finds 3 breaches, 1 needs review and a duty due in 7 days
- **THEN** the digest reads "3 new breaches, 1 needs review, 1 duty due in 7 days"

### Requirement: Register export
A compliance viewer SHALL be able to export, for a chosen period, funds and packs, the results at period end with figures, every register item opened or open in the period with its history, and every duty with evidence links, as Excel or PDF, generated in the background and limited to the user's fund access; every export SHALL state "Computed on data as entered at run time".

#### Scenario: Quarter export
- **WHEN** Meera exports Q2 FY27 for Growth Fund I as Excel
- **THEN** she receives a download link to a file with results, items and duties for that quarter

#### Scenario: Export states the data basis
- **WHEN** Meera exports Q2 FY27
- **THEN** the file states "Computed on data as entered at run time"

#### Scenario: Export limited by fund access
- **WHEN** a viewer without access to GIFT Opportunities exports all funds
- **THEN** the export contains no GIFT Opportunities rows

### Requirement: Screens explain themselves and update in place
The compliance screens SHALL use the app's standard layouts: the register filter and its Open / Closed / All tabs SHALL never disagree; tabs SHALL load lazily like the fund page; row actions SHALL update the row or summary in place with the flash; and every result page SHALL explain its working from the data stored at run time.

#### Scenario: Register filter and tabs agree
- **WHEN** the register is filtered by status = closed and by fund
- **THEN** the grid and its cards list only those items, and a status condition in the filter replaces the tabs with one "Filter results" tab

#### Scenario: Actions update in place
- **WHEN** a user assigns an item, requests or approves an explanation, marks a duty done, confirms facts or clicks Run now
- **THEN** the response replaces that item, row or facts card and shows the flash, without a full page load

#### Scenario: Result explains its working
- **WHEN** a user opens the concentration result of Horizon Growth Fund I (Acme ₹72.00 cr of ₹270.00 cr investable)
- **THEN** it shows the verdict "26.67% of investable funds — above the 25% limit", the numbered steps with their sources, and how to get back within the limit: reduce Acme to ₹67.50 cr (₹4.50 cr less) or raise investable funds to ₹288.00 cr

#### Scenario: Tabs load lazily
- **WHEN** a user opens the register, a pack version or a fund dashboard
- **THEN** each tab's content loads into its own frame when the tab is opened
