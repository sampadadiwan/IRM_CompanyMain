# Spec Delta

## Purpose

Imports meeting notes from a fund's Granola account and files each one as an internal Note on the
investor the meeting was with. Ambiguous meetings wait for human review, and meetings with no
investor contact are never filed.

## ADDED Requirements

### Requirement: Connect a Granola account
The system SHALL let a fund team member connect a per-user Granola connection, and a fund admin
connect one workspace Granola connection per entity. The system SHALL verify the API key with Granola
before saving it, SHALL store the key encrypted, and SHALL never display the full key after saving.

#### Scenario: Valid per-user key
- **WHEN** a fund team member enters a Granola API key that Granola accepts and clicks Connect
- **THEN** a per-user connection is saved for that user and entity with status "connected"
- **AND** an initial sync covering the previous 90 days is queued
- **AND** the key is displayed masked, showing only its last 4 characters

#### Scenario: Rejected key
- **WHEN** a user enters a key that Granola rejects and clicks Connect
- **THEN** no connection is saved
- **AND** the user sees "Granola rejected this API key. Check it and try again."

#### Scenario: Only one connection of each kind
- **WHEN** a user who already has a per-user connection for the entity tries to add another
- **THEN** the system refuses and offers Disconnect or reconnect with a new key instead

#### Scenario: Workspace connection restricted to fund admins
- **WHEN** a fund team member who is not a fund admin opens entity settings
- **THEN** the Granola workspace section is not shown
- **AND** a direct request to create a workspace connection is denied

#### Scenario: Disconnect keeps imported notes
- **WHEN** the owner of a connection clicks Disconnect and confirms
- **THEN** the connection stops syncing and its key is deleted
- **AND** every note already imported through it remains

### Requirement: Periodic sync of Granola meetings
The system SHALL check every active connection about every 15 minutes, and on demand via Sync now,
for Granola meetings created or updated since that connection's last successful sync. Each Granola
meeting SHALL be recorded at most once per entity, whichever connection returned it.

#### Scenario: New meeting picked up
- **WHEN** a meeting finishes in Granola and the next sync runs
- **THEN** the meeting is recorded for the entity and routed through matching

#### Scenario: Same meeting via two connections
- **WHEN** a meeting is returned by a partner's per-user connection and by the workspace connection
- **THEN** only one meeting record and at most one note per investor exist for it

#### Scenario: Nothing new
- **WHEN** a sync finds no meetings updated since the last sync
- **THEN** no notes change and the connection's last-sync time is updated

### Requirement: Match meeting attendees to investors
The system SHALL match a meeting to investors by comparing each attendee's email address,
case-insensitively, with the email addresses of investor contacts in the same entity. Attendees
whose email belongs to a fund team member of the entity SHALL be treated as internal and SHALL NOT
count toward matching.

#### Scenario: Single investor exact match is auto-filed
- **WHEN** at least one external attendee matches a contact exactly and all exact matches belong to one investor
- **THEN** the meeting is filed as a note on that investor without review

#### Scenario: Multiple investors go to review
- **WHEN** exact matches belong to two or more different investors
- **THEN** the meeting is placed in the Granola Inbox with every matched investor as a candidate
- **AND** no note is created until a user files it

#### Scenario: Domain-only match goes to review
- **WHEN** no attendee matches a contact exactly but an attendee's email domain matches an investor contact's domain
- **THEN** the meeting is placed in the Granola Inbox with those investors as candidates

#### Scenario: Public email domains never domain-match
- **WHEN** the only overlap is a public email domain such as gmail.com or outlook.com
- **THEN** that overlap does not make the investor a candidate

#### Scenario: No match is ignored
- **WHEN** no external attendee matches any investor contact by email or domain
- **THEN** the meeting is marked ignored and no note is created

#### Scenario: Internal-only meeting is ignored
- **WHEN** every attendee is a fund team member of the entity
- **THEN** the meeting is marked ignored

### Requirement: Filed note content
A filed meeting SHALL create one internal Note per chosen investor, owned by the investor. Each note
SHALL carry the meeting title and summary as its details, the meeting date as its date, the matched
contact as the person met, the tag `granola`, and a link to the meeting in Granola. Private notes
SHALL be included only when the connection returning them is per-user and Granola returns them.

#### Scenario: Note fields
- **WHEN** a meeting "Q3 check-in" held on 28 Sep 2026 with contact Jane Doe of Acme Pension is filed
- **THEN** Acme Pension has a note dated 28 Sep 2026, tagged `granola`, with Jane Doe as the person met, the title and summary in its details, and an Open in Granola link

#### Scenario: Private notes via per-user connection
- **WHEN** a meeting imported through a per-user connection has private notes
- **THEN** the note's details include them under a "Private notes" heading

#### Scenario: Author with per-user connection
- **WHEN** a meeting is filed from a per-user connection
- **THEN** the note's author is the user who owns that connection

#### Scenario: Author with workspace connection
- **WHEN** a meeting is filed from the workspace connection and the Granola meeting owner's email belongs to a fund team member of the entity
- **THEN** that team member is the note's author
- **AND** otherwise the admin who connected the workspace is the author and the note states "Imported from Granola (owner: <name>)"

### Requirement: Last interaction date uses meeting date
Filing a Granola meeting SHALL set the investor's last interaction date to the meeting date, and
SHALL NOT move it backwards. Manually created notes SHALL keep their existing behaviour.

#### Scenario: Backfilled old meeting
- **WHEN** a meeting from 60 days ago is filed today and the investor's last interaction date is 10 days ago
- **THEN** the last interaction date stays 10 days ago

#### Scenario: Recent meeting
- **WHEN** a meeting held yesterday is filed and the last interaction date is 30 days ago
- **THEN** the last interaction date becomes yesterday

### Requirement: Granola Inbox review
The system SHALL provide a Granola Inbox, scoped to the user's entity, listing meetings awaiting
review and, under an Ignored filter, meetings that matched nobody. A user SHALL be able to file a
meeting to one or more investors of the entity, discard it, or re-match ignored meetings.

#### Scenario: File to one investor
- **WHEN** a user selects Acme Pension Fund for an inbox meeting and clicks File
- **THEN** a note is created on Acme Pension Fund as described in "Filed note content"
- **AND** the meeting leaves the inbox and records who filed it and when

#### Scenario: File to several investors
- **WHEN** a user selects two candidate investors and clicks File
- **THEN** each investor gets its own note for the meeting

#### Scenario: Discard
- **WHEN** a user clicks Discard on an inbox meeting
- **THEN** the meeting leaves the inbox and is not re-queued by later syncs, even if it changes in Granola

#### Scenario: Re-match after adding a contact
- **WHEN** a user adds jane@acmepension.com as a contact of Acme Pension and clicks Re-match on an ignored meeting she attended
- **THEN** the meeting is filed on Acme Pension

#### Scenario: Inbox visibility follows note visibility
- **WHEN** a fund team member who is not a fund admin opens the Granola Inbox
- **THEN** they see only meetings whose resolved author is themselves
- **AND** a fund admin sees every meeting for the entity

#### Scenario: Cross-entity investor rejected
- **WHEN** a filing request names an investor belonging to a different entity
- **THEN** the request is denied and no note is created

### Requirement: Updates from Granola respect CapHive edits
When a filed meeting changes in Granola, the system SHALL update the notes it created for it, unless
a user has edited a note's details in CapHive since the system last wrote it. Such a note SHALL be
left unchanged and SHALL show that later Granola changes are not applied. Notes deleted in CapHive
SHALL NOT be recreated.

#### Scenario: Unedited note refreshed
- **WHEN** a filed meeting's summary changes in Granola and nobody has edited the note in CapHive
- **THEN** the note's details, date and person met are updated on the next sync

#### Scenario: Edited note preserved
- **WHEN** a user edited the note's details in CapHive and the meeting then changes in Granola
- **THEN** the note is not changed
- **AND** it shows "Edited in CapHive — later Granola changes are not applied"

#### Scenario: Deleted note not recreated
- **WHEN** a user deletes an imported note and the meeting later changes in Granola
- **THEN** no note is recreated for that investor

### Requirement: Connection failure alerting
When Granola rejects a connection's key during a sync, the system SHALL mark the connection "needs
attention" with the reason, pause its syncing, and notify the user who connected it by email and
in-app. Temporary failures (timeouts, rate limits, server errors) SHALL be retried without notifying
anyone, unless the connection has had no successful sync for 24 hours.

#### Scenario: Revoked key
- **WHEN** Granola returns an authentication error during a sync
- **THEN** the connection shows Needs attention, stops syncing, and its connector receives an email and an in-app notification

#### Scenario: Reconnect resumes
- **WHEN** the connector enters a valid key on a connection that needs attention
- **THEN** the connection returns to connected and resumes from its last successful sync point

#### Scenario: Prolonged outage
- **WHEN** a connection has had no successful sync for 24 hours because of temporary errors
- **THEN** its connector is notified once, and not again until a sync succeeds and later fails again
