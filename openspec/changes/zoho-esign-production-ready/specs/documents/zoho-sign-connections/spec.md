# Spec Delta

## Purpose

Lets a company whose eSign provider is Zoho connect its own Zoho Sign account, in any Zoho region, and
decides which Zoho account (the company's own or CapHive's platform account) each document uses.

## ADDED Requirements

### Requirement: Zoho eSign panel visibility and access
The system SHALL show a Zoho eSign panel on the company page only when the company's eSign provider is
Zoho. Only that company's company admins (who are not investor advisors) and CapHive support SHALL be
able to view the panel or connect, verify, reconnect, regenerate the webhook secret or disconnect. Any
other user SHALL be refused and nothing SHALL change. A connection SHALL belong to exactly one company,
and a company SHALL have at most one connection.

#### Scenario: Panel shown to a company admin on a Zoho company
- **WHEN** a company admin of a company whose eSign provider is Zoho opens the company page
- **THEN** the Zoho eSign panel is shown

#### Scenario: Panel hidden when the provider is not Zoho
- **WHEN** a company admin of a company whose eSign provider is Digio opens the company page
- **THEN** no Zoho eSign panel is shown

#### Scenario: Non-admin cannot connect
- **WHEN** a user who is not a company admin of the company submits a connect request for it
- **THEN** the request is refused and no connection is created

#### Scenario: Admin of another company cannot touch the connection
- **WHEN** a company admin of company B tries to view, reconnect or disconnect company A's connection
- **THEN** the request is refused and company A's connection is unchanged

### Requirement: Supported Zoho regions
The system SHALL offer exactly these Zoho regions: United States, Europe, India, Japan, Australia,
Canada, Saudi Arabia, United Kingdom, Singapore and UAE. Each region SHALL map to one fixed Zoho
accounts address and one fixed Zoho Sign address (for example United States: `accounts.zoho.com` and
`sign.zoho.com`; Japan: `accounts.zoho.jp` and `sign.zoho.jp`), and the system SHALL call only those
addresses for a connection in that region. A region outside the list SHALL be refused. Users SHALL NOT
be able to enter a free-form Zoho address.

#### Scenario: Region outside the list refused
- **WHEN** a connect request names a region that is not in the list
- **THEN** it is refused with "Pick a Zoho region" and nothing is saved

#### Scenario: Calls go to the chosen region
- **WHEN** a company connected in the Japan region sends a document
- **THEN** every Zoho call for that document goes to `accounts.zoho.jp` or `sign.zoho.jp`

### Requirement: Connect with a Zoho Self Client
The system SHALL connect an account from a region, Client ID, Client Secret and Zoho grant code. It SHALL
exchange the grant code with Zoho in the chosen region immediately. On success it SHALL store the
connection as Connected and record the moment of connection ("connected on"). On failure it SHALL save
nothing and SHALL show a message naming the likely cause: an expired or already used grant code, a
Client ID not known in that region, or a wrong Client Secret. The grant code SHALL NOT be stored.

#### Scenario: Successful connection
- **WHEN** a company admin submits region United States, a valid Client ID, Client Secret and an unused grant code
- **THEN** the connection is Connected, "Connected on" shows the current date and time, and the panel says documents sent from now on use the company's Zoho account

#### Scenario: Expired grant code
- **WHEN** Zoho rejects the grant code as invalid or expired
- **THEN** no connection is saved and the message says the grant code may have expired or already been used and to generate a new one

#### Scenario: Wrong region
- **WHEN** Zoho in the chosen region does not recognise the Client ID
- **THEN** no connection is saved and the message asks the user to check the region matches their Zoho account's address

#### Scenario: Missing fields
- **WHEN** the region, Client ID, Client Secret or grant code is blank on connect
- **THEN** nothing is saved and each blank field is marked as required

### Requirement: Secrets are protected
The system SHALL store the Client Secret, refresh and access tokens and webhook secret encrypted. It
SHALL NOT display the Client Secret, tokens or grant code after submission, and SHALL NOT write them to
logs or to the eSign log. The webhook secret SHALL be displayable once after it is generated; afterwards
it SHALL only be replaceable.

#### Scenario: Secret not shown again
- **WHEN** a company admin opens the panel after connecting
- **THEN** the Client Secret is not shown and the webhook secret is masked unless it has not been revealed yet

#### Scenario: Secrets kept out of logs
- **WHEN** a connect request is submitted
- **THEN** the request log shows the Client Secret and grant code as filtered

### Requirement: Which account a document uses (cutover)
For every Zoho action on a document (send, status check, reminder, extension, cancel, download of the
signed copy or certificate, live update), the system SHALL use the company's own connection when the
company has one and the document was sent at or after the connection's "connected on" moment. Otherwise
it SHALL use CapHive's platform Zoho account. A document not yet sent SHALL use the account that would be
chosen if it were sent now.

#### Scenario: Not connected
- **WHEN** a company without a connection sends a document
- **THEN** it is sent through CapHive's platform Zoho account

#### Scenario: Sent after connecting
- **WHEN** a company connected on 29 Oct 2026 11:42 sends a document on 29 Oct 2026 at 12:00
- **THEN** it is sent through the company's own Zoho account

#### Scenario: Sent before connecting
- **WHEN** a document sent on 28 Oct 2026 through CapHive's account is checked for updates after the company connected on 29 Oct 2026
- **THEN** the check uses CapHive's platform Zoho account and the document updates normally

### Requirement: Verify connection
The system SHALL offer "Verify connection", which makes one read-only call to Zoho with the stored
credentials and reports the result. A successful check SHALL leave or set the connection Connected; a
credential rejection SHALL set it to Needs reconnect.

#### Scenario: Verification succeeds
- **WHEN** a company admin clicks Verify connection and Zoho accepts the credentials
- **THEN** the panel shows "Connection verified" and the status Connected

#### Scenario: Verification fails on credentials
- **WHEN** Zoho rejects the stored credentials during verification
- **THEN** the status becomes Needs reconnect and the panel says to reconnect

### Requirement: Connection health and Needs reconnect
When Zoho rejects a connection's stored credentials during any call, the system SHALL set the connection
to Needs reconnect and SHALL email the company's company admins once per transition, not once per
document or call. While a connection needs reconnecting, sending a document that would use it SHALL be
refused with "<Company>'s Zoho account needs to be reconnected. Ask a company admin to reconnect it on
the company page." Status checks for documents on that connection SHALL leave the documents unchanged
(they SHALL NOT be marked Failed).

#### Scenario: Credentials revoked
- **WHEN** Zoho rejects the company's credentials while a status check runs for three documents
- **THEN** the connection becomes Needs reconnect, the company admins receive one email, and the three documents keep their statuses

#### Scenario: Sending blocked while reconnect is needed
- **WHEN** a user sends a document that would use a connection in Needs reconnect
- **THEN** the send is refused with the reconnect message and nothing is sent to Zoho

### Requirement: Reconnect keeps the cutover
The system SHALL let a company admin reconnect by submitting a new grant code (and optionally a new
region, Client ID or Client Secret; a blank Client Secret keeps the stored one). On success the
credentials SHALL be replaced, the status SHALL become Connected, and "connected on" SHALL stay
unchanged. On failure the existing connection SHALL be left as it was.

#### Scenario: Reconnect after revocation
- **WHEN** a company admin reconnects a Needs reconnect connection with a fresh grant code
- **THEN** the status is Connected, "connected on" is the original date, and documents already sent on the account update again

#### Scenario: Failed reconnect changes nothing
- **WHEN** a reconnect is attempted with an expired grant code
- **THEN** the stored credentials and status are unchanged and the expired-code message is shown

### Requirement: Disconnect
The system SHALL let a company admin disconnect after confirming, only when no document is out for
signature on that connection (sent at or after "connected on" and not Completed, Expired, Cancelled or
Failed). Otherwise it SHALL refuse with "<N> documents are still out for signature on this account. Wait
for them to finish or cancel them first." After disconnecting, new documents SHALL use CapHive's platform
account.

#### Scenario: Disconnect refused with documents out
- **WHEN** a company admin disconnects while 3 documents sent on the company's account are In progress
- **THEN** the connection stays and the message says 3 documents are still out for signature

#### Scenario: Disconnect allowed
- **WHEN** a company admin disconnects and no documents are out for signature on the account
- **THEN** the connection is removed and the next document is sent through CapHive's platform account

### Requirement: Company webhook address and secret
Each connection SHALL have its own webhook address containing an unguessable token, and its own webhook
secret generated by the system. The panel SHALL show the address, reveal the secret once, and offer
"Regenerate webhook secret", which after confirmation SHALL replace the secret so that updates signed
with the old one are refused. The panel SHALL show when the last accepted update arrived.

#### Scenario: Secret revealed once
- **WHEN** a company admin clicks Show webhook secret for the first time
- **THEN** the secret is shown, and on the next visit only Regenerate is offered

#### Scenario: Regenerated secret invalidates the old one
- **WHEN** the secret is regenerated and Zoho then sends an update signed with the old secret
- **THEN** the update is refused
