# Spec Delta

## Purpose

Gives the CapHive LP mobile app a secure, versioned data service. Phones sign in with the same
two-factor rules as the website, every phone holds its own revocable session, and every read is
limited to exactly what the signed-in investor can see on the website.

## ADDED Requirements

### Requirement: Phone sign-in enforces two-factor
The system SHALL let a phone sign in with email and password. It SHALL apply the website's
password check, account lockout and deactivation rules. When the user has two-factor enabled, the
system SHALL NOT issue a session until a valid one-time code for the user's configured method has
been verified. It SHALL return a short-lived, single-use challenge reference in place of a
session. The challenge SHALL expire after 10 minutes and SHALL allow at most 3 code attempts — the
website's rule — after which the challenge ends and the user must sign in again with their
password. A user with two-factor enabled SHALL NOT be able to obtain an API token from any other
token endpoint without verifying a code.

#### Scenario: User without two-factor signs in
- **WHEN** a user with no two-factor method signs in from a phone with the correct password
- **THEN** the system returns a phone session and registers the device

#### Scenario: User with two-factor must enter a code
- **WHEN** a user with authenticator two-factor signs in with the correct password
- **THEN** the system returns a challenge reference and no session
- **AND** a session is returned only after a valid authenticator code is submitted against that challenge

#### Scenario: Wrong code too many times
- **WHEN** three invalid codes are submitted against one challenge
- **THEN** the challenge is spent and the phone shows "Too many failed attempts. Please sign in again."

#### Scenario: Wrong password
- **WHEN** a phone sign-in uses an incorrect password
- **THEN** the system answers "Incorrect email or password" and counts the failure toward lockout

### Requirement: Only investor personas may use the phone service
The system SHALL issue phone sessions only to users who hold the investor role, the investor
advisor role or a family-office investor persona. Any other user SHALL be refused with "This app is
for investors. Please use the CapHive website."

#### Scenario: GP employee refused
- **WHEN** a fund-manager employee with no investor access signs in from a phone
- **THEN** the system refuses and no session or device is created

### Requirement: Each phone holds its own revocable session
The system SHALL bind every phone session to a device record holding the platform, device name,
app version, region and last-used time. A session SHALL expire 90 days after its last use. The
system SHALL end every phone session of a user when that user's password changes or the user is
deactivated. The system SHALL end a single phone's session when that device is signed out from the
app or from the website. A user SHALL hold at most 10 active devices. Signing in on another phone
SHALL end the least recently used one. Every request made with an ended session SHALL be refused
with an "unauthorised" answer.

#### Scenario: Device signed out from the website
- **WHEN** the user signs out "iPhone 15" from the website's Devices page
- **THEN** the next request from that phone is refused as unauthorised

#### Scenario: Password change ends phone sessions
- **WHEN** the user changes their password on the website
- **THEN** every phone session of that user is refused on its next request

#### Scenario: Eleventh device
- **WHEN** a user with 10 active devices signs in on another phone
- **THEN** the least recently used device's session ends and the new phone is registered

#### Scenario: Website API token cannot reach the phone service
- **WHEN** a request to the phone service carries a website API token that is not bound to a phone device
- **THEN** the system refuses it as unauthorised

#### Scenario: Two-factor user cannot mint a token without a code
- **WHEN** a user with two-factor enabled asks the website's token endpoint for a token with the correct password
- **THEN** the system refuses with "two_factor_required" and issues no token

### Requirement: Phone data matches website visibility
Every list and detail the phone service returns (funds and commitments, capital calls,
distributions, documents and notifications) SHALL be limited by the same access rules the website
applies to the signed-in user in their current investor persona. Where the website already has a
JSON endpoint for the data (commitments, capital calls, distribution payments, documents,
notifications) the app SHALL use it with its phone token rather than a duplicate endpoint. A record
the website would not show the user SHALL be refused ("not found" on the mobile endpoints, "access
denied" on the website's own endpoints). Monetary figures SHALL be the values the website's
LP fund card shows (committed, called, distributed, due) and SHALL NOT be recalculated. Lists
SHALL be paginated at no more than 25 items per page.

#### Scenario: Another investor's capital call
- **WHEN** an LP requests a capital call belonging to an investor they have no access to
- **THEN** the system refuses the request

#### Scenario: Figures match the website card
- **WHEN** an LP with ₹5,00,00,000 committed, ₹2,00,00,000 called, ₹1,25,00,000 collected and ₹30,00,000 distributed opens Home
- **THEN** the fund shows committed ₹5,00,00,000, called ₹2,00,00,000, due ₹75,00,000 and distributed ₹30,00,000

#### Scenario: NDA-gated documents stay hidden
- **WHEN** an LP lists documents in the app
- **THEN** only documents attached to their own commitments, capital calls and distribution payments are returned, and data-room documents (browsed on the website behind its NDA gate) are not

### Requirement: Investor advisors switch persona
The system SHALL let an investor advisor list the investors they advise and switch to one of them,
following the same authorisation as the website's advisor switch. After a switch, every read SHALL
reflect the chosen investor.

#### Scenario: Advisor switches investor
- **WHEN** an advisor to "Sharma Family Office" switches to it
- **THEN** Home lists Sharma Family Office's funds and no others

### Requirement: To-do list
The system SHALL return a to-do list holding only unpaid capital calls (earliest due date first) and
documents where the signed-in user is a pending signatory.

#### Scenario: Paid call drops off
- **WHEN** a capital call becomes fully paid
- **THEN** it no longer appears in the to-do list

### Requirement: Viewing a document is recorded
Opening a document through the phone service SHALL record that the user viewed it, as the website
does.

#### Scenario: View recorded
- **WHEN** an LP opens a quarterly statement in the app
- **THEN** the document's "viewed by" list includes that LP

### Requirement: Website hand-off for screens the app does not have
The system SHALL issue, for a signed-in phone session, a single-use web hand-off link that expires
after 5 minutes. When opened, it establishes a website session for the same user and lands on the
requested website path. The path SHALL be on the same site. A spent, expired or tampered link SHALL
land on the website sign-in page.

#### Scenario: Approval opens on the website
- **WHEN** the LP taps an approval notification
- **THEN** the in-app browser opens the website's approval page already signed in as that LP

#### Scenario: Link reused
- **WHEN** a hand-off link is opened a second time
- **THEN** the website sign-in page is shown

### Requirement: Minimum supported app version
The system SHALL refuse requests from an app version older than the configured minimum with an
"update required" answer that the app can recognise.

#### Scenario: Old app
- **WHEN** an app below the minimum version makes any request
- **THEN** the system answers "update required"
