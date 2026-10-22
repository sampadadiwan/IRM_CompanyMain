# Spec Delta

## Purpose

How the Ops Assistant reads and changes a client's data: only through CapHive's API as the asking user,
every change shown first as an approval card and carried out exactly as shown after the user approves,
some actions never allowed, and missing API features reported rather than worked around.

## ADDED Requirements

### Requirement: Only CapHive's API, as the asking user
Every read and write SHALL go through CapHive's own API, authenticated as the asking user, so that their
permissions apply and CapHive's change history records them. The assistant SHALL have no database access
of any kind.

#### Scenario: Change history shows the user
- **WHEN** an approved action updates an investor
- **THEN** the investor's change history shows the approving user, as if they had made the change on the screen

#### Scenario: Permission refused by the API
- **WHEN** the asking user's CapHive permissions do not allow an action the assistant proposes
- **THEN** carrying it out is refused with the same message the screen would give, and nothing is written

### Requirement: Every write is an approval card first
The assistant SHALL NOT write anything directly. Each intended write SHALL become an approval card that
shows: the action in plain words, the records and counts affected, money totals and dates, whether it
notifies investors, any file to be uploaded (downloadable, with its rows, columns and totals), and the
assistant's own summary labelled as such. Nothing SHALL be written until the user approves.

#### Scenario: Card shown, nothing written
- **WHEN** the assistant prepares a capital call
- **THEN** an approval card shows "Waiting for your approval" and no call exists in the fund yet

#### Scenario: Reject
- **WHEN** the user clicks Reject
- **THEN** the card shows "Rejected by <user>" and nothing is written

#### Scenario: Investor notification is flagged
- **WHEN** the card's action approves a capital call or distribution
- **THEN** the card states "This sends notices to investors" before the Approve button

### Requirement: Approval carries out exactly what was shown
On approval, CapHive SHALL carry out the stored request exactly as previewed, without the assistant
changing it. Only the user who asked SHALL be able to approve, only once, and only while the card is
waiting. If any figure the card relied on has changed since it was prepared, approval SHALL be refused.

#### Scenario: Approve
- **WHEN** the asking user clicks Approve on a waiting card
- **THEN** the card shows "Approved by <user> <time> — running" and then the result

#### Scenario: Double click
- **WHEN** Approve is clicked twice quickly
- **THEN** the action is carried out once

#### Scenario: Another user cannot approve
- **WHEN** a different user of the same entity opens the card
- **THEN** the card is read-only and a direct approve request is refused

#### Scenario: Data changed since prepared
- **WHEN** an investor was added to the fund after a call's card was prepared and the user then approves
- **THEN** approval is refused with "The data changed since this was prepared — ask me to prepare it again." and nothing is written

#### Scenario: Card expires
- **WHEN** a card has waited more than 24 hours
- **THEN** it shows "Expired" and can no longer be approved

### Requirement: Some actions are never done by the assistant
The assistant SHALL NOT propose, and CapHive SHALL refuse to carry out from a card, any delete, any undo
of an import, or any change to entity settings or entity permissions — even if the user would approve it.

#### Scenario: Asked to delete
- **WHEN** a user asks the assistant to delete a capital call
- **THEN** no approval card is shown and the answer says "I can't do that — please use the Capital Calls screen." with the steps

#### Scenario: Forbidden request slipped into a card
- **WHEN** a card's stored request is a delete or an entity-settings change
- **THEN** it is refused when proposed, and again if approval is attempted, and nothing is written

### Requirement: Failures are explained row by row
When an approved upload has failed rows, the assistant SHALL list each failed row with the reason and a
proposed fix, and any fix SHALL be a new approval card. It SHALL NOT retry on its own.

#### Scenario: Three rows fail
- **WHEN** an approved remittance upload creates 272 of 275 rows
- **THEN** the conversation lists the 3 failed rows with their reasons and offers a corrected card, and nothing more is written until it is approved

### Requirement: Missing API features are reported, not worked around
When CapHive's API cannot do what the user asks, the assistant SHALL say so, tell the user how to do it on
the screen, and record the gap for CapHive without any client data.

#### Scenario: No API for it
- **WHEN** the user asks for something no API endpoint offers
- **THEN** the answer says "CapHive doesn't let me do this through its API yet" with the screen steps, and the gap is recorded with only the kind of request, not the client's data

### Requirement: Transforms run without network or credentials
Files the assistant builds from the user's attachments SHALL be produced by scripts that run with no
network access and no CapHive or Anthropic credential, reading only that conversation's files.

#### Scenario: Script tries the network
- **WHEN** a transform script tries to reach CapHive's API or the internet
- **THEN** the connection fails and the script's output reports the failure
