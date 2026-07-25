# CapHive MCP Server — OAuth & Multi-Tenancy Design

## The Question

> Should each tenant (entity) have its own OAuth Client ID and Secret, or should all tenants share one Client ID per AI client?

**Answer:** One Client ID per AI client (Claude.ai, ChatGPT, Gemini), shared across all tenants. Tenant isolation is handled by OAuth tokens and entity governance — not Client IDs.

---

## How It Works

```
Claude.ai (one Client ID)
    │
    ├── Fund Manager A logs in → Token X → scoped to Entity A (employee role)
    ├── Fund Manager B logs in → Token Y → scoped to Entity B (employee role)
    └── LP C logs in → Token Z → scoped to Entity A (investor role)
```

- **Client ID** identifies the AI application (Claude.ai, ChatGPT, Gemini)
- **OAuth Token** identifies the user — scoped to their entity, role, and permissions
- Every MCP query returns only data the authenticated user is authorized to see
- No cross-tenant data is ever exposed

---

## Why One Client ID Per AI Client (Not Per Tenant)

### 1. It's How the MCP Protocol Works

Claude.ai (and other MCP clients) store **one server URL** per connector. The OAuth auto-discovery flow (`.well-known/` endpoints) resolves to one set of OAuth endpoints with one Client ID. There is no mechanism in Claude.ai to use different Client IDs per user or tenant — it's one URL, one Client ID, multiple users.

Even if we created per-tenant Client IDs, Claude.ai has no way to use them.

### 2. It's Standard OAuth 2.0 Design

RFC 6749 (the OAuth 2.0 specification) defines the Client ID as:

> *"A unique string representing the registration information provided by the client."*

The "client" is the **application** (Claude.ai), not the end user or tenant. This is the same pattern used by every "Sign in with Google" or "Sign in with GitHub" integration — the app has one Client ID, each user gets their own token.

### 3. Per-Tenant Client IDs Would Be Impractical

| Approach | What It Means | Problem |
|---|---|---|
| One Client ID per AI client | One Doorkeeper app for Claude.ai, one for ChatGPT | Simple, standard, works with MCP protocol |
| One Client ID per tenant | Create a new Doorkeeper app every time a new entity signs up | Admin overhead, separate MCP URLs per entity, defeats multi-tenant architecture |
| One Client ID per user | Create a new Doorkeeper app per user | Completely unmanageable, no MCP client supports this |

---

## How Tenant Isolation Actually Works

Tenant isolation is enforced at **four levels**, none of which depend on the Client ID:

### Level 1: CapHive Admin Gate (Billing)
- `enable_mcp` permission flag on Entity (bitflag)
- Controlled by CapHive admins (`super`/`support` role) at `/admin/entities`
- If OFF → MCP is completely invisible to the entity

### Level 2: Entity Admin Gate (Configuration)
- `mcp_enabled` toggle on EntitySetting
- Controlled by entity admins (`company_admin` role)
- If OFF → MCP is disabled for the entity

### Level 3: Role Allowlist
- `mcp_allowed_roles` on EntitySetting
- Entity admin chooses which roles (Fund Managers, LPs) can connect
- Users with non-allowed roles get denied

### Level 4: Client Allowlist
- `mcp_allowed_clients` on EntitySetting
- Entity admin can restrict which AI clients are allowed
- Empty = all registered AI clients allowed

### Token-Level Isolation
- Every MCP request carries an OAuth Bearer token
- Token resolves to a specific user → specific entity
- All data queries are scoped to that user's entity and role via existing Pundit policies
- Same authorization layer as the web UI — no new data access paths

---

## Revocation Options

| Scope | How | Who Can Do It |
|---|---|---|
| **All entities, all AI clients** | Delete or rotate the Doorkeeper application | CapHive admin |
| **All entities, one AI client** | Delete that specific Doorkeeper application (e.g., Claude.ai) | CapHive admin |
| **One entity, all AI clients** | Uncheck `enable_mcp` permission (Level 1 gate) | CapHive admin |
| **One entity, self-serve** | Disable `mcp_enabled` toggle (Level 2 gate) | Entity admin |
| **One role in an entity** | Remove role from `mcp_allowed_roles` | Entity admin |
| **One AI client for an entity** | Add client restriction in `mcp_allowed_clients` | Entity admin |
| **One user** | Revoke their OAuth token | CapHive admin (via Rails console; UI planned for production) |

---

## Analogy

Think of it like a building with a shared front door (Client ID) but individual apartment keys (tokens):

- The **front door** recognizes that you're coming from a known delivery service (Claude.ai, ChatGPT)
- Your **apartment key** (token) only opens your apartment (entity) and your rooms (role-based data)
- The **building management** (CapHive admin) decides which floors get delivery access (enable_mcp)
- The **floor manager** (entity admin) decides which apartments accept deliveries (mcp_enabled, allowed roles)
- You don't need a separate front door per apartment — that would defeat the purpose of a shared building

---

## Summary

| Component | Identifies | Shared Across | Created By |
|---|---|---|---|
| **Client ID + Secret** | The AI application (Claude.ai) | All tenants | CapHive admin (one-time) |
| **OAuth Token** | The user + entity | Nothing — unique per user per app | Doorkeeper (automatic on login) |
| **Entity Governance** | Tenant-level access rules | Nothing — unique per entity | CapHive admin + Entity admin |

**One Client ID per AI client. One token per user. Tenant isolation via governance + token scoping.**

---

## Technical Walkthrough: Token → User → Entity → Scoped Data

Here's exactly what happens when an AI client sends an MCP request:

### Step 1: Extract Token

```
POST /mcp
Authorization: Bearer mpfUa7xGnwtGRuno4agwyI6_8dJnkyYxXEUmULdL26A
Content-Type: application/json
{"jsonrpc":"2.0","method":"tools/call","params":{"name":"list_funds"},"id":1}
```

`McpController#authenticate_mcp!` extracts the Bearer token from the Authorization header.

### Step 2: Token → User → Entity

```ruby
# McpAuthService resolves the token chain:

# 1. Look up the token
token = Doorkeeper::AccessToken.by_token("mpfUa7xGn...")
# → Token 64, resource_owner_id: 103, application_id: 2

# 2. Token → User
user = User.find(token.resource_owner_id)
# → User 103, email: fm1@demofund.com, entity_id: 892

# 3. User → Entity
entity = user.entity
# → Entity 892 (Demo Fund)
```

At this point we know: **who** is asking (User 103) and **which tenant** they belong to (Entity 892).

### Step 3: Entity Governance Check

```ruby
# Level 1: Does this entity have MCP access? (CapHive admin gate)
entity.permissions.enable_mcp?        # → true (bitflag check, zero DB queries)

# Level 2: Has entity admin enabled MCP? (Entity admin gate)
entity.entity_setting.mcp_enabled?    # → true

# Level 3: Is user's role allowed?
allowed_roles = entity.entity_setting.mcp_allowed_roles_list  # → ["employee", "investor"]
user.has_role?(:employee)             # → true (FM role)

# Level 4: Is this AI client allowed?
allowed_clients = entity.entity_setting.mcp_allowed_clients_list  # → [] (empty = all allowed)
# → passes
```

All four checks pass → request proceeds to tool execution.

### Step 4: Scoped Data Query

```ruby
# The MCP tool receives the user via server_context
def self.call(server_context:, **params)
  user = server_context[:user]  # → User 103 (fm1@demofund.com, Entity 892)

  # Data manager is initialized with this user
  data_manager = FundAssistantDataManager.new(user: user)

  # Internally, the data manager scopes ALL queries to this user's entity:
  # → SELECT * FROM funds WHERE entity_id = 892 AND ...
  # → Pundit policy further restricts based on role
  data = data_manager.list_funds
end
```

### What Another User from a Different Entity Sees

If Fund Manager B (User 51, Entity 473) sends the same `list_funds` request:

```ruby
# Same token lookup flow, but resolves to:
user = User.find(51)         # → User 51, entity_id: 473
entity = user.entity         # → Entity 473

# Data manager scoped to Entity 473:
data_manager = FundAssistantDataManager.new(user: user)
# → SELECT * FROM funds WHERE entity_id = 473 AND ...
```

**Same Client ID, same MCP endpoint, same tool — completely different data.** Entity 892 never sees Entity 473's funds and vice versa. The token is the isolation boundary, not the Client ID.

### Visual Summary

```
Claude.ai (Client ID: abc123)
    │
    ├── Token X ──→ User 103 ──→ Entity 892 ──→ SELECT * FROM funds WHERE entity_id = 892
    │                                            Returns: Fund Alpha, Fund Beta
    │
    └── Token Y ──→ User 51  ──→ Entity 473 ──→ SELECT * FROM funds WHERE entity_id = 473
                                                 Returns: Growth Fund I, Growth Fund II
```

Same door, different keys, different rooms, different data.
