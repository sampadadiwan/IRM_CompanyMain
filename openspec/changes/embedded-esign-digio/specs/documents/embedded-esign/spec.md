# Spec Delta: Embedded eSigning

## Purpose

Lets a signer who is logged in to the platform sign a Digio eSign request from inside the platform instead of following the emailed link, while keeping the emailed link, the signing order and Digio's own confirmation as the source of truth.

## ADDED Requirements

### Requirement: Eligibility to sign inside the platform
The system SHALL offer in-platform signing for a signature request only to a logged-in user whose login email equals the signer's email (ignoring upper/lower case), and only while ALL of the following hold: the document was sent for eSignature through Digio, the document is waiting for signatures, that signer has not signed, and Embedded eSigning is switched on for the entity that owns the document.

#### Scenario: Matching logged-in signer is offered Sign now
- **WHEN** a logged-in user whose login email is a pending signer's email opens the document, and the document is waiting for signatures with Embedded eSigning on for its entity
- **THEN** the document page shows "Your signature is requested on this document." with a "Sign now" button

#### Scenario: Email match ignores letter case
- **WHEN** the signer email on the document is "Priya@LPFund.com" and the logged-in user's email is "priya@lpfund.com"
- **THEN** the user is treated as that signer and is offered "Sign now"

#### Scenario: Non-matching user is not offered Sign now
- **WHEN** a logged-in user whose email is not any pending signer's email opens the document
- **THEN** no signature banner and no "Sign now" button is shown

#### Scenario: Embedded eSigning switched off
- **WHEN** Embedded eSigning is off for the entity that owns the document
- **THEN** no "Sign now" is shown to anyone for that entity's documents and eSigning behaves exactly as before

#### Scenario: Support user impersonating a signer cannot sign
- **WHEN** a support user who is impersonating the signer opens the document or the signing page
- **THEN** no "Sign now" is shown and the signing page is refused

#### Scenario: Document is not waiting for signatures
- **WHEN** the document is cancelled, expired, failed, voided or already completed
- **THEN** no "Sign now" is shown, and opening the signing page directly shows "This document is no longer waiting for signatures."

#### Scenario: Employee signer sees Sign now on their own row
- **WHEN** an employee of the document's entity who is a pending signer views the document's Signatures tab
- **THEN** "Sign now" appears on that employee's own signer row only, and not on other signers' rows

### Requirement: Signing order is respected
The system SHALL only let a signer start signing when it is that signer's turn: if the document enforces a signing order, every earlier signer must have signed; if it does not, every pending signer may sign at any time.

#### Scenario: Earlier signer still pending
- **WHEN** the document enforces a signing order and an earlier signer has not signed
- **THEN** the signer sees "Your signature is requested on this document. You can sign after the previous signer has signed." with no "Sign now" button

#### Scenario: Signing page opened out of turn
- **WHEN** a signer opens the signing page directly while an earlier signer has not signed
- **THEN** the page shows "It isn't your turn to sign yet. You'll be able to sign after the previous signer has signed." and offers no way to start signing

#### Scenario: Turn arrives after the earlier signer signs
- **WHEN** the earlier signer's signature is confirmed
- **THEN** the next signer's document page shows "Sign now"

#### Scenario: Document without a signing order
- **WHEN** the document does not enforce a signing order and two signers are pending
- **THEN** both signers are offered "Sign now" at the same time

### Requirement: Signing page
The system SHALL provide a signing page inside the platform's normal layout for a signer to start and complete signing, identical on phone and computer. The page SHALL show the document name, the signer's email, the signer's position among the signers and label, and the signature method, and SHALL open Digio's signing panel only when the signer clicks "Start signing".

#### Scenario: Signing page shows the signer's context
- **WHEN** an eligible signer opens the signing page
- **THEN** it shows the document name, "Signing as: {email}", "Signer {n} of {total} - {label}", the signature method, a "Start signing" button and a "Back to document" link

#### Scenario: Start signing opens the panel
- **WHEN** the signer clicks "Start signing"
- **THEN** Digio's signing panel opens on the same page for that document and that signer's email

#### Scenario: Non-signer opens the signing page directly
- **WHEN** a logged-in user who is not a signer on the document opens the signing page address
- **THEN** the page is refused with "This signature request is not available for your account." and no document or signer detail is disclosed

#### Scenario: Signer who has already signed opens the page
- **WHEN** a signer whose signature is already confirmed opens the signing page
- **THEN** the page shows "You have already signed this document." and "Back to document" only

#### Scenario: Signing panel cannot be loaded
- **WHEN** the signer clicks "Start signing" and Digio's signing panel cannot be loaded
- **THEN** the page shows "We couldn't load the signing panel. Please check your connection and try again, or use the link in the email from Digio." with "Try again", and no change is made to the document

#### Scenario: Same flow on a phone-width screen
- **WHEN** an eligible signer uses a phone-width screen
- **THEN** the same banner, signing page and "Start signing" flow are used, with no separate mobile flow

### Requirement: Signer is verified by Digio, with no shortcut token
The system SHALL start the signing panel using only the Digio document and the signer's email, so that Digio itself verifies the signer. The system SHALL NOT request, store, display or send a signing access token to the browser.

#### Scenario: Signing request carries no access token
- **WHEN** a document is sent for eSignature, with or without Embedded eSigning on
- **THEN** the request to Digio does not ask for an access token

#### Scenario: Panel is opened with document and signer only
- **WHEN** a signer clicks "Start signing"
- **THEN** the only signing identifiers handed to the browser are the Digio document id and the signer's email

#### Scenario: Documents already sent can be signed
- **WHEN** Embedded eSigning is switched on for an entity that already has documents waiting for signatures
- **THEN** their pending signers are offered "Sign now" without the documents being re-sent

### Requirement: The signer's result is confirmed with Digio
The system SHALL treat a result reported by the browser only as a prompt to confirm with Digio. A signer SHALL become Signed only when Digio reports it, either by its own notification or by the system asking Digio for the document's status.

#### Scenario: Completion triggers confirmation
- **WHEN** the signing panel reports that signing completed
- **THEN** the page shows "Thank you. Your signature has been submitted and is being confirmed." and the system asks Digio for the document's status

#### Scenario: Confirmed signature updates the document
- **WHEN** Digio's status shows the signer as signed
- **THEN** the signer is shown as Signed, and the document completes when all signers are Signed, as for any other eSignature

#### Scenario: Browser reports success that Digio does not confirm
- **WHEN** the browser reports completion but Digio's status shows the signer as still requested
- **THEN** the signer remains Requested and no signed copy is created

#### Scenario: Signer closes the panel without finishing
- **WHEN** the signer closes the signing panel before completing
- **THEN** the page shows "Signing was cancelled. You can start again whenever you are ready." and "Start signing" is available again

### Requirement: Digio error codes become clear messages
The system SHALL translate every signing error code Digio reports into one of a fixed set of plain-language messages with a next step, SHALL show the same message for both spellings `DOCUMENT_NOT_READY_FOR_THIS_ACTION` and `DOCUEMNT_NOT_READY_FOR_THIS_ACTION`, and SHALL never show a raw error code to the signer.

#### Scenario: Retryable codes
- **WHEN** Digio reports `OTP_INVALID`, `AUTHENTICATION_FAILED`, `BIOMETRIC_DATA_MISMATCH`, `BIOMETRIC_LOCKED`, `INCORRECT_AADHAAR_ID`, `INVALID_ELECTRONIC_SIGNATURE`, `SIGNING_TIMED_OUT_ON_ESP` or `SIGNING_CANCELLED_ON_ESP`
- **THEN** the page shows "Signing didn't go through. Please check your details and try again." with "Try again"

#### Scenario: Signing service unavailable
- **WHEN** Digio reports `ERROR_FROM_ESP_UIDAI`, `ESP_UIDAI_DOWN`, `AADHAAR_ESIGN_TEMPORARILY_UNAVAILABLE` or `ESIGN_REQUEST_FAILURE`
- **THEN** the page shows "The signing service is temporarily unavailable. Please try again in a little while." with "Try again"

#### Scenario: Aadhaar cannot be used
- **WHEN** Digio reports `AADHAAR_HAS_NO_MOBILE`, `AADHAAR_HAS_NO_MOBILE_OR_EMAIL`, `AADHAAR_SUSPENDED`, `AADHAAR_NOT_AUTHENTICABLE` or `AADHAAR_CANCELLED`
- **THEN** the page shows "Your Aadhaar can't be used for eSign right now. Please contact UIDAI, or ask the sender to arrange a different signing method." and does not offer "Try again"

#### Scenario: Request already signed or in progress
- **WHEN** Digio reports `ALREADY_SIGNED` or `DUPLICATE_REQUEST`
- **THEN** the page shows "You have already signed this document." or "A signing request is already in progress. Please wait a moment and check the status again." respectively, and the system asks Digio for the document's status

#### Scenario: Request expired or method changed
- **WHEN** Digio reports `SIGN_REQUEST_EXPIRED` or `REQUESTED_SIGN_METHOD_DIFFERENT`
- **THEN** the page shows "This signing request has expired. Please ask the sender to send it again." or "The signing method for this document has changed. Please ask the sender to send it again." respectively, and does not offer "Try again"

#### Scenario: Document not ready, both spellings
- **WHEN** Digio reports `DOCUMENT_NOT_READY_FOR_THIS_ACTION` or `DOCUEMNT_NOT_READY_FOR_THIS_ACTION`
- **THEN** the page shows "This document isn't ready to be signed yet. Please try again in a few minutes." in both cases

#### Scenario: Not the signer's turn
- **WHEN** Digio reports `SIGNING_NOT_ALLOWED`
- **THEN** the page shows "It isn't your turn to sign yet. You'll be able to sign after the previous signer has signed."

#### Scenario: Problems on our side or Digio's
- **WHEN** Digio reports `NOT_SUFFICIENT_ENTITLEMENTS`, `INVALID_SIGNER`, `UNAUTHORIZED_ACCESS`, `SYSTEM_ERROR` or `UNKNOWN_ERROR`
- **THEN** the page shows "Something went wrong on our side and the team has been notified. Please try again later or contact support." and support is alerted with the code, the document and the signer, without the code appearing on the page

#### Scenario: Unrecognised error code
- **WHEN** Digio reports an error code that is not in the list
- **THEN** it is handled like a problem on our side or Digio's

### Requirement: Signing-page activity is recorded
The system SHALL record, against the document's eSign log, each result reported from the signing page — who the signer was, which event or error code was reported and when — so that support can reconstruct what happened.

#### Scenario: Completion is recorded
- **WHEN** the signing panel reports that signing completed
- **THEN** the document's eSign log gains an entry with the signer's email, the event name and the time

#### Scenario: Failure is recorded
- **WHEN** the signing panel reports an error code
- **THEN** the document's eSign log gains an entry with the signer's email, the code and the time

### Requirement: Rollout switch and environment
The system SHALL let CapHive admins switch Embedded eSigning on or off per entity, defaulting to off, and SHALL load Digio's signing panel from Digio's sandbox in sandbox environments and from Digio's production site in production.

#### Scenario: Default is off
- **WHEN** an entity has never been configured for Embedded eSigning
- **THEN** its documents are signed exactly as before and no "Sign now" is shown

#### Scenario: Switched on for one entity only
- **WHEN** an admin switches Embedded eSigning on for entity A
- **THEN** signers on entity A's documents are offered "Sign now" and signers on entity B's documents are not

#### Scenario: Sandbox environment
- **WHEN** the platform is configured against Digio's sandbox
- **THEN** the signing page loads Digio's panel from the sandbox site and tells it to run in sandbox mode

### Requirement: Signers are notified when it is their turn
The system SHALL notify a signer who is a platform user, in the platform and by email, when that signer becomes able to sign: when the document is sent for eSignature, and when an earlier signer's signature is confirmed. A signer SHALL be notified at most once per signing request, the notification SHALL open the signing page, and email SHALL follow the recipient's existing email permissions. A failure to notify SHALL NOT block sending the document or acknowledging Digio's notifications. Notifications SHALL NOT be sent retroactively for documents sent before Embedded eSigning was switched on, and WhatsApp is not part of this requirement.

#### Scenario: Ready signer is notified when the document is sent
- **WHEN** a document is sent for eSignature with Embedded eSigning on, and a signer who can sign now is a platform user
- **THEN** that signer receives a notification "Your signature is requested: {document name} from {entity name}" in the platform and an email with the subject "Your signature is requested: {document name}"

#### Scenario: Ordered document notifies only the first signer at send
- **WHEN** a document that enforces a signing order is sent and all three signers are platform users
- **THEN** only the first signer is notified, and the second and third signers receive nothing yet

#### Scenario: Next signer is notified when the earlier signature is confirmed
- **WHEN** the first signer's signature is confirmed, by Digio's notification or by the system asking Digio, on a document that enforces a signing order
- **THEN** the second signer, if a platform user, receives the notification and the email

#### Scenario: Unordered document notifies every pending signer at send
- **WHEN** a document that does not enforce a signing order is sent and two signers are platform users
- **THEN** both are notified at once

#### Scenario: Non-platform user or switch off gets no notification
- **WHEN** a signer is not a platform user, or Embedded eSigning is off for the document's entity
- **THEN** no notification or email is created for that signer by this feature

#### Scenario: Each request notifies a signer once
- **WHEN** the same confirmation reaches the system more than once (Digio notification repeated, or a status check and a notification together)
- **THEN** the signer is notified once for that signing request

#### Scenario: Re-send notifies again
- **WHEN** a document is re-sent for eSignature after signers' statuses were reset
- **THEN** each signer who can sign now is notified again for the new request

#### Scenario: Notification opens the signing page
- **WHEN** the signer clicks the platform notification or the "Sign now" button in the email
- **THEN** they arrive at the signing page for their own signature, after logging in if necessary

#### Scenario: Investor without email access gets the in-app notification only
- **WHEN** the signer is an investor user whose access for the entity has email turned off
- **THEN** the platform notification is created and no CapHive email is sent

#### Scenario: Switching on does not notify for already-sent documents
- **WHEN** Embedded eSigning is switched on for an entity that already has documents waiting for signatures
- **THEN** no notification is sent at that moment, and the next signer is notified only when their turn next arrives

#### Scenario: Notification failure does not block sending or webhooks
- **WHEN** creating or delivering a notification fails while a document is being sent, or while a Digio notification is being processed
- **THEN** the document is still sent, the signer statuses are still updated, Digio is still acknowledged, and support is alerted

