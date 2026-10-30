@zoho-http
Feature: A company's own Zoho Sign account

  Company admins (and CapHive support) of a company whose eSign provider is Zoho can connect the
  company's own Zoho Sign account in any Zoho region from the company page. Zoho is a WebMock fake
  (features/support/zoho_sign_stub.rb). Each scenario names its worked example in
  openspec/changes/zoho-esign-production-ready/design.md#worked-examples.

Background:
  Given Im logged in as a user "" for an entity "entity_type=Investment Fund"
  And the user has role "company_admin"
  And the esign provider is "Zoho"

# H1 — zoho-sign-connections/Panel shown to a company admin on a Zoho company
Scenario: A company admin sees the Zoho eSign panel
  When the admin opens the company page
  Then the Zoho eSign panel shows "Using CapHive's"

# E1 — zoho-sign-connections/Panel hidden when the provider is not Zoho
Scenario: A Digio company has no Zoho eSign panel
  Given the esign provider is "Digio"
  When the admin opens the company page
  Then there is no Zoho eSign panel

# H2 — zoho-sign-connections/Successful connection
Scenario: Connecting with a fresh grant code
  When the admin connects Zoho with region "United States (sign.zoho.com)" and grant code "code-1"
  Then the Zoho eSign panel shows "Connected — documents sent from now on use"
  And the company is connected to Zoho in "com"
  And the panel shows the connection time
  And the grant code was exchanged at "accounts.zoho.com"

# E3 — zoho-sign-connections/Missing fields
Scenario: Blank fields are marked required and nothing reaches Zoho
  When the admin connects Zoho leaving the client secret and grant code blank
  Then the Zoho eSign panel shows "Client secret is required"
  And the Zoho eSign panel shows "Grant code is required"
  And the company has no Zoho connection
  And nothing was sent to Zoho's accounts server

# E4 — zoho-sign-connections/Region outside the list refused
Scenario: A region outside the list is refused
  When a direct "post" request with region "xx" is sent to the company's Zoho connection
  Then the request is refused
  And the company has no Zoho connection
  And nothing was sent to Zoho's accounts server

# X3 — zoho-sign-connections/Expired grant code
Scenario: An expired grant code saves nothing
  Given Zoho will refuse "token" with error "invalid_code"
  When the admin connects Zoho with region "United States (sign.zoho.com)" and grant code "old-code"
  Then the Zoho eSign panel shows "Zoho did not accept the grant code — it may have expired or already been used."
  And the company has no Zoho connection

# X4 — zoho-sign-connections/Wrong region
Scenario: A Client ID unknown in the chosen region saves nothing
  Given Zoho will refuse "token" with error "invalid_client"
  When the admin connects Zoho with region "India (sign.zoho.in)" and grant code "code-1"
  Then the Zoho eSign panel shows "Zoho did not recognise this Client ID in the India region."
  And the company has no Zoho connection
  And the grant code was exchanged at "accounts.zoho.in"

# E5 — zoho-sign-connections/Successful connection (two requests at once)
Scenario: Two connect requests at once leave one connection
  When two connect requests for the company arrive together
  Then the company has exactly one Zoho connection
  And the second connect request is told "This company is already connected to Zoho."

# E8 — zoho-sign-connections/Secrets kept out of logs
Scenario: The client secret and grant code never reach the request log
  Then the client secret and grant code are filtered from the request log

# H3 — zoho-sign-connections/Secret revealed once; Secret not shown again
Scenario: The webhook secret is shown once
  Given the company has connected its Zoho account in "com"
  When the admin clicks "Show webhook secret" on the Zoho eSign panel
  Then the webhook secret is shown
  And the panel offers only to regenerate the webhook secret

# H4 — zoho-sign-connections/Verification succeeds
Scenario: Verifying a working connection
  Given the company has connected its Zoho account in "com"
  When the admin clicks "Verify connection" on the Zoho eSign panel
  Then the Zoho eSign panel shows "Connection verified"
  And the company's Zoho connection is "connected"

# X7 — zoho-sign-connections/Verification fails on credentials
Scenario: Zoho rejecting the stored credentials marks the connection for reconnecting
  Given the company has connected its Zoho account in "com"
  And Zoho will refuse "list" with status 401
  When the admin clicks "Verify connection" on the Zoho eSign panel
  Then the Zoho eSign panel shows "Zoho rejected the stored credentials. Reconnect with a new grant code."
  And the company's Zoho connection is "needs_reauth"
  And the company admins are emailed once that the Zoho account needs reconnecting

# H14 — zoho-sign-connections/Reconnect after revocation
Scenario: Reconnecting keeps the original connected on time
  Given the company has connected its Zoho account in "com"
  And the company's Zoho account needs reconnecting
  When the admin reconnects Zoho with grant code "code-2" leaving the client secret blank
  Then the Zoho eSign panel shows "Connected — documents sent from now on use"
  And the company's Zoho connection is "connected"
  And the company's Zoho connection keeps its original connected on time

# E6 — zoho-sign-connections/Reconnect after revocation (blank secret keeps the stored one)
Scenario: Reconnecting with a blank client secret uses the stored one
  Given the company has connected its Zoho account in "com"
  When the admin reconnects Zoho with grant code "code-2" leaving the client secret blank
  Then the grant code was exchanged with the stored client secret
  And the company's Zoho connection is "connected"

# X5 — zoho-sign-connections/Failed reconnect changes nothing
Scenario: A failed reconnect leaves the connection as it was
  Given the company has connected its Zoho account in "com"
  And the company's Zoho account needs reconnecting
  And Zoho will refuse "token" with error "invalid_code"
  When the admin reconnects Zoho with grant code "old-code" leaving the client secret blank
  Then the Zoho eSign panel shows "Zoho did not accept the grant code"
  And the company's Zoho connection is "needs_reauth"
  And the company's Zoho connection still has its original credentials

# H16 — zoho-sign-connections/Disconnect allowed
Scenario: Disconnecting when nothing is out for signature
  Given the company has connected its Zoho account in "com"
  When the admin disconnects the Zoho account and confirms
  Then the Zoho eSign panel shows "Using CapHive's"
  And the company has no Zoho connection

# X6 — zoho-sign-connections/Disconnect refused with documents out
Scenario: Disconnecting is refused while documents are out for signature
  Given the company has connected its Zoho account in "com"
  And 3 documents are out for signature on the company's Zoho account
  When the admin disconnects the Zoho account and confirms
  Then the Zoho eSign panel shows "3 documents are still out for signature on this account. Wait for them to finish or cancel them first."
  And the company has exactly one Zoho connection

# X1 — zoho-sign-connections/Non-admin cannot connect
Scenario: A user who is not a company admin cannot connect
  Given "Asha" is a user of the company without the company admin role
  And "Asha" is logged in
  When a direct "post" request with region "com" is sent to the company's Zoho connection
  Then the request is refused
  And the company has no Zoho connection

# X2 — zoho-sign-connections/Admin of another company cannot touch the connection
Scenario: A company admin of another company cannot change or remove the connection
  Given the company has connected its Zoho account in "com"
  And "Kabir" is a company admin of another company
  And "Kabir" is logged in
  When a direct "delete" request with region "com" is sent to the company's Zoho connection
  Then the request is refused
  And the company has exactly one Zoho connection
  When a direct "patch" request with region "jp" is sent to the company's Zoho connection
  Then the request is refused
  And the company's Zoho connection still has its original credentials
