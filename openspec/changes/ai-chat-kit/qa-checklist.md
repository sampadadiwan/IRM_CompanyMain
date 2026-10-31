# AI Chat Kit — Manual QA Checklist

> **Audience:** Testers running the feature by hand on a deployed build. No code knowledge needed.
> **Companion documents:** [Proposal](proposal.md) · [Design](design.md)

> **How to use:** work top to bottom. Tick ☐ → ☑ and write Pass or Fail for each row. For a Fail,
> put the defect link in Notes. Row IDs match the design's worked examples (H/E/X) and UI journeys
> (J), so a failure maps straight to the automated test that should have caught it.

**ID legend:** **H** = Happy path · **E** = Edge case · **X** = Error case · **J** = UI journey
step (J1.3 = journey 1, step 3) · **R** = Role sweep · **C** = Cross-cutting check

---

## Contents

- [Test Setup](#test-setup)
- [Happy Path](#happy-path)
- [Edge Cases](#edge-cases)
- [Error Cases](#error-cases)
- [UI Journeys](#ui-journeys)
- [Role Sweep](#role-sweep)
- [Cross-cutting Checks](#cross-cutting-checks)
- [Sign-off](#sign-off)

---

## Test Setup

| Item | Detail |
|---|---|
| Environment | Staging (IN), build under test |
| Accounts | Priya Sharma — fund manager at Golden Angels with Assistant and support-agent access; Kavya — investor user, LP in Golden Angels Fund I; a support user for the Support Console |
| Second entity | Arjun — fund manager at Beta Capital |
| Seed data | Golden Angels: Fund I; investor record Acme Robotics; KPI report "Q3 2026" for Acme with one PDF; Portfolio Assistant agent (chat on, suggestions "Show fill rate across deals", "Which deals need attention?"); Customer Support agent; LP assistant enabled |
| Background work | Assistants answer through a background job — wait up to a minute; if nothing arrives, ask a developer to check the job queue |
| Old answers | Before testing, have Priya keep one Fund I conversation from before the release, to check it shows in the new list |

---

## Happy Path

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | H1 | Support Console looks the same | Support user | 1. Open Support Console 2. Open a conversation 3. Ask a question | Same layout, sidebar, follow-ups and Ask buttons as before the release | | |
| ☐ | H2 | Assistants sidebar | Priya has Fund I chats | 1. Fund I › Assistant | Sidebar lists her Fund I chats, newest first, each "first question" over "Priya Sharma · time/date" | | |
| ☐ | H3 | Ask on the Assistants page | — | 1. Type "Which LPs are overdue on Call 3?" 2. Press Enter | Grey question bubble on the right; "Thinking…"; then the answer, any table inside a bordered card | | |
| ☐ | H4 | Export still works | H3 done | 1. Export ▾ › Export PowerPoint 2. Open the file | A slide contains the answer's table | | |
| ☐ | H5 | KPI chat | KPI report Q3 2026 | 1. Analysis tab › open a chat 2. Ask "Summarise revenue" | Kit layout with the report's chats in the sidebar; answer streams in | | |
| ☐ | H6 | Floating window ask | Acme Robotics page | 1. Click Need help? 2. Type a question, Enter | Kit window; question bubble; answer; **no** 👍/👎 | | |
| ☐ | H7 | Window conversations | 2 earlier conversations on Acme | 1. Window › Conversations | 2 rows: first question · who · when | | |
| ☐ | H8 | LP chat | Log in as Kavya | 1. Dashboard › Need help? 2. Ask "What is my unfunded commitment?" | Kit window; only Kavya's conversations listed; answer about her own commitment | | |
| ☐ | H9 | Customer Support 👍/👎 | Priya, dashboard | 1. Open the Customer Support agent 2. Ask 3. Click 👎 4. Type "Wrong fund" 5. Send 6. Close, reopen the conversation | 👎 filled red; "Thanks for your feedback"; after reopening, 👎 still filled; the rating appears in the CS feedback review queue | | |
| ☐ | H10 | Escalated badge | — | 1. Customer Support agent 2. Type "I need to talk to someone about my capital call notice" 3. Conversations | The reply says a person will follow up; the row shows **Escalated** | | |
| ☐ | H11 | Suggestions | Fresh window, Portfolio Assistant agent | 1. Click the text "Show fill rate across deals" 2. New chat 3. Click **Ask** on "Which deals need attention?" | Step 1 fills the box without sending; step 3 sends immediately | | |
| ☐ | H12 | Maximise | Window open | 1. Click ⤢ | Window widens; conversation list shows beside the thread | | |

## Edge Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | E1 | First visit | A fund Priya never used the assistant on | 1. Open its Assistant | One row "New conversation"; greeting "Hello, Priya" (screens that create no chat on open, e.g. the floating window, say "No conversations yet.") | | |
| ☐ | E2 | Quoted question | A conversation started with `"Why is TSTF2 overpaid?"` (with quotes) | 1. Look at its row | Title shows without the quote marks | | |
| ☐ | E3 | Dates by locale | A conversation from 28 Oct 2026 | 1. View its row under English (UK) and English (US) | 28/10/2026 and 10/28/2026 | | |
| ☐ | E4 | Blank question | — | 1. Press Enter in an empty box | Nothing is sent | | |
| ☐ | E5 | No documents | KPI report without PDF/CSV | 1. Open its chat | No document picker | | |
| ☐ | E6 | Fund Assistant (no record) | — | 1. Funds list › Assistant | Header shows the assistant without a record link | | |
| ☐ | E7 | No stray italics | — | 1. Ask something whose answer names `fund_id` and `entity_id` | No italics between them | | |
| ☐ | E8 | Charts still show | An assistant answer that includes a chart | 1. Open it | The chart renders | | |
| ☐ | E9 | New chat is new | Window with a conversation from 5 minutes ago | 1. New 2. Ask | A new row appears in Conversations | | |
| ☐ | E10 | Reopened conversation continues | 2 conversations | 1. Conversations › the older one 2. Ask | The question is added to that older conversation | | |
| ☐ | E11 | WhatsApp unchanged | A developer confirms | 1. Send a WhatsApp question to an agent (if configured) | Behaves as before | | |
| ☐ | E12 | No rating on other agents | — | 1. Portfolio Assistant answer | No 👍/👎 | | |
| ☐ | E13 | Record scoping | Conversations on Acme and on another company | 1. Window on Acme › Conversations | Only Acme's | | |
| ☐ | E14 | Long history | A developer seeds 51 chats | 1. Open the assistant | 50 rows; footer "50+ conversations" | | |
| ☐ | E15 | KPI blank answer | Ask a developer to simulate | 1. Ask | "The assistant was unable to generate a response…" shown in the answer | | |
| ☐ | E16 | One icon set | — | 1. Inspect the three screens | Tabler icons only (no Font Awesome / Bootstrap Icons look) | | |
| ☐ | E18 | Idle conversation | Window conversation last used over 30 minutes ago | 1. Open the window | A new, empty conversation; the older one under Conversations; opening it and asking continues it | | |
| ☐ | E17 | Microphone | Browser with a mic | 1. Hold 🎤, say "Call 3 status", release | The question "Call 3 status" appears and is answered | | |

## Error Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result (message, who is alerted) | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | X1 | AI unreachable | A developer blocks the AI provider on staging | 1. Ask in a window | "Not answered" with "AI service is temporarily unreachable (network/DNS). Please try again shortly."; question back in the box | | |
| ☐ | X2 | Agent failure | A developer forces a failure | 1. Ask | "Not answered" with "Chat agent execution failed" | | |
| ☐ | X3 | Assistant timeout | A developer forces a timeout | 1. Ask on the Assistants page | "The request timed out. Please try again or refine your query." | | |
| ☐ | X4 | KPI stream error | A developer forces an error | 1. Ask in KPI chat | An in-app alert to Priya, as before | | |
| ☐ | X5 | Console still strict | Support user | 1. Ask the Console something whose answer quotes HTML | No hidden or styled content from the answer | | |
| ☐ | X6 | Scripts stripped | A developer seeds an answer with a script | 1. Open it | No script runs; text only | | |
| ☐ | X7 | Another investor's conversation | Two investors | 1. As Kavya, ask a developer to replay a request with the other investor's conversation id | Her question goes to her own conversation | | |
| ☐ | X8 | Other entity's KPI chat | Arjun | 1. Open a Golden Angels chat link | Refused | | |
| ☐ | X9 | Feedback on another's message | Arjun | 1. A developer replays a rating request for Priya's message | Refused | | |

---

## UI Journeys

Journey 1 — Customer Support agent window (design Part 2 "What users see").

| ☐ | ID | Screen | Step | Expected | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | J1.1 | Dashboard | Click Need help? | Kit window titled "Customer Support" | | |
| ☐ | J1.2 | Window | Click Conversations | Kit rows; escalated ones with **Escalated** | | |
| ☐ | J1.3 | Window | Read a question | Grey bubble on the right | | |
| ☐ | J1.4 | Window | Read the answer | Plain text, tables in cards, Copy · time on hover | | |
| ☐ | J1.5 | Window | Click 👎 | 👎 filled red; note box opens | | |
| ☐ | J1.6 | Window | Type a note, Send | "Thanks for your feedback" | | |
| ☐ | J1.7 | Window | Type a new question, Enter | Question bubble, then "Thinking…", then the answer | | |

---

## Role Sweep

| ☐ | ID | Role | Assistants page | KPI chat | Floating window | Expected |
|---|---|---|---|---|---|---|
| ☐ | R1 | Fund manager (Priya) | Opens | Opens | Opens (Portfolio Assistant, Customer Support) | Own conversations only |
| ☐ | R2 | Investor (Kavya) | No button | No tab | LP chat opens | Own conversations only |
| ☐ | R3 | Other entity (Arjun) | Golden Angels links refused | Refused | No Golden Angels conversations | Nothing of Golden Angels visible |

---

## Cross-cutting Checks

| ☐ | ID | What to check | Steps | Expected | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | C1 | Escalation email | H10 | The CapHive CS team receives the escalation email as before; dates in "Mon dd, yyyy" | | |
| ☐ | C2 | Screen dates | Rows older than today | Locale format (C: E3) | | |
| ☐ | C3 | Narrow width | Phone-width browser on each screen | Sidebar stacks above the thread; window stays usable | | |
| ☐ | C4 | Tenant isolation | R3 | No cross-entity data | | |
| ☐ | C5 | Regression: Support Console | Ask, Stop, follow-ups, sidebar | Unchanged | | |
| ☐ | C6 | Regression: KPI Analysis tab list | Open the tab | Chat list table as before; opening a chat shows the kit page | | |
| ☐ | C7 | Regression: Export menu | AI Slides, Chat Slides, Efficiency Report | Each opens as before | | |
| ☐ | C8 | Regression: CS review queue | After H9 | The rating and note are in the queue | | |
| ☐ | C9 | Old conversations | The pre-release conversation from setup | Listed with its first question and opens correctly | | |

---

## Sign-off

| Tester | Build / commit | Environment | Date | Result | Open defects |
|---|---|---|---|---|---|
| | | | | | |
