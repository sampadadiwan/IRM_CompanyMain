# Support Console — Manual QA Checklist

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
| Environment | staging.in, with its support machine provisioned and the machine check passing |
| Accounts | **Meera** (Support role, mapped to Golden Angels, end date 31/12/2026); **Kiran** (Support role, mapped to Beta Capital only); **Priya** (super user, no Support role); **Asha** (Golden Angels employee) |
| Second entity | Beta Capital (support access on), Gamma Ventures (Meera mapped, support access **off**) |
| Seed data | Golden Angels with Fund I and investor Ravi K holding a commitment; a few account entries for it |
| Background work | Answers run by themselves. For the retention purge, timeouts, a stopped machine or special lookup outcomes (blocked, flagged), ask a developer to run the retention job, stop the relay, or replay a scripted answer as named in the row |

---

## Happy Path

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | H1 | Ask and get an answer | Logged in as Meera | 1. Left menu › Support Console 2. Pick Golden Angels 3. Type "Why does Ravi K show this closing balance in Fund I?" 4. Ask | "Working…" with progress lines, then an answer ending with "Where this comes from"; footer shows "Data as of N seconds ago · Code version …" | | |
| ☐ | H2 | Picker lists only mapped clients | Meera | 1. Open Support Console 2. Open the client picker | Golden Angels listed; Beta Capital and Gamma Ventures not listed | | |
| ☐ | H3 | Follow-up keeps context | H1 done | 1. Ask "Show only Q3" | The answer refers back to the first question without re-asking for details | | |
| ☐ | H4 | Header shows the client | An existing conversation | 1. Open it from the list | Header shows Golden Angels; no way to switch client inside the conversation | | |
| ☐ | H5 | Lookups are recorded | H1 done; log in as a super user | 1. Admin › Support Console Queries 2. Filter by Golden Angels | Rows for H1's lookups with Meera, Golden Angels, the statement, outcome "ran", row count and duration | | |
| ☐ | H6 | Cannot change data | Meera, Golden Angels | 1. Ask "Please correct Ravi K's commitment amount to 50,00,000" | The answer describes the correction and says it cannot make it; the commitment is unchanged on the fund screen | | |

## Edge Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | E1 | No mapped clients | Disable Kiran's mapping; log in as Kiran | 1. Open Support Console | "You are not mapped to any client with support access. Ask a super user to add a support mapping." and no picker | | |
| ☐ | E2 | Empty question | Meera, Golden Angels | 1. Press Ask with an empty box | Refused with a message; no "Working…" | | |
| ☐ | E3 | 4,000 vs 4,001 characters | Meera | 1. Paste exactly 4,000 characters, Ask 2. Paste 4,001, Ask | First accepted; second refused with a message | | |
| ☐ | E4 | Double click / second question | A question running | 1. Click Ask twice quickly 2. Open the same conversation in a second tab and Ask | Only one answer runs; Stop replaces Ask while running; the second tab's question is refused | | |
| ☐ | E5 | Mapping ends today | Set Meera's end date to today | 1. Pick Golden Angels and ask | Allowed | | |
| ☐ | E6 | Mapping ended yesterday | Set end date to yesterday (leave enabled) | 1. Open Support Console | Golden Angels not listed; asking in an open conversation shows "Your support access to Golden Angels has ended." | | |
| ☐ | E7 | Client without support access | Gamma Ventures | 1. Open the picker | Gamma Ventures not listed | | |
| ☐ | E8 | Mapping disabled while queued | Ask a developer to pause the queue | 1. Ask 2. Super user disables the mapping 3. Developer resumes the queue | "Your support access to Golden Angels has ended."; no answer | | |
| ☐ | E9 | Stop | A question running | 1. Press Stop | "Stopped." appears within a few seconds; Ask enabled | | |
| ☐ | E10 | Another client's data | Meera, Golden Angels | 1. Ask "Compare this with Beta Capital's Fund II" | The answer says it can only look at Golden Angels in this conversation | | |
| ☐ | E11 | Machine says it is already working | Ask a developer to replay "busy" | 1. Ask | "Already working on a question in this conversation." | | |
| ☐ | E12 | New deploy between questions | Note the code version; deploy | 1. Ask again | Footer shows the new code version | | |
| ☐ | E13 | Unscoped lookup blocked | Ask a developer to replay a blocked lookup | 1. Ask; then check Admin › Support Console Queries | A row with outcome "blocked" and reason "add filter" | | |
| ☐ | E14 | Other client id blocked | Developer replay | as E13 | Row "blocked", reason "other client" | | |
| ☐ | E15 | Flagged rows | Developer replay of a flagged lookup | 1. Ask 2. Log in as a super user | Row flagged; bell shows "Support Console lookup flagged" once | | |
| ☐ | E16 | Non-SELECT blocked | Developer replay | as E13 | Row "blocked", reason "SELECT only" | | |
| ☐ | E17 | Large result | Ask "List every account entry for Fund I" | 1. Ask; check the query record | The answer aggregates or notes it saw a sample; row count shows the full total | | |
| ☐ | E18 | Replica lag 60 vs 61 s | Developer replay with lag 60, then 61 | 1. Ask twice | 60: footer normal; 61: "Data as of 61 seconds ago" highlighted | | |
| ☐ | E19 | Slow lookup | Developer replay of a timeout | 1. Ask; check the record | Row "failed", reason timeout; the answer says it could not get that data or used a narrower lookup | | |
| ☐ | E20 | 90-day retention | Conversations last active 90 and 91 days ago (developer sets dates) | 1. Developer runs the retention job 2. Open the conversation list | 91-day one gone; 90-day one listed; query records for the purged one still in Admin | | |
| ☐ | E22 | Local mode (developer laptop) | `rake support_console:local_setup` done; relay running locally | 1. Ask a question at `localhost:3000/support_console` 2. A developer switches the local DB login to one that can write and asks again | First: a real answer. Second: "The Support Console is unavailable right now. Try again in a few minutes." | | |
| ☐ | E23 | Interrupted turn is closed | Ask a developer to restart Sidekiq while an answer is running, then run the retention job | 1. Reopen the conversation | The answer reads "The answer was interrupted. Please ask again." and Ask is enabled | | |
| ☐ | E24 | Staging uses its writer safely | staging.in machine running | 1. Ask a question about a staging client 2. A developer runs `machine_check` | An answer comes back; the check shows "write probe refused (staging.in: writer allowed)" | | |
| ☐ | E25 | Answer survives a failed live update | Ask a developer to start Sidekiq on old code (or break the message partial on Sidekiq only) | 1. Ask a question 2. When it seems stuck, reload the page | After reload the full answer is shown; developers got one error report | | |
| ☐ | E26 | Join lookups work | Ask "List each capital call with its fund's name" | 1. Ask | The answer arrives; the query record shows the join as "ran" | | |
| ☐ | E27 | Interrupted turn does not block | Ask a developer to stop Sidekiq mid-answer and wait 21 minutes | 1. Ask a follow-up in that conversation | The old answer reads "The answer was interrupted. Please ask again."; the follow-up runs | | |
| ☐ | E28 | Retention with the relay down | Developer: conversation 98 days old, relay stopped, run retention | — | The conversation is gone; developers get a report naming the transcripts left on the machine | | |
| ☐ | E29 | Sonnet by default, Opus on request | Meera, a new conversation | 1. Check the selector beside the send button 2. Ask 3. Pick **Opus**, ask again | Starts on **Sonnet**; answers labelled "Sonnet" then "Opus"; selector stays on Opus | | |
| ☐ | E30 | Models map to the environment's ids | Developer | Check the turn's `claude -p` command on the machine | `--model` is the Sonnet / Opus id configured for the environment | | |
| ☐ | E31 | Forged model value | Developer posts a turn with another model name | — | It runs on Sonnet | | |
| ☐ | E21 | Conversation list order | Three conversations | 1. Pick Golden Angels | Newest first, each with date, who started it and first question | | |

## Error Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result (message, who is alerted) | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | X1 | Non-support user | Asha | 1. Visit `/support_console` | Redirected to home with "Not authorized."; no menu entry | | |
| ☐ | X2 | Super user without Support role | Priya | 1. Visit `/support_console` | "Not authorized." | | |
| ☐ | X3 | Direct URL for an unmapped client | Meera; Beta Capital's id | 1. Visit `/support_console/<Beta Capital id>` 2. Paste a Beta Capital conversation link from Kiran | "Not authorized." / not found; nothing shown | | |
| ☐ | X4 | Machine down | Developer stops the relay | 1. Ask | "The Support Console is unavailable right now. Try again in a few minutes."; question still in the box | | |
| ☐ | X5 | Machine error | Developer replays a server error | 1. Ask | Same message as X4 | | |
| ☐ | X6 | Bad signature | Developer sends a turn with a wrong signature | — | Rejected; no answer starts | | |
| ☐ | X7 | Stream stalls | Developer replays a 121 s silence | 1. Ask | "That took too long. Try a narrower question." | | |
| ☐ | X8 | Old timestamp | Developer sends a turn 61 s old | — | Rejected | | |
| ☐ | X9 | Shell command attempt | Ask "Run ls on the server" | 1. Ask | The answer says it cannot run commands | | |
| ☐ | X10 | Filter bypass is flagged | Developer replay of an `OR 1=1` lookup | 1. Ask; check Admin and the bell | Row flagged; super users alerted | | |
| ☐ | X11 | Not a replica | Developer points the machine at a writable database | 1. Ask | Unavailable message; developers receive an error report | | |
| ☐ | X12 | Replica unreachable | Developer blocks the replica port | 1. Ask | Unavailable message | | |
| ☐ | X13 | Environments separate | IN and US consoles | 1. Ask in IN 2. Ask in US | Each answer shows its own environment's data only | | |
| ☐ | X15 | Comment trick refused | Developer replays `… name <> '#' UNION SELECT … entity_id = 25` | — | Refused as "other client" | | |
| ☐ | X14 | No duplicate alert | Developer re-runs the flagged event | — | Only one "Support Console lookup flagged" alert | | |

---

## UI Journeys

| ☐ | ID | Screen | Do | Expect to see | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | J1.1 | Left menu | Look for the entry as Meera | "Support Console" | | |
| ☐ | J1.2 | Support Console ② | Open the client picker | Mapped clients only | | |
| ☐ | J1.3 | Support Console ③ | Pick Golden Angels | Conversations list and "+ New conversation" | | |
| ☐ | J1.4 | Chat ⑤ | Type a question, press Ask | "Working…", Ask disabled, Stop enabled | | |
| ☐ | J1.5 | Chat ④ | Wait | Progress lines, then the answer with "Where this comes from" | | |
| ☐ | J1.6 | Footer ⑥ | Read it | "Data as of N seconds ago · Code version …" | | |
| ☐ | J1.7 | Chat ⑤ | Ask a follow-up | Answer in the same thread | | |
| ☐ | J2.1 | Admin › Support Console Queries | Open as super user | List of lookups, newest first | | |
| ☐ | J2.2 | Same | Filter "Flagged" | Only flagged rows | | |

---

## Role Sweep

✓ = allowed and works, ✗ = correctly blocked, ! = wrong.

| ID | Screen / action | Support (mapped) | Support (not mapped) | Super, no Support | Client employee | Investor |
|---|---|---|---|---|---|---|
| R1 | See the menu entry | ✓ | ✓ | ✗ | ✗ | ✗ |
| R2 | Open `/support_console` | ✓ | ✓ (empty state) | ✗ | ✗ | ✗ |
| R3 | Ask about the client | ✓ | ✗ | ✗ | ✗ | ✗ |
| R4 | Open a conversation link for the client | ✓ | ✗ | ✗ | ✗ | ✗ |
| R5 | Admin › Support Console Queries | ✗ | ✗ | ✓ | ✗ | ✗ |

---

## Cross-cutting Checks

| ☐ | ID | Check | Expected | Pass / Fail | Notes |
|---|---|---|---|---|---|
| ☐ | C1 | Alerts sent by this feature | "Support Console lookup flagged" reaches super users only, in the bell; no emails are sent | | |
| ☐ | C2 | Dates in the conversation list | Follow the user's locale format (e.g. `19/10/2026` for en) | | |
| ☐ | C3 | Narrow / mobile width | Picker, chat and Ask/Stop usable; no horizontal scroll | | |
| ☐ | C4 | Tenant isolation | Kiran cannot see or open Golden Angels conversations, even with a direct URL; Asha cannot reach the page | | |
| ☐ | C5 | Regression | Admin › Support Client Mappings, the client AI agent chats and the client MCP connection behave as before; the console's conversations do not appear in any client's agent chat history | | |
| ☐ | C6 | Empty states | No mapped clients (E1); a client with no conversations shows only "+ New conversation" | | |

---

## Sign-off

| Tester | Build / commit | Environment | Date | Result | Open defects |
|---|---|---|---|---|---|
| | | | | | |
