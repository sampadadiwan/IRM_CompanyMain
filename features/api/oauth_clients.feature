Feature: OAuth clients are recognised by where their codes go, not by the name they chose
  Dynamic client registration (POST /oauth/registration) was open to any redirect URI and any name,
  the MCP "Allowed AI Clients" list matched apps by name, and the mail add-in was trusted by name —
  so anyone could register "Claude" (or "CapHive Mail Add-in") pointing at their own server. Now a
  client may register only with the callbacks of a known kind (config/mcp_clients.yml; no loopback,
  urn: or http:// outside development), first-party names are reserved, entity allowlists hold
  kinds matched by redirect URI, the mail add-in requires its server-created app, the consent page
  shows where the user will be sent, and token introspection is off.
  Design: docs/security/security_review_2026_10.md, "Authentication and session — Medium / Low",
  M2 and N5.

  Background:
    Given there is a user "first_name=MCP-User" for an entity "entity_type=Investment Fund;name=Acme OAuth;currency=INR"
    And the user's entity has MCP enabled

  # M2-H — Happy path: Claude.ai registers with its own callback, the consent page names claude.ai, and the token works where the entity allows only Claude
  Scenario: Claude.ai registers, the user consents, and MCP works
    Given the entity allows only the AI client "claude"
    When Claude.ai registers itself as "Claude"
    Then the registration should succeed
    And the registered client should be of the kind "claude"
    When the user opens the consent page for that client
    Then the consent page should say the user will be sent back to "claude.ai"
    When the user authorizes that client
    And the MCP client posts the JSON-RPC method "tools/list"
    Then the MCP HTTP status should be 200
    And the MCP reply should list the "list_funds" tool

  # M2-H — Happy path: ChatGPT's per-connector callback is its kind too
  Scenario: ChatGPT registers with its connector callback
    When a client registers itself as "ChatGPT" with the redirect URIs "https://chatgpt.com/connector/oauth/conn_8Hx2"
    Then the registration should succeed
    And the registered client should be of the kind "chatgpt"

  # M2-1 — Error case: a callback that belongs to no known kind (another host, a look-alike host, a loopback, an out-of-band urn, plain http, or one bad URI among good ones) is refused and no app is created
  Scenario Outline: A registration with an unknown callback is refused
    When a client registers itself as "Totally Claude" with the redirect URIs "<redirect_uris>"
    Then the registration should be refused with "invalid_redirect_uri"
    And no OAuth application named "Totally Claude" should exist

    Examples:
      | redirect_uris                                                                  |
      | https://evil.test/oauth/callback                                               |
      | https://claude.ai.evil.test/api/mcp/auth_callback                              |
      | https://claude.ai/api/mcp/auth_callback/../../steal                            |
      | http://localhost:4321/callback                                                 |
      | http://127.0.0.1:4321/callback                                                 |
      | urn:ietf:wg:oauth:2.0:oob                                                      |
      | http://claude.ai/api/mcp/auth_callback                                         |
      | https://claude.ai/api/mcp/auth_callback,https://evil.test/oauth/callback       |
      | https://claude.ai/api/mcp/auth_callback,https://chatgpt.com/connector/oauth/x1 |

  # M2-2 — Error case (N5): first-party names are reserved, however they are spelt, even with a valid callback
  Scenario Outline: A registration under a reserved name is refused
    When a client registers itself as "<name>" with the redirect URIs "https://claude.ai/api/mcp/auth_callback"
    Then the registration should be refused with "invalid_client_metadata"
    And no OAuth application named "<name>" should exist

    Examples:
      | name                 |
      | CapHive Mail Add-in  |
      | caphive mail add-in  |
      |  CapHive  Mail Add-in |
      | CapHive Support      |
      | Paperclip            |

  # M2-3 — Edge case (N5): an app named "CapHive Mail Add-in" that the server did not create (one registered before this gate) is not the mail add-in — its token is refused by the mail API and the add-ins keep using the server's own app
  Scenario: An impostor mail add-in app is not trusted
    Given an OAuth app "CapHive Mail Add-in" was registered earlier with the callback "https://evil.test/oauth/callback"
    And the user has a token for that app as their mail token
    When I search the mail API owners endpoint for "Acme"
    Then the mail API response status should be 403
    And that token should not count as a mail add-in token
    And the mail add-in tokens should still be issued by the server-created app

  # M2-4 — Error case: an allowlist saved by name ("Claude", before kinds) no longer admits an app that only calls itself Claude
  Scenario: An app named Claude with someone else's callback is refused by a Claude-only entity
    Given the entity allows only the AI client "Claude"
    And an OAuth app "Claude" was registered earlier with the callback "https://evil.test/oauth/callback"
    And the user has an MCP access token for that app
    When the MCP client posts the JSON-RPC method "tools/list"
    Then the MCP HTTP status should be 403
    And the MCP reply should be a JSON-RPC error with code -32003 mentioning "is not authorized for your organization"

  # M2-4 — Edge case: the same legacy "Claude" entry still admits the real Claude.ai client, which is now matched by its callback
  Scenario: A legacy name entry still admits the real client of that kind
    Given the entity allows only the AI client "Claude"
    And an OAuth app "Claude" was registered earlier with the callback "https://claude.ai/api/mcp/auth_callback"
    And the user has an MCP access token for that app
    When the MCP client posts the JSON-RPC method "tools/list"
    Then the MCP HTTP status should be 200
    And the MCP reply should list the "list_funds" tool

  # M2-4 — Error case: an entity that allows only ChatGPT refuses a genuine Claude.ai client
  Scenario: A client of a kind the entity does not allow is refused
    Given the entity allows only the AI client "chatgpt"
    And an OAuth app "Claude" was registered earlier with the callback "https://claude.ai/api/mcp/auth_callback"
    And the user has an MCP access token for that app
    When the MCP client posts the JSON-RPC method "tools/list"
    Then the MCP HTTP status should be 403
    And the MCP reply should be a JSON-RPC error with code -32003 mentioning "Claude (claude.ai)"

  # M2-X — Error case: token introspection is off, so not even a token's own client learns anything from it
  Scenario: Token introspection is refused
    When the client introspects another of the user's tokens
    Then neither introspection should report the token
