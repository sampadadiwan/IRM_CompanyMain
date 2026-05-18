# CapHive MCP Server — Team Testing Guide

A step-by-step guide for team members to test the CapHive MCP Server on staging with Claude.ai, ChatGPT, and Gemini.

---

## What is This?

The CapHive MCP Server allows external AI clients (Claude.ai, ChatGPT, Gemini) to query fund management data directly from CapHive. Users authenticate via OAuth, and the AI can then call 23 read-only tools covering funds, capital activity, portfolios, cap tables, documents, and commitments.

**Staging URL:** `https://dev.altconnects.com/mcp`

---

## Prerequisites

MCP access is controlled by a **two-level governance model**:

| Level | Who Controls | Where | What It Does |
|---|---|---|---|
| **Level 1: CapHive Admin** | `super` / `support` role | `/admin/entities` | `enable_mcp` permission flag — billing/licensing gate. If off, MCP is completely invisible to the entity. |
| **Level 2: Entity Admin** | `company_admin` role | Entity edit page | `mcp_enabled` toggle + role/client allowlists — self-serve configuration. |

Both levels must be enabled before users can connect. Section A covers the admin setup, Section B covers connecting AI clients.

---

## Section A: Admin Setup (One-Time)

### A0. Enable MCP Permission (CapHive Admin Only)

This step is required before the entity can see or use MCP at all. Only CapHive admins (`super`/`support` role) can do this.

1. Log in as a CapHive admin
2. Go to **`/admin/entities`** (Administrate panel)
3. Find the entity and click **Edit**
4. Under **Permissions**, check **`enable_mcp`**
5. Save

This is the billing/licensing gate — it controls whether the entity has purchased MCP access. Without this, the "AI Client Integration" section won't appear on the entity's edit page.

### A1. Enable MCP for Your Entity (Entity Admin)

Once the CapHive admin has enabled the `enable_mcp` permission, the entity's own admin can configure it:

1. Log in to staging as an entity admin (`company_admin` role): `https://dev.altconnects.com`
2. Go to **Entity Settings** → Edit your entity
3. Scroll to the **"AI Client Integration (MCP)"** section
4. Check **"Enable AI Client Integration"**
5. Under **Allowed Roles**, check the roles that should have MCP access:
   - **Fund Managers** (employee role)
   - **Investors / LPs** (investor role)
6. Under **Allowed AI Clients**, leave all unchecked to allow all registered clients (or check specific ones to restrict)
7. Save

> See the PDF version of this guide for screenshots of the entity edit page with MCP settings.

### A2. Register OAuth Applications (CapHive Admin Only)

Go to **`https://dev.altconnects.com/oauth/applications`**. This page is restricted to CapHive admins (`super`/`support` roles) only.

Click **"New Application"** and create an app for each AI client you want to test:

#### For Claude.ai

| Field | Value |
|---|---|
| **Name** | `Claude.ai` |
| **Redirect URI** | `https://claude.ai/api/mcp/auth_callback` |
| **Confidential** | Unchecked (No) |
| **Scopes** | `read` |

After saving, you'll see the **Client ID (UID)** and **Client Secret**. Note them down — though for Claude.ai the auto-discovery flow means you typically won't need to enter these manually.

#### For ChatGPT

| Field | Value |
|---|---|
| **Name** | `ChatGPT` |
| **Redirect URI** | `https://chatgpt.com/connector/oauth/gNcOlNVloekj` |
| **Confidential** | Unchecked (No) |
| **Scopes** | `read` |

> Note: The ChatGPT redirect URI contains a unique connector ID. You'll get this when setting up the connector in ChatGPT — see Section B2.

#### For Gemini

| Field | Value |
|---|---|
| **Name** | `Gemini` |
| **Redirect URI** | _(TBD — depends on Gemini's MCP connector callback URL)_ |
| **Confidential** | Unchecked (No) |
| **Scopes** | `read` |

### A3. Verify the Server is Accessible

Run this from your terminal to confirm the MCP endpoint is live:

```bash
curl -X POST https://dev.altconnects.com/mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"initialize","id":1}'
```

**Expected response:**
```json
{"error":"Missing token"}
```

This means the endpoint is live and auth is working (it correctly rejects unauthenticated requests).

To verify the OAuth discovery endpoints:

```bash
# OAuth server metadata
curl -s https://dev.altconnects.com/.well-known/oauth-authorization-server | python3 -m json.tool

# MCP resource metadata
curl -s https://dev.altconnects.com/.well-known/oauth-protected-resource | python3 -m json.tool
```

Both should return JSON with the OAuth endpoints and MCP resource info.

---

## Section B: Connecting Your AI Client

### B1. Claude.ai

#### Step 1: Add the CapHive Connector

1. Go to [claude.ai](https://claude.ai)
2. Click **Settings** (gear icon) → **Customize** → **Connectors**
3. Click the **"+"** button to add a new connector
4. Enter the following:
   - **Name:** `CapHive` (or any name you prefer)
   - **URL:** `https://dev.altconnects.com/mcp`
   - **Advanced settings:** Enter the Client ID from the Doorkeeper OAuth application (optional — Claude.ai can auto-discover it)
5. Click **Add**

#### Step 2: Connect and Authorize

1. Click on the newly added **CapHive** connector
2. Click the **"Connect"** button
3. A browser popup opens with the CapHive login page
4. Log in with your staging credentials (e.g., `fm1@ian.com` / `password`)
5. You'll see an authorization prompt — click **"Authorize"**
6. The popup closes and you're connected. You should see a green "Connected" status with all 23 tools listed.

#### Step 3: Test It

Start a new conversation on Claude.ai and try these queries:

```
List all my funds
```

```
Show me capital calls for Fund Alpha
```

```
What are the portfolio companies in my fund?
```

```
Show me the cap table for [company name]
```

> See the PDF version of this guide for screenshots of each step and a working example of Claude.ai returning fund data.

---

### B2. ChatGPT

#### Step 1: Add the CapHive Connector

1. Go to [chatgpt.com](https://chatgpt.com)
2. Click your profile → **Settings** → **Connected Apps** (or **Connectors**)
3. Click **"Add Connector"** → **"Custom"**
4. Enter the MCP server URL: `https://dev.altconnects.com/mcp`
5. ChatGPT will auto-discover the OAuth configuration from the `.well-known` endpoints

#### Step 2: Authorize

1. ChatGPT will redirect you to CapHive's login page
2. Log in with your staging credentials
3. Click **"Authorize"** on the consent screen
4. You'll be redirected back to ChatGPT

#### Step 3: Test It

Start a new conversation and try:

```
Using CapHive, list all my funds with their committed amounts
```

> Note: ChatGPT may require you to explicitly mention "CapHive" or select the connector when asking questions.

---

### B3. Gemini

_(Testing instructions will be added once Gemini MCP connector setup is confirmed.)_

---

## Available Tools (23 Total)

Once connected, the AI client can discover and call these tools:

### Fund Tools
| Tool | Description |
|---|---|
| `list_funds` | List all funds with committed, collected, distribution amounts |
| `get_fund_details` | Detailed info for a specific fund (terms, dates, currency) |
| `list_fund_ratios` | Fund performance ratios (TVPI, RVPI, DPI, IRR) |

### Capital Activity Tools
| Tool | Description |
|---|---|
| `list_capital_calls` | Capital calls with amounts, due dates, status |
| `list_capital_commitments` | Investor commitments per fund |
| `list_capital_distributions` | Distributions with gross amounts and dates |
| `list_capital_remittances` | Payments received and verification status |
| `list_capital_remittance_payments` | Individual remittance payment details |
| `list_capital_distribution_payments` | Individual distribution payment details |

### Portfolio Tools
| Tool | Description |
|---|---|
| `list_portfolio_companies` | Portfolio company list with filtering |
| `get_portfolio_company_details` | Detailed company info |
| `get_portfolio_company_snapshot` | Company snapshot summary |
| `list_portfolio_investments` | Investments (buys, sells, FMV, gains) |
| `list_portfolio_kpis` | Company KPIs (actuals, budgets, periods) |
| `list_valuations` | Per-share valuations with dates |

### Cap Table Tools
| Tool | Description |
|---|---|
| `get_cap_table` | Cap table for a portfolio company |
| `get_investments_in_cap_table` | Investments by investor, round, category |

### Document Tools
| Tool | Description |
|---|---|
| `list_documents` | Document listing with filtering |
| `get_document` | Document details and content |

### Commitment Tools
| Tool | Description |
|---|---|
| `get_commitment_details` | Commitment details for a specific investor/fund |
| `list_fund_units` | Fund unit/class breakdown |
| `list_account_entries` | Account-level transaction entries |

---

## Sample Queries to Try

Here are some practical queries to test the full range of tools:

### Fund Overview
- "List all my funds"
- "What is the total committed capital across all funds?"
- "Show me fund details for [fund name]"
- "What are the TVPI and IRR ratios for my funds?"

### Capital Activity
- "Show me all capital calls due this month"
- "List the capital commitments for [fund name]"
- "What distributions have been made from [fund name]?"
- "Show remittance payments for the latest capital call"

### Portfolio
- "List all portfolio companies"
- "Give me a snapshot of [company name]"
- "What investments have been made in [company name]?"
- "Show me the latest KPIs for [company name]"
- "What are the current valuations for [company name]?"

### Documents & Cap Table
- "List recent documents"
- "Show me the cap table for [company name]"
- "Who are the investors in [company name]'s cap table?"

### Cross-Domain Analysis
- "Compare the committed amounts across all my USD funds"
- "Which portfolio company has the highest FMV?"
- "Summarize the capital activity for [fund name] this quarter"

---

## Troubleshooting

### "MCP is not available for this organization" (error code -32000)

**Cause:** The CapHive admin has not enabled the `enable_mcp` permission for this entity.

**Fix:** Ask a CapHive admin (`super`/`support` role) to:
1. Go to `/admin/entities` → Edit the entity
2. Check `enable_mcp` under Permissions
3. Save

### "MCP is not enabled for this organization" (error code -32001)

**Cause:** The entity admin has not toggled MCP on in entity settings.

**Fix:** Ask an entity admin (`company_admin` role) to:
1. Go to Entity Settings → Edit
2. Enable "AI Client Integration"
3. Save

### "Your role does not have MCP access" (error code -32002)

**Cause:** Your user role (e.g., FM, LP) is not in the allowed roles list.

**Fix:** Ask an entity admin to check your role under "Allowed Roles" in the MCP settings.

### "This AI client is not authorized for your organization" (error code -32003)

**Cause:** The entity has restricted which AI clients can connect, and yours isn't in the list.

**Fix:** Ask an entity admin to add your AI client to the "Allowed AI Clients" list in Entity Settings, or uncheck all clients to allow all.

### "Authorization with the MCP server failed"

**Cause:** OAuth flow failed — could be any of the above governance checks, or the OAuth application isn't registered.

**Fix:** Check the staging Rails logs for the specific error. Common causes:
- Entity governance not enabled (see above)
- OAuth application not created for this AI client
- Redirect URI mismatch

### "Missing token" error

**Cause:** The AI client hasn't completed the OAuth flow yet.

**Fix:** Click "Connect" on the connector and complete the login/authorization flow.

### "Invalid or expired token"

**Cause:** Your OAuth token has expired (tokens last 30 days).

**Fix:** Disconnect and reconnect the connector to get a fresh token.

### Connection works but no data returned

**Cause:** The user account may not have data in the staging environment, or the query doesn't match any records.

**Fix:** Try logging in with a user that has fund data (e.g., `fm1@ian.com` on staging).

### OAuth login page doesn't appear

**Cause:** The `.well-known` metadata endpoints may not be configured correctly.

**Fix:** Verify by running:
```bash
curl -s https://dev.altconnects.com/.well-known/oauth-authorization-server | python3 -m json.tool
```
Should return JSON with `authorization_endpoint`, `token_endpoint`, etc.

---

## Security Notes

- **Two-level governance:** CapHive admins control which entities have MCP access (billing gate). Entity admins configure roles and client restrictions (self-serve).
- **Read-only access:** The MCP server only exposes read operations. No data can be created, modified, or deleted through MCP.
- **User-scoped:** Every query returns only data the authenticated user is authorized to see. No cross-tenant data is ever exposed.
- **OAuth admin restricted:** The Doorkeeper OAuth applications UI (`/oauth/applications`) is restricted to CapHive `super`/`support` roles only.
- **OAuth tokens:** Tokens expire after 30 days. Users can revoke tokens from the CapHive UI.
- **All requests are logged:** Every MCP tool call is recorded in the server logs for audit purposes.

---

## Architecture Overview (For Technical Team Members)

```
AI Client (Claude/ChatGPT/Gemini)
    │
    ▼
POST https://dev.altconnects.com/mcp
    │
    ▼
┌─────────────────────────────────┐
│  McpController                  │
│  ├─ authenticate_mcp!           │  ← Validates OAuth Bearer token
│  ├─ enforce_entity_governance!  │  ← Level 1: enable_mcp? → Level 2: mcp_enabled? → roles → clients
│  └─ create (MCP::Server)       │  ← Executes the requested tool
└─────────────────────────────────┘
    │
    ▼
┌─────────────────────────────────┐
│  MCP Tools (23 tools)           │
│  └─ Delegates to Data Managers  │  ← Same services used by FM/LP assistants
└─────────────────────────────────┘
    │
    ▼
┌─────────────────────────────────┐
│  MySQL (user-scoped queries)    │
└─────────────────────────────────┘
```

**Transport:** Streamable HTTP (single POST endpoint, stateless)
**Auth:** OAuth 2.1 with PKCE via Doorkeeper gem
**Discovery:** RFC 8414 + RFC 9728 `.well-known` metadata endpoints
**Governance:** Two-level — `Entity.permissions.enable_mcp?` (CapHive admin) + `EntitySetting.mcp_enabled?` (entity admin)
