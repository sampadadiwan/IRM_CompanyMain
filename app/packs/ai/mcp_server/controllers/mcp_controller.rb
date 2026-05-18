# frozen_string_literal: true

# Handles MCP (Model Context Protocol) requests from external AI clients (Claude, ChatGPT, Gemini).
# Inherits from ActionController::API (not ApplicationController) to bypass Devise session auth —
# MCP clients authenticate via OAuth bearer tokens, not browser sessions.
#
# Request flow: authenticate_mcp! → enforce_entity_governance! → create (MCP tool execution)
#
# @see McpAuthService for token validation
# @see ApplicationMcpTool for tool base class
class McpController < ActionController::API
  before_action :set_mcp_cors_headers
  before_action :authenticate_mcp!, except: :preflight
  before_action :enforce_entity_governance!, except: :preflight

  # POST /mcp — JSON-RPC messages; GET /mcp — SSE for server-initiated messages (MCP Streamable HTTP)
  def create
    server = MCP::Server.new(
      name: "caphive-mcp",
      version: "1.0.0",
      tools: authorized_tools,
      server_context: { user: @mcp_user, entity: @mcp_entity }
    )
    transport = MCP::Server::Transports::StreamableHTTPTransport.new(
      server, stateless: true
    )
    status, headers, body = transport.handle_request(request)
    render json: body.first, status: status, headers: headers
  end

  # OPTIONS /mcp — CORS preflight; auth skipped so browsers can discover OAuth headers freely
  def preflight
    head :ok
  end

  private

  # Adds CORS headers so browser-based MCP clients (Claude.ai) can read the WWW-Authenticate
  # header and response body across origins. WWW-Authenticate must be explicitly exposed.
  def set_mcp_cors_headers
    response.set_header('Access-Control-Allow-Origin', request.headers['Origin'] || '*')
    response.set_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
    response.set_header('Access-Control-Allow-Headers', 'Content-Type, Authorization, Mcp-Session-Id')
    response.set_header('Access-Control-Expose-Headers', 'WWW-Authenticate, Mcp-Session-Id')
    response.set_header('Access-Control-Allow-Credentials', 'true')
  end

  # Extracts and validates the OAuth bearer token from the Authorization header.
  # Sets @mcp_user and @mcp_entity for use by governance checks and tool execution.
  # Returns 401 with WWW-Authenticate header on failure (triggers MCP client OAuth discovery).
  def authenticate_mcp!
    token = request.headers['Authorization']&.sub(/^Bearer /i, '')
    result = McpAuthService.authenticate(token)
    @mcp_user = result.user
    @mcp_entity = result.entity
    @mcp_token = result.doorkeeper_token
  rescue McpAuthService::AuthenticationError => e
    # Include resource_metadata so MCP clients (Claude.ai etc.) can discover the OAuth server via RFC 9728
    resource_metadata_url = "#{request.base_url}/.well-known/oauth-protected-resource"
    response.set_header('WWW-Authenticate', %(Bearer realm="#{request.base_url}", resource_metadata="#{resource_metadata_url}"))
    render json: { error: e.message }, status: :unauthorized
  end

  # Enforces two-level MCP governance before allowing tool execution.
  # Level 1: CapHive admin gate — entity.permissions.enable_mcp? (bitflag, managed at /admin/entities)
  # Level 2: Entity admin gate — entity_setting.mcp_enabled? (boolean, managed at /entities/edit)
  # Level 3: Role allowlist — entity_setting.mcp_allowed_roles_list
  # Level 4: Client allowlist — entity_setting.mcp_allowed_clients_list (optional)
  # @return [void] renders JSON-RPC error (codes -32000 to -32003) and halts on denial
  def enforce_entity_governance!
    unless @mcp_entity.permissions.enable_mcp?
      render json: {
        jsonrpc: "2.0", id: nil,
        error: { code: -32_000, message: "MCP is not available for this organization. Contact CapHive to enable AI client integration." }
      }, status: :forbidden
      return
    end

    setting = @mcp_entity.entity_setting

    unless setting&.mcp_enabled?
      render json: {
        jsonrpc: "2.0", id: nil,
        error: { code: -32_001, message: "MCP is not enabled for this organization. Contact your administrator to enable AI client integration." }
      }, status: :forbidden
      return
    end

    allowed_roles = setting.mcp_allowed_roles_list
    unless allowed_roles.any? { |role| @mcp_user.has_role?(role) }
      render json: {
        jsonrpc: "2.0", id: nil,
        error: { code: -32_002, message: "Your role does not have MCP access. Contact your administrator to update allowed roles." }
      }, status: :forbidden
      return
    end

    allowed_clients = setting.mcp_allowed_clients_list
    if allowed_clients.present?
      app_name = @mcp_token&.application&.name

      unless allowed_clients.include?(app_name)
        render json: {
          jsonrpc: "2.0", id: nil,
          error: { code: -32_003, message: "This AI client (#{app_name}) is not authorized for your organization." }
        }, status: :forbidden
      end
    end
  end

  # @return [Array<Class>] MCP tool classes accessible by the current user
  def authorized_tools
    [
      # Fund tools
      ListFundsTool,
      GetFundDetailsTool,
      ListFundRatiosTool,
      # Capital tools
      ListCapitalCallsTool,
      ListCapitalCommitmentsTool,
      ListCapitalDistributionsTool,
      ListCapitalRemittancesTool,
      ListCapitalRemittancePaymentsTool,
      ListCapitalDistributionPaymentsTool,
      # Portfolio tools
      ListPortfolioCompaniesTool,
      GetPortfolioCompanyDetailsTool,
      GetPortfolioCompanySnapshotTool,
      ListPortfolioInvestmentsTool,
      ListPortfolioKpisTool,
      ListValuationsTool,
      # Cap table tools
      GetCapTableTool,
      GetInvestmentsInCapTableTool,
      # Document tools
      ListDocumentsTool,
      GetDocumentTool,
      # Commitment tools
      GetCommitmentDetailsTool,
      ListFundUnitsTool,
      ListAccountEntriesTool
    ].select { |t| t.accessible_by?(@mcp_user) }
  end
end
