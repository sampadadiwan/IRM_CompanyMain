@zoho-http
Feature: Zoho eSign

  Sending, tracking, extending, reminding and cancelling documents through Zoho Sign. Zoho is a
  WebMock fake (features/support/zoho_sign_stub.rb). Each scenario names its worked example in
  openspec/changes/zoho-esign-production-ready/design.md#worked-examples.

Background:
  Given Im logged in as a user "" for an entity "entity_type=Investment Fund"
  And the user has role "company_admin"
  And the esign provider is "Zoho"
  And there is an approved Zoho document "Arka Fund I - Q3 Statement"

# H6 — zoho-sign-connections/Not connected
Scenario: A company without its own Zoho account sends on CapHive's account in India
  Given the document is to be signed by "rohan@example.com,priya@example.com"
  When the document is sent for Zoho eSign
  Then the Zoho request was created at "sign.zoho.in"
  And every Zoho call went to "accounts.zoho.in" or "sign.zoho.in"
  And the document's eSign status is "inprogress"

# H7 — zoho-esign/Configured values sent
Scenario: Sending a document for Zoho eSign includes the configured expiration and reminder settings
  Given the document's Zoho expiration is set to "30" days with reminders every "7" days
  When the document is sent for Zoho eSign
  Then the Zoho eSign request includes an expiration of "30" days and reminders every "7" days

# H7 — zoho-esign/Configured values sent (shown on the document page)
Scenario: Document show page displays the Zoho eSignature expiry and reminder details
  And the document has "2" e_signatures by Zoho
  Then the document shows its Zoho eSignature expiry and reminder details

# E13 — zoho-esign/Defaults applied
Scenario: Blank expiry and reminder period are sent as Zoho's defaults
  Given the document's Zoho expiry and reminder period are blank
  When the document is sent for Zoho eSign
  Then the Zoho eSign request includes an expiration of "90" days and reminders every "4" days

# E17 — zoho-esign/Too many signers (the limit itself is allowed)
Scenario: A document with 25 signers is sent
  Given the document has 25 Zoho signers
  When the document is sent for Zoho eSign
  Then the document's eSign status is "inprogress"

# X12 — zoho-esign/Too many signers
Scenario: A document with 26 signers is refused before anything reaches Zoho
  Given the document has 26 Zoho signers
  When the document is sent for Zoho eSign
  Then nothing was sent to Zoho
  And the sender is alerted with "Zoho allows at most 25 signers per document."

# E18 — zoho-esign/Signature boxes on every page
Scenario: Signature boxes on every page for every signer, without overlapping
  Given the document is to be signed by "rohan@example.com,priya@example.com"
  And the document places signature boxes on the "All" page
  When the document is sent for Zoho eSign
  Then each signer gets a signature box on pages "1,2,3"

# E19 — zoho-esign/Signature boxes on every page (first page only)
Scenario: Signature boxes on the first page only
  Given the document is to be signed by "rohan@example.com,priya@example.com"
  And the document places signature boxes on the "First" page
  When the document is sent for Zoho eSign
  Then each signer gets a signature box on pages "1"

# E20 — zoho-esign/Forced signing order
Scenario: Forced signing order is sent as a sequential request
  Given the document is to be signed by "rohan@example.com,priya@example.com"
  And the document forces the signing order
  When the document is sent for Zoho eSign
  Then the Zoho request is sequential with signing orders "0,1"

# X13 — zoho-esign/Zoho unreachable
Scenario: Zoho not answering while sending fails the document, which can be resent
  Given the document is to be signed by "rohan@example.com,priya@example.com"
  And Zoho will time out on "create"
  When the document is sent for Zoho eSign
  Then the document's eSign status is "failed"
  And the sender is alerted with "Error sending Arka Fund I - Q3 Statement for eSigning"
  And the document can be sent again

# X14 — zoho-esign/Unreadable file
Scenario: A file that is not a readable PDF fails the document
  Given the document is to be signed by "rohan@example.com,priya@example.com"
  And the document's file is not a PDF
  When the document is sent for Zoho eSign
  Then the document's eSign status is "failed"
  And nothing was sent to Zoho
  And the sender is alerted with "Error sending Arka Fund I - Q3 Statement for eSigning"

# X15 — zoho-esign/Zoho unreachable (submit refused after the draft was created)
Scenario: Zoho refusing the submit fails the document and deletes the draft
  Given the document is to be signed by "rohan@example.com,priya@example.com"
  And Zoho will refuse "submit" with status 400
  When the document is sent for Zoho eSign
  Then the document's eSign status is "failed"
  And the Zoho draft was deleted

# H9 — zoho-esign/Partially signed
Scenario: A status check finds one signer signed and the other not yet
  Given the document is to be signed by "rohan@example.com,priya@example.com"
  And the document is sent for Zoho eSign
  And Zoho reports "rohan@example.com" as "SIGNED"
  And Zoho reports "priya@example.com" as "YET_TO_SIGN"
  When the user fetches the eSignature updates
  Then the signer "rohan@example.com" has eSign status "signed"
  And the signer "priya@example.com" has eSign status "requested"
  And the document's eSign status is "inprogress"

# H9 — zoho-esign/Partially signed (signer statuses on the page)
Scenario: The document is partially signed via Zoho
  And the document has "2" e_signatures by Zoho
  Then the document is partially signed via Zoho

# H10 — zoho-esign/Completed once (through a status check)
Scenario: The Zoho eSign completes and the completion certificate is attached
  And the document has "2" e_signatures by Zoho
  Then the document is signed by Zoho and the completion certificate is attached

# E25 — zoho-esign/Expiry reconciled
Scenario: A status check takes Zoho's expiry date
  Given the document is to be signed by "rohan@example.com,priya@example.com"
  And the document is sent for Zoho eSign
  And Zoho reports the expiry as "15 Dec 2026 18:00"
  When the user fetches the eSignature updates
  Then the document's eSign expiry date is "15 Dec 2026"

# E30 — zoho-esign/Recalled in Zoho
Scenario: A request recalled directly in Zoho shows Cancelled and can be resent
  Given the document is to be signed by "rohan@example.com,priya@example.com"
  And the document is sent for Zoho eSign
  And Zoho reports the request as "recalled"
  When the user fetches the eSignature updates
  Then the document's eSign status is "cancelled"
  And the document can be sent again

# X23 — zoho-esign/Unknown status
Scenario: A Zoho status the app does not know changes nothing and is logged
  Given the document is to be signed by "rohan@example.com,priya@example.com"
  And the document is sent for Zoho eSign
  And Zoho reports the request as "paused"
  And Zoho reports "rohan@example.com" as "ON_HOLD"
  When the user fetches the eSignature updates
  Then the document's eSign status is "inprogress"
  And the signer "rohan@example.com" has eSign status "requested"
  And the Zoho response with "paused" is in the eSign log

# X9 — zoho-esign/Zoho slow during a background check
Scenario: Zoho not answering the daily check leaves the document unchanged and retries
  Given the document is to be signed by "rohan@example.com,priya@example.com"
  And the document is sent for Zoho eSign
  And Zoho will time out on "get"
  When the daily eSign status check runs
  Then the document's eSign status is "inprogress"
  And Zoho was asked 6 times for the request

# X10 — zoho-esign/Rate limited
Scenario: Zoho rate limiting the daily check does not fail the document
  Given the document is to be signed by "rohan@example.com,priya@example.com"
  And the document is sent for Zoho eSign
  And Zoho will refuse "get" with status 429
  When the daily eSign status check runs
  Then the document's eSign status is "inprogress"
  And Zoho was asked 6 times for the request

# H11 — zoho-esign/Valid extension
Scenario: Extending the Zoho eSignature expiry with a valid date updates the document
  And the document has "2" e_signatures by Zoho
  Then the Zoho eSignature expiry is extended to a valid future date

# H11 — zoho-esign/Valid extension (Zoho told the chosen date)
Scenario: Extending to a date some weeks out
  Given the document is to be signed by "rohan@example.com,priya@example.com"
  And the document is sent for Zoho eSign
  When the user extends the Zoho eSignature expiry to "D+47"
  Then the user sees "Document's eSignature expiry was extended"
  And the document shows eSignature Expires On "D+47"
  And Zoho was asked to "extend" 1 time

# E21 — zoho-esign/Valid extension (tomorrow is the earliest date)
Scenario: Extending to tomorrow is accepted
  Given the document is to be signed by "rohan@example.com,priya@example.com"
  And the document is sent for Zoho eSign
  When the user extends the Zoho eSignature expiry to "D+1"
  Then the user sees "Document's eSignature expiry was extended"
  And the document shows eSignature Expires On "D+1"

# E22 — zoho-esign/Far-future date accepted
Scenario: Extending more than a year out is accepted and not shortened
  Given the document is to be signed by "rohan@example.com,priya@example.com"
  And the document is sent for Zoho eSign
  When the user extends the Zoho eSignature expiry to "D+400"
  Then the user sees "Document's eSignature expiry was extended"
  And the document shows eSignature Expires On "D+400"

# E23 — zoho-esign/Past date refused
Scenario: Extending to a past date is refused without calling Zoho
  Given the document is to be signed by "rohan@example.com,priya@example.com"
  And the document is sent for Zoho eSign
  When the user extends the Zoho eSignature expiry to "D-28"
  Then the user sees the extension refused
  And the document's eSign expiry is unchanged
  And Zoho was not asked to "extend"

# E24 — zoho-esign/Past date refused (today)
Scenario: Extending to today is refused
  Given the document is to be signed by "rohan@example.com,priya@example.com"
  And the document is sent for Zoho eSign
  When the user extends the Zoho eSignature expiry to "D"
  Then the user sees the extension refused
  And the document's eSign expiry is unchanged
  And Zoho was not asked to "extend"

# X16 — zoho-esign/Tampered value
Scenario: Extending the Zoho eSignature expiry rejects a tampered, invalid date
  And the document has "2" e_signatures by Zoho
  Then extending the Zoho eSignature expiry with an invalid date is rejected without raising

# X16 — zoho-esign/Tampered value (through the page)
Scenario: A tampered extension date shows the refusal, not an error page
  Given the document is to be signed by "rohan@example.com,priya@example.com"
  And the document is sent for Zoho eSign
  When the user extends the Zoho eSignature expiry to "not-a-real-date"
  Then the user sees the extension refused
  And the document's eSign expiry is unchanged
  And Zoho was not asked to "extend"

# X17 — zoho-esign/Valid extension (Zoho refuses)
Scenario: Zoho refusing the extension leaves the expiry unchanged
  Given the document is to be signed by "rohan@example.com,priya@example.com"
  And the document is sent for Zoho eSign
  And Zoho will refuse "extend" with status 400
  When the user extends the Zoho eSignature expiry to "D+47"
  Then the user sees "Error extending eSignature expiry"
  And the document's eSign expiry is unchanged

# H12 — zoho-esign/Reminder sent
Scenario: Send Reminder asks Zoho to remind pending signers
  Given the document is to be signed by "rohan@example.com,priya@example.com"
  And the document is sent for Zoho eSign
  When the user sends a Zoho reminder
  Then the user sees "Reminder was sent to pending signer(s)"
  And Zoho was asked to "remind" 1 time

# E26 — zoho-esign/Not offered on completed documents
Scenario: A completed document offers no reminder and refuses a direct request
  Given the document is to be signed by "rohan@example.com,priya@example.com"
  And the document is sent for Zoho eSign
  And the document's eSign status is set to "completed"
  Then the Send Reminder button is not offered
  When the user requests "send reminder" for the document directly
  Then Zoho was not asked to "remind"

# H13 — zoho-esign/Cancelled
Scenario: Cancelling recalls the request in Zoho
  Given the document is to be signed by "rohan@example.com,priya@example.com"
  And the document is sent for Zoho eSign
  When the user cancels the eSignatures
  Then the user sees "Document's eSignature(s) was cancelled"
  And the document's eSign status is "cancelled"
  And the signer "rohan@example.com" has eSign status "cancelled"
  And the signer "priya@example.com" has eSign status "cancelled"

# X25 — zoho-esign/Recall refused
Scenario: Zoho refusing the recall changes nothing
  Given the document is to be signed by "rohan@example.com,priya@example.com"
  And the document is sent for Zoho eSign
  And Zoho will refuse "recall" with status 400
  When the user cancels the eSignatures
  Then the user sees "Error cancelling eSignature(s)"
  And the document's eSign status is "inprogress"
  And the signer "rohan@example.com" has eSign status "requested"

# E2 — zoho-esign/Hidden for Digio
Scenario: A Digio company sees none of the Zoho-only actions and cannot call them
  Given the esign provider is "Digio"
  And the document is to be signed by "rohan@example.com,priya@example.com"
  And the document is out for signature
  Then the Zoho-only eSign actions are not offered
  When the user requests "extend expiry" for the document directly
  Then Zoho was not asked to "extend"

# E14 — zoho-esign/Out-of-range expiry refused (the limits are allowed)
Scenario: Expiry of 99 and 1 days are saved
  When the document's eSign expiry is set to 99 days
  Then the document is saved
  When the document's eSign expiry is set to 1 days
  Then the document is saved

# E15 — zoho-esign/Out-of-range expiry refused
Scenario: Expiry of 0 or 100 days is refused
  When the document's eSign expiry is set to 0 days
  Then the document is not saved and shows "must be between 1 and 99"
  When the document's eSign expiry is set to 100 days
  Then the document is not saved and shows "must be between 1 and 99"

# E16 — zoho-esign/Out-of-range expiry refused (reminder period)
Scenario: Reminder period of 30 days is saved and 31 is refused
  When the document's eSign reminder period is set to 30 days
  Then the document is saved
  When the document's eSign reminder period is set to 31 days
  Then the document is not saved and shows "must be between 1 and 30"

# H5 — zoho-esign/Successful send; zoho-sign-connections/Sent after connecting; Calls go to the chosen region
Scenario: A company with its own Zoho account in the US sends through it
  Given the company has connected its Zoho account in "com"
  And the document is to be signed by "rohan@example.com,priya@example.com"
  And the document's Zoho expiration is set to "30" days with reminders every "7" days
  When the document is sent for Zoho eSign
  Then the Zoho request was created at "sign.zoho.com"
  And every Zoho call went to "accounts.zoho.com" or "sign.zoho.com"
  And the document's eSign expiry date is "D+30"

# E9 — zoho-sign-connections/Sent before connecting
Scenario: A document sent before the company connected keeps using CapHive's account
  Given the document is to be signed by "rohan@example.com,priya@example.com"
  And the document is sent for Zoho eSign
  And the company has connected its Zoho account in "com"
  And the document was sent 60 seconds before the company connected
  And Zoho's call log is cleared
  When the daily eSign status check runs
  Then every Zoho call went to "accounts.zoho.in" or "sign.zoho.in"
  And the document's eSign status is "inprogress"

# E10 — zoho-sign-connections/Sent after connecting (exactly at the cutover)
Scenario: A document sent at the moment the company connected uses the company's account
  Given the document is to be signed by "rohan@example.com,priya@example.com"
  And the document is sent for Zoho eSign
  And the company has connected its Zoho account in "com"
  And the document was sent exactly when the company connected
  And Zoho's call log is cleared
  When the daily eSign status check runs
  Then every Zoho call went to "accounts.zoho.com" or "sign.zoho.com"

# E11 — zoho-sign-connections/Sent before connecting (one second before)
Scenario: A document sent one second before the company connected uses CapHive's account
  Given the document is to be signed by "rohan@example.com,priya@example.com"
  And the document is sent for Zoho eSign
  And the company has connected its Zoho account in "com"
  And the document was sent 1 second before the company connected
  And Zoho's call log is cleared
  When the daily eSign status check runs
  Then every Zoho call went to "accounts.zoho.in" or "sign.zoho.in"

# E12 — zoho-esign/Token not reused after reconnect
Scenario: New credentials get a new access token
  Given Zoho access tokens are cached
  And the company has connected its Zoho account in "com"
  And the document is to be signed by "rohan@example.com,priya@example.com"
  And the document is sent for Zoho eSign
  When the daily eSign status check runs
  And the company reconnects with new credentials
  And the daily eSign status check runs
  Then Zoho issued access tokens for refresh tokens "arka-refresh-token,arka-refresh-token-2"

# X8 — zoho-sign-connections/Credentials revoked
Scenario: Zoho rejecting the company's credentials during the daily check
  Given the company has connected its Zoho account in "com"
  And 3 documents are out for signature on the company's Zoho account
  And Zoho will refuse "get" with status 401
  When the daily eSign status check runs
  Then the company's Zoho connection is "needs_reauth"
  And the company admins are emailed once that the Zoho account needs reconnecting
  And the documents out for signature keep their status "inprogress"

# X11 — zoho-sign-connections/Sending blocked while reconnect is needed
Scenario: Sending is refused while the company's Zoho account needs reconnecting
  Given the company has connected its Zoho account in "com"
  And the company's Zoho account needs reconnecting
  And the document is to be signed by "rohan@example.com,priya@example.com"
  When the document is sent for Zoho eSign
  Then nothing was sent to Zoho
  And the sender is alerted with "Zoho account needs to be reconnected. Ask a company admin to reconnect it on the company page."
