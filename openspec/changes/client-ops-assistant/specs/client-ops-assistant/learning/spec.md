# Spec Delta

## Purpose

How the Ops Assistant adapts to one client: everything it knows is kept as documents in one Ops Assistant
folder under the client's Documents root; it proposes learnings and skills, a company admin confirms or
discards them, and only confirmed ones are used — never across clients.

## ADDED Requirements

### Requirement: One Ops Assistant folder per client holds its knowledge
Each entity with the Ops Assistant SHALL have one private Ops Assistant folder under its Documents root,
with the sub-folders Skills, Learnings, Proposed and Reports. Skills, learnings, proposals and task
reports SHALL be kept there as documents, readable, editable and downloadable like any other document by
those allowed to see the folder.

#### Scenario: Folder created on switch-on
- **WHEN** a super user switches the Ops Assistant on for an entity
- **THEN** Documents › Ops Assistant exists with Skills, Learnings, Proposed and Reports, and investors cannot see it

#### Scenario: Admin writes a skill
- **WHEN** a company admin uploads "Raise a capital call.md" into Ops Assistant › Skills
- **THEN** the assistant follows it in the next conversation

#### Scenario: Task report kept
- **WHEN** an approved task completes
- **THEN** a report of its steps, checks and results is saved in Ops Assistant › Reports

### Requirement: Learnings are proposed, not adopted
The assistant SHALL be able to propose a learning (a fact about how this client works) or a playbook (the
steps of a recurring job) from a conversation. A proposal SHALL be pending until a company admin of the
entity confirms or discards it.

#### Scenario: Proposed learning
- **WHEN** the assistant proposes "Bank statements put the folio after FOLIO- in the narration"
- **THEN** a document is saved in Ops Assistant › Proposed and appears under What I've learned, showing the conversation it came from

### Requirement: Only confirmed learnings are used
Only the documents in the Skills and Learnings folders SHALL be given to the assistant in later
conversations of that entity. Confirming SHALL move a proposal into Skills or Learnings; discarding SHALL
delete it. Proposals SHALL NOT be used.

#### Scenario: Confirmed learning used
- **WHEN** a company admin confirms a learning and a user then starts a new conversation
- **THEN** the assistant applies it, and the answer names it when it relied on it

#### Scenario: Discarded learning not used
- **WHEN** a learning is discarded
- **THEN** no later conversation uses it

### Requirement: Admins control what is remembered
Only a company admin of the entity SHALL confirm, discard or remove learnings. Removing a confirmed
learning SHALL stop its use from the next question on.

#### Scenario: Employee cannot confirm
- **WHEN** an employee without the company admin role tries to confirm a learning
- **THEN** it is refused and the learning stays pending

### Requirement: Learnings never cross clients
A learning SHALL belong to one entity and SHALL never be visible to or used for another entity.

#### Scenario: Other client
- **WHEN** another entity's assistant answers a question
- **THEN** none of this entity's learnings are given to it
