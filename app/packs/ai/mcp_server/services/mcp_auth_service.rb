# frozen_string_literal: true

# Validates OAuth bearer tokens and resolves user + entity for MCP requests.
class McpAuthService
  class AuthenticationError < StandardError; end

  Result = Struct.new(:user, :entity, :doorkeeper_token, keyword_init: true)

  # @param token [String] OAuth bearer token from Authorization header
  # @return [McpAuthService::Result] with user and entity
  # @raise [McpAuthService::AuthenticationError] if token is missing, invalid, or expired
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
end
