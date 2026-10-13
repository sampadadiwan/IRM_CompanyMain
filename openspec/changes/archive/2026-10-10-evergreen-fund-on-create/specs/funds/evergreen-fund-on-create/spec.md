# Spec Delta

## Purpose

Lets a fund admin choose closed-end or open-ended when creating a fund, creates an open-ended fund
together with its evergreen terms in one flow, and keeps a fund's type fixed afterwards.

## ADDED Requirements

### Requirement: Fund type chosen on New Fund
The system SHALL show a Fund type choice (Closed-end / Open-ended, default Closed-end) at the top of
the New Fund wizard only when the company has evergreen funds and units switched on. Closed-end SHALL
create the fund exactly as before.

#### Scenario: Company with evergreen on
- **WHEN** a fund admin of a company with evergreen funds and units switched on opens New Fund
- **THEN** step 1 shows Fund type with Closed-end selected

#### Scenario: Company without evergreen
- **WHEN** a fund admin of a company without evergreen funds opens New Fund
- **THEN** no Fund type choice is shown, and a sent value is ignored (the fund is closed-end)

#### Scenario: Closed-end
- **WHEN** a fund admin saves New Fund with Fund type Closed-end
- **THEN** the fund is created as before with "Fund was successfully created."

### Requirement: An open-ended fund is created complete
With Fund type Open-ended, the system SHALL continue the New Fund wizard into the evergreen steps,
build one class card per unit type entered, and on Create fund SHALL save the fund and its evergreen
terms together, or nothing at all.

#### Scenario: Create an open-ended fund
- **WHEN** a fund admin chooses Open-ended, enters unit types "A, B", picks a preset, sets starting prices for A and B and clicks Create fund
- **THEN** the fund exists, is evergreen with those terms, and its page shows "Alpha Long-Short Fund created as an open-ended fund"

#### Scenario: Class cards follow the unit types
- **WHEN** the unit types are changed from "A, B" to "A"
- **THEN** the Classes step shows one card, for Class A

#### Scenario: Invalid evergreen term
- **WHEN** Create fund is clicked with Class B's starting price blank
- **THEN** no fund is saved, the wizard shows "Class B needs a starting price" and every entered value is kept

#### Scenario: No unit types
- **WHEN** Create fund is clicked with Open-ended chosen and Unit Types blank
- **THEN** no fund is saved and step 1 shows "Add at least one unit class for an open-ended fund"

### Requirement: A fund's type cannot be switched
The system SHALL NOT offer or perform a change of a fund's type after creation: no way to make an
existing fund evergreen, and no way to make an evergreen fund closed-end. The edit form SHALL show
the type read-only.

#### Scenario: Existing closed-end fund
- **WHEN** a fund admin opens an existing closed-end fund
- **THEN** the Actions menu has no "Make this fund evergreen", and a direct request to make it evergreen is refused with "A fund's type is chosen when it is created and can't be changed"

#### Scenario: Evergreen fund
- **WHEN** a fund admin opens Evergreen Settings of an evergreen fund
- **THEN** there is no "Make closed-end again", and a direct request to switch it back is refused with the same message

#### Scenario: Edit form
- **WHEN** a fund admin edits a fund
- **THEN** Fund type is shown as read-only text
