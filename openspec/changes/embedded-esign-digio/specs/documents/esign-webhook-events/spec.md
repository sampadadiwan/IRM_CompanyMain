# Spec Delta: eSign webhook events

## Purpose

Defines how the platform interprets Digio's server notifications about a signature request, so that each event type — signed, failed, rejected — has its own well-defined effect and unknown notifications never break processing.

## ADDED Requirements

### Requirement: Notifications are interpreted by event type
The system SHALL decide how to process a Digio notification from its event type: `doc.signed`, `doc.sign.failed` and `doc.sign.rejected`. It SHALL always acknowledge a received notification with success so that Digio does not keep retrying.

#### Scenario: Signed notification updates signers
- **WHEN** a `doc.signed` notification arrives listing signers with their statuses
- **THEN** each listed signer on the document takes the reported status, and the document completes when every signer is Signed

#### Scenario: Partially signed document
- **WHEN** a `doc.signed` notification arrives and at least one signer is still requested
- **THEN** the signers who signed are shown Signed and the document remains waiting for signatures

#### Scenario: Failed notification marks the signer failed
- **WHEN** a `doc.sign.failed` notification arrives with a signer email and an error code
- **THEN** that signer is shown as Failed and the notification is recorded in the document's eSign log

#### Scenario: Notification is always acknowledged
- **WHEN** any notification arrives, including ones that cannot be matched to a document
- **THEN** the platform answers with success

### Requirement: Rejected signatures are shown as Rejected
The system SHALL, on a `doc.sign.rejected` notification, mark the signer identified by the notification as Rejected, record the notification, alert support, and leave the document itself otherwise unchanged.

#### Scenario: Rejection marks the signer Rejected
- **WHEN** a `doc.sign.rejected` notification arrives for a signer on a document waiting for signatures
- **THEN** that signer is shown as Rejected with a danger-coloured badge, the document is not cancelled, and support is alerted

#### Scenario: Rejection without a signer list does not fail processing
- **WHEN** a `doc.sign.rejected` notification arrives with no list of signers and no error code
- **THEN** it is processed as a rejection and no processing error occurs

#### Scenario: Rejection for a signer not on the document
- **WHEN** a `doc.sign.rejected` notification names an email that is not a signer on the matching document
- **THEN** support is alerted with the document and the email, and the platform still answers with success

### Requirement: Unknown or missing event types behave as before
The system SHALL process a notification that carries no event type, or an event type it does not know, according to its content exactly as the platform did before event types were read: a notification with an error code is a failure; one without an error code that lists signers updates those signers; anything else is acknowledged and reported without changing data.

#### Scenario: Legacy notification without an event type
- **WHEN** a notification arrives with no event type and lists signers with statuses
- **THEN** those signers take the reported statuses, as before

#### Scenario: Notification with an unknown event type
- **WHEN** a notification arrives with an event type that is not signed, failed or rejected
- **THEN** it is acknowledged, no signer is marked Rejected or Failed because of the event type alone, and nothing breaks

#### Scenario: Notification without a document
- **WHEN** a notification arrives that names no document
- **THEN** it is acknowledged and reported to support, and no data changes

### Requirement: A later notification cannot undo a signature
The system SHALL NOT change a signer who is already Signed to Failed or Rejected because of a later or repeated notification.

#### Scenario: Late rejection after signing
- **WHEN** a signer is Signed and a `doc.sign.rejected` or `doc.sign.failed` notification for that signer arrives afterwards
- **THEN** the signer remains Signed and the late notification is only recorded

### Requirement: Digio's audit trail is filed with the signed copy
The system SHALL, when a Digio document completes, fetch Digio's audit trail PDF in the background and file it as a locked, approved document named "<document name> - Audit Trail" with the tag "Audit Trail", beside the signed copy and not tagged "Signed". It SHALL file one per document. It SHALL try again when Digio does not hand it over, because Digio refuses until the signing flow is complete, and SHALL alert support if it never arrives, leaving the document Completed.

#### Scenario: Audit trail filed on completion
- **WHEN** the last signature completes a Digio document
- **THEN** the signed copy and the audit trail are both on the document's owner

#### Scenario: Repeated confirmation
- **WHEN** Digio repeats the completing notification or a status check confirms it again
- **THEN** one audit trail is filed and Digio is asked once

#### Scenario: Digio is not ready yet
- **WHEN** Digio refuses the audit trail and then hands it over on a later attempt
- **THEN** it is filed and support is not alerted

#### Scenario: Digio never hands it over
- **WHEN** every attempt is refused
- **THEN** the document stays Completed with its signed copy, no audit trail is filed, and support is alerted

### Requirement: A completed document always has its signed copy
The system SHALL NOT mark a Digio document Completed unless the signed copy was downloaded, and SHALL file the signed copy and the audit trail in the document's own folder when the document has no owner.

#### Scenario: Signed copy cannot be downloaded
- **WHEN** every signer has signed and Digio's download fails
- **THEN** the document stays as it was, no signed copy is created, support is alerted, and Digio is answered with success
- **AND** the next notification or status check completes it

#### Scenario: Document with no owner
- **WHEN** the last signature completes a document that has a folder but no owner
- **THEN** the document is Completed and its signed copy and audit trail are in its folder

### Requirement: Digio's responses are kept in the eSign log
The system SHALL record Digio's send, status, cancel and notification responses in the document's eSign log and SHALL NOT copy them onto the signer rows.

#### Scenario: Status check and notification
- **WHEN** a status check runs and a notification arrives for a signer
- **THEN** both are in the eSign log and no signer row holds Digio's response
