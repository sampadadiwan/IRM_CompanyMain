Feature: The MCP endpoint answers every JSON-RPC message with a single JSON body
  As an external AI client talking to CapHive over MCP
  I want unsupported protocol features declined with a JSON-RPC error
  So that a newer client never gets a 500 from the server

  # MCP 2026-07-28 clients (Claude Code 2.1.296+) open a `subscriptions/listen` stream for
  # list-changed notifications. The transport answers it with a streaming SSE body, and
  # McpController#create rendered `body.first` -- NoMethodError on a Proc, a 500 per client
  # connection. The server is stateless and pushes no notifications, so the method is declined.

  Background:
    Given there is a user "first_name=MCP-Client" for an entity "entity_type=Investment Fund;name=Acme MCP;currency=INR"
    And the user's entity has MCP enabled
    And the user has an MCP access token

  Scenario: subscriptions/listen is declined as an unsupported method, not a server error
    When the MCP client posts the JSON-RPC method "subscriptions/listen"
    Then the MCP HTTP status should be 200
    And the MCP reply should be a JSON-RPC error with code -32601 mentioning "subscriptions/listen"

  Scenario: ordinary requests still work after a declined listen
    When the MCP client posts the JSON-RPC method "subscriptions/listen"
    And the MCP client posts the JSON-RPC method "tools/list"
    Then the MCP HTTP status should be 200
    And the MCP reply should list the "list_funds" tool
