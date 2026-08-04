# CapHive MCP Server — Business Design

## Executive Summary

Expose CapHive's fund management data to **all major frontier AI models** (Claude, ChatGPT, Gemini) through a single MCP (Model Context Protocol) server. This allows CapHive clients — fund managers, LPs, CFOs — to query their fund data conversationally using whichever AI tool they prefer, without needing to learn CapHive's UI or wait for custom reports.

---

## The Problem

Today, accessing fund data requires either:
- Navigating CapHive's UI dashboards and reports
- Asking the internal FM/Portfolio Assistant (embedded chat)
- Requesting custom reports from the operations team

Power users and clients increasingly want to use their **own AI tools** (ChatGPT, Claude, Gemini) to analyze data on their terms — ask ad-hoc questions, build custom analyses, integrate with their own workflows. Currently there's no way to connect these external AI tools to CapHive data.

## The Solution

Build an MCP server that acts as a **universal AI adapter** for CapHive data. Any MCP-compatible AI client can connect, discover available data tools, and query fund data conversationally.

```
Fund Manager opens ChatGPT
  → Connects to CapHive MCP server (one-time setup)
  → Asks: "What's my total committed capital across all USD funds?"
  → ChatGPT calls CapHive's list_funds tool
  → CapHive returns scoped, authorized data
  → ChatGPT presents the answer
```

---

## Why Now?

As of mid-2026, **all three major AI platforms** support MCP:

| Platform | MCP Support | Status |
|---|---|---|
| **Claude** (Anthropic) | Native — Desktop, Code, Cursor | Production-ready |
| **ChatGPT** (OpenAI) | Via Connectors / Developer Mode | Available now |
| **Gemini** (Google) | Via Enterprise Custom Data Store, CLI, SDK | Available now |

**Build one server, serve all three.** This was not possible 6 months ago — the ecosystem has converged on MCP as the standard protocol for AI-to-data connectivity.

---

## What is MCP? (Non-Technical Explanation)

MCP is a **universal standard for connecting AI models to data sources**. Think of it as USB for AI — before USB, every device had its own cable. MCP is one protocol that every AI tool speaks.

### Without MCP
- Each AI tool needs a custom integration
- Someone must write glue code for every new AI client
- API docs, auth flows, data formatting — all duplicated per client

### With MCP
- One server, one set of tools
- AI clients auto-discover what data is available
- The AI decides which tool to call based on the user's question
- New AI clients connect without any code changes

---

## User Stories

### Fund Manager using ChatGPT
> "As a fund manager, I want to connect my ChatGPT account to CapHive so I can ask questions about my funds in natural language without switching to the CapHive dashboard."

**Flow:** ChatGPT Settings → Connectors → Paste CapHive MCP URL → Log in to CapHive → Authorize → Start asking questions. No Client ID or Secret needed — the AI client registers itself automatically via Dynamic Client Registration (RFC 7591).

### LP using Claude
> "As an LP, I want to use Claude Desktop to analyze my portfolio commitments across multiple funds, cross-referencing with my own spreadsheets."

**Flow:** Claude Desktop config → Add CapHive MCP server URL → Authenticate via browser (OAuth) → Ask: "Show me my commitments across all funds, sorted by amount."

### CFO using Gemini (via Google Workspace)
> "As a CFO, I want Gemini Enterprise to pull fund performance data directly into my analysis workflow alongside our Google Sheets financial models."

**Flow:** Gemini Enterprise → Data Stores → Add Custom MCP Server → CapHive URL → Authorize via OAuth → Query fund ratios and cash positions.

### Developer using Cursor/Claude Code
> "As a developer building a client report, I want to query live fund data from my IDE to verify calculations without switching to the CapHive UI."

**Flow:** Claude Code / Cursor → MCP settings → Add CapHive server → Authorize via browser (OAuth) → Query data inline while coding.

---

## What Data is Exposed?

All data goes through CapHive's existing authorization layer — users only see data they're permitted to access.

### Domain 1: Funds
- List all funds with committed, collected, and distribution amounts
- Fund details (terms, dates, currency, category)
- Fund performance ratios (TVPI, RVPI, DPI, IRR)

### Domain 2: Capital Activity
- Capital calls (amounts, due dates, status)
- Capital commitments / folios (investor commitments per fund)
- Capital distributions (gross amounts, dates, completion status)
- Capital remittances (payments received, verification status)
- Remittance and distribution payment details

### Domain 3: Portfolio Companies
- Portfolio company list with filtering
- Company details and snapshots
- Portfolio investments (buys, sells, conversions, FMV, gains)
- Valuations (per-share values, dates, synthetic flags)

### Domain 4: KPIs & Analytics
- Portfolio company KPIs (actuals, budgets, monthly/quarterly/yearly)
- Fund ratios at company level

### Domain 5: Documents
- Document listing with filtering
- Document details and full text content
- Document analysis (LLM-powered extraction and Q&A)

### Domain 6: Cap Table
- Cap table by portfolio company
- Investments in cap table (by investor, funding round, category)

### Domain 7: Cash Flow (Future)
- Cash position across funds
- Runway calculations
- Expense forecasts

---

## How It Relates to Existing AI Assistants

The MCP server is **complementary** to our existing FM Assistant, LP Assistant, and Portfolio Assistant — not a replacement.

| | Existing Assistants | MCP Server |
|---|---|---|
| **Intelligence** | CapHive's LLM thinks and reasons | External AI thinks and reasons |
| **Skills & memory** | Yes — progressive disclosure, self-improving | No — stateless data access |
| **Controlled UX** | Yes — we design the experience | No — the external AI presents results |
| **Installation** | None — embedded in CapHive UI | User connects via their AI client |
| **Target audience** | All users (guided experience) | Power users (self-service) |
| **Competitive moat** | Our intelligent assistant is the product | Data access is the product |

**Think of it as:**
- **FM Assistant** = a smart analyst who knows CapHive deeply and guides you
- **MCP Server** = giving someone keys to the filing cabinet to look up whatever they want

Both serve different user needs. The FM Assistant is our product differentiator. The MCP server is an integration layer that increases platform stickiness and meets users where they already are (ChatGPT, Claude, Gemini).

---

## Client-Facing Value Proposition

### For Fund Managers
- Query fund data from **any AI tool** — no need to learn new dashboards
- Ad-hoc analysis without waiting for custom reports
- Cross-reference CapHive data with external data in the same AI conversation

### For LPs / Investors
- Access portfolio information through their preferred AI tool
- Natural language queries instead of navigating portals
- Combine CapHive data with their own spreadsheets and models

### For CapHive (Business)
- **Platform stickiness** — clients who connect their AI tools to CapHive data are more deeply integrated
- **Differentiation** — "CapHive works with any AI" is a strong sales pitch
- **Reduced support load** — clients self-serve ad-hoc queries instead of requesting custom reports
- **Future-proof** — MCP is the emerging industry standard; early adoption positions CapHive ahead of competitors

---

## Security & Access Control

- **Two-level entity governance:**
  - **Level 1 — CapHive Admin (billing gate):** MCP must be enabled per-entity by a CapHive admin (`super`/`support` role) via the admin panel (`/admin/entities`). This is a chargeable feature — entities without it cannot see or use MCP at all.
  - **Level 2 — Entity Admin (self-serve config):** Once CapHive enables MCP, the entity's own admin (`company_admin` role) can toggle it on/off, choose which roles (Fund Managers, LPs) have access, and restrict which AI clients are allowed.
- **Authentication:** OAuth 2.1 Authorization Code flow with PKCE — users log in via CapHive's existing Devise authentication and authorize the AI client to access their data. AI clients auto-discover OAuth endpoints via standard `/.well-known/` metadata URLs (RFC 8414 + RFC 9728) and self-register via Dynamic Client Registration (RFC 7591) — users only need to paste the MCP URL, no Client ID or Secret required.
- **Authorization:** Same Pundit policies as the web UI — users only see data their role permits
- **Entity scoping:** Every query is scoped to the user's entity — no cross-tenant data leakage
- **Read-only:** Initial release is read-only (no creates, updates, or deletes via MCP)
- **OAuth admin restricted:** The Doorkeeper OAuth applications UI (`/oauth/applications`) is restricted to CapHive `super`/`support` roles only
- **Token management:** Users can view and revoke active OAuth tokens from a settings page in CapHive UI
- **Audit logging:** Every MCP tool call is logged (who, what, when)
- **Rate limiting:** Per-token rate limits to prevent abuse

---

## Rollout Plan

### Phase 1: Internal Demo (1 day) — DONE
- Single tool (list_funds) with hardcoded entity
- Tested with Claude Code
- Demo to team

### Phase 2: Fund Domain — Staging (1 week) — DONE
- All fund-related tools (funds, capital calls, commitments, distributions, remittances, fund ratios)
- OAuth 2.1 authentication with PKCE (Doorkeeper gem) + entity resolution
- Deployed to staging server
- Tested with Claude.ai on staging (2026-05-18)

### Phase 3: Full Domain Coverage (2 weeks) — DONE
- All 23 tools across 6 domains: funds, capital, portfolio, cap table, documents, commitments
- Streamable HTTP transport via official `mcp` gem (v0.15.0)
- Two-level entity governance: CapHive admin billing gate + entity admin self-serve config
- Doorkeeper OAuth admin restricted to super/support roles
- Multiple team members connected and tested on staging (2026-05-19)
- Local testing via ngrok confirmed working (2026-05-21)

### Phase 3.5: Tool Description Improvements — IN PROGRESS
- Improve MCP tool descriptions with usage hints, default limits, workflow guidance
- Add default limit (25-50) to all list tools
- Align with richer RubyLLM tool descriptions used by embedded assistants
- Consider compound tools for common multi-step queries

### Phase 3.6: Dynamic Client Registration — DONE
- Enabled RFC 7591 Dynamic Client Registration via `doorkeeper-openid_connect` gem
- AI clients (Claude.ai, ChatGPT, Gemini) auto-register as OAuth applications — no manual Client ID/Secret entry
- End-user experience simplified to: paste MCP URL → log in → connected
- Verified working with Claude.ai on 2026-07-06

### Phase 4: Production Readiness (1 week)
- Disable `reuse_access_token` and reduce token lifetime to 7 days
- OAuth token management UI (view/revoke active tokens)
- Audit logging dashboard
- Rate limiting
- Per-role tool filtering (override `accessible_by?` in tool classes)
- Documentation for end users (connection guides per AI client)

### Phase 5: Advanced (Future)
- Write operations (create capital calls, update records)
- MCP Resources (expose static data like fund terms documents)
- Webhook notifications (notify AI clients when data changes)
- Custom analytics tools (cash position, runway, stress scenarios)

---

## Key Decisions Made

1. **Who gets MCP access?** — Two-level governance: CapHive admin enables per-entity (billing gate), entity admin configures roles and client restrictions (self-serve). Not all entities get it by default — it's a chargeable feature.
2. **Read-only or read-write?** — Read-only for Phases 1-4. Write operations in Phase 5.
3. **OAuth scopes** — Single "read" scope. Simpler, sufficient for read-only access.
4. **Hosting** — Same Rails app, mounted at `POST /mcp`. No separate service.
5. **OAuth Client ID model** — One Client ID per AI client (Claude.ai, ChatGPT, Gemini), shared across all tenants. Tenant isolation via token + entity governance. See `docs/mcp_server/oauth_multi_tenancy_design.md` for detailed rationale.
6. **Dynamic Client Registration** — AI clients self-register via RFC 7591, eliminating manual OAuth app creation per client. Users only need the MCP URL to connect.

---

## Competitive Landscape

As of mid-2026, no major fund management / IRM platform offers native MCP connectivity. This would make CapHive a **first mover** in the space, positioned as the fund management platform that "works with any AI."
