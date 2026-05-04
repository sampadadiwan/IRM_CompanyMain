# LP Assistant — Business Design

## Purpose

The LP Assistant is an AI chat experience embedded inside the LP (investor) portal. An LP types natural-language questions about their fund holdings — performance metrics, commitments, capital calls, distributions, portfolio companies, and documents — and receives concise, accurate answers grounded in live fund data.

It exists to remove friction from the most common LP questions ("what's my latest NAV?", "send me my last Statement of Account", "what was my drawdown for Q3?") that today require a human at the FM to look up and respond by email.

## Who uses it

- **Limited Partners (investors)** — anyone with a valid LP login on a Caphive-hosted FM portal.
- The assistant is opened from the LP dashboard. It runs only inside the LP portal session — it has no public surface.

## Single Fund Manager per chat

Every LP Assistant chat is bound to **exactly one Fund Manager (FM) tenant**. If LP-A holds investments across two FMs (e.g. Angelia FM and Beta FM), they see **two separate chat panels**, one per FM, each scoped to the funds and documents of that FM only.

Why this matters:

- Different FMs have different fund books, different document libraries, different APIs, sometimes different LLM providers (per-tenant API keys). Mixing them in one chat would be confusing for the LP and a privacy risk for the FMs.
- It keeps the trust model simple: one chat, one FM, one set of accessible funds.

## What an LP can ask

The assistant answers questions across six data domains:

| Domain | Example questions |
|---|---|
| **Fund Ratios** | "What's my IRR / TVPI / DPI for Angelia Growth Fund?" |
| **Commitments** | "How much have I committed?" "How much is paid vs called?" |
| **Capital Calls** | "When is my next drawdown due?" "Show me Call-3." |
| **Distributions** | "What distributions have I received this year?" |
| **Portfolio** | "What companies does the fund hold?" |
| **Documents** | "Send me my last SOA." "Show me the LPA." "Q4 fund update?" |

Anything outside these six domains is politely declined.

## Walkthrough — LP-A asks for their Statement of Account

1. **LP-A logs into the portal** for Angelia FM (Devise authentication).
2. **LP-A opens the LP Assistant** chat panel from the dashboard.
3. **LP-A types**: *"Send me my last Statement of Account."*
4. The assistant looks up the relevant data domain ("documents"), locates LP-A's own most recent SOA in Angelia Growth Fund, and replies:

   > Your most recent Statement of Account is **[SOA - Q4 2025](https://...)** for **Angelia Growth Fund**, issued **15 Jan 2026**.

5. LP-A clicks the link. The PDF opens in a new tab via a short-lived (~1 hour) signed URL. After the URL expires, asking again regenerates a fresh link.

The same pattern applies to drawdown notices, distribution notices, the LPA, fund reports, and any other document the LP is entitled to see.

## Privacy & data isolation — what's protected

The assistant enforces three concentric guarantees:

1. **Tenant isolation** — LP-A can never see data belonging to a different FM. Each chat is bound to one FM tenant.
2. **Fund-level access** — within an FM, LP-A can only see funds they have an `AccessRight` for. If LP-A is invested in Growth Fund but not in Opportunity Fund, the latter is invisible to the assistant.
3. **Per-LP isolation within shared funds** — this is the most subtle and important guarantee. Two LPs (call them LP-A and LP-B) may hold commitments in the **same fund** managed by the **same FM**. Each LP receives their own quarterly Statement of Account, distribution notice, etc. — these are *per-investor* documents. The assistant guarantees that LP-A can never retrieve LP-B's SOA, even though both documents live in the same folder of the same fund.

The third guarantee is enforced in two independent places (described in the technical design) so that a single oversight cannot cause a leak.

## What the LP Assistant does NOT do

- Place trades, redeem units, or move capital — read-only by design.
- Give regulatory, tax, or investment advice.
- Discuss other LPs' positions or compare returns across investors.
- Answer questions outside the six data domains. ("What's the weather?" → polite refusal.)
- Persist chat history across sessions (current scope; may change in a future phase).

## Why the LP can trust the answer

- All numbers come from live MySQL queries against the FM's own fund book — no separate AI knowledge base, no caching, no embeddings. If the FM corrects a number in their system, the next question reflects the correction.
- Document links are signed S3 URLs minted server-side after a fresh access check — the assistant never invents links and never serves cached files.
- If the assistant cannot answer (no data, ambiguous question, out of scope), it says so honestly rather than guess.

## Demo

See `docs/lp_assistant/lp_assistant_demo.pptx` for the latest walk-through deck.
