# Spec Delta

## MODIFIED Requirements

### Requirement: Acknowledge steps
An `acknowledge` step SHALL pass when a user allowed to update the record confirms it and its check, if
any, passes. A confirmation made before the step was last invalidated SHALL NOT count. An acknowledge
step's check MAY instead report that the record's own data already confirms the step; the step SHALL then
pass without a confirmation, showing the check's message, provided that evidence is newer than the step's
last invalidation. An acknowledge step's check MAY also explicitly ask for review with its own message and
action; while the step is current, that message SHALL be shown in place of "Not confirmed yet" and that
action SHALL be offered next to "Mark reviewed". A check that does neither SHALL behave exactly as before.

#### Scenario: Confirming a step
- **WHEN** a user with update rights clicks "Mark reviewed" on the current acknowledge step
- **THEN** the confirmation is recorded with user and time, and the journey moves on

#### Scenario: Confirmation invalidated by later change
- **WHEN** an undoing action invalidates the step after the confirmation, e.g. the call email template is edited
- **THEN** the step is no longer passed, the confirmation is cleared and the reason shows, e.g. "Email template changed after review"

#### Scenario: Read-only user cannot confirm
- **WHEN** a user without update rights views the current acknowledge step
- **THEN** no "Mark reviewed" button is shown and a direct request to confirm is refused

#### Scenario: Data confirms the step
- **WHEN** a KYC's AI document validation passed every answer and its "Validate documents" step is reached
- **THEN** the step passes as "Validated by AI" with no confirmation, and history records it as passed by the system

#### Scenario: Data confirmation older than an invalidation
- **WHEN** a document is replaced after the AI validation passed, invalidating the step
- **THEN** the step is current again until a newer AI validation passes or a user confirms it

#### Scenario: Check message shown while waiting
- **WHEN** an acknowledge step is current and its check says "AI could not validate 2 of 12 answers — check them and mark reviewed"
- **THEN** the panel shows that message with "Mark reviewed" and the check's "Open validation" action

#### Scenario: Existing acknowledge steps unchanged
- **WHEN** a capital call's "Review email" step is current
- **THEN** it behaves exactly as before: "Mark reviewed" is required, the message is "Not confirmed yet" and no second button is shown

## ADDED Requirements

### Requirement: Closing step
A `system` step's check MAY be declared closing. When a closing step's check passes, every earlier step
that is neither passed nor not applicable SHALL be shown as not applicable with the closing check's reason
(e.g. "Verified without this step"), so the journey can complete. Steps already passed SHALL keep their
status, and no confirmation or vote SHALL be cleared by closing. When the closing check stops passing, the
steps SHALL be evaluated normally again.

#### Scenario: Verified before earlier tasks
- **WHEN** a KYC is verified while "Upload required documents" and "Run AML screening" are not done
- **THEN** both show "–" "Verified without this step", passed tasks keep ✓, and the journey is complete

#### Scenario: Closing check fails again
- **WHEN** the same KYC is unverified
- **THEN** "Upload required documents" is current again and the move back is recorded

#### Scenario: Journeys without a closing check
- **WHEN** a capital call or distribution journey is evaluated
- **THEN** no step is closed and the walk is exactly as before
