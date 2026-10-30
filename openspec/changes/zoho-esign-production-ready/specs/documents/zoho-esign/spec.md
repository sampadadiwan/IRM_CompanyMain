# Spec Delta

## Purpose

Defines how documents are sent for signature through Zoho Sign and tracked to completion: sending,
deadlines and reminders, cancelling, live updates from Zoho, status rules and the signed outputs.

## ADDED Requirements

### Requirement: Sending a document through Zoho
When a document of a company whose eSign provider is Zoho is sent for eSignature, the system SHALL create
one Zoho request on the account chosen by the cutover rule, with one signature box per signer on the
page(s) chosen by the document's "display on page" setting (first, last or all pages), signers in the
document's signer order, and sequential signing when the document forces signing order. On success the
document SHALL be marked sent, with status Requested, the Zoho request reference, the send time and an
expiry date of send time plus the expiry days. The sender SHALL be told "Document - <name> sent for
eSigning".

#### Scenario: Successful send
- **WHEN** a user sends a document with two signers, expiry 30 days, on 29 Oct 2026
- **THEN** the document status is Requested, it shows "eSignature Expires On 28/11/2026", and Zoho receives a request with two signers

#### Scenario: Signature boxes on every page
- **WHEN** a three-page document with "display on page" set to All is sent to two signers
- **THEN** each signer gets a signature box on each of the three pages and the boxes of the two signers do not overlap

#### Scenario: Forced signing order
- **WHEN** a document with forced signing order is sent to two signers
- **THEN** the Zoho request is sequential with the signers in the document's order

### Requirement: Expiry and reminder settings
For Zoho companies a document SHALL carry an expiry of 1 to 99 days (default 90 when blank), automatic
reminders on or off (default on), and a reminder period of 1 to 30 days (default 4 when blank). These
values SHALL be sent to Zoho with the request. Values outside the ranges SHALL be refused when the
document is saved.

#### Scenario: Configured values sent
- **WHEN** a document with expiry 30 days, reminders on and reminder period 7 days is sent
- **THEN** the Zoho request has expiration 30 days, email reminders on and a reminder period of 7 days

#### Scenario: Defaults applied
- **WHEN** a document with blank expiry and blank reminder period is sent
- **THEN** the Zoho request has expiration 90 days and a reminder period of 4 days

#### Scenario: Out-of-range expiry refused
- **WHEN** a user saves a document with "eSign Expires In (days)" set to 120
- **THEN** the save is refused with a message that the value must be between 1 and 99

### Requirement: Send limits and failures
The system SHALL refuse to send a document with more than 25 signers with "Zoho allows at most 25
signers per document." and SHALL refuse a file larger than 25 MB with the existing size message. When a
send fails for any other reason (the file cannot be read, Zoho cannot be reached or does not respond in
time, or Zoho refuses the request) the system SHALL mark the document Failed, alert the sender with
"Error sending <name> for eSigning - <reason>", record the response in the eSign log, and allow the
document to be sent again. A request created in Zoho but not sent out SHALL be deleted in Zoho on a
best-effort basis.

#### Scenario: Too many signers
- **WHEN** a user sends a document with 26 signers
- **THEN** nothing is sent to Zoho and the sender sees "Zoho allows at most 25 signers per document."

#### Scenario: Zoho unreachable
- **WHEN** Zoho does not respond in time while a document is being sent
- **THEN** the document is Failed, the sender is alerted with the reason, and the document can be sent again

#### Scenario: Unreadable file
- **WHEN** the document's file is not a readable PDF
- **THEN** the document is Failed and the sender is alerted with the reason

### Requirement: Status vocabulary
A Zoho document's eSign status SHALL be one of Requested, In progress, Completed, Expired, Cancelled or
Failed, and a signer's status one of Sent, Requested, Signed, Failed, Cancelled or Expired. The system
SHALL map Zoho's statuses to these: request in progress → In progress; completed → Completed (only via
the completion rule); expired → Expired; recalled → Cancelled; declined → Failed. A Zoho status not in
this mapping SHALL be recorded in the eSign log and SHALL NOT change the document or signer.

#### Scenario: Recalled in Zoho
- **WHEN** a status check finds the Zoho request recalled
- **THEN** the document shows Cancelled and can be sent again

#### Scenario: Unknown status
- **WHEN** a status check returns a Zoho status the system does not know
- **THEN** the document and signer statuses are unchanged and the response is in the eSign log

### Requirement: Live updates are authenticated
The system SHALL accept a live update from Zoho only if its X-ZS-WEBHOOK-SIGNATURE header equals the
base64-encoded HMAC-SHA256 of the raw request body computed with the webhook secret of the account the
update was addressed to: the company's secret for a company webhook address, CapHive's platform secret
for the shared address. An update with a missing or wrong signature SHALL be refused with HTTP 401 and
SHALL change nothing. In staging and production the shared address SHALL refuse Zoho updates when no
platform secret is configured; in development and test it SHALL accept them and log a warning.

#### Scenario: Missing signature refused
- **WHEN** an update without an X-ZS-WEBHOOK-SIGNATURE header is posted to a company's webhook address
- **THEN** the response is 401 and no document changes

#### Scenario: Wrong signature refused
- **WHEN** an update signed with a different secret is posted to the shared address
- **THEN** the response is 401 and no document changes

#### Scenario: Valid signature accepted
- **WHEN** an update signed with the company's webhook secret is posted to that company's webhook address
- **THEN** the response is 200

### Requirement: Live updates are tenant-scoped
An update received on a company's webhook address SHALL only affect documents of that company sent on
that company's account. An update received on the shared address SHALL only affect documents sent on
CapHive's platform account. An update naming a document outside that scope, or an unknown document,
SHALL be acknowledged with HTTP 200, recorded, and SHALL change nothing.

#### Scenario: Update for another company's document
- **WHEN** company B's webhook address receives a correctly signed update naming a request of company A's document
- **THEN** the response is 200 and company A's document is unchanged

#### Scenario: Unknown request
- **WHEN** a correctly signed update names a Zoho request the system does not know
- **THEN** the response is 200 and nothing changes

### Requirement: Live updates are acknowledged immediately
After authenticating an update the system SHALL reply HTTP 200 without waiting for the update to be
applied, and SHALL apply it in the background shortly after. Applying the same update twice SHALL have
the same effect as applying it once.

#### Scenario: Acknowledged before processing
- **WHEN** a correctly signed completion update arrives
- **THEN** the response is 200 before the signed copy is downloaded, and the document becomes Completed shortly after

#### Scenario: Duplicate update
- **WHEN** the same signer-signed update is delivered twice
- **THEN** the signer is Signed and the document state is the same as after one delivery

### Requirement: Applying live updates
The system SHALL apply Zoho update types as follows: request submitted → signers with no status become
Sent; signing success → that signer becomes Signed, then the completion rule runs; request rejected
(declined) → that signer becomes Failed and the document Failed; request recalled → document and all
signers Cancelled; request expired → document and all signers Expired; request completed → the
completion rule runs; request forwarded → the signer's slot is kept and later events from the new signer
update that slot; request viewed → recorded only. The signer SHALL be identified by Zoho's signer
reference recorded at send time, falling back to the email address.

#### Scenario: Signer declines
- **WHEN** an update reports that Priya declined
- **THEN** Priya's status is Failed, the document is Failed, and it can be sent again

#### Scenario: Forwarded then signed
- **WHEN** Rohan forwards the document to a colleague and the colleague signs
- **THEN** Rohan's signer slot shows Signed and the document can complete

#### Scenario: Submitted
- **WHEN** an update reports the request was submitted
- **THEN** every signer with no status shows Sent

### Requirement: Status check (pull)
"Get eSignatures' updates" and the daily eSign status check SHALL fetch the request from Zoho on the
document's account, apply the status vocabulary, reconcile the expiry date with Zoho's, update each
signer, run the completion rule, and record the response in the eSign log. The user SHALL be told
whether anything changed ("status updated" or "fetched - no changes"). A credential rejection SHALL be
handled by the connection health rule and SHALL NOT mark the document Failed.

#### Scenario: Partially signed
- **WHEN** a status check finds Rohan signed and Priya not yet
- **THEN** Rohan shows Signed, Priya shows Requested and the document shows In progress

#### Scenario: Expiry reconciled
- **WHEN** Zoho reports an expiry of 15 Dec 2026 for a document showing 28/11/2026
- **THEN** the document shows "eSignature Expires On 15/12/2026"

### Requirement: Completion
When every signer of a document is Signed, the system SHALL mark the document Completed, add the signed
copy from Zoho as a new signed document, and add Zoho's completion certificate as a separate document
named "<name> - Signature Certificate". This SHALL happen exactly once per document even when completion
is reported more than once or concurrently. If the certificate cannot be downloaded the document SHALL
still be Completed and the failure SHALL be logged.

#### Scenario: Completed once
- **WHEN** a completion update and a manual status check both report completion
- **THEN** the document is Completed and there is exactly one signed copy and exactly one certificate

#### Scenario: Certificate unavailable
- **WHEN** Zoho fails to return the completion certificate
- **THEN** the document is Completed with its signed copy and the failure is logged

### Requirement: Extend expiry
For a Zoho document that is out for signature (not Completed, Expired, Cancelled or Failed) a user who
can edit the document SHALL be able to extend the expiry to any real date from tomorrow onward; CapHive
SHALL NOT impose an upper limit and SHALL NOT shorten the chosen date. A missing, malformed, past or
today's date SHALL be refused with "Choose a date from <tomorrow> onward." and SHALL NOT change the
expiry or call Zoho. When Zoho accepts the extension the document SHALL show the new expiry; when Zoho
refuses it the user SHALL see "Error extending eSignature expiry" and the expiry SHALL be unchanged.

#### Scenario: Valid extension
- **WHEN** on 29 Oct 2026 a user extends a document's expiry to 15 Dec 2026 and Zoho accepts
- **THEN** the document shows "eSignature Expires On 15/12/2026" and "Document's eSignature expiry was extended"

#### Scenario: Far-future date accepted
- **WHEN** on 29 Oct 2026 a user extends a document's expiry to 31 Dec 2027 and Zoho accepts
- **THEN** the document shows "eSignature Expires On 31/12/2027", not a shortened date

#### Scenario: Past date refused
- **WHEN** on 29 Oct 2026 a user submits 29 Oct 2026
- **THEN** the user sees "Choose a date from 30/10/2026 onward.", the expiry is unchanged and Zoho is not called

#### Scenario: Tampered value
- **WHEN** the submitted date is "not-a-real-date"
- **THEN** the same refusal is shown, no error page appears, and Zoho is not called

### Requirement: Send reminder now
For a Zoho document out for signature and not Completed, a user who can edit the document SHALL be able
to ask Zoho to remind pending signers immediately. Success SHALL show "Reminder was sent to pending
signer(s)"; a Zoho refusal SHALL show "Error sending reminder".

#### Scenario: Reminder sent
- **WHEN** a user clicks Send Reminder on an In progress Zoho document
- **THEN** Zoho is asked to remind pending signers and the success message is shown

#### Scenario: Not offered on completed documents
- **WHEN** a user opens a Completed Zoho document
- **THEN** no Send Reminder button is shown and a direct request is refused

### Requirement: Cancel
For a Zoho document out for signature, "Cancel eSignatures" SHALL first refresh the status and then
recall the request in Zoho. On success the document and its signers SHALL be Cancelled and the document
can be sent again; on failure the user SHALL see "Error cancelling eSignature(s)" and nothing changes.

#### Scenario: Cancelled
- **WHEN** a user cancels an In progress Zoho document and Zoho accepts the recall
- **THEN** the document and its signers show Cancelled

#### Scenario: Recall refused
- **WHEN** Zoho refuses the recall
- **THEN** the user sees "Error cancelling eSignature(s)" and the statuses are unchanged

### Requirement: Zoho-only actions follow the provider
Extend Expiry, Send Reminder and the expiry and reminder fields SHALL be offered only for companies whose
eSign provider supports them (Zoho). For Digio and Docusign companies they SHALL be hidden and direct
requests refused, with Digio and Docusign behaviour otherwise unchanged.

#### Scenario: Hidden for Digio
- **WHEN** a user opens a sent document of a Digio company
- **THEN** no Extend Expiry or Send Reminder button and no expiry or reminder fields are shown

### Requirement: Calls to Zoho are bounded
Every call to Zoho SHALL give up after a bounded time. A rate-limit or temporary Zoho error during a
background status check or live update SHALL be retried later rather than marking the document Failed.
An access token SHALL be reused until shortly before it expires, SHALL be kept per account, and SHALL
never be reused after that account's credentials change.

#### Scenario: Zoho slow during a background check
- **WHEN** Zoho does not respond in time during the daily status check
- **THEN** the document's status is unchanged and the check is retried later

#### Scenario: Rate limited
- **WHEN** Zoho answers a status check with a rate-limit error
- **THEN** the document is not marked Failed and the check is retried later

#### Scenario: Token not reused after reconnect
- **WHEN** a company reconnects with new credentials and a document is then checked
- **THEN** the check obtains a new access token for the new credentials
