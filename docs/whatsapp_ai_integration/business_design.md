# WhatsApp AI Agent Integration — Business Design

## 1. Purpose

Enable investors and fund managers to interact with the platform's AI assistants via WhatsApp — the same agents that power the web chat (LP Assistant and Customer Support Agent) — without requiring users to log into the platform.

This reduces L1 support load, gives investors instant self-service access to fund data and documents, and provides users with 24/7 platform support — all through a channel they already use daily.

## 2. User Personas

| Persona | Agent | Who has access |
|---------|-------|----------------|
| **Investor (LP)** | LP Assistant | Users with approved investor access to a fund |
| **Any user** | Customer Support Agent | Available to all registered users — investors, fund managers, and any other role |

> **Note**: A user with access to both agents (e.g. an LP who is also a fund manager) will see an agent selection menu. A user who only qualifies for one agent is routed directly without a menu.

## 3. How It Works — User Journey

### 3.1 First Message (New Session)

1. User sends any message to the entity's WhatsApp number.
2. The system identifies the user by their phone number.
3. **If the user qualifies for only one agent** — the system auto-selects and proceeds immediately (no menu).
4. **If the user qualifies for multiple agents** — the system responds with a menu:

   > Hi [Name]! How can I help you today?
   >
   > 1 - Investment queries (view fund data, SOA, performance)
   > 2 - Platform support (how-to questions, troubleshooting)
   >
   > Reply with the number. You can also type *menu* at any time to see this menu again.

5. User replies with their number choice.

### 3.2 LP Assistant — Fund Selection

After the LP Assistant is selected (or auto-selected), the system checks the user's accessible funds:

- **One fund** — auto-selected, session starts immediately with that fund.
- **Multiple funds** — user sees a fund menu:

  > Which fund would you like to query?
  >
  > 1 - Growth Fund II
  > 2 - Venture Partners III
  >
  > Reply with the number.

Once a fund is selected, the session is locked to it. All queries run against that fund's data — identical to choosing a fund on the web portal.

### 3.3 Customer Support Agent — Immediate Start

The CS Agent is entity-scoped (not fund-scoped), so the conversation starts immediately after selection. No additional step is required.

### 3.4 Ongoing Conversation

- Messages go back and forth naturally — user asks, bot responds.
- The bot uses the **same backend as web chat**: same tools, same data access, same user guides.
- **Session timeout**: after 30 minutes of inactivity the session expires. The next message starts a fresh session.

### 3.5 Returning to the Menu

At any point the user can type the word **menu** (on its own) to restart the selection flow — change agent, change fund, or start fresh.

> Only the exact word **"menu"** triggers this. Phrases like "show menu" or "switch" do not.

### 3.6 Ending a Conversation

Typing **"thanks"**, **"bye"**, or **"done"** closes the conversation. For CS Agent sessions, this also triggers a feedback prompt (see below).

### 3.7 Feedback (CS Agent Only)

After the user signals the conversation is over, the bot asks:

> Was this helpful? Reply *YES* or *NO*

- **YES / Y / 👍** → recorded as positive feedback.
- **NO / N / 👎** → bot asks: "What could be improved?" → negative feedback with notes recorded.
- **Any other message** → treated as a new question (feedback skipped).

Feedback flows into the same review dashboard the support team uses for web conversations.

### 3.8 Escalation

If the CS Agent cannot resolve a query, or the user asks to speak to a human:

1. Bot sends: "I've connected you with the support team — they'll review your conversation and respond shortly."
2. Email notification goes to the support team with a conversation summary.
3. Session is marked as escalated.
4. Support team resolves via the web dashboard. Resolution goes back to the user on WhatsApp.

### 3.9 Unrecognised Users

If a message comes from a phone number not registered in the system, no reply is sent and the message is silently dropped (we have no endpoint to route it to). Users who believe their number should be registered should contact their fund administrator.

## 4. Key Capabilities by Agent

### 4.1 LP Assistant on WhatsApp

| Capability | Example |
|---|---|
| Fund performance metrics | "What's my current IRR?" |
| Statement of accounts | "Show my latest SOA" |
| Capital calls | "Any upcoming capital calls?" |
| Distributions | "How much have I received in distributions?" |
| Portfolio companies | "How is Company X performing?" |
| Documents | "Send me the Q4 report" → sends download link |

**Documents**: The bot sends a clickable URL rather than the file itself.

**Charts**: On web, the LP Assistant renders interactive charts. On WhatsApp, the bot provides text-formatted summaries with key numbers.

### 4.2 Customer Support Agent on WhatsApp

| Capability | Example |
|---|---|
| How-to guidance | "How do I create a capital call?" |
| Feature navigation | "Where do I find investor KYC status?" |
| Data lookups | "How many investors are in Fund II?" |
| Troubleshooting | "Why can't I generate a distribution?" |
| Escalation | "I need to talk to someone" |

## 5. Entity Setup

Each entity that wants WhatsApp AI agents must have:

1. **WhatsApp number configured** — v1 endpoint + token in entity settings (or global credentials).
2. **WhatsApp feature enabled** — `enable_whatsapp` permission on the entity.
3. **Support agents configured** — LP Assistant and/or CS Agent enabled with chat enabled.
4. **WATI v3 endpoint configured** — for template messages and future v3 session APIs.

## 6. What This Does NOT Include (Future Phases)

| Feature | Phase |
|---|---|
| Inline image/chart rendering on WhatsApp | V2.3+ |
| Code-as-context for CS Agent | V3 |
| Proactive bot-initiated conversations (template messages) | V3 |
| Voice message support | V3+ |

## 7. Success Metrics

- **L1 support ticket reduction** — escalation rate (target: <20% of WhatsApp conversations escalate)
- **Response accuracy** — LLM-as-judge scores on WhatsApp CS responses (target: >7/9 average)
- **Adoption** — % of users who have used WhatsApp assistant at least once per quarter
- **Resolution time** — time from first message to issue resolved (compare web vs WhatsApp)

## 8. Risks and Mitigations

| Risk | Mitigation |
|---|---|
| 24-hour session window (WATI policy) | Bot is reactive — user always initiates, so the window is always open |
| User sends message outside business hours | Bot is available 24/7 |
| Sensitive data over WhatsApp | All data gated by existing access controls; WhatsApp is end-to-end encrypted |
| User confusion about which agent they're talking to | Clear menu labels; type *menu* to restart |

---

## 9. Implementation Status

**Status**: ✅ **IMPLEMENTED**

### What's Live

- ✅ WhatsApp message ingestion via WATI webhook (inbound `message` events only)
- ✅ User identification by phone number (`waId`)
- ✅ `conversation_id` passed from webhook through to reply delivery
- ✅ Multi-agent routing with agent selection menu
- ✅ LP Assistant with fund selection (auto-select for single fund)
- ✅ CS Agent available to all users — no access restriction
- ✅ Session persistence and state management (30-min timeout)
- ✅ *menu* keyword to restart session
- ✅ Goodbye keywords (`thanks`/`bye`/`done`) to close session
- ✅ Feedback collection for CS Agent (positive/negative with notes)
- ✅ Message formatting for WhatsApp (plain text)
- ✅ Template message API (v3) with `custom_params`
- ✅ File upload API (v3) with binary multipart
- ✅ File via URL API (v3)
- ✅ Graceful error handling — non-JSON WATI responses logged, not raised

### Deployment Checklist

- [ ] Add `WATI_V3_ENDPOINT` credential (bare host, no account-ID path)
- [ ] Run test suite and Cucumber features
- [ ] Manual end-to-end test on staging with WATI webhook
- [ ] Monitor Sidekiq logs post-deploy
- [ ] Deprecate legacy `WhatsappChatJob` after stable in production

### For Support Team

- Session and message data stored in `AgentChatSession` / `AgentChatMessage` tables with `channel: "whatsapp"`
- Feedback from WhatsApp flows into the same dashboard as web chats
- Escalations from WhatsApp appear in the support dashboard with full conversation context
- All access controls from the web platform apply equally to WhatsApp
