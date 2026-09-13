# CapHive MCP Server — Admin Setup & Claude.ai Connection Guide

A step-by-step guide for CapHive admins and entity admins to enable MCP access and connect Claude.ai.

> **Where to find it:** Entity admins: top-bar **Company menu → Company Profile** → **Edit** → **AI Client Integration (MCP)**, which appears once CapHive has enabled `enable_mcp` for the entity under [**Admin → Entities**](/admin/entities). Users then add the MCP URL as a connector in Claude.ai and authorise it. Configuring needs the **company_admin** role; connecting needs a role ticked under **Allow access for**.

---

## What is This?

The CapHive MCP Server lets users query fund management data from CapHive using Claude.ai. Users authenticate via OAuth, and Claude can then call 22 read-only tools covering funds, capital activity, portfolios, cap tables, documents, and commitments.

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

This step is required before the entity can see or use MCP at all. Only CapHive admins (`super` or `support` role) can do this.

1. Log in as a CapHive admin
2. Go to [**Admin → Entities**](/admin/entities) (Administrate panel)
3. Find the entity and click **Edit**
4. Under **Permissions**, check **`enable_mcp`**
5. Save

This is the billing/licensing gate — it controls whether the entity has purchased MCP access. Without this, the "AI Client Integration" section won't appear on the entity's edit page.

> **Screenshot:** `[TODO: Screenshot of /admin/entities edit page with enable_mcp checkbox highlighted]`

---

## Step 2: Configure MCP Settings (Entity Admin)

Once the CapHive admin has enabled the `enable_mcp` permission, the entity's own admin can configure it:

1. Log in as an entity admin (`company_admin` role)
2. Open the top-bar **Company menu** (the house icon at the top right) → **Company Profile** and click **Edit**
3. Scroll to the **"AI Client Integration (MCP)"** section
4. Check **"Enable AI Client Integration"**
5. Under **Allow access for**, check the roles that should have MCP access:
   - **Fund Managers** (employee role)
   - **Investors (LPs)** (investor role)
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

## Available Tools (22)

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
**Fix:** Go to [**Admin → Entities**](/admin/entities) → Edit → check `enable_mcp` → Save.

### "MCP is not enabled for this organization"

**Cause:** Entity admin has not toggled MCP on.
**Fix:** Company menu → Company Profile → Edit → tick "Enable AI Client Integration" → Save.

### "Your role does not have MCP access"

**Cause:** User's role is not in the allowed roles list.
**Fix:** Entity admin → Company Profile → Edit → check the user's role under "Allow access for".

### "This AI client is not authorized for your organization"

**Cause:** Entity has restricted allowed AI clients, and "Claude" is not checked.
**Fix:** Entity admin → Company Profile → Edit → under **Allowed AI Clients** either uncheck all clients (allow all) or check **"Claude"**.

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
- [**OAuth admin panel**](/oauth/applications) is restricted to `super` and `support` roles only.

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

## Frequently Asked Questions

### Navigation and getting there

**Where does an entity admin turn on MCP access in CapHive?**
Open the top-bar **Company menu → Company Profile**, click **Edit**, and scroll to **AI Client Integration (MCP)**. Tick **Enable AI Client Integration**, choose roles under **Allow access for**, optionally restrict **Allowed AI Clients**, and save.

**I don't see the AI Client Integration (MCP) section on the edit page. Why?**
The section only appears after CapHive has switched on the `enable_mcp` permission for your entity, which is a licensing step. Contact CapHive support to request it; see [Step 1](#step-1-enable-mcp-permission-caphive-admin).

**Where does a CapHive admin enable MCP for an entity?**
In the admin panel under [**Admin → Entities**](/admin/entities): find the entity, click **Edit**, tick `enable_mcp` under **Permissions** and save. Only `super` and `support` users can open it.

**What address do I give Claude.ai?**
The MCP URL of your CapHive site, `https://app.caphive.com/mcp` for the main CapHive site. Add it in Claude.ai under **Settings → Integrations → Add More**. See [Step 3: Connect Claude.ai](#step-3-connect-claude-ai).

**Where can I see and revoke the AI clients I have authorised?**
While signed in to CapHive, open the [authorised applications page](/oauth/authorized_applications), which lists the applications you have authorised and lets you revoke one. There is no menu link to it; you can also disconnect the connector from Claude.ai.

**Where do CapHive admins manage registered OAuth clients?**
In the [OAuth admin panel](/oauth/applications), restricted to `super` and `support` users. The names listed there are the ones shown under **Allowed AI Clients** on the entity edit page.

### Setting up, changing and removing access

**How do I connect Claude.ai to CapHive?**
In Claude.ai add a connector named CapHive with the MCP URL, click **Connect**, log in to CapHive in the popup and click **Authorize**. No client ID or secret is needed. See [Connect and Authorize](#connect-and-authorize).

**How do I choose which users can connect?**
On the entity's **Edit** page, under **Allow access for**, tick **Fund Managers** (employee role), **Investors (LPs)** (investor role), or both, and save. A user whose role is not ticked gets "Your role does not have MCP access".

**How do I restrict access to Claude only?**
Under **Allowed AI Clients** on the entity's **Edit** page, tick **Claude** and save. Leaving every client unticked allows all registered AI clients.

**How do I turn MCP off for my organisation?**
Untick **Enable AI Client Integration** on the entity's **Edit** page and save. Connected clients are refused from their next request, and the setting can be switched back on at any time.

**How do I disconnect my own Claude.ai account?**
Disconnect or remove the CapHive connector in Claude.ai, or revoke it on CapHive's [authorised applications page](/oauth/authorized_applications). To use it again, click **Connect** and authorise once more.

**What permission do I need to configure MCP?**
The **company_admin** role in your entity to edit the Company Profile, plus the `enable_mcp` permission switched on for the entity by CapHive. Users who only connect a client need a role ticked under **Allow access for**.

### Why use the MCP server

**Why connect an AI client to CapHive?**
You can ask questions of live fund data in plain language, such as calls, distributions, portfolio valuations, cap tables and fund ratios, and get answers you can combine with your own analysis in Claude, without exporting spreadsheets.

**What can Claude do once connected?**
It can call 22 read-only tools covering funds, capital activity, portfolio companies, cap tables, documents, commitments, fund units and account entries. See [Available Tools](#available-tools-22).

**Is it safe to give an AI client access to our data?**
Access is read-only and runs as the signed-in CapHive user, so Claude only sees data that user can already see. Admins control which entities, roles and clients are allowed, and each user can revoke access at any time.

**Who typically uses the MCP connection?**
Fund managers and analysts who already use Claude for research or reporting and want to query CapHive data from it, and LPs where the entity chooses to allow the investor role.

### What happens when I…

**What happens when I click Authorize in the CapHive popup?**
CapHive issues Claude an access token for your user, valid for 30 days and refreshed automatically, and Claude can start calling the tools. Nothing changes in your CapHive data and no one is notified.

**What happens when Claude asks CapHive a question?**
Each request is checked in order: MCP licensed for the entity, integration enabled, your role allowed, and the client allowed. If all pass, the tool reads data within your own permissions and returns it; nothing is created, changed or deleted.

**What happens when an admin unticks my role or disables the integration?**
Your connector stays listed in Claude.ai, but every request is refused with "Your role does not have MCP access" or "MCP is not enabled for this organization" until the setting is restored.

**What happens when I revoke or disconnect the connector?**
The token stops working immediately and Claude can no longer read CapHive data for you. Reconnecting and authorising again issues a new token.

**What happens if my CapHive permissions change?**
MCP answers follow your current permissions on every request, so newly granted funds appear and removed access disappears without reconnecting.

### Troubleshooting and edge cases

**Can Claude change data in CapHive?**
No. All MCP tools are read-only; no create, update or delete operation is possible through MCP.

**Does it work on the Claude mobile app?**
Add and connect the CapHive connector from Claude.ai in a desktop browser; the setup steps in this guide are not supported on mobile.

**The connector says "Missing token" or "Invalid or expired token".**
The authorisation was not completed or the token has expired. Disconnect and reconnect the connector in Claude.ai and authorise again.

**Claude connects but returns no data.**
Your CapHive user may not have access to any funds or portfolio companies. Check what you can see when you log in to CapHive directly, and ask your admin to grant access if something is missing.

**Can other AI clients such as ChatGPT or Gemini connect?**
Only clients that support MCP with OAuth can connect, and only if **Allowed AI Clients** is left empty or includes them. This guide covers Claude.ai; other clients are set up in their own settings.

## Related Guides

- [AI Features](../ai_features_user_guide) — the AI tools available inside CapHive itself.
- [Support Agents](../support_agents_user_guide) — in-app AI agents and their AI governance and compliance FAQ.
- [LLM Configuration Guide](../llm_configuration_guide) — provider keys for AI features that run inside CapHive.
- [Entities](../entities_user_guide) — the Company Profile edit page that holds the MCP settings.
- [User Role Management](../user_role_management_user_guide) — the roles that decide who may connect.
- [Two-Factor Authentication](../two_factor_authentication_user_guide) — the sign-in step when you authorise a client.
