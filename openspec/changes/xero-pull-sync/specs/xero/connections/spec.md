# Spec Delta

## Purpose

Lets a fund or a portfolio company be linked to exactly one Xero organisation with read-only
access, and keeps that link's health visible so a broken connection is never mistaken for an
absence of data.

## ADDED Requirements

### Requirement: Feature gated per entity
The system SHALL show Xero connection controls and run Xero syncs only for entities that have
the Xero feature switched on.

#### Scenario: Feature off
- **WHEN** a fund admin of an entity without the Xero feature opens a fund
- **THEN** no Xero tab is shown and no Xero sync runs for that entity's funds or portfolio companies

#### Scenario: Feature on
- **WHEN** a fund admin of an entity with the Xero feature opens a fund
- **THEN** a Xero tab is shown with status "Not connected" and a Connect Xero action

### Requirement: Connect through Xero consent
The system SHALL connect a fund or portfolio company by sending the user to Xero's consent
screen requesting read-only access, and on return SHALL store the chosen organisation's
identity and base currency. Where the consent covers more than one organisation, the user
SHALL choose one.

#### Scenario: Single organisation
- **WHEN** a fund admin completes Xero consent covering one organisation
- **THEN** the fund shows that organisation's name and currency with status "Connected"

#### Scenario: Several organisations
- **WHEN** the consent covers three organisations
- **THEN** the user is asked to pick one, and only the picked one is connected

#### Scenario: Consent cancelled
- **WHEN** the user cancels on Xero's consent screen
- **THEN** the user returns to the same page with the message "Xero connection was cancelled." and nothing is connected

### Requirement: Fund organisation must match the fund
The system SHALL refuse to connect a fund to an organisation whose base currency differs from
the fund currency, or to an organisation already connected to another fund of the same
entity.

#### Scenario: Currency mismatch
- **WHEN** a fund in AUD is connected to an organisation reporting in USD
- **THEN** the connection is refused with a message naming both currencies

#### Scenario: Organisation already used by another fund
- **WHEN** an organisation already connected to Beta Fund is chosen for Alpha Fund in the same entity
- **THEN** the connection is refused with the message "This Xero organisation is already connected to Beta Fund."

### Requirement: No switching organisation in place
The system SHALL refuse a reconnect that picks a different organisation from the one the fund
or company is connected to; the user MUST disconnect first.

#### Scenario: Reconnect to a different organisation
- **WHEN** a fund connected to organisation A is reconnected and organisation B is chosen
- **THEN** the reconnect is refused with "Disconnect first. Reconnecting to a different organisation is not supported." and the fund stays linked to A

#### Scenario: Reconnect to the same organisation
- **WHEN** a fund whose connection needs reconnecting is reconnected to the same organisation
- **THEN** the status returns to "Connected" and existing account mappings are kept

### Requirement: Connection health is surfaced
The system SHALL mark a connection "Needs reconnecting" when Xero rejects its authorisation,
and "Sync failing" when temporary failures persist for 24 hours. Each transition SHALL notify
the user who connected it and the entity's fund admins once. A connection in either state
SHALL show a Reconnect action. Temporary failures shorter than 24 hours SHALL be retried
without notification.

#### Scenario: Authorisation expired or withdrawn
- **WHEN** a nightly sync is rejected by Xero as unauthorised
- **THEN** the status becomes "Needs reconnecting", one notification is sent, and further syncs for that connection stop until reconnected

#### Scenario: Temporary failure recovers
- **WHEN** a sync fails because Xero is unavailable and succeeds on retry the same night
- **THEN** no notification is sent and the status stays "Connected"

#### Scenario: Temporary failure persists
- **WHEN** syncs for a connection have failed with temporary errors for 24 hours
- **THEN** the status becomes "Sync failing" and one notification is sent

### Requirement: Disconnect
The system SHALL let an authorised user disconnect, which stops syncing and withdraws
CapHive's access at Xero. Previously imported account entries and KPIs SHALL remain.

#### Scenario: Disconnect a fund
- **WHEN** a fund admin disconnects a fund's Xero connection
- **THEN** the status shows "Not connected", no further syncs run, and entries imported earlier are unchanged

### Requirement: Access control
The system SHALL allow only users who can update the fund to connect, sync, map or disconnect
a fund's Xero; only users with KPI access to the portfolio company, or users of the
portfolio company's own entity from a report open to them, to connect a portfolio company.
All Xero data SHALL be scoped to the owning entity.

#### Scenario: Investor user
- **WHEN** an investor-side user opens a fund
- **THEN** no Xero tab or action is available

#### Scenario: Founder connects from a pending report
- **WHEN** a portfolio company user opens a pending KPI report shared with them and chooses "Connect Xero instead of uploading"
- **THEN** the company's Xero is connected for the fund entity that owns the report

#### Scenario: Other entity
- **WHEN** a user of another entity requests a Xero connection page for this fund
- **THEN** access is denied
