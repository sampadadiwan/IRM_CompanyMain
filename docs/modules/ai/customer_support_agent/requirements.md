# Customer Support Agent — Requirements

**Source:** `customer_support_agent_prd.html` (PRD by Product, 2026-06-05)
**Status:** Draft — requirements extracted for clarity, implementation TBD

---

## Table of Contents

1. [What is this?](#1-what-is-this)
2. [Who is it for?](#2-who-is-it-for)
3. [What can the agent do?](#3-what-can-the-agent-do)
4. [Channels](#4-channels)
5. [Escalation to humans](#5-escalation-to-humans)
6. [User feedback (rating)](#6-user-feedback-rating)
7. [Automated quality scoring (LLM-as-judge)](#7-automated-quality-scoring-llm-as-judge)
8. [Guide gap tracking](#8-guide-gap-tracking)
9. [Golden test set (regression guard)](#9-golden-test-set-regression-guard)
10. [Few-shot example library](#10-few-shot-example-library)
11. [Permissions](#11-permissions)
12. [Success metrics](#12-success-metrics)
13. [What is NOT in scope](#13-what-is-not-in-scope)
14. [Open questions](#14-open-questions)

---

## 1. What is this?

An AI chatbot that answers Fund Manager (FM) support questions — so the Caphive Customer
Success (CS) team doesn't have to handle every incoming query manually.

Today, FM users contact the CS team via WhatsApp and email for questions like:
- "How do I send a capital call notice?"
- "Why is Investor X still showing KYC incomplete?"
- "Did we already send the drawdown notice for Fund II?"

Most of these are answerable without a human. The agent handles them instantly. When it
can't, it hands off to the CS team with full context so the FM user doesn't have to repeat
themselves.

> **PRD reference:** Sections 1 (Problem Statement), 2 (Goals)

---

## 2. Who is it for?

**Users of the agent:**
- FM admins, ops managers, and ops users — anyone with an FM-side Caphive account.
- NOT LPs (investors). LPs continue to use the LP Assistant.

**Support team (behind the scenes):**
- Caphive's own CS team. They handle escalated conversations and review the feedback queue.

> **PRD reference:** Section 3 (Who It's For)

---

## 3. What can the agent do?

The agent answers questions by combining **three data sources**. It decides which sources
to use — the user never has to specify.

### Source 1 — User Guides (documentation)

Caphive platform documentation stored as markdown files. The agent searches these to
answer how-to and workflow questions.

**Example questions it can answer:**
- "How do I add a co-investor?"
- "What documents are required for KYC approval?"
- "How does the drawdown notice get sent?"
- "What does 'pending approval' status mean on a document?"

### Source 2 — Entity Data (live database)

The FM's live data in the Caphive database — investors, KYC statuses, capital calls,
commitments, distributions, documents, notifications, WhatsApp logs.

**Example questions it can answer:**
- "Why is Investor X still showing KYC incomplete?" — looks up investor KYC records
- "Has the drawdown notice for Fund II been sent?" — looks up WhatsApp logs + notifications
- "How much is uncalled for Acme Capital?" — looks up capital commitments
- "What documents are still pending for the May capital call?" — looks up documents

**Critical rule:** All queries are scoped to the FM's entity. The agent cannot access
another entity's data.

### Source 3 — Conversation History

The FM user's prior support conversations. The agent uses this when the user references
something from a previous session ("you told me last week...", "what about the issue I
mentioned before?"). This prevents the user from repeating context.

### How the agent combines sources (chaining)

For compound questions, the agent chains sources in multiple steps. Example:
1. User asks: "The investor says they uploaded their PAN — why are they still blocked?"
2. Agent searches the User Guide for what "KYC complete" means (Source 1)
3. Agent queries the DB for the investor's actual KYC status (Source 2)
4. Agent compares and gives a specific answer

The agent can take up to **6 reasoning steps**. If it can't reach a confident answer after
6 steps, it escalates automatically.

### What the agent does NOT do

If the query is outside the agent's three sources — billing questions, platform outages,
"can you email this investor", general knowledge — the agent:
- Declines politely and honestly
- Offers to connect the user to the CS team
- Does NOT attempt a tool call, hallucinate an answer, or pretend the question is answerable

Example response for an out-of-scope question:
> "That's outside what I can look up directly. I can connect you to the Caphive support
> team if you'd like — just say 'escalate'."

### What makes a good response

Every response should meet three criteria:
1. **Complete** — answers the full question, including sub-questions implied by context
2. **Grounded** — every factual claim is traceable to a tool result (guide passage or DB
   row). No fabricated data.
3. **Actionable** — tells the user what to do next, not just what the current state is

> **PRD reference:** Section 4 (Agent Capabilities)

---

## 4. Channels

The agent is available on **two channels**. Both deliver the same answer quality.

### 4.1 Web (in-app)

- Accessible via the existing floating chat panel in the FM dashboard
- Response formatted as Markdown (tables, numbered lists, code)
- Feedback via thumbs-up / thumbs-down buttons below each reply (see Section 6)

### 4.2 WhatsApp (via WATI)

- FM users send a WhatsApp message to the Caphive support number
- Agent replies within ~30 seconds
- Response formatted as plain text (no Markdown)
- Feedback via follow-up prompt: "Was this helpful? Reply YES or NO" (see Section 6)

### Cross-channel continuity

Both channels share the same conversation history. An FM user can start on WhatsApp and
continue on the web (or vice versa) in the same logical session.

> **PRD reference:** Section 5 (Channels)

---

## 5. Escalation to humans

### When does the agent escalate?

| Trigger | Condition |
|---------|-----------|
| Customer-requested | User says "human", "agent", "escalate", "speak to", "help me" |
| Low confidence | Agent cannot give a confident answer after exhausting all tools |
| Complex / access issue | Issue needs Caphive infrastructure access (billing, admin config) |
| Max iterations | ReAct loop reaches 6 steps without resolution |

### What happens on escalation?

1. Agent tells the user: "Connecting you to the Caphive support team. Someone will be in
   touch shortly."
2. The conversation is assigned to the Caphive CS team inbox on WATI.
3. CS team receives an email with: entity name, user name, escalation reason, a 2-sentence
   summary, and a link to the full conversation.
4. The agent **stops auto-replying**. All subsequent messages go directly to the CS team.
5. Once CS resolves the issue and marks it resolved, the agent can handle new messages
   from that user again.

> **PRD reference:** Section 7 (Escalation)

---

## 6. User feedback (rating)

Every agent reply can be rated by the FM user. Rating is voluntary but always offered.

### 6.1 Web — Thumbs inline below each reply

After every assistant message, a small row appears:

```
Was this helpful?   [Thumbs Up: Yes]    [Thumbs Down: No]
```

- **Thumbs up** — immediate confirmation ("Got it — glad that helped."), rating recorded
  as `positive`
- **Thumbs down** — expands an optional note field ("What was missing or wrong?"), user
  can submit a note or skip. Rating recorded as `negative` (with or without note).
- Rating is **per message**, not per session
- User can only rate once per message (locked after submit)
- Rating row is hidden on escalation notices (nothing to rate)
- Rating available for up to 24 hours after the message

### 6.2 WhatsApp — Two-turn flow

3 seconds after the agent reply, a follow-up is sent:

```
Was this helpful?
Reply YES or NO
(or ask your next question to skip)
```

- **YES** — "Thanks — glad that helped!" → recorded as `positive`
- **NO** — agent asks: "What was missing or wrong? Reply with your note, or SKIP to skip."
  - User sends a note → recorded as `negative` with note
  - User replies SKIP → recorded as `negative` without note
  - User asks a new question instead → feedback window closes, new question processed
- **Expiry:** The feedback window expires 10 minutes after the prompt. After that, any
  message is treated as a new query.

### What happens with feedback?

- **Negative feedback** → item marked `needs_review` in the feedback queue
- **Positive feedback** → recorded for analytics
- All feedback (both channels) goes into the same table
- A message rated on one channel cannot be re-rated on the other

> **PRD reference:** Section 6 (Response Rating UX)

---

## 7. Automated quality scoring (LLM-as-judge)

**Problem this solves:** Most users don't rate responses. A quietly wrong answer that goes
unrated shows up as "no signal." The judge catches these.

**How it works:**
- After every agent reply, a separate (cheaper) LLM call scores the response
- Runs asynchronously — does not slow down the reply to the user
- Scores on three dimensions (0-3 each, max total = 9):
  - **Completeness** — does it answer the full question?
  - **Grounding** — is every claim traceable to a tool result?
  - **Actionability** — does it tell the user what to do next?
- If total score < 6/9 → auto-flagged as `needs_review` (no user rating required)

**Why this matters:**
- Catches wrong or incomplete answers even when users don't leave feedback
- Enables regression detection: if the rolling 7-day average score drops after a guide
  edit or system prompt change, the dashboard shows a quality alert
- Provides a consistent, comparable quality metric across all responses

**Relationship to user feedback:**
- The judge runs regardless of whether the user rates
- Both judge scores and user ratings appear in the feedback review dashboard
- They are complementary — user feedback is high-trust but low-coverage; the judge is
  medium-trust but 100% coverage

> **PRD reference:** Section 8, Layer 2 (LLM-as-Judge)

---

## 8. Guide gap tracking

**Problem this solves:** You can't fix what you don't know is missing. If users keep asking
about "waterfall distributions" and there's no guide for it, the agent fails silently.

**How it works:**
- Every time the agent searches user guides, it records whether it found at least one
  matching passage (`guide_search_hit = true/false`)
- Weekly, a background job looks at all `guide_search_hit = false` messages from the
  past 7 days
- It clusters them by keyword and produces a ranked report:

```
Week of 2026-06-02 — Guide Gap Report
  17 queries  →  "co-investor"           (no guide match)
  11 queries  →  "waterfall distribution"
   8 queries  →  "email template"
   5 queries  →  "bulk upload investors"
```

- This report is emailed to the CS team weekly
- The CS team reviews and assigns guide sections to write
- Target: ≥ 80% of repeated no-hit clusters have a guide update within 2 weeks

**Why this matters:**
- Drives proactive content creation — filling gaps before users complain
- Over time, the agent's coverage grows because the guides grow

> **PRD reference:** Section 8, Layer 3 (Guide Gap Tracking)

---

## 9. Golden test set (regression guard)

**Problem this solves:** A guide edit that fixes one thing can silently break another.
Without regression testing, you only find out when users complain.

**How it works:**
- A set of 20-50 canonical question + expected answer pairs is maintained
- Sources: past resolved tickets, positive-feedback responses on common queries
- Before any deploy that touches guide files, examples, system prompt, or tools, the
  test set is run:
  - Each question goes through the agent
  - Each response is scored by the judge
  - A test case **fails** if the judge score drops more than 1 point vs its baseline
  - Failing tests block the deploy
- Test cases are added by CS after resolving feedback items

**Industry context:** No major support platform (Intercom, Zendesk, Ada) currently blocks
deploys with automated test suites — they use advisory testing + post-deploy monitoring.
The PRD's approach is more ambitious. We may want to start with advisory-only (alert but
don't block) and graduate to blocking once the test set is mature.

> **PRD reference:** Section 8, Golden Test Set

---

## 10. Few-shot example library

**Problem this solves:** The agent needs to know what a "good answer" looks like — the
right tone, format, depth, and level of actionability.

**How it works:**
- A curated file (`cs_examples.md`) contains 10-20 canonical question → ideal answer pairs
- Loaded into the system prompt at request time (fresh on every request)
- CS team edits this file directly — no code change or deploy required
- New examples added from: positive-feedback responses on common queries, or responses
  CS would have written themselves for escalated tickets

**Example entry:**
```
## Q: Why is Investor X showing KYC incomplete?

**Good answer:**
Investor X (Acme Capital) is missing two fields: PAN card and address proof.
You can request re-submission from: Settings → Investors → Acme Capital → KYC.
The investor re-submits via their portal login. Once both fields are uploaded,
KYC status updates automatically within a few minutes.

**Why this is good:** names the specific missing fields from the DB, gives the
navigation path from the guide, tells the FM what the user needs to do.
```

**Industry context:** Production systems (Intercom, Ada) have moved toward natural-language
instruction rules rather than example libraries. A well-written system prompt with clear
instructions may be sufficient. The example library is a nice-to-have but not critical
for Phase 1.

> **PRD reference:** Section 8, Layer 4 (Few-Shot Example Library)

---

## 11. Permissions

| Action | Super Admin | Entity Admin | CS Manager | FM Ops User |
|--------|:-----------:|:------------:|:----------:|:-----------:|
| Use the chat agent (web + WhatsApp) | Yes | Yes | Yes | Yes |
| Submit feedback ratings | Yes | Yes | Yes | Yes |
| View feedback review queue | All entities | Own entity | All entities | No |
| Resolve / annotate feedback items | Yes | Own entity | Yes | No |
| View guide gap report | Yes | Own entity | Yes | No |
| Edit guide files / cs_examples.md | Yes | No | Yes | No |
| View judge scores | Yes | Own entity | Yes | No |
| Manage golden test set | Yes | No | Yes | No |
| View escalations | All entities | Own entity | All entities | No |
| Resolve escalations | Yes | No | Yes | No |
| Configure the agent record | Yes | Own entity | No | No |

> **PRD reference:** Section 9 (Permissions)

---

## 12. Success metrics

These are for Phase 1 (first 60 days):

| Metric | Target | What it means |
|--------|--------|---------------|
| Self-resolution rate | ≥ 70% | Agent answered without escalating AND (user gave positive feedback, OR no follow-up within 10 min, OR judge score ≥ 6/9) |
| User-rated positive feedback rate | ≥ 80% of rated | Of responses that users actually rated, 80%+ are positive |
| Automated judge score ≥ 6/9 | ≥ 85% | 85% of all responses score 6 or higher out of 9 |
| Guide search hit rate | ≥ 80% | For how-to queries, the guide search finds at least 1 passage 80% of the time |
| Guide gap items acted on weekly | ≥ 80% | 80% of no-hit query clusters get a guide update within 2 weeks |
| Median response time (WhatsApp) | < 30 seconds | End-to-end from user message to agent reply |
| Median response time (Web) | < 15 seconds | End-to-end from user message to agent reply |
| Escalations reviewed within SLA | 100% | Every escalation reviewed within 4 business hours |
| Golden test set pass rate | 100% | All test cases pass before deploy |

### Definition of "Resolved"

A query is **resolved** when:
- The agent produced a final answer (not an escalation), AND
- At least one of:
  - (a) the user gave positive feedback
  - (b) the user sent no follow-up within 10 minutes
  - (c) the automated judge scored completeness ≥ 2 AND grounding ≥ 2

A query is **unresolved** if it was escalated, received negative feedback, or was flagged
by the judge.

> **PRD reference:** Section 2 (Goals & Success Metrics)

---

## 13. What is NOT in scope

- **Embeddings / vector search** — guides are searched with keyword grep, not embeddings
- **Guide authoring UI** — guides are edited as markdown files, no in-app editor
- **Automated guide writing** — the agent flags gaps, but humans write content
- **Voice or email channel** — web chat and WhatsApp only
- **Multi-language** — English only
- **Ticket system integration** — escalations go to WATI inbox + email, no Jira/Zendesk
- **Proactive outreach** — the agent only responds to inbound messages
- **LP-facing support** — LPs use the LP Assistant; this agent is for FM users only

> **PRD reference:** Section 10 (Non-Goals)

---

## 14. Open questions

These need answers before or during implementation:

| # | Question | Owner | Needed by |
|---|----------|-------|-----------|
| 1 | Does the current WATI plan include `assignConversation` (team inbox API)? What is the Caphive CS team ID? | Ops | Sprint 1 |
| 2 | Where do the FM-facing User Guides live today — `docs/user_guides/` in this repo, Notion, or a help site? | Product | Sprint 1 |
| 3 | Should the agent handle queries from all FM-role users, or only Admins and Managers? | Product | Sprint 1 |
| 4 | Should prior WhatsApp message history (pre-AgentChatMessage era) be searchable? | Engineering | Sprint 2 |
| 5 | WATI inbound webhook: what is the signature header and HMAC algorithm for verification? | Ops | Sprint 2 |
| 6 | Should the web chat show feedback inline after each reply, or only at end of session? | Product | Sprint 4 |
| 7 | Which model should the LLM-as-judge use? A cheaper/faster model is preferred for cost. | Engineering | Sprint 5 |
| 8 | Should the golden test set live as a YAML file (version-controlled) or a DB table (editable in-app)? | Product | Sprint 5 |

> **PRD reference:** Section 11 (Open Questions)

---

## Feedback review workflow (how bad responses get fixed)

This ties together Sections 6, 7, and 8 — it's the process that makes the agent improve
over time.

**Items enter the review queue from two sources:**
1. User gives negative feedback (thumbs down / NO) → `needs_review`
2. LLM judge scores response < 6/9 → auto-flagged `needs_review`

**Each review item shows:**
- The user's original question
- The agent's full reply
- Which guide files were searched + which passages were returned (or "no match")
- Judge scores (completeness / grounding / actionability) with issue notes
- User rating + free-text note (if given)

**What the reviewer does:**

| What's wrong | Action |
|-------------|--------|
| Guide is incomplete or wrong | Edit the guide markdown file → re-test |
| Guide is missing entirely | Write a new guide section → re-test |
| A good example is needed | Add entry to `cs_examples.md` → re-test |
| Tool limitation (engineering needed) | File an engineering issue, mark "pending engineering" |
| Answer was actually correct | Dismiss with a note |

**Re-test:** The reviewer can replay the original question through the agent and see the
new response inline — verifying the fix worked before marking resolved.

**Resolution:** Reviewer marks resolved with a required note describing what changed
(e.g. "Added PAN card re-submission steps to kyc_guide.md §3.2").

> **PRD reference:** Section 8, Feedback Review Workflow
