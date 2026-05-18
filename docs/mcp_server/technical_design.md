# CapHive MCP Server — Technical Design

## Overview

A Rails-native MCP (Model Context Protocol) server that exposes CapHive fund management data to external AI clients (Claude, ChatGPT, Gemini). Built using the official `mcp` gem (v0.15.0, Streamable HTTP), mounted inside the existing Rails application, reusing existing ActiveRecord models, Pundit policies, and data manager services.

---

## Architecture

### High-Level Flow

```
┌─────────────────┐                    ┌──────────────────────────────────────┐
│  Claude.ai (web) │──HTTP─────┐       │         CapHive Rails App            │
│  Claude Desktop  │           │       │                                      │
│  Claude Code     │           │       │  ┌──────────────────────────────┐    │
└─────────────────┘           │       │  │  McpController               │    │
                               ▼       │  │  POST /mcp (Streamable HTTP) │    │
┌─────────────────┐    ┌──────────┐    │  │                              │    │
│  ChatGPT        │──►│  OAuth   │───►│  │  ┌────────────────────────┐  │    │
│  (Connector)    │    │  2.1     │    │  │  │  McpAuthService        │  │    │
└─────────────────┘    │  + PKCE  │    │  │  │  Token → User/Entity  │  │    │
                       └──────────┘    │  │  └────────────────────────┘  │    │
                               ▲       │  │                              │    │
┌─────────────────┐           │       │  │  ┌────────────────────────┐  │    │
│  Gemini         │──HTTP──────┘       │  │  │  MCP Tools             │  │    │
│  (Enterprise)   │                    │  │  │  - ListFundsTool       │  │    │
└─────────────────┘                    │  │  │  - ...20+ tools        │  │    │
                                       │  │  └──────────┬─────────────┘  │    │
                                       │  └─────────────┼────────────────┘    │
                                       │                │                     │
                                       │                ▼                     │
                                       │  ┌──────────────────────────────┐    │
                                       │  │  Existing Data Layer         │    │
                                       │  │  - ActiveRecord Models       │    │
                                       │  │  - Data Manager Services     │    │
                                       │  │  - Pundit Policies           │    │
                                       │  │  - Entity Scoping            │    │
                                       │  └──────────────┬───────────────┘    │
                                       │                 │                    │
                                       │                 ▼                    │
                                       │           ┌──────────┐              │
                                       │           │  MySQL    │              │
                                       │           └──────────┘              │
                                       └──────────────────────────────────────┘
```

### Key Architectural Decisions

1. **Rails-native, not standalone** — mounted inside the existing Rails app via the official `mcp` gem, not a separate Python process. This means all tools reuse existing models, services, scopes, and policies.

2. **Reuse existing data managers** — the FM Assistant and Portfolio Assistant already have data manager services (`FundAssistantDataManager`, `PortfolioAssistantDataManager`) that handle Ransack queries, entity scoping, aggregations, and formatting. MCP tools call these same services.

3. **Streamable HTTP transport** — single `POST /mcp` endpoint via `McpController`. Works with all clients (Claude.ai, ChatGPT, Gemini, Claude Desktop, CLI). Stateless mode for multi-worker Puma compatibility.

4. **OAuth 2.1 authentication with PKCE** — All clients authenticate via OAuth 2.1 Authorization Code flow with PKCE (S256), powered by the Doorkeeper gem. Users log in via existing Devise session and authorize the AI client. PKCE is enforced via `force_pkce` in Doorkeeper config.

---

## Transport Compatibility Matrix

| AI Client | Transport | Auth Method | Status |
|---|---|---|---|
| Claude.ai (web) | Streamable HTTP | OAuth 2.1 + PKCE | **Working** |
| Claude Desktop | Streamable HTTP | OAuth 2.1 + PKCE | Untested |
| Claude Code / CLI | Streamable HTTP | OAuth 2.1 + PKCE | Untested |
| ChatGPT (Connector) | Streamable HTTP | OAuth 2.1 + PKCE | OAuth flow blocked (ngrok cookie issue) |
| Gemini Enterprise | Streamable HTTP | OAuth 2.1 + PKCE | Untested |
| Gemini CLI | Streamable HTTP | OAuth 2.1 + PKCE | Untested |

**Transport: Streamable HTTP** — single `POST /mcp` endpoint via `McpController`. Works with all clients. Stateless mode, no persistent connections.

### Transport Protocol Details

**Streamable HTTP (current implementation):**
```
Client sends:     POST /mcp  (JSON-RPC request, Authorization: Bearer <token>)
Server responds:  JSON-RPC response (application/json)
```
Single endpoint, no persistent connection. Stateless. Simpler to deploy behind load balancers.

**Note:** SSE transport is NOT used. The project switched from `fast-mcp` (SSE-only) to the official `mcp` gem (Streamable HTTP) in Phase 2.

---

## File Structure

```
config/
  initializers/
    doorkeeper.rb                        # OAuth 2.1 provider config (Doorkeeper) — PKCE enforced
  routes/
    ai.rb                               # post '/mcp' route
  routes.rb                             # use_doorkeeper, well-known metadata routes

app/controllers/
  oauth_metadata_controller.rb           # RFC 8414 + RFC 9728 metadata endpoints

app/packs/ai/mcp_server/
  controllers/
    mcp_controller.rb                    # McpController — auth + entity governance + MCP request handling
  tools/
    application_mcp_tool.rb              # Base class for all MCP tools (MCP::Tool)
    fund_tools/                          # Fund domain (✅ all working)
      list_funds_tool.rb                 # ✅ Working
      get_fund_details_tool.rb           # ✅ Working
      list_fund_ratios_tool.rb           # ✅ Working
    capital_tools/                       # Capital activity domain (✅ all working)
      list_capital_calls_tool.rb         # ✅ Working
      list_capital_commitments_tool.rb   # ✅ Working
      list_capital_distributions_tool.rb # ✅ Working
      list_capital_remittances_tool.rb   # ✅ Working
      list_capital_remittance_payments_tool.rb  # ✅ Working
      list_capital_distribution_payments_tool.rb  # ✅ Working
    portfolio_tools/                     # Portfolio domain (✅ all working)
      list_portfolio_companies_tool.rb   # ✅ Working
      get_portfolio_company_details_tool.rb  # ✅ Working
      list_portfolio_kpis_tool.rb        # ✅ Working
      list_valuations_tool.rb            # ✅ Working
      list_portfolio_investments_tool.rb # ✅ Working
      get_portfolio_company_snapshot_tool.rb  # ✅ Working
    cap_table_tools/                     # Cap table domain (✅ all working)
      get_cap_table_tool.rb              # ✅ Working
      get_investments_in_cap_table_tool.rb  # ✅ Working
    document_tools/                      # Document domain (✅ all working)
      list_documents_tool.rb             # ✅ Working
      get_document_tool.rb               # ✅ Working
    commitment_tools/                    # Commitment domain (✅ all working)
      get_commitment_details_tool.rb     # ✅ Working
      list_fund_units_tool.rb            # ✅ Working
      list_account_entries_tool.rb       # ✅ Working
  services/
    mcp_auth_service.rb                  # OAuth token validation + entity resolution
    mcp_audit_logger.rb                  # Audit logging for MCP tool calls (planned)

app/packs/core/entities/
  models/
    entity_setting.rb                    # MCP governance fields: mcp_enabled, mcp_allowed_roles, mcp_allowed_clients
  views/entities/
    _form_fields.html.erb                # Entity edit form — "AI Client Integration" section
    show.html.erb                        # Entity show page — MCP status display

app/packs/core/base/controllers/concerns/
  with_authentication.rb                 # Modified: after_sign_in_path_for reads oauth_return_to cookie

db/migrate/
  xxx_create_doorkeeper_tables.rb        # oauth_applications, oauth_access_grants, oauth_access_tokens
  20260512055236_add_entity_id_to_oauth_access_tokens.rb  # entity_id for multi-tenant scoping
```

---

## Implementation Details

### 1. Gem & Configuration

**Gemfile:**
```ruby
gem 'mcp'           # Official MCP Ruby SDK (v0.15.0) — Streamable HTTP
gem 'doorkeeper'     # OAuth 2.0/2.1 provider
```

**config/initializers/doorkeeper.rb (key settings):**
```ruby
Doorkeeper.configure do
  orm :active_record

  # Cookie-based return URL — survives Devise session fixation reset
  resource_owner_authenticator do
    if current_user
      current_user
    else
      cookies[:oauth_return_to] = { value: request.fullpath, httponly: true, secure: !Rails.env.development? }
      redirect_to new_user_session_url
      nil
    end
  end

  access_token_expires_in 30.days
  use_refresh_token
  custom_access_token_attributes [:entity_id]
  default_scopes :read
  base_controller 'ActionController::Base'
  reuse_access_token
  grant_flows %w[authorization_code password]
  force_pkce  # Enforce PKCE (S256) for all authorization code grants
end
```

**config/routes.rb (relevant sections):**
```ruby
use_doorkeeper_openid_connect
use_doorkeeper

get '/.well-known/oauth-authorization-server', to: 'oauth_metadata#show'
get '/.well-known/oauth-protected-resource', to: 'oauth_metadata#protected_resource'
```

**config/routes/ai.rb:**
```ruby
post '/mcp', to: 'mcp#create'
```

**app/controllers/oauth_metadata_controller.rb:**
```ruby
# Serves OAuth 2.0 Authorization Server Metadata (RFC 8414)
# and Protected Resource Metadata (RFC 9728) for MCP client discovery.
class OauthMetadataController < ActionController::API
  def show
    base_url = request.base_url
    render json: {
      issuer: base_url,
      authorization_endpoint: "#{base_url}/oauth/authorize",
      token_endpoint: "#{base_url}/oauth/token",
      response_types_supported: ["code"],
      grant_types_supported: ["authorization_code"],
      code_challenge_methods_supported: ["S256"],
      scopes_supported: ["read"]
    }
  end

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
```

### 2. Base Tool Class & Controller

**app/packs/ai/mcp_server/tools/application_mcp_tool.rb:**
```ruby
# frozen_string_literal: true

# Base class for all CapHive MCP tools.
class ApplicationMcpTool < MCP::Tool
  class << self
    def accessible_by?(_user)
      true
    end
  end
end
```

**app/packs/ai/mcp_server/controllers/mcp_controller.rb:**
```ruby
# frozen_string_literal: true

# Handles MCP (Model Context Protocol) requests from AI clients.
# Authenticates via OAuth bearer token, enforces entity governance, and delegates to MCP tools.
class McpController < ActionController::API
  before_action :authenticate_mcp!
  before_action :enforce_entity_governance!

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

  private

  def authenticate_mcp!
    token = request.headers['Authorization']&.sub(/^Bearer /i, '')
    result = McpAuthService.authenticate(token)
    @mcp_user = result.user
    @mcp_entity = result.entity
  rescue RuntimeError => e
    response.set_header('WWW-Authenticate', 'Bearer')
    render json: { error: e.message }, status: :unauthorized
  end

  # Enforces two-level MCP governance:
  # Level 1: CapHive admin gate — entity.permissions.enable_mcp? (bitflag, /admin/entities)
  # Level 2: Entity admin gate — entity_setting.mcp_enabled? (boolean, /entities/edit)
  # Level 3: Role allowlist — entity_setting.mcp_allowed_roles_list
  # Level 4: Client allowlist — entity_setting.mcp_allowed_clients_list (optional)
  def enforce_entity_governance!
    # Level 1: CapHive admin billing/license gate
    unless @mcp_entity.permissions.enable_mcp?
      render json: { jsonrpc: "2.0", id: nil,
        error: { code: -32_000, message: "MCP is not available for this organization. Contact CapHive to enable AI client integration." }
      }, status: :forbidden
      return
    end

    # Level 2: Entity admin self-serve toggle
    setting = @mcp_entity.entity_setting
    unless setting&.mcp_enabled?
      render json: { jsonrpc: "2.0", id: nil,
        error: { code: -32_001, message: "MCP is not enabled for this organization. Contact your administrator to enable AI client integration." }
      }, status: :forbidden
      return
    end

    # Level 3: Role allowlist
    allowed_roles = setting.mcp_allowed_roles_list
    unless allowed_roles.any? { |role| @mcp_user.has_role?(role) }
      render json: { jsonrpc: "2.0", id: nil,
        error: { code: -32_002, message: "Your role does not have MCP access. Contact your administrator to update allowed roles." }
      }, status: :forbidden
      return
    end

    # Level 4: Client allowlist (optional — empty means all allowed)
    allowed_clients = setting.mcp_allowed_clients_list
    if allowed_clients.present?
      app_name = @mcp_token&.application&.name
      unless allowed_clients.include?(app_name)
        render json: { jsonrpc: "2.0", id: nil,
          error: { code: -32_003, message: "This AI client (#{app_name}) is not authorized for your organization." }
        }, status: :forbidden
      end
    end
  end

  def authorized_tools
    [
      ListFundsTool,
      ListPortfolioCompaniesTool,
      GetPortfolioCompanyDetailsTool,
      ListPortfolioKpisTool,
      ListValuationsTool,
      ListPortfolioInvestmentsTool,
      GetPortfolioCompanySnapshotTool,
      GetCapTableTool,
      GetInvestmentsInCapTableTool
    ].select { |t| t.accessible_by?(@mcp_user) }
  end
end
```

### 3. Tool Implementation Pattern

Each MCP tool is a thin adapter over existing data manager methods. Tools use `input_schema()` (JSON Schema) and `def self.call(server_context:, ...)` class methods.

**app/packs/ai/mcp_server/tools/list_funds_tool.rb:**
```ruby
# frozen_string_literal: true

# MCP tool to list funds with committed, collected and distribution amounts.
class ListFundsTool < ApplicationMcpTool
  description "List all funds with committed, collected and distribution amounts. " \
              "Supports filtering, sorting, and aggregation."

  input_schema(
    properties: {
      scope: { type: "string",  description: "Filter: 'feeder_funds' or 'master_funds'" },
      query: { type: "object",  description: "Filter hash, e.g. { name_cont: 'Venture', currency_eq: 'USD' }" },
      sort: { type: "string", description: "Sort string, e.g. 'name asc', 'committed_amount_cents desc'" },
      limit: { type: "integer", description: "Limit number of results" },
      aggregate: { type: "string", description: "Aggregation: 'count', 'sum', or 'group_by'" },
      aggregate_field: { type: "string", description: "Field to aggregate on" },
      group_by_field: { type: "string", description: "Field to group results by" }
    }
  )

  def self.call(server_context:, scope: nil, query: {}, sort: nil,
                limit: nil, aggregate: nil, aggregate_field: nil, group_by_field: nil)
    data_manager = FundAssistantDataManager.new(user: server_context[:user])

    q = (query || {}).with_indifferent_access
    q[:aggregate_field] ||= aggregate_field if aggregate_field.present?
    q[:group_by] ||= group_by_field if group_by_field.present?

    data = data_manager.list_funds(
      scope: scope, query: q, sort: sort,
      limit: limit, aggregate: aggregate
    )

    MCP::Tool::Response.new([{ type: "text", text: data.to_json }])
  end
end
```

**Key differences from the RubyLLM tool pattern:**
1. Inherit from `ApplicationMcpTool` (which inherits `MCP::Tool`), not `FastMcp::Tool`
2. Use `input_schema()` with JSON Schema, not `arguments do ... end` DSL
3. Use `def self.call(server_context:, ...)` — class method, not instance method
4. Instantiate data manager with `server_context[:user]` only (entity resolved internally)
5. Return `MCP::Tool::Response.new(...)`, not raw `.to_json`
6. Do NOT include `required: []` in `input_schema` — the `mcp` gem rejects empty required arrays

### 4. Existing RubyLLM → MCP Tool Mapping

| Existing Tool (RubyLLM) | MCP Tool | Data Manager Method |
|---|---|---|
| `FundAssistantTools::ListFunds` | `ListFundsTool` | `data_manager.list_funds(...)` |
| `FundAssistantTools::GetFundDetails` | `GetFundDetailsTool` | `data_manager.get_fund_details(...)` |
| `FundAssistantTools::ListCapitalCalls` | `ListCapitalCallsTool` | `data_manager.list_capital_calls(...)` |
| `FundAssistantTools::ListCapitalCommitments` | `ListCapitalCommitmentsTool` | `data_manager.list_capital_commitments(...)` |
| `FundAssistantTools::ListCapitalRemittances` | `ListCapitalRemittancesTool` | `data_manager.list_capital_remittances(...)` |
| `FundAssistantTools::ListCapitalDistributions` | `ListCapitalDistributionsTool` | `data_manager.list_capital_distributions(...)` |
| `FundAssistantTools::ListCapitalRemittancePayments` | `ListCapitalRemittancePaymentsTool` | `data_manager.list_capital_remittance_payments(...)` |
| `FundAssistantTools::ListCapitalDistributionPayments` | `ListCapitalDistributionPaymentsTool` | `data_manager.list_capital_distribution_payments(...)` |
| `FundAssistantTools::ListPortfolioInvestments` | `ListPortfolioInvestmentsTool` | `data_manager.list_portfolio_investments(...)` |
| `FundAssistantTools::ListFundRatios` | `ListFundRatiosTool` | `data_manager.list_fund_ratios(...)` |
| `FundAssistantTools::ListAccountEntries` | `ListAccountEntriesTool` | `data_manager.list_account_entries(...)` |
| `PortfolioAssistantTools::ListPortfolioCompanies` | `ListPortfolioCompaniesTool` | `data_manager.list_portfolio_companies(...)` |
| `PortfolioAssistantTools::GetPortfolioCompanyDetails` | `GetPortfolioCompanyDetailsTool` | `data_manager.get_portfolio_company_details(...)` |
| `PortfolioAssistantTools::ListValuations` | `ListValuationsTool` | `data_manager.list_valuations(...)` |
| `PortfolioAssistantTools::ListPortfolioKpis` | `ListPortfolioKpisTool` | `data_manager.list_portfolio_kpis(...)` |
| `PortfolioAssistantTools::ListDocuments` | `ListDocumentsTool` | `data_manager.list_documents(...)` |
| `PortfolioAssistantTools::GetDocument` | `GetDocumentTool` | `data_manager.get_document(...)` |
| `PortfolioAssistantTools::AnalyzeDocument` | `AnalyzeDocumentTool` | `data_manager.analyze_documents(...)` |
| `PortfolioAssistantTools::GetCapTable` | `GetCapTableTool` | `data_manager.get_cap_table(...)` |
| `PortfolioAssistantTools::GetInvestmentsInCapTable` | `GetInvestmentsInCapTableTool` | `data_manager.get_investments_in_cap_table(...)` |

---

## Authentication & Authorization

### Phase 1 (Demo): Hardcoded Entity
```ruby
entity = Entity.find(157)
```

### Phase 2 (Current): OAuth 2.1 + PKCE Authentication

**Gem: `doorkeeper`** — OAuth 2.0/2.1 provider for Rails, integrates with Devise.

**Doorkeeper tables (generated by `doorkeeper:install`):**
- `oauth_applications` — registered AI clients (ChatGPT, Claude.ai, etc.)
- `oauth_access_grants` — authorization codes (short-lived)
- `oauth_access_tokens` — bearer tokens (used in MCP requests), with `entity_id` column

**OAuth endpoints (mounted by Doorkeeper):**
```
GET  /oauth/authorize   → consent screen (user logs in via Devise, authorizes app)
POST /oauth/token        → exchange auth code for access token
POST /oauth/revoke       → revoke a token
```

**MCP OAuth discovery endpoints (RFC 8414 + RFC 9728):**
```
GET /.well-known/oauth-authorization-server  → OAuth server metadata (issuer, endpoints, PKCE support)
GET /.well-known/oauth-protected-resource    → Protected resource metadata (MCP endpoint URL)
```
These are required by MCP clients (Claude.ai, ChatGPT) to auto-discover OAuth endpoints.

**Complete auth flow (verified working with Claude.ai):**
```
1. AI Client → POST /mcp (no token) → 401 + WWW-Authenticate: Bearer header
2. AI Client → GET /.well-known/oauth-protected-resource → discovers MCP resource + auth server URL
3. AI Client → GET /.well-known/oauth-authorization-server → discovers authorize/token endpoints + PKCE support
4. AI Client → GET /oauth/authorize?client_id=...&redirect_uri=...&response_type=code&code_challenge=...&code_challenge_method=S256
   → Doorkeeper's resource_owner_authenticator runs
   → User not logged in → save return URL in cookie → redirect to Devise login
5. User logs in via Devise → after_sign_in_path_for reads cookie → redirects back to /oauth/authorize
6. Doorkeeper shows consent screen → user clicks "Authorize"
7. Redirect to AI client callback with auth code
8. AI Client → POST /oauth/token (exchanges code + code_verifier for access_token)
9. AI Client → POST /mcp with Authorization: Bearer <token>
   → McpAuthService validates token via Doorkeeper → returns { user:, entity: }
   → Tool executes with user-scoped data
```

**Critical implementation detail — cookie-based OAuth return URL:**
Devise session fixation protection resets the session on sign-in, which clears `stored_location_for`. The solution is to save the OAuth return URL in a cookie (`oauth_return_to`) before redirecting to login, then read and delete it in `after_sign_in_path_for`. This is the standard pattern when Devise session fixation protection is enabled.

**For CLI/desktop clients** (Claude Code, Cursor, Gemini CLI):
- Uses OAuth with localhost redirect (`http://localhost:<port>/callback`)
- Client opens browser → user logs in → token returned to localhost → client stores token
- Similar to how `gh auth login` works for GitHub CLI

**McpAuthService implementation (app/packs/ai/mcp_server/services/mcp_auth_service.rb):**
```ruby
# frozen_string_literal: true

# Validates OAuth bearer tokens and resolves user + entity for MCP requests.
class McpAuthService
  Result = Struct.new(:user, :entity, keyword_init: true)

  # @param token [String] OAuth bearer token from Authorization header
  # @return [McpAuthService::Result] with user and entity
  def self.authenticate(token)
    raise 'Missing token' if token.blank?

    doorkeeper_token = Doorkeeper::AccessToken.by_token(token)
    raise 'Invalid or expired token' unless doorkeeper_token&.accessible?

    user = User.find(doorkeeper_token.resource_owner_id)
    entity = if doorkeeper_token.entity_id.present?
               Entity.find(doorkeeper_token.entity_id)
             else
               user.entity
             end

    Result.new(user: user, entity: entity)
  end
end
```

---

## Client Configuration Guides

### Claude.ai (Web App) — ✅ Verified Working

1. Go to Claude.ai → Settings → Customize → Connectors → Add custom connector
2. Enter the MCP server URL: `https://<your-domain>/mcp`
3. Claude.ai auto-discovers OAuth endpoints via `/.well-known/oauth-protected-resource` and `/.well-known/oauth-authorization-server`
4. On first use, Claude opens a browser popup for CapHive login → user authorizes → token stored automatically
5. Subsequent conversations reuse the stored token

**Doorkeeper OAuth Application setup:**
- Name: Claude.ai
- Redirect URI: `https://claude.ai/api/mcp/auth_callback`
- Scopes: read
- Confidential: false (public client — Claude.ai uses PKCE, no client secret)

### Claude Desktop / Claude Code

Claude Desktop and Claude Code support OAuth for MCP servers. On first connection, the client opens a browser window for CapHive login.

**Add MCP server via CLI:**
```bash
claude mcp add --transport http caphive https://app.caphive.com/mcp
```

**Or manually in config:**

Linux: `~/.config/Claude/claude_desktop_config.json`
macOS: `~/Library/Application Support/Claude/claude_desktop_config.json`

```json
{
  "mcpServers": {
    "caphive": {
      "url": "https://app.caphive.com/mcp"
    }
  }
}
```

On first use, Claude opens a browser for CapHive OAuth login. The token is stored automatically.

### ChatGPT (Connector)

1. Open ChatGPT → Settings → Connectors → Developer Mode → Advanced
2. Add Custom Connector
3. Server URL: `https://app.caphive.com/mcp`
4. Auth: OAuth 2.0 → authorize URL: `https://app.caphive.com/oauth/authorize`
5. ChatGPT auto-discovers tools

**Doorkeeper OAuth Application setup:**
- Name: ChatGPT
- Redirect URI: `https://chatgpt.com/connector/oauth/<connector_id>`
- Scopes: read
- Confidential: false

### Gemini Enterprise

1. Google Cloud Console → Gemini Enterprise → Data Stores
2. Create Data Store → Custom MCP Server
3. URL: `https://app.caphive.com/mcp` (Streamable HTTP)
4. Description: "CapHive fund management data"
5. Auth: OAuth 2.0 or service account
6. Wait for status: Active

### Gemini CLI

```bash
# Add to Gemini CLI settings
gemini mcp add caphive https://app.caphive.com/mcp --transport http
```

### Cursor IDE

Settings → MCP → Add Server:
```json
{
  "caphive": {
    "url": "https://app.caphive.com/mcp"
  }
}
```

---

## Deployment Architecture

### Staging (demo/testing)

```
CapHive Staging Server (existing)
  └── Rails app on port 3001
       ├── POST /mcp                                     (Streamable HTTP — MCP endpoint)
       ├── GET /.well-known/oauth-authorization-server    (RFC 8414 metadata)
       ├── GET /.well-known/oauth-protected-resource      (RFC 9728 metadata)
       ├── GET /oauth/authorize                           (Doorkeeper consent screen)
       └── POST /oauth/token                              (Token exchange)
```

### Production

```
CapHive Production
  └── Rails app behind Nginx/ALB
       ├── POST /mcp                                     (Streamable HTTP — all AI clients)
       ├── GET /.well-known/oauth-authorization-server    (RFC 8414 metadata)
       ├── GET /.well-known/oauth-protected-resource      (RFC 9728 metadata)
       ├── GET /oauth/authorize                           (OAuth consent screen)
       └── POST /oauth/token                              (Token exchange)
```

### Hosting Options for Demo

| Option | Pros | Cons |
|---|---|---|
| **Staging server** | Already deployed, real data | May affect staging stability |
| **Hostinger VPS** | Cheap ($5-10/mo), isolated | Need to deploy Rails + MySQL |
| **Railway/Render** | Easy deploy, free tier | May not have MySQL |
| **ngrok tunnel** | Free, instant, no deploy | Unstable for demos, URL changes |

**Recommendation:** Use staging server for team demo. For client-facing demo, consider a dedicated VPS or Railway deployment.

---

## Security Considerations

### Two-Level Entity Governance

MCP access is controlled by a two-level governance model that separates billing from configuration:

```
CapHive Admin (/admin/entities)          Entity Admin (/entities/edit)
─────────────────────────────           ──────────────────────────────
Level 1: enable_mcp permission           Level 2: mcp_enabled setting
  (bitflag on Entity via                   (boolean on EntitySetting)
   EntityEnabled concern)                  - Allowed roles (FM, LP)
  Managed by super/support roles           - Allowed AI clients
  Controls billing/licensing               Managed by company_admin role
                                           Controls self-serve config
```

**Level 1 — CapHive Admin gate (`entity.permissions.enable_mcp?`):**
- Part of the `EntityEnabled` concern's `flag :permissions` bitflag system (same mechanism as `enable_documents`, `enable_ai_chat`, etc.)
- Toggled only from the Administrate admin panel (`/admin/entities`) by users with `super` or `support` roles
- Acts as the billing/licensing gate — if CapHive hasn't enabled MCP for an entity, the feature is completely invisible (entity edit form hides the MCP section)
- Error code: `-32000`

**Level 2 — Entity Admin gate (`entity_setting.mcp_enabled?`):**
- Boolean field on `EntitySetting`, configurable from the entity's own edit form (`/entities/:id/edit`)
- Managed by users with the `company_admin` role within the entity
- Controls whether MCP is active for the entity (even after CapHive has enabled it)
- Also controls role allowlist (`mcp_allowed_roles`) and client allowlist (`mcp_allowed_clients`)
- Error code: `-32001`

**Level 3 — Role allowlist:** checks user role against `mcp_allowed_roles_list` (error `-32002`)
**Level 4 — Client allowlist:** checks OAuth app name against `mcp_allowed_clients_list` (error `-32003`, optional — empty means all allowed)

The Doorkeeper OAuth admin UI (`/oauth/applications`) is separately restricted to `super`/`support` roles via `admin_authenticator`, matching the same role check as `Admin::ApplicationController`.

### Data Protection
- All queries entity-scoped — no cross-tenant data leakage
- Read-only by default (no create/update/delete tools in Phase 1-3)
- Pundit policies applied — same authorization as web UI
- OAuth tokens managed by Doorkeeper (hashed, expirable, revocable)
- Users can view and revoke active tokens from CapHive settings UI

### Network Security
- HTTPS required for production (TLS 1.2+)
- CORS headers configured for known AI client origins
- Rate limiting per OAuth token (e.g., 100 requests/minute)
- IP allowlisting option for enterprise clients

### Audit & Compliance
- Every MCP tool call logged: user_id, entity_id, tool_name, params, timestamp
- Audit log accessible to entity admins
- Retention policy aligned with CapHive's data retention policy
- No PII in tool responses beyond what the user is authorized to see

### MCP-Specific Security
- PKCE enforced (`force_pkce` in Doorkeeper) — prevents authorization code interception
- `WWW-Authenticate: Bearer` header on 401 responses — triggers MCP client OAuth discovery
- `stateless: true` transport — no server-side sessions, safe for multi-worker Puma
- Tool filtering based on user role via `accessible_by?(user)` hook on `ApplicationMcpTool`. Currently returns `true` for all 23 tools (no per-role restriction yet). To add per-role filtering, override `accessible_by?` in individual tool classes. `McpController#authorized_tools` calls this at discovery time so restricted tools won't appear in `tools/list`. Planned for a future phase.

---

## Performance Considerations

- MCP tools call the same ActiveRecord queries as the web UI — same performance profile
- Ransack queries use database indexes (same as existing AG Grid searches)
- `limit` parameter enforced to prevent unbounded result sets
- No N+1 queries — data managers already use `includes` for eager loading
- SSE keepalive prevents connection timeouts behind proxies
- Connection pooling handled by Rails (ActiveRecord connection pool)

---

## Official `mcp` Gem Reference

### Tool Definition (JSON Schema)

```ruby
class MyTool < MCP::Tool
  description "What this tool does"

  input_schema(
    properties: {
      name: { type: "string", description: "Parameter description" },
      limit: { type: "integer", description: "Optional param" },
      filters: { type: "object", description: "Filter hash" }
    }
  )

  def self.call(server_context:, name: nil, limit: nil, filters: {})
    # server_context[:user] — authenticated user from OAuth token
    data = SomeDataManager.new(user: server_context[:user]).fetch(name: name, limit: limit)
    MCP::Tool::Response.new([{ type: "text", text: data.to_json }])
  end
end
```

### Key Differences from fast-mcp
- `MCP::Tool` base class (not `FastMcp::Tool`)
- `input_schema()` with JSON Schema (not `arguments do ... end` DSL)
- `def self.call(server_context:, ...)` — class method with `server_context` (not instance `def call`)
- Returns `MCP::Tool::Response` (not raw string)
- Do NOT include `required: []` — the gem's JSON Schema validator rejects empty required arrays
- Transport via `MCP::Server::Transports::StreamableHTTPTransport` (not `FastMcp.mount_in_rails`)
- No SSE — Streamable HTTP only

### Transport
- Single `POST /mcp` endpoint handled by `McpController`
- `MCP::Server.new(name:, version:, tools:, server_context:)` — creates the server
- `StreamableHTTPTransport.new(server, stateless: true)` — stateless mode, no in-memory sessions
- `transport.handle_request(request)` — returns `[status, headers, body]` Rack-style tuple

---

## Local Development & Testing

### What works on localhost

| Client | Localhost? | Notes |
|---|---|---|
| Claude Desktop | Yes | Local process → localhost:3001, OAuth via browser |
| Claude Code / CLI | Yes | Same — local process |
| Cursor IDE | Yes | Same — local process |
| Gemini CLI | Yes | Local process |
| MCP Inspector | Yes | Browser-based, runs locally |
| Claude.ai (web) | **No** | Anthropic servers can't reach localhost — use ngrok |
| ChatGPT Connector | **No** | OpenAI servers can't reach localhost — use ngrok |
| Gemini Enterprise | **No** | Google servers can't reach localhost — use ngrok |

### ngrok for ChatGPT / Gemini Enterprise

ChatGPT and Gemini Enterprise connectors need to reach the MCP server over the internet. Use **ngrok** to tunnel localhost.

**Setup:**
```bash
# Install ngrok (one-time)
curl -sSL https://ngrok-agent.s3.amazonaws.com/ngrok-v3-stable-linux-amd64.tgz \
  | sudo tar xvz -C /usr/local/bin
ngrok config add-authtoken YOUR_TOKEN   # free account at ngrok.com

# Start tunnel (each dev session)
ngrok http 3001
# → gives you https://abc123.ngrok-free.app
```

**Important:** The ngrok URL changes on every restart (free plan). For a stable subdomain, use ngrok paid ($8/mo). Update the `oauth_applications.redirect_uri` each time the URL changes (or use a paid fixed subdomain).

**With ngrok running:**

| Client | URL |
|---|---|
| Claude Desktop / Code | `http://localhost:3001/mcp` (no tunnel needed) |
| Claude.ai (web) | `https://abc123.ngrok-free.dev/mcp` |
| ChatGPT Connector | `https://abc123.ngrok-free.dev/mcp` |
| Gemini Enterprise | `https://abc123.ngrok-free.dev/mcp` |
| OAuth authorize | `https://abc123.ngrok-free.dev/oauth/authorize` |

**Dev workarounds required for ngrok (revert before production):**
- `SKIP_AUTHENTICITY_TOKEN=true rails s -p 3001` — bypasses CSRF for ngrok cross-domain login
- `config/initializers/session_store.rb`: `tld_length: 3` — correct cookie domain for `*.ngrok-free.dev` (production uses `tld_length: 2`)
- `config/environments/development.rb`: `config.hosts << /[a-z0-9-]+\.ngrok-free\.app/` — allow ngrok host
- `set_current_entity` in `with_authentication.rb`: early return for `ngrok-free` domain
- `grant_flows %w[authorization_code password]` — password grant enabled for curl testing

### Phase 2 Implementation Steps — ✅ COMPLETED

Phase 1 (hardcoded entity, `list_funds` tool with Claude Code) is complete. Phase 2 added OAuth authentication so any CapHive user can connect with their own identity. **Claude.ai web app successfully connected via OAuth 2.1 + PKCE on 2026-05-13.**

**Step 1: Add gems**
```bash
# Add to Gemfile
gem 'doorkeeper'

# Install
bundle install
```

**Step 2: Install Doorkeeper**
```bash
rails generate doorkeeper:install
rails generate doorkeeper:migration
```
This creates `config/initializers/doorkeeper.rb` and a migration for `oauth_applications`, `oauth_access_grants`, `oauth_access_tokens` tables.

**Step 3: Configure Doorkeeper initializer**

Edit `config/initializers/doorkeeper.rb` — set `resource_owner_authenticator` to use Devise, add `custom_access_token_attributes [:entity_id]`, set `grant_flows %w[authorization_code]`, set token expiry to 30 days. (See full config in Implementation Details section above.)

**Step 4: Add entity_id column to migration**

Before running the migration, add `entity_id` to the `oauth_access_tokens` table:
```ruby
# In the generated migration, add to the oauth_access_tokens create_table block:
t.bigint :entity_id, null: true
```

**Step 5: Run migration**
```bash
rails db:migrate
```

**Step 6: Add OAuth routes**

Create `config/routes/oauth.rb`:
```ruby
Rails.application.routes.draw do
  use_doorkeeper
end
```

**Step 7: Create OAuth application for Claude Desktop**

Via Rails console:
```ruby
app = Doorkeeper::Application.create!(
  name: 'Claude Desktop (Dev)',
  redirect_uri: 'http://127.0.0.1:4321/callback http://localhost:4321/callback',
  scopes: 'read',
  confidential: false
)
puts "Client ID: #{app.uid}"
puts "Client Secret: #{app.secret}"
```

Note: The redirect URI depends on what Claude Desktop sends during OAuth. Multiple URIs can be space-separated. Adjust after testing the actual redirect Claude sends.

**Step 8: Update McpAuthService**

Replace hardcoded entity lookup with Doorkeeper token validation. (See full implementation in Authentication & Authorization section above.)

**Step 9: Update ApplicationMcpTool**

Change `current_user` and `current_entity` to read from the request env (set by `filter_tools` in the initializer) instead of `Thread.current`:
```ruby
def current_entity
  @current_entity ||= Thread.current[:mcp_entity]
end

def current_user
  @current_user ||= Thread.current[:mcp_user]
end
```

**Step 10: Update fast_mcp initializer filter_tools**

Set `Thread.current` values after auth so tools can access them:
```ruby
server.filter_tools do |request, tools|
  token = request.env['HTTP_AUTHORIZATION']&.sub(/^Bearer /i, '')

  auth_result = McpAuthService.authenticate(token)
  Thread.current[:mcp_user] = auth_result.user
  Thread.current[:mcp_entity] = auth_result.entity

  tools.select { |t| t.accessible_by?(auth_result.user) }
end
```

**Step 11: Test the OAuth flow manually**

1. Start Rails: `rails s -p 3001`
2. Open browser: `http://localhost:3001/oauth/authorize?client_id=CLIENT_ID&redirect_uri=http://localhost:4321/callback&response_type=code`
3. Log in via Devise (e.g., `fm1@ian.com` / `password`)
4. Click "Authorize"
5. Browser redirects to `http://localhost:4321/callback?code=AUTH_CODE` (will fail since nothing listens — copy the code from the URL)
6. Exchange code for token:
```bash
curl -X POST http://localhost:3001/oauth/token \
  -d "grant_type=authorization_code" \
  -d "code=AUTH_CODE" \
  -d "client_id=CLIENT_ID" \
  -d "redirect_uri=http://localhost:4321/callback"
```
7. Use the returned `access_token` in MCP requests:
```bash
curl -N http://localhost:3001/mcp/sse \
  -H "Authorization: Bearer ACCESS_TOKEN"
```

**Step 12: Test with Claude Desktop**

Configure Claude Desktop to point to localhost and verify the full end-to-end flow: Claude opens browser → CapHive login → authorize → token stored → `list_funds` works with the logged-in user's entity.

---

## Testing

### MCP Inspector (visual testing)
```bash
npx @modelcontextprotocol/inspector
```
Opens a browser-based UI to discover tools, call them, inspect responses. Connect to `http://localhost:3001/mcp`.

### Curl testing (Streamable HTTP)
```bash
# Get OAuth token via password grant (dev only)
curl -X POST http://localhost:3001/oauth/token \
  -d "grant_type=password&username=fm1@ian.com&password=password&client_id=CLIENT_UID&scope=read"

# List available tools
curl -X POST http://localhost:3001/mcp \
  -H "Authorization: Bearer ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"tools/list","id":1}'

# Call a tool
curl -X POST http://localhost:3001/mcp \
  -H "Authorization: Bearer ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "method": "tools/call",
    "params": {
      "name": "list_funds",
      "arguments": { "limit": 5 }
    },
    "id": 2
  }'
```

### RSpec testing
```ruby
RSpec.describe ListFundsTool do
  let(:user) { create(:user) }
  let!(:fund) { create(:fund, entity: user.entity) }

  it "returns funds as JSON" do
    result = described_class.call(server_context: { user: user }, limit: 10)
    parsed = JSON.parse(result.content.first[:text])
    expect(parsed).to be_an(Array)
    expect(parsed.first["name"]).to eq(fund.name)
  end
end
```

---

## Known Issues / Deferred

| # | Priority | Issue | Reason Deferred |
|---|----------|-------|-----------------|
| 1 | ~~High~~ | ~~`admin_authenticator` in `doorkeeper.rb` allows any logged-in user to access `/oauth/applications`~~ | **RESOLVED** — restricted to `super`/`support` roles, matching `Admin::ApplicationController#authenticate_admin`. |
| 2 | High | `ListFundUnitsTool` calls private `perform_aggregation` via `.send` on `FundAssistantDataManager` — no public `list_fund_units` method exists on the data manager. All other 22 tools delegate to public methods; this is the only one reaching into internals. Fix: add a public `list_fund_units` method to `FundAssistantDataManager`. | Works correctly; encapsulation cleanup for a follow-up PR. |
| 3 | High | `access_token_expires_in 30.days` + `reuse_access_token` — wide exposure window for token theft. Consider reducing to `7.days` with refresh token rotation, or disabling `reuse_access_token` so each authorization creates a fresh token. AI clients (Claude.ai) support transparent refresh. | Acceptable for staging; must revisit before production deploy. |
| 4 | Medium | `mcp_allowed_roles` and `mcp_allowed_clients` stored as JSON strings in `string` columns — should be native `json` columns | Works correctly; schema change deferred to avoid migration churn. |
| 5 | Medium | `Doorkeeper::Application.all` queried in `_form_fields.html.erb` view — should be preloaded in controller | Small table; optimize when OAuth app count grows. |
| 6 | Low | Boilerplate duplication across 17 tools (query normalization, response building) — `ApplicationMcpTool` could provide helpers | Explicit code is fine; refactor when adding more tools. |
| 7 | Low | `show.html.erb` MCP settings rows use inconsistent indentation | Cosmetic; fix in next touch. |
