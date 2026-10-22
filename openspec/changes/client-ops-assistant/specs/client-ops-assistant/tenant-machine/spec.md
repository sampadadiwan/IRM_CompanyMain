# Spec Delta

## Purpose

Each client with the Ops Assistant gets its own assistant machine: prepared when CapHive switches the
assistant on, started on demand, stopped when idle, holding only that client's working files, and never
holding a CapHive credential.

## ADDED Requirements

### Requirement: One machine per client
Switching the Ops Assistant on for an entity SHALL prepare a machine used only by that entity. No other
entity's questions SHALL ever run on it.

#### Scenario: Prepared on switch-on
- **WHEN** a super user switches the Ops Assistant on for an entity that has no machine
- **THEN** a machine is prepared for that entity and its status becomes Ready (stopped)

#### Scenario: Second entity
- **WHEN** a second entity is switched on
- **THEN** it gets its own machine, and neither machine can read the other's files

### Requirement: Started on demand, stopped when idle
A stopped machine SHALL be started when a question arrives, and the question SHALL then be answered. A
machine with no question or background work for 30 minutes SHALL be stopped.

#### Scenario: Question to a stopped machine
- **WHEN** a user asks a question while their entity's machine is stopped
- **THEN** the page shows "Starting your assistant (about 2 minutes)" and then answers

#### Scenario: Idle stop
- **WHEN** 30 minutes pass with no question and no background work
- **THEN** the machine is stopped

#### Scenario: Background work keeps it running
- **WHEN** background work is still being watched at the 30-minute mark
- **THEN** the machine is not stopped

### Requirement: No CapHive credentials on the machine
The machine SHALL hold no CapHive database credential, application secret or long-lived API token. The
asking user's access SHALL reach it only for the duration of one question and SHALL end when it ends. The
entity's Anthropic key SHALL reach it only for one question and SHALL NOT be written to its disk.

#### Scenario: Token expires with the question
- **WHEN** a question ends (answered, stopped or failed)
- **THEN** the access it used no longer works

### Requirement: The client's working files survive the machine
The assistant's working files and saved history for an entity SHALL be stored outside the machine, in
storage only that entity's machine can reach, so that a stopped or replaced machine continues where it
left off.

#### Scenario: Machine replaced
- **WHEN** an entity's machine is replaced and the user continues an earlier conversation
- **THEN** the assistant still has that conversation's history and files

### Requirement: Switching off stops the machine
Switching the Ops Assistant off for an entity SHALL stop its machine and refuse new questions; the
entity's conversations and learnings SHALL be kept.

#### Scenario: Switched off
- **WHEN** a super user switches the Ops Assistant off
- **THEN** the machine is stopped and the menu item disappears for the entity's users
