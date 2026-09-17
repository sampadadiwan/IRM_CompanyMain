# frozen_string_literal: true

# Resolves an OAuth bearer token into the user and entity it was issued for.
#
# Shared by every token-authenticated surface: the MCP server (McpAuthService) and the
# mail add-in API used by the Outlook task pane and the Gmail add-on. Session cookies
# cannot serve those clients — Outlook frames the task pane cross-site, where a
# SameSite=Lax session cookie is never sent, and Apps Script has no browser session at all.
#
# The entity comes from the token's own custom `entity_id` attribute
# (`custom_access_token_attributes [:entity_id]` in config/initializers/doorkeeper.rb),
# falling back to the user's default entity for tokens issued before that existed.
class OauthBearerAuthenticator
  class AuthenticationError < StandardError; end

  Result = Struct.new(:user, :entity, :doorkeeper_token, keyword_init: true)

  # @param token [String] the raw bearer token, header prefix already stripped
  # @return [OauthBearerAuthenticator::Result]
  # @raise [AuthenticationError] when the token is missing, unknown, expired or revoked
  def self.authenticate(token)
    raise AuthenticationError, 'Missing token' if token.blank?

    doorkeeper_token = Doorkeeper::AccessToken.by_token(token)
    raise AuthenticationError, 'Invalid or expired token' unless doorkeeper_token&.accessible?

    user = User.find(doorkeeper_token.resource_owner_id)
    entity = if doorkeeper_token.entity_id.present?
               Entity.find(doorkeeper_token.entity_id)
             else
               user.entity
             end

    Result.new(user: user, entity: entity, doorkeeper_token: doorkeeper_token)
  end

  # Pulls the token out of an `Authorization: Bearer <token>` header.
  # @param request [ActionDispatch::Request]
  # @return [String, nil]
  def self.token_from(request)
    request.headers['Authorization']&.sub(/\ABearer /i, '')
  end
end
