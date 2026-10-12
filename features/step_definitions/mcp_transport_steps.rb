# frozen_string_literal: true

# Drives POST /mcp end to end (OAuth bearer token → governance gates → transport) through a
# Rack::Test session, as an MCP client would. Covers features/ai/mcp_server/mcp_transport.feature.

# A minimal MCP-over-HTTP client: one Rack::Test session posting JSON-RPC messages
class McpHttpClient
  include Rack::Test::Methods

  def initialize(token)
    @token = token
  end

  def app
    Rails.application
  end

  # Posts one JSON-RPC request and returns the Rack response
  def rpc(method, params: {})
    header "Authorization", "Bearer #{@token}"
    header "Content-Type", "application/json"
    header "Accept", "application/json, text/event-stream"
    post "/mcp", { jsonrpc: "2.0", id: "#{method}:1", method:, params: }.to_json
    last_response
  end
end

Given("the user's entity has MCP enabled") do
  # Gate 1 (CapHive admin permission) and gate 2 (the entity's own switch); the default allowed
  # role (employee) covers the user, and no client allowlist is set
  @entity.permissions.set(:enable_mcp)
  @entity.save!(validate: false)
  setting = @entity.entity_setting || @entity.build_entity_setting
  setting.update!(mcp_enabled: true)
end

Given("the user has an MCP access token") do
  app = Doorkeeper::Application.create!(name: "Cucumber MCP client", redirect_uri: "http://localhost/callback", scopes: "read")
  @mcp_token = Doorkeeper::AccessToken.create!(application: app, resource_owner_id: @user.id, entity_id: @entity.id,
                                               scopes: "read", expires_in: 1.hour.to_i).token
end

When("the MCP client posts the JSON-RPC method {string}") do |method|
  @mcp_client ||= McpHttpClient.new(@mcp_token)
  @mcp_response = @mcp_client.rpc(method)
end

Then("the MCP HTTP status should be {int}") do |status|
  expect(@mcp_response.status).to eq(status), "got #{@mcp_response.status}: #{@mcp_response.body.first(300)}"
end

Then("the MCP reply should be a JSON-RPC error with code {int} mentioning {string}") do |code, fragment|
  reply = JSON.parse(@mcp_response.body)
  expect(reply.dig("error", "code")).to eq(code)
  expect(reply.dig("error", "message")).to include(fragment)
end

Then("the MCP reply should list the {string} tool") do |tool_name|
  reply = JSON.parse(@mcp_response.body)
  expect(reply.dig("result", "tools").pluck("name")).to include(tool_name)
end
