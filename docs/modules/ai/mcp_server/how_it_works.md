# CapHive MCP Server — How It Works

A quick guide to how Claude.ai (or any AI client) connects to CapHive and answers fund-related questions using real data.

---

## What is MCP?

MCP (Model Context Protocol) is a standard that lets AI assistants like Claude, ChatGPT, and Gemini connect to external data sources. Think of it as a **USB port for AI** — one standard interface that works across all AI platforms.

With MCP, a fund manager can open Claude.ai and ask *"What are my top 5 funds by committed amount?"* — and Claude fetches the answer directly from CapHive.

---

## One-Time Setup (2 minutes)

### Step 1: Add the CapHive connector in Claude.ai

```
Claude.ai → Settings → Customize → Connectors → Add custom connector
```

Enter the CapHive MCP server URL:
```
https://app.caphive.com/mcp
```

### Step 2: Authorize on first use

When you start a conversation and Claude needs CapHive data, a browser popup opens for CapHive login. This is the **OAuth flow** — the same pattern used by "Sign in with Google" or "Login with GitHub." Here's what happens step by step:

```
┌─────────────────────────────────────┐
│  Sign in to CapHive                 │
│                                     │
│  Email:    [fm@fundco.com        ]  │
│  Password: [••••••••             ]  │
│                                     │
│  [Sign In]                          │
└─────────────────────────────────────┘
            ↓
┌─────────────────────────────────────┐
│  Authorize Claude.ai?              │
│                                     │
│  Claude.ai is requesting access    │
│  to your CapHive account (read).   │
│                                     │
│  [Authorize]    [Deny]             │
└─────────────────────────────────────┘
```

That's it. The token is saved — you won't need to log in again for 30 days.

---

## The OAuth Flow — How Authentication Works

This is the core of how CapHive securely connects to AI clients without ever sharing the user's password.

### Key Concepts

**OAuth 2.1** is an authorization protocol. It lets a third-party app (Claude.ai) access a user's data on another service (CapHive) *without the user giving their password to Claude.ai*. Instead, the user logs in directly on CapHive and CapHive issues a temporary **access token** to Claude.

**Bearer Token** is like a hotel key card. When Claude.ai wants to fetch fund data, it sends this token in every request — `Authorization: Bearer abc123xyz`. CapHive checks the token, identifies who the user is, and returns only that user's data. The token itself doesn't contain the password — it's a random string that CapHive issued and can revoke at any time.

**PKCE** (Proof Key for Code Exchange, pronounced "pixie") is a security enhancement. Before starting the OAuth flow, Claude.ai generates a random secret (`code_verifier`) and sends a hashed version (`code_challenge`) to CapHive. When Claude.ai later exchanges the authorization code for a token, it must prove it knows the original secret. This prevents a man-in-the-middle from intercepting the authorization code and using it — they won't have the original secret.

**Redirect URI** is the URL that CapHive sends the user back to after they click "Authorize." For Claude.ai, this is `https://claude.ai/api/mcp/auth_callback`. CapHive only redirects to pre-registered URIs — so even if someone crafts a fake authorization link, the code goes back to the real Claude.ai, not to an attacker.

### The Complete Flow (9 Steps)

Here is exactly what happens from the moment a user asks Claude a question to the moment they get an answer, including every OAuth step:

```
PHASE 1: DISCOVERY
━━━━━━━━━━━━━━━━━━

Step 1: Claude tries to call CapHive (and gets rejected)
─────────────────────────────────────────────────────────

  Claude.ai                              CapHive
     │                                      │
     │  POST /mcp                           │
     │  (no token — first time)             │
     │─────────────────────────────────────►│
     │                                      │
     │  401 Unauthorized                    │
     │  WWW-Authenticate: Bearer            │
     │◄─────────────────────────────────────│

  Claude sees the 401 + "Bearer" header and knows:
  "I need an OAuth token. Let me find out where to get one."


Step 2: Claude discovers CapHive's OAuth endpoints
──────────────────────────────────────────────────

  Claude.ai                              CapHive
     │                                      │
     │  GET /.well-known/                   │
     │      oauth-protected-resource        │
     │─────────────────────────────────────►│
     │                                      │
     │  {                                   │
     │    "resource": ".../mcp",            │
     │    "authorization_servers": ["..."]   │
     │  }                                   │
     │◄─────────────────────────────────────│
     │                                      │
     │  GET /.well-known/                   │
     │      oauth-authorization-server      │
     │─────────────────────────────────────►│
     │                                      │
     │  {                                   │
     │    "authorization_endpoint":         │
     │       ".../oauth/authorize",         │
     │    "token_endpoint":                 │
     │       ".../oauth/token",             │
     │    "code_challenge_methods_supported":│
     │       ["S256"]                       │
     │  }                                   │
     │◄─────────────────────────────────────│

  Now Claude knows:
  - Where to send the user to log in (/oauth/authorize)
  - Where to exchange the code for a token (/oauth/token)
  - That PKCE with S256 is supported


PHASE 2: USER AUTHENTICATION
━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Step 3: Claude generates a PKCE secret and opens a browser popup
───────────────────────────────────────────────────────────────

  Claude.ai (internally):
    code_verifier  = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"  (random secret)
    code_challenge = SHA256(code_verifier) = "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"

  Claude opens a browser popup pointing to:

    https://app.caphive.com/oauth/authorize?
      client_id=NsBh9FIk5r...          ← identifies Claude.ai as the requesting app
      redirect_uri=https://claude.ai/api/mcp/auth_callback
      response_type=code               ← "give me an authorization code"
      code_challenge=E9Melh...         ← hashed PKCE secret
      code_challenge_method=S256       ← "I used SHA-256 to hash it"
      scope=read                       ← "I only need read access"


Step 4: CapHive redirects to login (Devise)
───────────────────────────────────────────

  Browser                             CapHive (Doorkeeper)
     │                                      │
     │  GET /oauth/authorize?...            │
     │─────────────────────────────────────►│
     │                                      │
     │  Doorkeeper checks: is user          │
     │  logged in? NO.                      │
     │                                      │
     │  Saves /oauth/authorize?... URL      │
     │  in a cookie (oauth_return_to)       │
     │                                      │
     │  302 Redirect to /users/sign_in      │
     │◄─────────────────────────────────────│

  Why a cookie? Because when Devise logs the user in (Step 5),
  it resets the session for security (session fixation protection).
  If we stored the return URL in the session, it would be lost.
  The cookie survives the session reset.


Step 5: User logs in via Devise
───────────────────────────────

  Browser                              CapHive (Devise)
     │                                      │
     │  User enters email + password        │
     │  POST /users/sign_in                 │
     │─────────────────────────────────────►│
     │                                      │
     │  Devise authenticates the user       │
     │  Resets session (security)           │
     │                                      │
     │  after_sign_in_path_for checks:      │
     │  → cookie oauth_return_to exists?    │
     │  → YES: redirect to that URL         │
     │  → Delete the cookie                 │
     │                                      │
     │  302 Redirect to /oauth/authorize?...│
     │◄─────────────────────────────────────│

  The user is now logged in AND back at the OAuth authorize page.


Step 6: User clicks "Authorize"
───────────────────────────────

  Browser                              CapHive (Doorkeeper)
     │                                      │
     │  GET /oauth/authorize?...            │
     │─────────────────────────────────────►│
     │                                      │
     │  Doorkeeper checks: is user          │
     │  logged in? YES.                     │
     │                                      │
     │  Shows consent screen:               │
     │  "Claude.ai wants read access"       │
     │  [Authorize] [Deny]                  │
     │◄─────────────────────────────────────│
     │                                      │
     │  User clicks [Authorize]             │
     │  POST /oauth/authorize (grant)       │
     │─────────────────────────────────────►│
     │                                      │
     │  Doorkeeper generates auth code      │
     │  (short-lived, ~10 minutes)          │
     │                                      │
     │  302 Redirect to:                    │
     │  https://claude.ai/api/mcp/          │
     │  auth_callback?code=AUTH_CODE_xyz    │
     │◄─────────────────────────────────────│

  The browser popup redirects back to Claude.ai with a
  one-time authorization code. The popup closes.


PHASE 3: TOKEN EXCHANGE
━━━━━━━━━━━━━━━━━━━━━━━

Step 7: Claude exchanges the code for an access token
─────────────────────────────────────────────────────

  Claude.ai                              CapHive (Doorkeeper)
     │                                      │
     │  POST /oauth/token                   │
     │  {                                   │
     │    grant_type: "authorization_code", │
     │    code: "AUTH_CODE_xyz",            │
     │    client_id: "NsBh9FIk5r...",       │
     │    redirect_uri: "https://claude.ai  │
     │      /api/mcp/auth_callback",        │
     │    code_verifier: "dBjftJeZ4CVP..."  │  ← PKCE: proves Claude is the original requester
     │  }                                   │
     │─────────────────────────────────────►│
     │                                      │
     │  Doorkeeper verifies:                │
     │  ✓ code is valid and not expired     │
     │  ✓ client_id matches                 │
     │  ✓ redirect_uri matches              │
     │  ✓ SHA256(code_verifier) matches     │
     │    the code_challenge from Step 3    │
     │                                      │
     │  {                                   │
     │    "access_token": "Bearer_abc123",  │
     │    "token_type": "Bearer",           │
     │    "expires_in": 2592000,            │  ← 30 days
     │    "refresh_token": "refresh_xyz",   │
     │    "scope": "read"                   │
     │  }                                   │
     │◄─────────────────────────────────────│

  Claude now has a Bearer token. It stores this securely.
  The authorization code is consumed — it can't be used again.


PHASE 4: DATA ACCESS
━━━━━━━━━━━━━━━━━━━━

Step 8: Claude calls the MCP tool with the token
─────────────────────────────────────────────────

  Claude.ai                              CapHive (McpController)
     │                                      │
     │  POST /mcp                           │
     │  Authorization: Bearer Bearer_abc123 │
     │  {                                   │
     │    "jsonrpc": "2.0",                 │
     │    "method": "tools/call",           │
     │    "params": {                       │
     │      "name": "list_funds",           │
     │      "arguments": {"limit": 5}       │
     │    }                                 │
     │  }                                   │
     │─────────────────────────────────────►│
     │                                      │
     │  McpAuthService:                     │
     │  ✓ Token valid + not expired         │
     │  ✓ User: fm@fundco.com (id: 21)     │
     │  ✓ Entity: Fund Company ABC (id: 42)│
     │                                      │
     │  ListFundsTool executes:             │
     │  → FundAssistantDataManager          │
     │  → SELECT funds WHERE entity_id=42   │
     │  → Only this user's funds returned   │
     │                                      │
     │  {                                   │
     │    "jsonrpc": "2.0",                 │
     │    "result": [fund data as JSON]     │
     │  }                                   │
     │◄─────────────────────────────────────│


Step 9: Claude formats and presents the answer
───────────────────────────────────────────────

  Claude receives the raw JSON and presents it naturally:

  "Here are your top 5 funds by committed amount:

   | Fund Name        | Currency | Committed     |
   |------------------|----------|---------------|
   | Growth Fund III  | USD      | $50,000,000   |
   | Venture Fund II  | USD      | $30,000,000   |
   | Asia PE Fund I   | SGD      | $25,000,000   |
   | ..."

  For all subsequent questions in this conversation (and future
  conversations), Claude reuses the stored Bearer token — no
  login needed again. Steps 1-7 are skipped entirely.
```

### How Does McpAuthService Know the User and Entity?

The Bearer token itself is just a random string — it doesn't contain any user information. All the mapping lives in the database. Here's how it works:

**When the token was created (Step 6-7):**

When the user clicked "Authorize," Doorkeeper's `resource_owner_authenticator` block ran:

```ruby
# config/initializers/doorkeeper.rb
resource_owner_authenticator do
  if current_user          # ← Devise's current_user (the logged-in user)
    current_user            # ← Doorkeeper stores this user's ID as resource_owner_id
  else
    # ...redirect to login
  end
end
```

Doorkeeper took the `current_user` (from Devise) and saved a row in the `oauth_access_tokens` table:

```
oauth_access_tokens table:
┌──────────────────┬────────────────────┬───────────┬───────┬─────────────┐
│ token            │ resource_owner_id  │ entity_id │ scope │ expires_at  │
├──────────────────┼────────────────────┼───────────┼───────┼─────────────┤
│ Bearer_abc123    │ 21                 │ NULL      │ read  │ 2026-06-12  │
└──────────────────┴────────────────────┴───────────┴───────┴─────────────┘
                     ↑
                     This is current_user.id from Devise at the time of authorization
```

**When the token is used (Step 8):**

Claude sends `Authorization: Bearer Bearer_abc123`. McpAuthService looks up the token and traces back to the user:

```ruby
# mcp_auth_service.rb
doorkeeper_token = Doorkeeper::AccessToken.by_token(token)
#                  ↑ finds the row above in oauth_access_tokens

user = User.find(doorkeeper_token.resource_owner_id)
#                ↑ resource_owner_id = 21 → User.find(21) → fm@fundco.com

entity = if doorkeeper_token.entity_id.present?
           Entity.find(doorkeeper_token.entity_id)
         else
           user.entity   # ← falls back to the user's default entity
         end
```

**The complete chain:**

```
Devise login → current_user (id: 21, fm@fundco.com)
    ↓
Doorkeeper saves resource_owner_id: 21 in oauth_access_tokens table
    ↓
Token "Bearer_abc123" is sent to Claude.ai
    ↓
Claude sends: Authorization: Bearer Bearer_abc123
    ↓
Doorkeeper::AccessToken.by_token("Bearer_abc123") → row with resource_owner_id: 21
    ↓
User.find(21) → fm@fundco.com
    ↓
user.entity → Entity (id: 42, "Fund Company ABC")
    ↓
ListFundsTool queries: SELECT * FROM funds WHERE entity_id = 42
```

The token is just a lookup key. The real identity mapping is in the database, created at authorization time and read at every MCP request.

### Summary: What Each Component Does

| Component | Role | Analogy |
|---|---|---|
| **OAuth 2.1** | Authorization protocol | The rules for how hotel key cards work |
| **PKCE** | Prevents code interception | Sealed envelope — only the original sender can open the reply |
| **Doorkeeper** (gem) | OAuth server inside Rails | The hotel front desk that issues key cards |
| **Devise** | User authentication | The ID check — proves you are who you say you are |
| **Authorization Code** | Temporary, one-time code | A claim ticket — exchange it for the real key card |
| **Bearer Token** | Long-lived access credential | The hotel key card itself — show it to access your room |
| **Refresh Token** | Renews expired Bearer tokens | Auto-renewal — get a new key card without going to the front desk again |
| **`/.well-known/` endpoints** | OAuth discovery (RFC 8414 + 9728) | The hotel directory — tells you where the front desk is |
| **`oauth_return_to` cookie** | Survives Devise session reset | A sticky note on the door — "come back here after checking in" |
| **McpAuthService** | Token validation + user lookup | The door lock — reads the key card and decides if you can enter |

### Why Not Just Use Username/Password?

The user *never* gives their CapHive password to Claude.ai. Here's why this matters:

1. **Password stays with CapHive** — Claude.ai never sees, stores, or transmits the password
2. **Revocable** — the user (or admin) can revoke Claude.ai's access without changing their password
3. **Scoped** — the token only grants `read` access, not full account control
4. **Time-limited** — tokens expire after 30 days
5. **Auditable** — every token usage is logged with user, entity, tool, and timestamp

This is the same pattern used by "Sign in with Google," GitHub OAuth, Slack integrations, etc.

---

## End-to-End Architecture

```
┌─────────────┐     ┌─────────────────────────────────────────────────┐
│             │     │              CapHive Rails App                  │
│  Claude.ai  │     │                                                 │
│  ChatGPT    │     │  ┌──────────────────────────────────────────┐   │
│  Gemini     │     │  │  OAuth Layer (Doorkeeper + Devise)       │   │
│             │     │  │                                          │   │
│             │     │  │  /.well-known/* → OauthMetadataController│   │
│  Step 1-2:  │     │  │  /oauth/authorize → Consent Screen      │   │
│  Discovery  │────►│  │  /oauth/token → Token Exchange          │   │
│             │     │  │  /users/sign_in → Devise Login          │   │
│             │     │  └──────────────────────────────────────────┘   │
│             │     │                                                 │
│  Step 8-9:  │     │  ┌──────────────────────────────────────────┐   │
│  Data calls │────►│  │  MCP Layer                               │   │
│  w/ Bearer  │     │  │                                          │   │
│  token      │     │  │  POST /mcp → McpController               │   │
│             │     │  │    → McpAuthService (validate token)     │   │
│             │◄────│  │    → MCP Tools (ListFundsTool, etc.)     │   │
│             │     │  │    → Data Managers (existing services)    │   │
│             │     │  │    → MySQL (entity-scoped queries)       │   │
│             │     │  └──────────────────────────────────────────┘   │
└─────────────┘     └─────────────────────────────────────────────────┘
```

---

## Security Model

```
┌──────────────────────────────────────────────────┐
│                                                  │
│  Every request is scoped to the logged-in user   │
│                                                  │
│  ✓  OAuth 2.1 + PKCE — no password shared       │
│  ✓  User sees only their entity's data           │
│  ✓  Read-only — no data can be modified          │
│  ✓  Same permissions as the CapHive web UI       │
│  ✓  Tokens expire after 30 days                  │
│  ✓  Users can revoke access anytime              │
│  ✓  All tool calls are logged and auditable      │
│                                                  │
└──────────────────────────────────────────────────┘
```

No data is stored by Claude — it queries CapHive in real-time and presents the results.

---

## What Can You Ask?

Currently available (Phase 2):
- **List funds** — with filtering, sorting, and aggregation

Coming next (Phase 3 — 20+ tools):
- Fund details, ratios, and performance metrics
- Capital calls, commitments, distributions
- Portfolio companies and valuations
- KPIs and account entries
- Documents

### Example questions a fund manager can ask:

```
"List all my funds"
"Show me USD funds sorted by committed amount"
"What is the total committed amount across all funds?"
"How many funds do I have grouped by currency?"
```

---

## Supported AI Platforms

| Platform | Status |
|---|---|
| Claude.ai (web) | **Working** |
| Claude Desktop | Ready (untested) |
| Claude Code (CLI) | Ready (untested) |
| ChatGPT | Configured (pending) |
| Gemini Enterprise | Ready (untested) |
| Gemini CLI | Ready (untested) |
| Cursor IDE | Ready (untested) |

One MCP server serves all platforms — build once, connect everywhere.
