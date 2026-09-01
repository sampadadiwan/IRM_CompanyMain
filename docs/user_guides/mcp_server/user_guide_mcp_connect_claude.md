# CapHive MCP Server — Admin Setup & Claude.ai Connection Guide

A step-by-step guide for CapHive admins and entity admins to enable MCP access and connect Claude.ai.

---

## What is This?

The CapHive MCP Server lets users query fund management data from CapHive using Claude.ai. Users authenticate via OAuth, and Claude can then call 23 read-only tools covering funds, capital activity, portfolios, cap tables, documents, and commitments.

**MCP URL:** `https://app.caphive.com/mcp`

---

## How It Works

Connecting Claude.ai to CapHive is a simple process:

1. A **CapHive admin** enables MCP for the entity (one-time)
2. An **entity admin** configures MCP settings — roles, allowed clients (one-time)
3. The **fund manager** pastes the MCP URL into Claude.ai → logs in → connected

No OAuth Client ID or Secret is needed. Claude registers itself automatically via Dynamic Client Registration (RFC 7591).

---

## Step 1: Enable MCP Permission (CapHive Admin)

This step is required before the entity can see or use MCP at all. Only CapHive admins (`super`/`support` role) can do this.

1. Log in as a CapHive admin
2. Go to **`/admin/entities`** (Administrate panel)
3. Find the entity and click **Edit**
4. Under **Permissions**, check **`enable_mcp`**
5. Save

This is the billing/licensing gate — it controls whether the entity has purchased MCP access. Without this, the "AI Client Integration" section won't appear on the entity's edit page.

> **Screenshot:** `[TODO: Screenshot of /admin/entities edit page with enable_mcp checkbox highlighted]`

---

## Step 2: Configure MCP Settings (Entity Admin)

Once the CapHive admin has enabled the `enable_mcp` permission, the entity's own admin can configure it:

1. Log in as an entity admin (`company_admin` role)
2. Go to **Entity Settings** → Edit your entity
3. Scroll to the **"AI Client Integration (MCP)"** section
4. Check **"Enable AI Client Integration"**
5. Under **Allowed Roles**, check the roles that should have MCP access:
   - **Fund Managers** (employee role)
   - **Investors / LPs** (investor role)
6. Under **Allowed AI Clients**, you can either:
   - Leave all unchecked → allows all AI clients
   - Check **"Claude"** → restricts to Claude only
7. Save

> **Screenshot:** `[TODO: Screenshot of entity edit page showing "AI Client Integration (MCP)" section with checkboxes]`

> **Important:** The allowed client name is **"Claude"** (not "Claude.ai"). This is the name Claude registers itself with during the automatic registration process.

---

## Step 3: Connect Claude.ai

This is what the fund manager (or any authorized user) does:

### Add the CapHive Connector

1. Go to [claude.ai](https://claude.ai) (desktop browser only — mobile is not supported)
2. Click **Settings** (gear icon) → **Integrations** → **Add More**
3. Enter the following:
   - **Name:** `CapHive` (or any name you prefer)
   - **URL:** `https://app.caphive.com/mcp`
   - No Client ID or Secret needed — Claude auto-registers automatically
4. Click **Add**

> **Screenshot:** `[TODO: Screenshot of Claude.ai Integrations page with "Add" dialog showing Name and URL fields]`

### Connect and Authorize

1. Click on the newly added **CapHive** connector
2. Click the **"Connect"** button
3. A browser popup opens with the CapHive login page
4. Log in with your credentials
5. You'll see an authorization prompt — click **"Authorize"**
6. The popup closes and you're connected

> **Screenshot:** `[TODO: Screenshot of CapHive OAuth authorization page]`

> **Screenshot:** `[TODO: Screenshot of Claude.ai showing "Connected" status with tools listed]`

### Test It

Start a new conversation on Claude.ai and try these queries:

- "List all my funds"
- "Show me capital calls for [fund name]"
- "What are the portfolio companies in my fund?"
- "Show me the cap table for [company name]"
- "What are the TVPI and IRR ratios for my funds?"

> **Screenshot:** `[TODO: Screenshot of Claude.ai conversation showing fund data response]`

---

## Available Tools (23)

Once connected, Claude can call these tools:

| Domain | Tools |
|---|---|
| **Funds** | `list_funds`, `get_fund_details`, `list_fund_ratios` |
| **Capital Activity** | `list_capital_calls`, `list_capital_commitments`, `list_capital_distributions`, `list_capital_remittances`, `list_capital_remittance_payments`, `list_capital_distribution_payments` |
| **Portfolio** | `list_portfolio_companies`, `get_portfolio_company_details`, `get_portfolio_company_snapshot`, `list_portfolio_investments`, `list_portfolio_kpis`, `list_valuations` |
| **Cap Table** | `get_cap_table`, `get_investments_in_cap_table` |
| **Documents** | `list_documents`, `get_document` |
| **Commitments** | `get_commitment_details`, `list_fund_units`, `list_account_entries` |

All tools are **read-only** — no data can be created, modified, or deleted through MCP.

---

## Troubleshooting

### "MCP is not available for this organization"

**Cause:** CapHive admin has not enabled `enable_mcp` for this entity.
**Fix:** Go to `/admin/entities` → Edit → check `enable_mcp` → Save.

### "MCP is not enabled for this organization"

**Cause:** Entity admin has not toggled MCP on.
**Fix:** Entity Settings → Edit → Enable "AI Client Integration" → Save.

### "Your role does not have MCP access"

**Cause:** User's role is not in the allowed roles list.
**Fix:** Entity admin → Edit entity → check the user's role under "Allowed Roles".

### "This AI client is not authorized for your organization"

**Cause:** Entity has restricted allowed AI clients, and "Claude" is not checked.
**Fix:** Entity admin → Edit entity → either uncheck all clients (allow all) or check **"Claude"**.

### "Missing token" or "Invalid or expired token"

**Cause:** OAuth flow not completed, or token expired (tokens last 30 days).
**Fix:** Disconnect and reconnect the connector in Claude.ai.

### Connection works but no data returned

**Cause:** User account may not have fund data.
**Fix:** Verify the user has funds/portfolios assigned in CapHive.

---

## Security

- **Two-level governance:** CapHive admin controls which entities have MCP access (billing gate). Entity admin configures roles and client restrictions (self-serve).
- **Read-only:** No create, update, or delete operations are possible through MCP.
- **User-scoped:** Every query returns only data the authenticated user is authorized to see. No cross-tenant data is ever exposed.
- **Automatic registration:** Claude registers itself as a public OAuth client using PKCE — no shared secrets.
- **Token lifetime:** Access tokens expire after 30 days with automatic refresh. Users can revoke access by disconnecting in Claude.ai.
- **Audit trail:** Every MCP tool call is logged for audit purposes.
- **OAuth admin panel** (`/oauth/applications`) is restricted to `super`/`support` roles only.

---

## Verification (Admin)

To verify the MCP server is running correctly on staging:

```bash
# Check MCP endpoint is live (should return "Missing token")
curl -X POST https://app.caphive.com/mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"initialize","id":1}'

# Check OAuth discovery metadata (should include registration_endpoint)
curl -s https://app.caphive.com/.well-known/oauth-authorization-server | python3 -m json.tool
```

---
