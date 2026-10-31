Feature: OAuth tokens are stored hashed, and tokens issued before the change keep working
  Doorkeeper stored access tokens, refresh tokens, authorization codes and client secrets in
  plaintext, so anyone holding a copy of the database (the production dump restored onto the dev
  box) held live tokens. Now they are stored as SHA-256 hashes. A row written before the change is
  still found and is rewritten hashed the first time it is used. reuse_access_token is off, because
  a hashed token cannot be handed out again: every authorization mints a new token.
  Design: docs/security/security_review_2026_10.md, "Authentication and session — Medium / Low",
  L2 (Phase 1).

  Background:
    Given there is a user "first_name=Hash-User" for an entity "entity_type=Investment Fund;name=Acme Hash;currency=INR"
    And the user's entity has MCP enabled

  # L2-H — Happy path: a token from the real OAuth flow works on /mcp, while the database holds only its hash
  Scenario: An MCP token from the OAuth flow is stored hashed and works
    When Claude.ai registers itself as "Claude"
    Then the registration should succeed
    When the user authorizes that client
    Then the access token should be stored hashed, not as issued
    When the MCP client posts the JSON-RPC method "tools/list"
    Then the MCP HTTP status should be 200
    And the MCP reply should list the "list_funds" tool

  # L2-H — Happy path: a mail add-in token is stored hashed and the add-in API still accepts it
  Scenario: A mail add-in token is stored hashed and works
    Given I have a mail add-in token
    Then the mail token should be stored hashed, not as issued
    When I search the mail API owners endpoint for "Acme"
    Then the mail API response status should be 200

  # L2-1 — Edge case: a token stored in plaintext before the upgrade still works and is rewritten hashed on first use
  Scenario: A token stored before the upgrade keeps working and is upgraded on use
    Given the user has an MCP access token
    And the user's MCP access token was stored in plaintext before the upgrade
    When the MCP client posts the JSON-RPC method "tools/list"
    Then the MCP HTTP status should be 200
    And the access token row should now be stored hashed

  # L2-E — Edge case: authorizing the same client again mints a new token instead of handing back the old one, and the earlier token stays live
  Scenario: A second authorization mints a new token
    When Claude.ai registers itself as "Claude"
    Then the registration should succeed
    When the user authorizes that client
    And the user authorizes that client again
    Then the second token should differ from the first and both should be live
