# LP Assistant — Business Design

## Purpose

The LP Assistant is a conversational AI inside the Caphive investor portal that lets Limited Partners (LPs) ask natural-language questions about **their own** fund data — performance, commitments, capital calls, distributions, portfolio companies, statements, and drawdown notices — without having to navigate through tabs, filters, and reports.

Instead of clicking through the UI to find a piece of information, the LP simply asks, and the assistant responds with the answer, the relevant chart, or the correct document.

## Target user

**Limited Partners (LPs) / investors** logged into the Caphive investor portal. The assistant is available to any LP whose investor access has been approved.

A single LP has **one login on Caphive even if they invest across multiple fund managers** (e.g. Kedara + Fireside). Caphive merges investor records behind the scenes (keyed on email) so the LP sees a unified view of all their funds across FMs. The LP Assistant is expected to mirror this — a question like "show me my latest Statement of Account" returns SoAs across every fund the LP holds, regardless of which FM manages it.

A future product enhancement will add **per-FM subdomain routing** (e.g. `kedara.caphive.com`) so an LP can narrow their session to a single FM's funds, with a dropdown to switch. Until then, the default is "all my funds, everywhere."

Phase 1 is delivered inside the **CapHive UI**. Phase 2 will extend the same assistant to **WhatsApp**.

## Why this matters

- LPs today navigate across Investments, Commitments, Statements, Data Rooms, Funds, and KYC tabs to piece together simple answers. Each tab is a click cost.
- Many LPs are not daily users of the portal; they visit around reporting cycles or capital events, and re-learn the UI each time.
- LP-side queries to the investor-relations team often repeat across investors — "what's my IRR," "when is the next call," "what's the NAV." A self-serve assistant deflects predictable questions and frees the IR team for higher-value interactions.
- LPs expect this experience from consumer products. Making fund data ask-able closes that gap.

## Scope — what the LP can ask in Phase 1

The assistant will answer questions across **six domains** in Phase 1. Each is driven by a real user need visible on the LP dashboard and by illustrative queries shared by the client.

### 1. Fund performance (already live)

- "What is my IRR for Growth Fund?"
- "Show me IRR for Growth Fund for the last 8 quarters as a line chart."
- "What is my NAV / TVPI / DPI / MOIC across all my funds?"
- "Compare performance metrics across my funds."

### 2. Capital calls and drawdowns

- "Show me the drawdown notice for my last call."
- "What is my due amount right now?"
- "When was my last capital call? What was the amount?"
- "Show me my call history for Growth Fund."

The drawdown notice document is delivered as a link the LP can open directly from the chat.

### 3. Commitments

- "How much have I committed to Growth Fund?"
- "What is my total commitment across all my funds?"
- "How much of my commitment is still uncalled?"

### 4. Distributions

- "How much have I received in distributions from Growth Fund?"
- "Show me my distribution history."
- "What was my most recent distribution?"

### 5. Portfolio companies

- "What is the portfolio for Growth Fund?" — list of companies the fund invested in
- "Show me the MOIC for all portfolio companies in Growth Fund."
- "What's the latest valuation of Acme Corp?"
- "Which sectors does my Growth Fund portfolio cover?"

(Visibility is automatically limited to funds and portcos the LP is authorized to see.)

### 6. Documents and statements

- "What is my last quarter Statement for Growth Fund?" — returns the SOA
- "Show me my most recent documents."
- "Where is my subscription agreement for Growth Fund?"

Documents referenced by other answers (drawdown notices, distribution notices) are resolved through this same domain.

## Scope — what is explicitly NOT in Phase 1

**Phase 2 (planned next):**
- KYC status, expiry, missing documents
- Pending approvals requiring LP action
- WhatsApp delivery of the same assistant

**Deferred pending scope confirmation with the client:**
- Secondary market: deals, offers, interests
- New investment opportunities / subscription windows

These dashboard tabs exist today, but product direction on whether LPs transact here via the assistant is not yet locked.

## User experience

### Entry point

A **prominent icon on the LP Dashboard** triggers the chat. The LP does not need to navigate to a separate page; the assistant opens as a chat panel on the dashboard itself. The same entry point is rendered on both the investor and VC dashboard variants.

### Conversation behavior

- The LP asks a question in natural English. The assistant may reply with a short answer, a table, or a chart (line chart, bar chart) where appropriate to the data.
- Links to documents (statements, drawdown notices, distribution notices) are returned inline.
- The assistant says "I could not find that" honestly rather than guessing when data is unavailable for the LP's funds.
- Conversations are scoped to a single LP session; the assistant never surfaces data belonging to other LPs or to funds outside the LP's authorized set.

### Guardrails

- Only read access to fund data — the assistant cannot change commitments, approve documents, or trigger actions on the LP's behalf.
- All answers are filtered by the LP's existing access rights; an LP sees exactly the same data through the assistant that they would see by navigating the portal.
- Soft-deleted records, scenario/what-if data, and non-finalized records are excluded from answers.

## Benefits

### For the LP
- **Faster answers** — typical navigation time (clicks, filters, report generation) replaced with a single question.
- **Accessible** — no need to remember which tab or report holds a given piece of information.
- **Uniform experience** — same assistant works across performance, capital events, portfolio, and documents.

### For the Fund Manager / IR team
- **Deflects routine queries** — the assistant handles "what's my IRR / next call / last distribution" type questions that would otherwise land in IR's inbox.
- **Drives portal engagement** — a more usable portal is a more-used portal, which reduces email-based data requests.
- **Same data governance** — the assistant respects existing access-rights and approval gates; no new permissions to manage.

### For Caphive (product)
- **Differentiator** — a native, investor-facing AI assistant that is tenant-scoped and access-rights-aware is not standard in fund-admin products.
- **Foundational investment** — the same assistant architecture extends to FMs, Analysts, and WhatsApp in subsequent phases.

## Delivery plan

| Phase | What's delivered | Channel |
|-------|------------------|---------|
| Phase 1 (current) | Six domains above, live in investor portal | CapHive UI |
| Phase 2 | KYC, Approvals + WhatsApp channel | CapHive UI + WhatsApp |
| Later | Secondaries / Opportunities (if in scope); FM-side assistant | CapHive UI + WhatsApp |

## Pending commercial / configuration decisions (2026-04-20)

The following product decisions are open and need to be locked with the business side (Mohith) before the assistant architecture is finalized. None of these block the skill-file authoring work; they affect how the `SupportAgent` is configured and who pays for the LLM usage.

1. **Scope of the LP Assistant.** The assistant's scope must follow the LP — all funds across all FMs the LP has touched — not the FM. Current Phase 2 code restricts to a single FM's funds; this is a bug that needs a small redesign. Three options are documented in `technical_design.md` (Session 4).
2. **Billing model.** Because a cross-FM conversation may touch data from more than one FM, we need to decide who pays for the LLM tokens:
   - **A — Caphive platform absorbs the cost**, recovered via FM subscription tier.
   - **B — Per-FM enablement**, where only FMs that pay for AI have their funds included in scope.
   - **C — Caphive pays at call time; bills FMs back monthly** based on usage telemetry.
   - Interim recommendation: Model A + day-1 telemetry, so a switch to B or C later is data-backed.
3. **Per-FM context dropdown.** If an LP is invested across multiple FMs, should the chat UI offer a dropdown to narrow scope to one FM? Probably "later" — aligns with the upcoming subdomain-routing feature.

These decisions will be captured in a follow-up session once discussed with Mohith.

## Success indicators (to instrument post-launch)

- % of LP sessions that use the assistant at least once
- # of questions per session
- Fallback rate ("I couldn't find that") — a signal of missing skill coverage
- Document-open rate on assistant-returned links
- Reduction in routine IR email volume (qualitative, via IR team feedback)
