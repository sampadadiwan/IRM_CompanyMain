# Spec Delta

## Purpose

Defines the rules a new capital call must satisfy before it is created, so that a call is never
created when no investor commitment applies to it.

## ADDED Requirements

### Requirement: A new capital call requires at least one applicable commitment
When a capital call is created, the system SHALL refuse it unless at least one capital commitment
in the call's fund applies to the call. A commitment applies when the call's fund closes include
"All", when the call names no fund closes, or when the commitment's fund close is one of the call's
fund closes. The rule SHALL apply to every call basis, including "Upload". Any commitment counts,
whatever its committed amount.

A refused call SHALL NOT be saved, and no remittances SHALL be created for it. The refusal SHALL
carry the message "No commitments in this fund apply to this call. Add commitments for the selected
fund closes before creating a capital call."

#### Scenario: Fund with no commitments
- **WHEN** a user creates a capital call on a fund that has no capital commitments
- **THEN** the call is not saved
- **AND** the user sees the message "No commitments in this fund apply to this call. Add commitments for the selected fund closes before creating a capital call."

#### Scenario: Selected fund close has no commitments
- **WHEN** a fund has commitments only in "First Close"
- **AND** a user creates a capital call whose fund closes are "Second Close"
- **THEN** the call is not saved
- **AND** the user sees the same message

#### Scenario: One of several selected closes has commitments
- **WHEN** a fund has commitments only in "First Close"
- **AND** a user creates a capital call whose fund closes are "First Close" and "Second Close"
- **THEN** the call is saved
- **AND** remittances are created only for the "First Close" commitments

#### Scenario: Call for all closes on a fund with commitments
- **WHEN** a fund has at least one commitment
- **AND** a user creates a capital call whose fund closes are "All"
- **THEN** the call is saved and its remittances are created as before this change

#### Scenario: Upload-basis call on a fund with no commitments
- **WHEN** a user creates a capital call with call basis "Upload" on a fund that has no capital commitments
- **THEN** the call is not saved
- **AND** the user sees the same message

#### Scenario: Upload-basis call on a fund with commitments
- **WHEN** a user creates a capital call with call basis "Upload" on a fund that has at least one commitment
- **THEN** the call is saved

### Requirement: The rule is enforced on every way of creating a call
The system SHALL apply the applicable-commitment rule when a call is created from the New Capital
Call form, from the capital call JSON create endpoint, and from a capital call import. On the form,
the user SHALL stay on the form with their entered values, and the message SHALL appear in the
form's error list. The JSON endpoint SHALL respond with status 422 and the message. In an import,
only the affected row SHALL fail, with the message in the import's error report; other rows SHALL be
processed as before.

#### Scenario: Form keeps the user's input
- **WHEN** a user submits the New Capital Call form for a fund with no applicable commitments
- **THEN** the form is shown again with the values the user entered
- **AND** the form's error list contains the message

#### Scenario: JSON create is refused
- **WHEN** a client creates a capital call through the JSON endpoint for a fund with no applicable commitments
- **THEN** the response status is 422
- **AND** the response body contains the message

#### Scenario: Import row fails and others continue
- **WHEN** a capital call import contains one row whose fund closes have no commitments and one row whose fund closes have commitments
- **THEN** the first row fails with the message in the import's error report
- **AND** the call in the second row is created

### Requirement: The rule applies only when a call is created
The system SHALL NOT apply the applicable-commitment rule when an existing capital call is edited, and
SHALL NOT change or remove existing calls that have no applicable commitments.

#### Scenario: Editing an existing call is unaffected
- **WHEN** a user edits an existing capital call and changes its fund closes to a close that has no commitments
- **THEN** the edit is saved as before this change
