Feature: Provider webhooks prove who sent them, and a captured one cannot be replayed
  WATI (WhatsApp) and the Digio / DocuSign branches of /documents/signature_progress used to apply
  any post, so anyone could drive a user's WhatsApp agent by phone number or mark an agreement
  "signed". Now each environment's callback URL carries its own secret (?webhook_token=), and a
  DocuSign Connect HMAC is checked when DocuSign sends one. Refusal starts only when ops set
  WEBHOOK_TOKEN_ENFORCE=1; before that a post without the token is accepted and logged. With no
  token configured, development and test accept posts, as the Zoho webhook does.
  users_sync's signed requests are accepted once, and an UPSERT older than the last one applied is
  refused; a Zoho body is applied once, and an older Zoho event for the same signer is ignored.
  Design: docs/security/security_review_2026_10.md, "Authentication and session — Medium / Low",
  M1 and L9.

  # M1-H — Happy path: WATI's post carries this environment's token while enforcement is on; the message reaches the agent, without the secret
  Scenario: A WhatsApp message with the right token reaches the agent
    Given this environment's WhatsApp webhook token is "wati-in-secret"
    And webhook token enforcement is on
    And webhook side effects are recorded
    When WATI posts an inbound message with the webhook token "wati-in-secret"
    Then the webhook should be answered with 200
    And the WhatsApp message should have been handed to the agent without the webhook token

  # M1-H — Happy path: Digio's post carries the eSign token while enforcement is on; the update is applied, without the secret
  Scenario: A Digio notification with the right token is applied
    Given this environment's eSign webhook token is "esign-in-secret"
    And webhook token enforcement is on
    And webhook side effects are recorded
    When Digio posts a signed notification with the webhook token "esign-in-secret"
    Then the webhook should be answered with 200
    And the eSign update should have been applied without the webhook token

  # M1-1 — Error case: once enforced, a WhatsApp post with no token, a wrong token, or another region's token is refused and nothing reaches the agent
  Scenario Outline: A WhatsApp post without this environment's token is refused once enforced
    Given this environment's WhatsApp webhook token is "wati-in-secret"
    And webhook token enforcement is on
    And webhook side effects are recorded
    When WATI posts an inbound message with the webhook token "<token>"
    Then the webhook should be answered with 401
    And the WhatsApp message should not have been handed to the agent

    Examples:
      | token           |
      |                 |
      | guessed         |
      | wati-us-secret  |
      | wati-in-secre   |

  # M1-2 — Error case: once enforced, a Digio or DocuSign post with no token or a wrong one is refused and the agreement is not touched
  Scenario Outline: An eSign post without this environment's token is refused once enforced
    Given this environment's eSign webhook token is "esign-in-secret"
    And webhook token enforcement is on
    And webhook side effects are recorded
    When <provider> posts <notification> with the webhook token "<token>"
    Then the webhook should be answered with 401
    And the eSign update should not have been applied

    Examples:
      | provider | notification          | token   |
      | Digio    | a signed notification |         |
      | Digio    | a signed notification | guessed |
      | DocuSign | a completed envelope  |         |
      | DocuSign | a completed envelope  | guessed |

  # M1-3 — Edge case: a valid DocuSign Connect HMAC is proof enough without the URL token
  Scenario: A DocuSign post with a valid Connect HMAC is applied
    Given this environment's eSign webhook token is "esign-in-secret"
    And this environment's DocuSign Connect HMAC key is "connect-key-in"
    And webhook token enforcement is on
    And webhook side effects are recorded
    When DocuSign posts a completed envelope signed with the key "connect-key-in" and the webhook token ""
    Then the webhook should be answered with 200
    And the eSign update should have been applied without the webhook token

  # M1-3 — Error case: a forged DocuSign HMAC is refused even when the URL carries the right token
  Scenario: A DocuSign post with a wrong Connect HMAC is refused once enforced
    Given this environment's eSign webhook token is "esign-in-secret"
    And this environment's DocuSign Connect HMAC key is "connect-key-in"
    And webhook token enforcement is on
    And webhook side effects are recorded
    When DocuSign posts a completed envelope signed with the key "someone-elses-key" and the webhook token "esign-in-secret"
    Then the webhook should be answered with 401
    And the eSign update should not have been applied

  # M1-E — Edge case: during rollout (enforcement off) an untokened post is still applied, and logged so ops can see which dashboard still needs the new URL
  Scenario: Before enforcement an untokened post is accepted and logged
    Given this environment's WhatsApp webhook token is "wati-in-secret"
    And this environment's eSign webhook token is "esign-in-secret"
    And webhook token enforcement is off
    And webhook side effects are recorded
    When WATI posts an inbound message with the webhook token ""
    And Digio posts a signed notification with the webhook token ""
    Then the webhook should be answered with 200
    And the WhatsApp message should have been handed to the agent without the webhook token
    And the eSign update should have been applied without the webhook token
    And a warning should be logged that the "WhatsApp webhook" was accepted without authentication
    And a warning should be logged that the "eSign webhook" was accepted without authentication

  # M1-E — Edge case: in development and test with no token configured, posts are accepted even with enforcement on (the Zoho rule), so local webhook testing keeps working
  Scenario: With no token configured, the test environment accepts untokened posts
    Given this environment's WhatsApp webhook token is ""
    And this environment's eSign webhook token is ""
    And webhook token enforcement is on
    And webhook side effects are recorded
    When WATI posts an inbound message with the webhook token ""
    And Digio posts a signed notification with the webhook token ""
    Then the webhook should be answered with 200
    And the WhatsApp message should have been handed to the agent without the webhook token
    And the eSign update should have been applied without the webhook token

  # L9-H — Happy path: two signed UPSERTs in order are both applied
  @rack_test @cross-region-cache
  Scenario: Consecutive signed UPSERTs are both applied
    Given the server region is "US" and an HMAC secret is configured
    And a user exists via a prior UPSERT for "reid@example.com"
    And I prepare an UPSERT payload for "reid@example.com" from origin "IN" with roles "employee" existing "false"
    And the payload was built just now
    When I POST the signed request to "/internal/sync/users"
    Then the response status should be 200
    And the JSON response should include "applied" = true

  # L9-1 — Error case: the identical signed request sent again within the timestamp window is refused as a replay
  @rack_test @cross-region-cache
  Scenario: A replayed users_sync request is refused
    Given the server region is "US" and an HMAC secret is configured
    And I prepare an UPSERT payload for "replay@example.com" from origin "IN" with roles "employee" existing "false"
    When I POST the same signed request to "/internal/sync/users" twice
    Then the first copy should have been applied
    And the response status should be 409
    And the JSON response should include "error" = "replayed_request"

  # L9-2 — Edge case: an UPSERT built before the one already applied (slow, or replayed later with a fresh signature) is refused rather than rolling the user back
  @rack_test @cross-region-cache
  Scenario: An UPSERT older than the last one applied is refused
    Given the server region is "US" and an HMAC secret is configured
    And a user exists via a prior UPSERT for "ordered@example.com"
    And I prepare an UPSERT payload for "ordered@example.com" from origin "IN" with roles "employee" existing "false"
    And the payload was built 1 minute before the last update applied to "ordered@example.com"
    When I POST the signed request to "/internal/sync/users"
    Then the response status should be 409
    And the JSON response should include "reason" = "stale_event"

  # L9-2 — Edge case: a byte-identical Zoho body delivered again is acknowledged but applied once
  @zoho-http @cross-region-cache
  Scenario: The same Zoho body is applied once
    Given there is a user "" for an entity "entity_type=Investment Fund"
    And the esign provider is "Zoho"
    And there is an approved Zoho document "Arka Fund I - Q3 Statement"
    And the document is to be signed by "rohan@example.com,priya@example.com"
    And the document is out for signature
    And Zoho webhook deliveries are counted
    When Zoho posts "RequestSigningSuccess" for "rohan@example.com" performed 1 minute ago
    And Zoho posts the same body again
    Then the webhook should be answered with 200
    And the Zoho update should have been queued 1 time
    And the signer "rohan@example.com" has eSign status "signed"

  # L9-2 — Edge case: an older event for a signer arriving after a newer one is ignored, while another signer's event still applies
  @zoho-http @cross-region-cache
  Scenario: An older Zoho event for the same signer is ignored
    Given there is a user "" for an entity "entity_type=Investment Fund"
    And the esign provider is "Zoho"
    And there is an approved Zoho document "Arka Fund I - Q3 Statement"
    And the document is to be signed by "rohan@example.com,priya@example.com"
    And the document is out for signature
    When Zoho posts "RequestSigningSuccess" for "rohan@example.com" performed 2 minutes ago
    And Zoho posts "RequestRejected" for "rohan@example.com" performed 5 minutes ago
    And Zoho posts "RequestViewed" for "priya@example.com" performed 6 minutes ago
    Then the signer "rohan@example.com" has eSign status "signed"
    And the document's eSign status is "requested"
    And the Zoho webhook "RequestViewed" is in the eSign log
