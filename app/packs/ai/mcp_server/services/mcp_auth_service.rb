# frozen_string_literal: true

# Validates OAuth bearer tokens and resolves user + entity for MCP requests.
#
# The logic now lives in OauthBearerAuthenticator, shared with the mail add-in API.
# The error and result classes are aliased rather than subclassed so that existing
# `rescue McpAuthService::AuthenticationError` call sites keep working unchanged.
class McpAuthService
  AuthenticationError = OauthBearerAuthenticator::AuthenticationError
  Result = OauthBearerAuthenticator::Result

  # @param token [String] OAuth bearer token from Authorization header
  # @return [McpAuthService::Result] with user and entity
  # @raise [McpAuthService::AuthenticationError] if token is missing, invalid, or expired
  def self.authenticate(token)
    OauthBearerAuthenticator.authenticate(token)
  end
end
