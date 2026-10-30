@zoho-http
Feature: Zoho eSign webhooks

  Zoho Sign updates for documents sent on CapHive's platform account arrive at
  documents/signature_progress; updates from a company's own Zoho account arrive at that company's
  zoho_sign/webhooks/:token address. They are HMAC-verified (X-ZS-WEBHOOK-SIGNATURE), acknowledged with
  200 and applied in the background. Each scenario names its worked example in
  openspec/changes/zoho-esign-production-ready/design.md#worked-examples.

Background:
  Given Im logged in as a user "" for an entity "entity_type=Investment Fund"
  And the user has role "company_admin"
  And the esign provider is "Zoho"
  And there is an approved Zoho document "Arka Fund I - Q3 Statement"
  And the document is to be signed by "rohan@example.com,priya@example.com"
  And the document is sent for Zoho eSign

# E34 — zoho-esign/Valid signature accepted (development/test without a platform secret)
Scenario: A Zoho eSign webhook reports a signer as signed
  When a Zoho eSign webhook reports the first signer as signed
  Then the first signer's status is updated to signed and the second signer remains pending

# X19 — zoho-esign/Wrong signature refused
Scenario: A Zoho eSign webhook request with an invalid signature is rejected
  Given CapHive's Zoho webhook secret is "plat-secret"
  When Zoho posts "RequestSigningSuccess" for "rohan@example.com" to the shared address signed with "wrong"
  Then the webhook response is 401
  And the signer "rohan@example.com" has eSign status "requested"

# X19 — zoho-esign/Wrong signature refused (any update with a mismatching signature)
Scenario: A webhook whose signature verification fails is rejected as unauthorized
  Given the Zoho eSign webhook signature verification will fail
  When a Zoho eSign webhook request is received with an invalid signature
  Then the webhook request is rejected as unauthorized

# X22 — zoho-esign/Wrong signature refused (staging without a platform secret)
Scenario: Staging refuses unsigned Zoho updates when no platform secret is configured
  Given unsigned Zoho updates are refused as in staging
  When Zoho posts "RequestSigningSuccess" for "rohan@example.com" to the shared address signed with "nothing"
  Then the webhook response is 401
  And the signer "rohan@example.com" has eSign status "requested"

# H8 — zoho-esign/Valid signature accepted (shared address, platform secret)
Scenario: A correctly signed update is accepted and applied
  Given CapHive's Zoho webhook secret is "plat-secret"
  When Zoho posts "RequestSigningSuccess" for "rohan@example.com" to the shared address signed with "plat-secret"
  Then the webhook response is 200
  And the signer "rohan@example.com" has eSign status "signed"
  And the signer "priya@example.com" has eSign status "requested"

# H15 — zoho-esign/Submitted
Scenario: Request submitted marks signers with no status as Sent
  Given the signers have no eSign status yet
  When Zoho posts "RequestSubmitted" to the shared address signed with "nothing"
  Then the signer "rohan@example.com" has eSign status "sent"
  And the signer "priya@example.com" has eSign status "sent"

# E27 — zoho-esign/Duplicate update
Scenario: The same signed update delivered twice has the effect of one
  When Zoho posts "RequestSigningSuccess" for "rohan@example.com" to the shared address signed with "nothing"
  And Zoho posts "RequestSigningSuccess" for "rohan@example.com" to the shared address signed with "nothing"
  Then the signer "rohan@example.com" has eSign status "signed"
  And the signer "priya@example.com" has eSign status "requested"
  And the document's eSign status is "inprogress"

# E35 — zoho-esign/Duplicate update (viewed is recorded only)
Scenario: A viewed update is only recorded
  When Zoho posts "RequestViewed" for "rohan@example.com" to the shared address signed with "nothing"
  Then the webhook response is 200
  And the signer "rohan@example.com" has eSign status "requested"
  And the document's eSign status is "inprogress"
  And the Zoho webhook "RequestViewed" is in the eSign log

# X24 — zoho-esign/Signer declines
Scenario: A signer declining fails the signer and the document, which can be resent
  When Zoho posts "RequestRejected" for "priya@example.com" to the shared address signed with "nothing"
  Then the signer "priya@example.com" has eSign status "failed"
  And the document's eSign status is "failed"
  And the document can be sent again

# E31 — zoho-esign/Recalled in Zoho (expired event)
Scenario: An expired update expires the document and its signers
  When Zoho posts "RequestExpired" to the shared address signed with "nothing"
  Then the document's eSign status is "expired"
  And the signer "rohan@example.com" has eSign status "expired"
  And the signer "priya@example.com" has eSign status "expired"

# H10 — zoho-esign/Completed once
Scenario: A completion update completes the document with its signed copy and certificate
  Given both signers have signed in Zoho
  When Zoho posts "RequestCompleted" to the shared address signed with "nothing"
  Then the document's eSign status is "completed"
  And the document has 1 signed copy and 1 signature certificate

# E28 — zoho-esign/Completed once (webhook and status check both report completion)
Scenario: Completion reported twice adds the signed copy and certificate once
  Given both signers have signed in Zoho
  And Zoho reports the request as "completed"
  When Zoho posts "RequestCompleted" to the shared address signed with "nothing"
  And the user fetches the eSignature updates
  Then the document's eSign status is "completed"
  And the document has 1 signed copy and 1 signature certificate

# E33 — zoho-esign/Acknowledged before processing
Scenario: The update is acknowledged before the signed copy is downloaded
  Given both signers have signed in Zoho
  And background jobs are queued instead of run
  When Zoho posts "RequestCompleted" to the shared address signed with "nothing"
  Then the webhook response is 200
  And the document's eSign status is "inprogress"
  When the queued Zoho webhook jobs run
  Then the document's eSign status is "completed"

# X26 — zoho-esign/Certificate unavailable
Scenario: Completion stands when Zoho cannot return the certificate
  Given both signers have signed in Zoho
  And Zoho will refuse "certificate" with status 500
  And Zoho errors are reported
  When Zoho posts "RequestCompleted" to the shared address signed with "nothing"
  Then the document's eSign status is "completed"
  And the document has 1 signed copy and 0 signature certificate
  And the certificate failure is reported

# H8 — zoho-esign/Valid signature accepted (company address)
Scenario: A company's own Zoho account posts a correctly signed update to its address
  Given the company had connected its Zoho account in "com" before the document was sent
  When Zoho posts "RequestSigningSuccess" for "rohan@example.com" to the company's webhook address signed with "arka-secret"
  Then the webhook response is 200
  And the signer "rohan@example.com" has eSign status "signed"
  And the signer "priya@example.com" has eSign status "requested"
  And the company's webhook shows a last update

# X18 — zoho-esign/Missing signature refused
Scenario: An unsigned update to a company's address is refused
  Given the company had connected its Zoho account in "com" before the document was sent
  When Zoho posts "RequestSigningSuccess" for "rohan@example.com" to the company's webhook address signed with "nothing"
  Then the webhook response is 401
  And the signer "rohan@example.com" has eSign status "requested"

# E7 — zoho-sign-connections/Regenerated secret invalidates the old one
Scenario: After regenerating the secret, updates signed with the old one are refused
  Given the company had connected its Zoho account in "com" before the document was sent
  When the admin regenerates the webhook secret and confirms
  And Zoho posts "RequestSigningSuccess" for "rohan@example.com" to the company's webhook address signed with "arka-secret"
  Then the webhook response is 401
  And the signer "rohan@example.com" has eSign status "requested"

# E29 — zoho-esign/Forwarded then signed
Scenario: A signer forwards the request and the colleague's signature completes that slot
  Given the company had connected its Zoho account in "com" before the document was sent
  When Zoho posts "RequestForwarded" by "rohan@example.com" for the signer slot of "rohan@example.com" to the company's webhook address signed with "arka-secret"
  And Zoho posts "RequestSigningSuccess" by "sam@example.com" for the signer slot of "rohan@example.com" to the company's webhook address signed with "arka-secret"
  Then the signer "rohan@example.com" has eSign status "signed"
  And the signer "priya@example.com" has eSign status "requested"

# E32 — zoho-esign/Unknown request
Scenario: A signed update for a request CapHive does not know is acknowledged and ignored
  Given the company had connected its Zoho account in "com" before the document was sent
  When Zoho posts "RequestCompleted" for request "999" to the company's webhook address signed with "arka-secret"
  Then the webhook response is 200
  And the document's eSign status is "inprogress"

# X20 — zoho-esign/Update for another company's document
Scenario: Another company's address cannot change this company's document
  Given the company had connected its Zoho account in "com" before the document was sent
  And another company "Bodhi Partners" has its own Zoho connection with webhook secret "bodhi-secret"
  When Zoho posts "RequestRecalled" for the company's request to "Bodhi Partners"'s webhook address signed with "bodhi-secret"
  Then the webhook response is 200
  And the document's eSign status is "inprogress"

# X21 — zoho-esign/Missing signature refused (an address nobody was given)
Scenario: An unknown webhook address answers 404
  When Zoho posts "RequestCompleted" to the webhook address "nope"
  Then the webhook response is 404
