# frozen_string_literal: true

# Base class for all CapHive MCP tools.
# Provides permission filtering; user/entity context comes via server_context.
class ApplicationMcpTool < MCP::Tool
  # @param _user [User] the authenticated user
  # @return [Boolean] whether this tool is accessible
  def self.accessible_by?(_user)
    true
  end
end
