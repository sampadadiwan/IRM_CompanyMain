# Spec Delta

## Purpose

How a client user talks to the Ops Assistant: conversations owned by one user and one entity, live
progress, stop, attachments and produced files, background work that reports back, notifications, and
retention until the client deletes.

## ADDED Requirements

### Requirement: Conversations belong to one entity and one user
Each conversation SHALL belong to one entity and be started by one user. A user SHALL see only their own
conversations; a company admin SHALL also see every conversation of their entity, read-only.

#### Scenario: Another employee's conversation
- **WHEN** an employee with the Ops Assistant permission opens a conversation started by a colleague
- **THEN** they see "Not authorized."

#### Scenario: Company admin reads a conversation
- **WHEN** a company admin opens a colleague's conversation
- **THEN** it is shown read-only, without the ask box or approval buttons

### Requirement: Asking shows live progress and can be stopped
A question SHALL be answered in the background with live progress shown in the page. Only one question
SHALL run per conversation at a time, and the user SHALL be able to stop it.

#### Scenario: Live progress
- **WHEN** a user sends a question
- **THEN** the page shows plain-words progress lines while the assistant works, then the answer, without a reload

#### Scenario: One question at a time
- **WHEN** a question is still running in a conversation
- **THEN** the ask box is disabled and a second question for that conversation is refused

#### Scenario: Stop
- **WHEN** the user presses Stop while a question runs
- **THEN** the work is cut off, the answer shows "Stopped.", and no write is started by that question

### Requirement: Answers use only the asking user's data and cite their source
An answer SHALL be based only on what the asking user can read through CapHive's API and on CapHive's
product documentation and code. It SHALL give figures with how they were worked out and a link to the
CapHive screen that shows them, and SHALL NOT quote source code.

#### Scenario: Fund the user cannot see
- **WHEN** a user asks about a fund their CapHive permissions do not cover
- **THEN** the answer says "You don't have access to that fund." and contains none of its figures

### Requirement: Files go in and come out through the conversation
A user SHALL be able to attach up to 5 files (xlsx, xls, csv or pdf, each up to 20 MB) to a question.
Files the assistant produces SHALL be offered for download in its answer. A file SHALL be saved to the
entity's Documents only through an approved action.

#### Scenario: Attachment refused
- **WHEN** a user attaches a 25 MB file or a .exe file
- **THEN** it is refused with the allowed types and size, and the question is not sent

#### Scenario: Produced file
- **WHEN** the assistant builds an upload file
- **THEN** the file is downloadable from the answer and from its approval card

### Requirement: Long work continues in the background and reports back
Work that outlasts a question (for example an import of thousands of rows) SHALL continue after the
answer ends and after the page is closed. Its result SHALL be posted into the same conversation.

#### Scenario: Long upload
- **WHEN** an approved upload of 4,118 rows is still processing when the answer ends
- **THEN** the answer says the work has started, and when it finishes the result (rows created, failed, totals) appears in the same conversation

### Requirement: The user is notified when they are needed or work finishes
The asking user SHALL receive an in-app notification and an email when an approval card is waiting for
them, when background work finishes, and when it fails. A company admin SHALL receive one when a learning
is proposed.

#### Scenario: Background work finishes
- **WHEN** background work started from a user's approval finishes
- **THEN** that user gets one in-app notification and one email linking to the conversation

#### Scenario: Not sent twice
- **WHEN** the same background work is checked again after it was reported
- **THEN** no second notification is sent

### Requirement: Conversations are kept until the client deletes them
Conversations, their files and their history SHALL be kept until deleted. The user who started a
conversation, or a company admin of the entity, SHALL be able to delete it; deleting SHALL remove its
messages, files and the assistant's saved history of it.

#### Scenario: Delete a conversation
- **WHEN** a company admin deletes a conversation
- **THEN** it disappears from the list and its files can no longer be downloaded
