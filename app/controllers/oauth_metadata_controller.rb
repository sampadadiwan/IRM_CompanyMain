# frozen_string_literal: true

# Serves OAuth 2.0 metadata endpoints required by MCP clients for auto-discovery.
# MCP clients (Claude.ai, ChatGPT, Gemini) fetch these before initiating the OAuth flow.
#
# @see https://datatracker.ietf.org/doc/html/rfc8414 RFC 8414 — Authorization Server Metadata
# @see https://datatracker.ietf.org/doc/html/rfc9728 RFC 9728 — Protected Resource Metadata
class OauthMetadataController < ActionController::API
  # GET /.well-known/oauth-authorization-server
  # Returns OAuth server metadata: endpoints, supported grant types, PKCE support.
  # @return [JSON] RFC 8414 Authorization Server Metadata
  def show
    render json: {
      issuer: root_url.chomp('/'),
      authorization_endpoint: "#{root_url.chomp('/')}/oauth/authorize",
      token_endpoint: "#{root_url.chomp('/')}/oauth/token",
      response_types_supported: ["code"],
      grant_types_supported: ["authorization_code"],
      code_challenge_methods_supported: ["S256"],
      scopes_supported: ["read"]
    }
  end

  # GET /.well-known/oauth-protected-resource
  # Returns protected resource metadata: MCP endpoint URL and required auth method.
  # @return [JSON] RFC 9728 Protected Resource Metadata
  def protected_resource
    base_url = request.base_url

    render json: {
      resource: "#{base_url}/mcp",
      authorization_servers: [base_url],
      scopes_supported: ["read"],
      bearer_methods_supported: ["header"]
    }
  end
end
