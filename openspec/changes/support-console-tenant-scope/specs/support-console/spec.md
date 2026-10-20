# Spec Delta

## ADDED Requirements

### Requirement: Tables without a client marker are read only along real relationships
The system SHALL allow a lookup to read a table that has no client marker only when the table is joined, by one of its real relationships (a foreign key, or a type-and-id pair with the record type named), to data already limited to the conversation's client. A lookup that joins such a table any other way SHALL be refused before it runs, and the refusal SHALL name the relationships that may be used. A table with no relationship to the client's data SHALL NOT be readable.

#### Scenario: Wrong-column join is refused
- **WHEN** a lookup reads document shares joined to the client's documents on the share's own id instead of its document reference
- **THEN** the lookup is refused before it runs, with "join on a real relationship: doc_shares can be joined by doc_shares.document_id = documents.id"

#### Scenario: Real-relationship join runs
- **WHEN** a lookup reads document shares joined through their document reference to documents limited to the client
- **THEN** the lookup runs and returns only shares of the client's documents

#### Scenario: Subquery returning the wrong column is refused
- **WHEN** a lookup limits document shares to a list of folder references of the client's documents
- **THEN** the lookup is refused before it runs

#### Scenario: Type-and-id relationship needs its type
- **WHEN** a lookup joins notes to the client's investors by record id without naming the record type
- **THEN** the lookup is refused; naming the record type as investor lets it run

#### Scenario: Unlinked table is refused
- **WHEN** a lookup reads a table that has no client marker and no relationship to the client's data
- **THEN** the lookup is refused with "table not allowed" and does not run

### Requirement: Secret and chat-log tables are always refused
The system SHALL refuse any lookup that reads login codes, tokens, admin data, change history or AI chat logs, even when the table is joined by a real relationship to the client's data.

#### Scenario: AI chat logs are refused
- **WHEN** a lookup reads AI chat messages joined through their sessions to the client's users
- **THEN** the lookup is refused with "table not allowed"

### Requirement: Rows of another client are held back
The system SHALL check every row a lookup returns against the client of each table in it that carries a client marker. If any row belongs to another client, the system SHALL return no rows to the assistant, record the lookup as blocked and flagged, and alert super users with the existing flagged-lookup notification.

#### Scenario: A row from another client is held back
- **WHEN** a lookup that passed the checks returns a row whose document belongs to another client
- **THEN** the assistant receives no rows, the lookup is recorded as blocked and flagged, and super users are alerted

#### Scenario: Grouped totals are checked
- **WHEN** a lookup totals the client's remittance payments grouped by capital call
- **THEN** the totals are returned when every grouped row belongs to the client

### Requirement: References to other entities are never blocked
The system SHALL judge a row only by the client it belongs to. Columns that reference another entity (for example an investor's LP firm) SHALL NOT be filtered, removed or used to hold back a lookup, and that entity's own record SHALL stay readable through the reference; the referenced entity's own data SHALL still require the conversation's client.

#### Scenario: An investor's LP firm is shown
- **WHEN** a lookup reads the client's investors with the LP firm each one references
- **THEN** the rows, including the LP firm's name and PAN, are returned and the lookup is not flagged

#### Scenario: The LP firm's own funds are refused
- **WHEN** a lookup reads funds of the LP firm referenced by the client's investor
- **THEN** the lookup is refused with "add filter"
