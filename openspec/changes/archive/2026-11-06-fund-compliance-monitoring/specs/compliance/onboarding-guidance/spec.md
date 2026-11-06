# Spec Delta

## Purpose

Guides a fund manager that is new to Compliance from "just switched on" to "working breaches day to day". Every compliance page says what it is for, what its terms mean, and what to do next. A welcome notice and a few reminders bring people back, and CapHive support can see which firms are stuck. All guidance is worked out from the firm's own data. Nothing is stored as "done", and guidance never changes a result.

## ADDED Requirements

### Requirement: Getting started journey
Compliance home SHALL show a Getting started panel with eight steps, in order:
1. owner and approvers;
2. attach packs;
3. map inputs;
4. reference lists;
5. first run;
6. digest recipients;
7. monitoring on;
8. every open item has an owner.

Each step's state SHALL be worked out from the firm's data on every view, and SHALL NOT be stored as done. The first step not yet done SHALL be shown as current, with a "What's needed now" line, the reason it matters, and a button that opens the place to do it. A step whose data stops being true SHALL become not done again. A reference-list step that no attached check needs SHALL show "Not needed for your packs" and count as done. Users who cannot act (viewers) SHALL see the steps without buttons, and be told who can act. When all steps are done, the panel SHALL fold to one line with a "Show steps" link.

#### Scenario: Getting started on first visit
- **WHEN** Meera opens Compliance home for a firm with an owner and an approver but no packs
- **THEN** the panel shows "Getting started — 1 of 8 done", with step 2 current and an "Attach a pack" button

#### Scenario: Steps tick from data
- **WHEN** Meera attaches SEBI — AIF to Growth Fund I
- **THEN** step 2 is done, and step 3 asks her to map Sponsor/manager and estimated expenses, saying that 4 checks would otherwise show Could not check

#### Scenario: First run from Getting started
- **WHEN** steps 1–4 are done and Meera presses "Run now on Growth Fund I" in step 5
- **THEN** results appear without waiting for 02:00, and step 5 is done

#### Scenario: Setup complete folds away
- **WHEN** all eight steps are done
- **THEN** Compliance home shows "Setup complete · Show steps" above the dashboard

### Requirement: What's next panel
Every compliance show page and list page SHALL show a "What's next" panel of at most three actions. The actions SHALL be worked out from the page's record, its state and the user's role:
- breach: assign, request an explanation, or fix the data;
- could not check: map the named input, linking to it in Setup;
- request pending: approve or reject for an eligible approver; "waiting for an approver" for the requester;
- duty due: upload evidence and mark done;
- facts waiting: confirm against the quote;
- draft version: test, then publish.

A page with nothing to do SHALL say so, and say when the next run is.

#### Scenario: What's next on a result
- **WHEN** Meera opens a concentration breach of 26.67%
- **THEN** the panel offers Assign, Request an explanation, and "fix the data — the next run clears it"

#### Scenario: What's next on a register item
- **WHEN** Rahul, an approver, opens an item with Meera's pending explanation
- **THEN** the panel offers Approve and Reject; Meera, opening the same item, sees "Waiting for an approver" and no Approve button

#### Scenario: Empty pages say what to do
- **WHEN** the register has no open items
- **THEN** it shows "Nothing open. The next run is tonight at 02:00 IST."

### Requirement: Timing banner
Compliance home, the fund's compliance page and the register SHALL show which run the results come from and when the next run is, in the firm's time zone:
- results more than 26 hours old SHALL show an amber "may be out of date" banner;
- a firm with no runs SHALL be told the first run is tonight, and offered Run now.

#### Scenario: Timing banner
- **WHEN** the 05/11/2026 02:00 IST run succeeded and Meera opens Compliance home at 10:00
- **THEN** it shows "Results from the 02:00 IST run on 05/11/2026 · next run 06/11/2026 02:00 IST"

### Requirement: Terms and pages explained in place
Every compliance page SHALL open with a one- or two-line description of what it is for. Every compliance term in a column heading, label or status SHALL carry a tooltip. Tooltip wording SHALL come from one glossary, matching the design's Key concepts. Each page's guide icon SHALL open the compliance user guide at that page's own section.

#### Scenario: Terms explained in place
- **WHEN** Meera hovers the information icon beside the status "Explained"
- **THEN** the tooltip reads "An approver accepted this breach with a reason. It reopens if the figure gets worse."

#### Scenario: Guide opens at the page's section
- **WHEN** Meera presses the guide icon on the register
- **THEN** the compliance user guide opens at its register section

### Requirement: Section bar on every page
Every compliance page SHALL show one section bar: Home, Register, Duties, Facts to confirm, Packs, Setup. The current section SHALL be active. The bar SHALL show counts of open items, due duties and waiting facts.

#### Scenario: Section bar on every page
- **WHEN** there are 3 open items, 1 duty due and 6 facts waiting
- **THEN** the bar reads "Home · Register (3) · Duties (1) · Facts to confirm (6) · Packs · Setup"

#### Scenario: Section bar loads sections in place
- **WHEN** Meera opens Compliance with the Register tab selected (or clicks Register on the Compliance hub)
- **THEN** the Register pill is active and its pane loads lazily into the page from the register's own URL, without a full page visit; on other compliance pages the same pill returns to the hub with that tab open

#### Scenario: Step popups
- **WHEN** Meera clicks the "Map inputs" circle in the Getting started rail
- **THEN** a popup, like every other journey's step popup, shows what to do, each input with mapped or not mapped and the checks a missing one blocks, the Map inputs button, what the step is and why it matters; an investor is refused and an unknown step is not found

#### Scenario: Minimise Getting started
- **WHEN** Meera minimises Getting started and later reopens Compliance
- **THEN** only its header (title and "n of 8 done") shows until she expands it again

### Requirement: One funds grid
Compliance home SHALL show one funds grid: every fund the user can see, one column per attached pack (classification · version and that pack's latest results), open items, and per-row actions. A compliance editor SHALL be able to attach a pack from any row, with that fund already chosen. The old Fund packs page SHALL lead to the same grid; there SHALL NOT be a second fund × pack view.

#### Scenario: One funds grid
- **WHEN** Meera presses Attach on Horizon Seed Fund's row and attaches SEBI — AIF as Category II
- **THEN** the form opened with Seed Fund chosen, and the row now shows "Category II · v1" under SEBI — AIF instead of Not monitored; opening /compliance/fund_packs lands on the same grid

### Requirement: Welcome notice and reminders
When a firm's compliance setup is first created, its company admins and users tagged Compliance SHALL receive one welcome notice, in-app and by email, linking to Getting started. If setup is still incomplete after 7 days, the owner SHALL receive one reminder naming the next step, and one more after 21 days. No reminders SHALL be sent after that, or once setup is complete. A firm without the Compliance entity flag SHALL receive none.

#### Scenario: Welcome notice
- **WHEN** Horizon's compliance setup is created
- **THEN** company admins and Compliance-tagged users get "Compliance is on for Horizon Capital — start with Getting started (8 steps)", once

### Requirement: Customer setup progress
CapHive super admins SHALL see a Customer setup list showing, for each firm with Compliance on:
- the number of steps done;
- the next step;
- the date setup started.

It SHALL show step names and counts only: no fund names, figures or people. Any other user SHALL be refused.

#### Scenario: Customer setup progress
- **WHEN** a super admin opens Compliance › Customer setup
- **THEN** the list shows "Horizon Capital · 3 of 8 · next: Map inputs · since 04/11/2026"

### Requirement: Guidance is for compliance users only
Getting started, What's next and the section bar SHALL be shown only to compliance viewers of the firm, on pages (and the Getting started frame) authorized like any other compliance page. A direct request from an investor or another firm SHALL be refused.

#### Scenario: Guidance is for compliance users only
- **WHEN** an investor requests the Getting started frame directly, or another firm's admin requests a Horizon result page (which carries its What's next)
- **THEN** the request is refused

### Requirement: About this check
Every check in a pack definition SHALL carry a plain-words description: what it tests, why it matters, and what usually causes a failure. A version SHALL NOT be published while any check has no description; a draft SHALL list the checks missing one. AI drafting SHALL propose a description that the editor can change before saving. The result page and the register item SHALL open with an "About this check" card showing it, and the version page SHALL show it under each check.

#### Scenario: About this check
- **WHEN** Meera opens a concentration result or its register item
- **THEN** the first card, "About this check", explains what the check tests, why SEBI caps it and what usually causes a breach

#### Scenario: Publish needs descriptions
- **WHEN** a draft has a check with no description and its editor presses Publish
- **THEN** publishing is refused with "Add a description to every check" naming the check

### Requirement: Descriptions backfilled
A one-off task SHALL write descriptions into versions that were published before descriptions existed, from the pack files. It SHALL write only the description text; any version whose rules differ from its file SHALL be skipped and reported. It SHALL be a dry run unless EXECUTE=1, SHALL record an audit row per version changed, and SHALL refuse production unless forced.

#### Scenario: Descriptions backfilled
- **WHEN** the task runs with EXECUTE=1 over a SEBI v1 loaded without descriptions
- **THEN** every check gains its description and every other field of the definition is unchanged

### Requirement: How we checked
The working of every result SHALL be titled "How we checked", with the run it comes from ("Step by step, from your records as they stood at the 02:00 IST run on 06/11/2026", or the Run now time), shown as numbered steps wherever a working appears. A summary SHALL appear once. Records dated before a check started SHALL be described in words with a link to them. Amounts SHALL use the same crore format as the rest of the page.

#### Scenario: How we checked
- **WHEN** Meera opens a document-check result with 4 records to look at and 22 made before the check started
- **THEN** the card is titled "How we checked", the summary appears once, and it reads "22 investments made before this check started are not checked" with a link to them

