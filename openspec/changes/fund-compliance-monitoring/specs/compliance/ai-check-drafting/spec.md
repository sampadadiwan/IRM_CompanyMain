# Spec Delta

## Purpose

Lets a compliance editor or CapHive content admin type a rule as a sentence and get an AI-drafted structured check (or manual duty) that they review in plain words with a test run before saving; AI never runs at check time.

## ADDED Requirements

### Requirement: Describe a check in words
"Describe in words" SHALL be available wherever a check can be added, in CapHive packs and entity packs. The sentence MUST be present and at most 1,000 characters.

#### Scenario: Draft from a sentence
- **WHEN** Meera types "No more than 15% of investable funds in any one sector — LPA clause 8.2" and presses Draft check
- **THEN** a draft appears with figure "largest investment cost per sector", divided by "investable funds", limit ≤ 15% and source "LPA cl. 8.2"

#### Scenario: Over-long sentence refused
- **WHEN** a sentence longer than 1,000 characters is submitted
- **THEN** it is refused with "Keep the rule under 1,000 characters"

### Requirement: Plain-words review with mandatory test run
The draft SHALL be shown field by field in plain words, naming any assumption the AI made, and SHALL be test-run on a fund the user picks with the working shown. Save MUST stay disabled until the draft has been tested since the last edit (a preview; nothing is stored); editing any field MUST clear the test run. Nothing is saved until the user presses Save.

#### Scenario: Assumption named
- **WHEN** the sentence says "of the fund" without saying commitments or paid-in
- **THEN** the draft shows "Assumed: commitments" as an editable line

#### Scenario: Save disabled until test run
- **WHEN** a draft has not been test-run
- **THEN** Save check is disabled

#### Scenario: Edit clears the test run
- **WHEN** the user edits the limit of a tested draft
- **THEN** the test run is cleared and Save is disabled until it is re-run

#### Scenario: Cancel saves nothing
- **WHEN** the user drafts and then cancels
- **THEN** no check is saved

### Requirement: Unexpressible rules become manual duties
When a sentence needs data CapHive does not hold, the draft SHALL be a manual duty and SHALL say why.

#### Scenario: Key-person rule drafted as a duty
- **WHEN** Meera types "Key-person event must be notified to LPs within 30 days"
- **THEN** the draft is an on-demand manual duty "Key-person event notified", evidence required, with "CapHive does not record key-person events"

### Requirement: Drafts validated like form input
An AI draft SHALL be validated exactly like a form-built check and MUST consist only of the check's structured fields, never formula code. A draft naming an unknown field MUST be refused like a form entry.

#### Scenario: Draft with an unknown field refused
- **WHEN** the AI draft names a field CapHive does not hold
- **THEN** the draft shows "Unknown field: <name>" and cannot be saved until the field is changed

### Requirement: Provenance of AI-drafted checks
A saved check drafted with AI SHALL record that it was drafted with AI, the original sentence, and who confirmed it and when.

#### Scenario: Provenance shown on the check
- **WHEN** Meera saves an AI-drafted check
- **THEN** the check shows "Drafted with AI from: '<sentence>' · confirmed by Meera, <date>"

### Requirement: AI unavailable
If the entity's AI-drafting switch is off, the form SHALL still work and "Describe in words" SHALL show "Describe in words is unavailable — use the form". If the AI provider errors or times out while drafting, the system SHALL show "Drafting failed — try again or use the form" and MUST save nothing.

#### Scenario: AI not configured
- **WHEN** the entity's AI-drafting switch is off and a user opens Describe in words
- **THEN** the message is shown and the form remains usable

#### Scenario: AI provider error while drafting
- **WHEN** the switch is on and the AI provider errors or times out while drafting
- **THEN** "Drafting failed — try again or use the form" is shown and nothing is saved

### Requirement: AI context and run-time isolation
The drafting request SHALL send only the sentence, the names of fields and figures CapHive can check, the entity's input names and examples from the requesting entity's own checks; it MUST NOT send investor records or another entity's data. The test run SHALL happen inside CapHive. No nightly or on-demand run SHALL call AI.

#### Scenario: No investor data sent
- **WHEN** a draft is requested
- **THEN** the request contains no investor names, amounts or documents

#### Scenario: Examples only from own entity
- **WHEN** Horizon drafts a check
- **THEN** example checks shown to the AI come only from Horizon's packs and CapHive packs

#### Scenario: Runs never call AI
- **WHEN** the nightly run evaluates an AI-drafted check
- **THEN** the result is computed without any AI call and is identical on two runs over the same data
