# Spec Delta

## Purpose

Lets CapHive support users ask an AI assistant, which reads the deployed code and looks up one mapped
client's data read-only from the replica, why something in the product behaves the way it does for that client.

## ADDED Requirements

### Requirement: Support Console access is limited to the Support role
The system SHALL show the Support Console menu entry and page only to users holding the Support role.
Any other user SHALL be refused.

#### Scenario: Support user sees the console
- **WHEN** a user with the Support role opens the left menu
- **THEN** a "Support Console" entry is shown and opens the console page

#### Scenario: Other users are refused
- **WHEN** a user without the Support role requests the Support Console page
- **THEN** the system redirects to the home page with "Not authorized."

### Requirement: Client picker follows support mappings
The client picker SHALL list exactly the clients for which the user has a support mapping that is
enabled and not past its end date, and where the client has support access enabled.

#### Scenario: Only mapped clients are listed
- **WHEN** a support user is mapped to Golden Angels (enabled, in date, support enabled) and not to Beta Capital
- **THEN** the picker lists Golden Angels and does not list Beta Capital

#### Scenario: Expired mapping is not listed
- **WHEN** the user's mapping to Golden Angels has an end date before today
- **THEN** Golden Angels is not listed

#### Scenario: Client without support access is not listed
- **WHEN** the mapping is enabled but the client's support access is switched off
- **THEN** the client is not listed

#### Scenario: No mapped clients
- **WHEN** a support user has no qualifying mapping
- **THEN** the page shows "You are not mapped to any client with support access. Ask a super user to add a support mapping." and no picker

### Requirement: Access is rechecked on every question
The system SHALL recheck the user's support role, mapping and the client's support access before every
question, including follow-ups in an existing conversation, and SHALL refuse the question when any check fails.

#### Scenario: Mapping ended during a conversation
- **WHEN** a user asks a follow-up in a Golden Angels conversation after their mapping was disabled
- **THEN** the question is not sent to the assistant and the chat shows "Your support access to Golden Angels has ended."

### Requirement: A conversation belongs to one client
Each conversation SHALL be tied to the single client picked when it started and SHALL NOT be moved to
another client. The assistant SHALL be told the client's name and id at the start of every question.

#### Scenario: Header shows the client
- **WHEN** a user opens a conversation
- **THEN** its header shows the client it belongs to and offers no way to change it

#### Scenario: Question about another client
- **WHEN** the user asks to compare with another client's data
- **THEN** the answer states it can only look at the conversation's client

### Requirement: Questions run in the background with live updates
The system SHALL run each question in the background and stream progress and the answer into the page
without a reload. Only one question SHALL run per conversation at a time.

#### Scenario: Streaming answer
- **WHEN** a user submits a question
- **THEN** "Working…" and progress lines appear, followed by the answer, without a page reload

#### Scenario: Second question while one is running
- **WHEN** a question is running in a conversation
- **THEN** Ask is disabled and a second submission for that conversation is refused

#### Scenario: Question validation
- **WHEN** a user submits an empty question or one longer than 4,000 characters
- **THEN** the question is refused with a message and nothing is sent to the assistant

### Requirement: Stop a running question
The system SHALL let the user stop a running question. Stopping SHALL end the assistant's work and
record the answer so far followed by "Stopped."

#### Scenario: User stops an answer
- **WHEN** the user presses Stop while a question is running
- **THEN** the assistant stops, "Stopped." is appended, and Ask is enabled again

### Requirement: Answers cite their sources
Every completed answer SHALL end with a "Where this comes from" section naming the code locations and
the data lookups it relied on, and the page footer SHALL show the code version used.

#### Scenario: Sources shown
- **WHEN** an answer completes
- **THEN** it includes a "Where this comes from" section and the footer shows the code version

### Requirement: Data is read from the replica only, read-only
The assistant's data lookups SHALL go only to the read replica, through a login that can only read. The
data tool SHALL refuse to run when it is connected to a database that is not read-only, or when its login
holds any privilege beyond reading. Lookups SHALL be
limited to SELECT statements, a 30-second time limit and a capped number of returned rows, and the result
SHALL state the total row count when rows were cut.

#### Scenario: Not connected to a replica
- **WHEN** the data tool connects to a database reporting it is writable
- **THEN** it refuses every lookup and the chat shows "The Support Console is unavailable right now. Try again in a few minutes."

#### Scenario: Non-SELECT statement
- **WHEN** the assistant submits a statement that is not a SELECT
- **THEN** the lookup is refused with the reason and nothing is executed

#### Scenario: Slow lookup
- **WHEN** a lookup runs longer than 30 seconds
- **THEN** it is cancelled and the assistant receives "query timed out"

#### Scenario: Large result
- **WHEN** a lookup matches more rows than the cap
- **THEN** only the capped rows are returned with the total row count

### Requirement: Replica lag is shown
The system SHALL show how far behind the main database the replica is for the last answer, and SHALL
highlight it when it is more than 60 seconds.

#### Scenario: Replica lagging
- **WHEN** the replica is 95 seconds behind during an answer
- **THEN** the footer shows "Data as of 95 seconds ago" highlighted as a warning

### Requirement: Lookups are checked against the conversation's client
Before a lookup runs, the system SHALL parse it as MySQL and block it when any SELECT in it (each UNION
part, subquery and derived table) reads a table that is not tied to the conversation's client, when it
names a different client id, or when it reads a credential or cross-client table. The statement that runs
SHALL be the one rebuilt from the checked parse. After a lookup, the system SHALL flag any returned row
whose client column differs from the conversation's client.

#### Scenario: Unfiltered lookup is blocked
- **WHEN** the assistant submits a lookup on capital calls without filtering on the conversation's client
- **THEN** the lookup is blocked and the assistant is told to filter on that client

#### Scenario: Other client named
- **WHEN** a lookup filters on a client id other than the conversation's
- **THEN** the lookup is blocked

#### Scenario: Other client's rows returned
- **WHEN** a lookup returns rows belonging to another client
- **THEN** the lookup is recorded as flagged and super users are notified

### Requirement: Every lookup is recorded
The system SHALL record every lookup with the support user who asked it, the client, the conversation, the statement,
whether it was blocked or flagged, its row count and its duration, and SHALL let super users review the
record.

#### Scenario: Lookup recorded
- **WHEN** the assistant runs a lookup
- **THEN** a record exists with the user, client, statement, outcome, row count and duration

### Requirement: The assistant cannot change anything
The assistant SHALL have no means to write data, run shell commands, edit files, reach the internet or
send messages, and SHALL NOT be able to read the support machine's secrets or another client's saved
conversations. Answers SHALL NOT load images or other remote content when displayed. Asked for a change,
it SHALL describe the change instead of making it.

#### Scenario: Asked to fix data
- **WHEN** the user asks the assistant to correct a record
- **THEN** the answer describes the correction and states it cannot make it

### Requirement: Earlier conversations are kept per client for 90 days
The system SHALL list a client's conversations, newest first, and allow continuing them. Conversations
and their transcripts SHALL be removed 90 days after their last message.

#### Scenario: Continue a conversation
- **WHEN** the user opens an earlier Golden Angels conversation and asks a follow-up
- **THEN** the assistant answers with the earlier messages in context

#### Scenario: Old conversation removed
- **WHEN** a conversation's last message is more than 90 days old
- **THEN** it is no longer listed and its transcript is deleted

### Requirement: Support machine unavailability is reported
When the support machine cannot be reached or fails, the system SHALL show "The Support Console is
unavailable right now. Try again in a few minutes." and keep the question in the input box.

#### Scenario: Machine unreachable
- **WHEN** the support machine does not respond to a question
- **THEN** the chat shows the unavailable message and the question text remains in the box

### Requirement: Environments are independent
Each production environment SHALL have its own support machine, read-only login, AI access and secrets;
no URL, credential or transcript SHALL be shared between environments.

#### Scenario: India and US separate
- **WHEN** the console is used in production India
- **THEN** the question reaches only the India support machine, which reads only the India replica

### Requirement: Model chosen per question
The composer SHALL offer **Sonnet** and **Opus**, defaulting to Sonnet for a new conversation and to the
last choice within a conversation. Only these two SHALL be accepted; any other value SHALL be treated as
Sonnet. Each answer SHALL show which model produced it.

#### Scenario: Model chosen per question
- **WHEN** a user asks with Sonnet, then picks Opus and asks again
- **THEN** the first answer is produced by Sonnet and labelled "Sonnet", the second by Opus and labelled "Opus", and the selector stays on Opus
