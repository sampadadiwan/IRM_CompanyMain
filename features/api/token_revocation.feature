Feature: Security M4 / N6 - bearer tokens end with the account
  Web sessions and phones already ended on deactivation and password change; devise-api, OAuth
  (MCP / mail add-in) and Profile API tokens did not, and deactivating a firm flips its users with
  update_all, which skips every callback. Now a deactivated user's tokens are refused at use (the
  `active` column, so a short lockout does not break integrations), a deactivation revokes all of
  them, and a password change revokes OAuth and sign-in tokens - connectors re-authorise - while
  Profile API tokens keep running (revoked on deactivation only).
  Design: docs/security/security_review_2026_10.md, "Authentication and session — Medium / Low", M4 (incl. N6)

  Background:
    Given there is a user "first_name=Meera" for an entity "name=Acme Capital;entity_type=Investment Fund;enable_funds=true;currency=INR"
    And the user has role "company_admin"
    And there is a fund "name=Acme Growth Fund I;currency=INR" for the entity
    And "me" has the API token "Quarterly script"
    And the user's entity has MCP enabled
    And the user has an MCP access token

  # M4-H — Happy path: an active user's Profile API token and MCP token both work
  Scenario: M4-H An active user's tokens work
    When "me" sends GET "/funds.json"
    Then the API status is 200
    When the MCP client posts the JSON-RPC method "tools/list"
    Then the MCP HTTP status should be 200

  # M4-1 — Edge case (N6): the firm is deactivated by the cascade job's update_all; no token row is revoked, yet both tokens are refused at use
  Scenario: M4-1 Users of a deactivated firm are refused at once
    When the deactivation job for "Acme Capital" runs the way Sidekiq runs it
    And "me" sends GET "/funds.json"
    Then the API status is 401
    And the API token "Quarterly script" is still live
    When the MCP client posts the JSON-RPC method "tools/list"
    Then the MCP HTTP status should be 401

  # M4-2 — Error case: an admin deactivates the user; the MCP token is refused and the Profile API token is revoked
  Scenario: M4-2 A deactivated user's tokens are refused and revoked
    When an admin deactivates the user
    And the MCP client posts the JSON-RPC method "tools/list"
    Then the MCP HTTP status should be 401
    When "me" sends GET "/funds.json"
    Then the API status is 401
    And "me" has 0 live API tokens
    And the user's MCP access token is revoked

  # M4-3 — Edge case: a password change revokes the MCP token and the sign-in token, but the Profile API token keeps working
  Scenario: M4-3 A password change ends connectors, not Profile API tokens
    Given the user also has a token from the token sign-in endpoint
    When the user changes their password to "NewPassw0rd!23"
    And the MCP client posts the JSON-RPC method "tools/list"
    Then the MCP HTTP status should be 401
    And the sign-in token is refused on GET "/funds.json"
    When "me" sends GET "/funds.json"
    Then the API status is 200
    And "me" has 1 live API token
