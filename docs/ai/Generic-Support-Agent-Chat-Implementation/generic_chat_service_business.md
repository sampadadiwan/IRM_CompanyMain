# Generic Chat Service — Business Overview

**Product:** Caphive IRM — AI Support Agents
**Date:** 2026-02-23
**Audience:** Product, Operations, Fund Management, Client Success

---

## Table of Contents

1. [What Is the Generic Chat Service?](#1-what-is-the-generic-chat-service)
2. [The Problem It Solves](#2-the-problem-it-solves)
3. [How It Works — Plain English](#3-how-it-works--plain-english)
4. [Live Agents That Use Chat Today](#4-live-agents-that-use-chat-today)
5. [The Chat Experience](#5-the-chat-experience)
6. [What Makes It "Generic"](#6-what-makes-it-generic)
7. [Adding Chat to Any Future Agent](#7-adding-chat-to-any-future-agent)
8. [AI Model Flexibility](#8-ai-model-flexibility)
9. [Security & Data Boundaries](#9-security--data-boundaries)
10. [Conversation Continuity](#10-conversation-continuity)
11. [Key Benefits Summary](#11-key-benefits-summary)
12. [Rollout Checklist for New Agents](#12-rollout-checklist-for-new-agents)

---

## 1. What Is the Generic Chat Service?

The **Generic Chat Service** is a shared conversational AI capability built into every Caphive IRM Support Agent. It gives any agent the ability to answer natural-language questions from analysts and fund managers — directly inside the platform — without leaving the page they are already working on.

Think of it as a **built-in AI assistant button** that can appear on any screen in the platform. When an analyst clicks "Ask AI", a chat panel slides open. The analyst types a question in plain English, and the AI responds using the real, live data already processed by that agent.

The same underlying technology powers every chat panel across the platform. Adding chat to a new agent requires only a short configuration — not a full rebuild.

---

## 2. The Problem It Solves

Fund management teams routinely need quick answers to questions like:

- *"Which of our funds are at risk of a cash shortfall in the next 90 days?"*
- *"Has the KYC for Investor X been fully verified?"*
- *"What documents are still missing before we can issue this capital call notice?"*

Without the chat service, answering these questions means:
1. Opening a report
2. Scrolling through data tables
3. Mentally computing or cross-referencing numbers
4. Sometimes exporting to Excel and doing manual analysis

With the chat service, the analyst simply **asks the question**. The AI has already ingested the relevant data (via the agent's last run) and answers immediately, in plain language, with figures and context.

---

## 3. How It Works — Plain English

```
Analyst types a question
        ↓
The system finds the relevant agent and the object being discussed
(e.g. "Fund A" and the "Cash Flow Assistant")
        ↓
The AI receives:
  • Its identity and role (system prompt)
  • The latest analysis data for that object (context)
  • The full history of this conversation so far (memory)
  • The analyst's new question
        ↓
The AI formulates an answer
        ↓
The answer is shown in the chat panel
        ↓
The conversation is saved so the analyst can pick up where they left off
```

The AI never invents data. It answers from the structured output of the agent's most recent run. If data is stale or missing, the AI says so.

---

## 4. Live Agents That Use Chat Today

### Cash Flow Assistant Agent

**What the agent does:**
Aggregates cash positions, investments, operating expenses, and buffers across funds. Calculates runway (days of cash remaining) and flags funds at risk of shortfall.

**What you can ask the chat:**
- *"Which funds are in shortfall right now?"*
- *"What is Fund A's current runway and how does it compare to last month?"*
- *"Break down where the cash in Fund B is sitting."*
- *"Show me a chart of the expense trajectory for Fund C."*

The chat draws on the latest completed analysis run. The AI is scoped strictly to cash flow questions and will decline off-topic queries.

---

### Portfolio Chat Agent (Document-Aware)

**What the agent does:**
Loads portfolio reports from a document folder (PDFs, DOCX files) and makes their content conversationally queryable. Also has access to web search.

**What you can ask the chat:**
- *"Summarise the key risks mentioned in the Q4 portfolio report."*
- *"What was the IRR stated for Portfolio Company X in the latest report?"*
- *"Search for recent news about this portfolio company's sector."*

---

### KYC Onboarding Agent *(chat capability available, enable per entity)*

**What the agent does:**
Validates investor KYC completeness — checks required fields, document presence, document validity, and field-to-document consistency.

**Potential chat use:**
- *"What is still outstanding for Investor Y's KYC?"*
- *"Which investors have field-to-document mismatches?"*

---

### Call Notice Agent *(chat capability available, enable per entity)*

**What the agent does:**
Validates all pre-conditions before a capital call notice can be issued — KYC completeness, document generation, approvals, and notification configuration.

**Potential chat use:**
- *"Is Capital Call #12 ready to send?"*
- *"Which investors are blocking the call notice from going out?"*

---

## 5. The Chat Experience

### Panel Behaviour
- The chat panel appears as a **floating, resizable widget** on the relevant page.
- The panel can be opened and closed without losing the conversation.
- The panel is resizable by dragging its edges — analysts can make it as large or small as they need.

### Message Rendering
- AI responses support **bold**, *italic*, `inline code`, and line breaks.
- When the AI presents numerical comparisons or trends, it can render inline charts directly in the chat (no separate export needed).
- User messages appear on the right in blue; AI responses appear on the left in grey.

### Conversation Memory
- Each analyst has their own persistent conversation per agent per object (e.g., per fund, per investor).
- Returning to the same page later shows the full previous conversation.
- Analysts can clear the conversation at any time with the "Clear Chat" button, starting fresh.

### Response Quality
- The AI is given a **strict scope** — it only answers questions relevant to its designated role.
- It will say *"I don't know"* rather than fabricate an answer.
- First-message context (the latest agent data) is prepended automatically, so the AI always has current information.

---

## 6. What Makes It "Generic"

The key architectural insight is that **chat is separated from domain logic**.

There are two distinct layers:

| Layer | Responsibility | Changes per agent? |
|---|---|---|
| **Chat engine** (`GenericChatAgent`) | Manages the conversation loop, session, memory, LLM calls | Never — shared across all agents |
| **Chat provider** (`*ChatProvider`) | Defines who the AI is, what context it has, what tools it can use | Yes — one provider per agent type |

This means:
- Adding chat to a new agent is a **configuration task**, not a rebuild.
- Improvements to the core chat engine (latency, memory management, UI) benefit all agents simultaneously.
- Each agent's AI persona and context remain fully independent and customised.

---

## 7. Adding Chat to Any Future Agent

To give a new or existing Support Agent chat capability, the team needs to:

1. **Write a Chat Provider** — a small class (~30 lines) that defines:
   - The AI's identity and instructions
   - What data to pull from the database as context
   - Any special tools (e.g., web search)

2. **Register it** — one line added to the provider factory.

3. **Enable it on the agent record** — set `chat_config.enabled = true` in the agent's configuration (can be done from the admin UI or console).

4. **Add the panel to the view** — one ERB partial include on the relevant page.

No new database tables, no new routes, no new JavaScript controllers are required.

---

## 8. AI Model Flexibility

The platform supports multiple AI providers and models. Chat can be configured to use:

| Provider | Example Models |
|---|---|
| OpenAI | `gpt-4o`, `gpt-4o-mini`, `o3-mini` |
| Google Gemini | `gemini-2.5-flash`, `gemini-2.0-pro` |
| Anthropic | `claude-opus-4-6`, `claude-sonnet-4-6` |
| OpenRouter | Any model via aggregation |

**Model selection hierarchy (highest priority first):**
1. Model set on the individual `SupportAgent` chat config
2. Default LLM model set in the Entity's settings (per-client override)
3. Platform-wide environment default

This means a client entity can bring their own API key and choose their preferred model, without affecting other entities on the platform.

---

## 9. Security & Data Boundaries

### Isolation
- Each `AgentChatSession` is scoped to a specific `(analyst, agent, target object)` triple.
- Analyst A cannot see Analyst B's conversation history.
- Conversations for Fund A are never surfaced when chatting in the context of Fund B.

### Data Scope
- The AI's context is built exclusively from the agent's own processed output and the entity's own records.
- Cross-entity data leakage is prevented at the database query level — all context queries are filtered by entity ID.
- The AI does not have access to raw financial data outside of what the agent has explicitly computed and formatted.

### Prompt Injection Defence
- User messages are passed as a separate message role, not concatenated into the system prompt.
- The system prompt is generated server-side by the Chat Provider and is not influenced by user input.
- Strict scope prompts instruct the AI to reject attempts to redirect it outside its domain.

### API Key Security
- API keys are stored in encrypted credentials (`config/credentials/`) or as entity-level settings.
- Keys are never exposed to the frontend or logged.

---

## 10. Conversation Continuity

Each conversation is stored permanently until the analyst clears it. This enables:

- **Interrupted workflows:** Close the browser, come back tomorrow — the conversation is exactly where you left it.
- **Audit trail:** A record of what questions were asked and what the AI said, tied to a specific agent run.
- **Collaboration context:** Team leads can review what questions analysts have been asking (future feature possibility, using the shared session model).

The conversation history is sent to the AI on every turn, so it maintains full awareness of everything discussed in the current thread.

---

## 11. Key Benefits Summary

| Benefit | Detail |
|---|---|
| **Instant answers** | No more manual report-reading; ask in plain English |
| **Grounded in real data** | AI answers from the agent's latest processed output, not from general knowledge |
| **Persistent memory** | Conversations survive page refreshes and login sessions |
| **Scoped and safe** | Each chat knows only what it is supposed to know |
| **Multi-model** | Use GPT-4o for one agent, Gemini for another, entity's own keys if preferred |
| **Zero rebuild to add** | New agents get chat with ~50 lines of configuration code |
| **Consistent UI** | One chat panel component works everywhere; no per-page frontend work |
| **Resizable and non-blocking** | Panel floats over the page; does not interrupt normal workflow |

---

## 12. Rollout Checklist for New Agents

Use this as a quick checklist when enabling chat on a new or existing agent:

- [ ] **Chat Provider created** — `*ChatProvider` class with `system_prompt`, `build_context`, `tools`
- [ ] **Provider registered** — added to `BaseChatProvider.resolve` factory
- [ ] **Agent type registered** — added to `SupportAgent::AGENT_TYPES`
- [ ] **Agent record configured** — `chat_config: { enabled: true, model: "..." }` set
- [ ] **Panel added to view** — `shared/agent_chat_panel` partial included on target page
- [ ] **Tested with sample questions** — verified AI stays in scope and answers correctly
- [ ] **System prompt reviewed** — confirmed identity, scope restrictions, and date awareness
- [ ] **Context payload verified** — confirmed `build_context` returns meaningful, formatted data
- [ ] **History loading tested** — re-opened session shows previous messages correctly
- [ ] **Clear chat tested** — session clears and resets cleanly

---

*For technical implementation details, see [Generic Chat Service — Technical Documentation](generic_chat_service_technical.md).*
