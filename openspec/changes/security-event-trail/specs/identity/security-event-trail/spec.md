# Spec Delta

## Purpose

Records every security-relevant moment (sign-ins, two-factor, account changes, role and support-access
changes, credentials and data exports) as an append-only, firm-scoped event, so firms and CapHive can
see, be alerted on, and export who got in and who got power — without ever slowing or blocking the user.

## ADDED Requirements

### Requirement: Sign-in outcomes are recorded for every door
The system SHALL record one event for every successful sign-in and every refused sign-in attempt, naming
the door used (website password, two-factor, email/WhatsApp link, password reset, mobile app, API sign-in,
region switch, mobile hand-off, mail add-in), the account when known, the IP address, the user agent and
the reason for a refusal. A password-correct sign-in that still needs a two-factor code SHALL NOT be
recorded as a success until the code is accepted.

#### Scenario: Wrong password on the website
- **WHEN** a user submits the sign-in form with a wrong password
- **THEN** the user sees the same message as before this change
- **AND** a "sign-in failed" event with reason "invalid" and the request IP is recorded for that user's firm

#### Scenario: Unknown email
- **WHEN** someone submits the sign-in form with an email that belongs to no user
- **THEN** a "sign-in failed" event is recorded with no firm and no account, holding only a one-way digest of the email
- **AND** the event is visible only to CapHive super users

#### Scenario: Two-factor user signs in
- **WHEN** a two-factor user enters a correct password and then a correct code
- **THEN** exactly one "sign-in succeeded" event is recorded, with door "two-factor", after the code is accepted

#### Scenario: Locked account
- **WHEN** a locked user submits a correct password
- **THEN** a "sign-in failed" event with reason "locked" is recorded

#### Scenario: Mobile, API, link, region-switch and add-in sign-ins
- **WHEN** a user signs in through the mobile app, the API sign-in endpoint, an email link, a region switch, a mobile hand-off or a mail add-in
- **THEN** a "sign-in succeeded" or "sign-in failed" event is recorded with that door

#### Scenario: Bearer token refused
- **WHEN** an MCP or mail add-in request carries an invalid token or the token of a deactivated user
- **THEN** a "sign-in failed" event with door "oauth" or "mail add-in" is recorded
- **AND** a request with no token at all records nothing

#### Scenario: Sign-out
- **WHEN** a signed-in user signs out of the website and no CapHive support user was signed in as them
- **THEN** no security event is recorded (a plain sign-out is not recorded; only the end of a support visit is)

### Requirement: Two-factor events are recorded
The system SHALL record a wrong two-factor code, two-factor being switched on or off, a two-factor method
being set, and a two-factor method being reset, naming who did it.

#### Scenario: Wrong code
- **WHEN** a user enters a wrong two-factor code on the website or in the mobile app
- **THEN** a "two-factor code wrong" event with the attempt number is recorded and the user sees the same message as before

#### Scenario: Admin resets a user's method
- **WHEN** a company admin resets another user's two-factor method
- **THEN** a "two-factor method reset" event is recorded with the admin as Done by and the user as Account

#### Scenario: Two-factor switched off
- **WHEN** a user's two-factor flag is turned off by any route
- **THEN** a "two-factor disabled" event is recorded

### Requirement: Account security changes are recorded
The system SHALL record a password change, a password reset request, a phone change, an account lock and
unlock, an account deactivation and reactivation, and a whole-firm deactivation, by whichever route the
change is made. Phone numbers SHALL appear only as their last two digits.

#### Scenario: Locked after too many passwords
- **WHEN** a user's sixth consecutive wrong password locks the account
- **THEN** an "account locked" event with reason "too many passwords" is recorded

#### Scenario: Locked after too many codes
- **WHEN** a user's tenth wrong two-factor code in an hour locks the account
- **THEN** an "account locked" event with reason "too many codes" is recorded

#### Scenario: Password changed
- **WHEN** a user's password changes through the profile, a reset link or the admin console
- **THEN** a "password changed" event is recorded naming who changed it

#### Scenario: Firm deactivated
- **WHEN** CapHive deactivates a whole firm
- **THEN** one "firm deactivated" event is recorded for that firm

### Requirement: Role and support-access changes are recorded and alerted
The system SHALL record every role granted to or removed from a user, by any route, and every change of a
user's "Enable support" switch. When the role is company admin or approver and the user does not hold the
support role, or when the support switch changes, the system SHALL send an email and an in-app
notification to every active company admin of the firm, including the person who made the change.

#### Scenario: Admin grants themselves approver
- **WHEN** a company admin ticks Approver on their own profile and saves
- **THEN** a "role granted" event names them as both Account and Done by
- **AND** every company admin of the firm receives "Approver role given to <name>"

#### Scenario: Employee role granted by import
- **WHEN** a user import grants the employee role
- **THEN** a "role granted" event is recorded and no alert is sent

#### Scenario: Support switch turned on
- **WHEN** a company admin turns on "Enable support"
- **THEN** a "support access enabled" event is recorded and the firm's company admins are alerted

### Requirement: CapHive support access is recorded and alerted
The system SHALL record when a CapHive support user signs in as a client user, when that support session
ends, and when a support user switches into or back out of a client firm, and SHALL alert the client
firm's company admins when support signs in as one of its users or switches into the firm. These support visits
SHALL be announced by in-app notification only, never by email.

#### Scenario: Support signs in as a user
- **WHEN** a support user uses Login as on a client user
- **THEN** a "support signed in as user" event is recorded with the support user as Done by and the client's firm
- **AND** the firm's company admins receive the in-app notification "CapHive support (<support name>) signed in as <user name>"
- **AND** no email is sent about it

#### Scenario: Support session ends
- **WHEN** the support user signs out while signed in as the client user
- **THEN** a "support session ended" event is recorded for the client's firm

### Requirement: Credential and connected-app changes are recorded
The system SHALL record API key creation and revocation, mobile device revocation and a connected app
(OAuth or MCP client) being authorised, naming the key or app but never its secret.

#### Scenario: API key created
- **WHEN** a user creates an API key named "Zapier sync"
- **THEN** an "API key created" event with the name "Zapier sync" is recorded and the token value is stored nowhere in the event

### Requirement: Data exports are recorded
The system SHALL record every spreadsheet download, folder or document bulk download, audit download,
report download and firm data dump, naming what was exported.

#### Scenario: Spreadsheet download
- **WHEN** a user downloads the capital calls list as a spreadsheet
- **THEN** a "data exported" event naming "capital_calls#index (xlsx)" is recorded

### Requirement: Recording never affects the user
Recording SHALL NOT change any message, redirect, status code or outcome of the action that triggered it,
and a failure to record SHALL NOT fail that action. Events SHALL be written outside the request when the
background queue is available and directly otherwise; if both fail the event SHALL be written to the
application log.

#### Scenario: Queue down at sign-in
- **WHEN** the background queue is unavailable and a user signs in
- **THEN** the user is signed in as normal and the event is still saved

#### Scenario: Everything down
- **WHEN** both the background queue and the event write fail
- **THEN** the action still completes and one log line records the event

### Requirement: Events are append-only and never hold secrets
The system SHALL never update or delete an event except by the retention clean-up, and SHALL never store a
password, two-factor code, token, signed link or session id in an event. Events older than 13 months
SHALL be removed automatically.

#### Scenario: Retention
- **WHEN** the nightly clean-up runs
- **THEN** events that occurred more than 13 months ago are removed and newer events are untouched

### Requirement: Security Events screen is firm-scoped
The system SHALL offer a Security Events list to company admins (their own firm's events), CapHive support
users (firms they support with support enabled) and CapHive super users (all events, including those with
no firm), with filters for dates, group, kind, outcome, account and IP, stats cards equal to the filtered
rows, and a spreadsheet download delivered by email. All other users SHALL be refused.

#### Scenario: Company admin sees own firm only
- **WHEN** a company admin of firm A opens Security Events
- **THEN** only firm A's events are listed

#### Scenario: Employee refused
- **WHEN** an employee or investor opens Security Events by URL
- **THEN** they see "You are not authorized to perform this action."

#### Scenario: Download
- **WHEN** a company admin clicks Download
- **THEN** they see "Your request is being processed. You will receive an email shortly." and receive a spreadsheet of the filtered events of their firm only

### Requirement: Weekly review pack
The system SHALL email the address in the region's `SECURITY_EVENTS_WEEKLY_TO` setting (support@caphive.com in
both regions), each Monday at 07:00 local time, a spreadsheet of the previous Monday–Sunday's events across all
firms in that region, with the region named in the subject.

#### Scenario: Monday pack
- **WHEN** the weekly pack runs on Monday 09 Nov 2026
- **THEN** support@caphive.com receives "[IN] Security events 02 Nov – 08 Nov 2026" with events from 02 Nov 00:00 to 08 Nov 23:59 and a "Failed sign-ins by account" sheet

#### Scenario: Setting missing
- **WHEN** the weekly pack runs on a box without `SECURITY_EVENTS_WEEKLY_TO`
- **THEN** no email is sent and a warning is logged
