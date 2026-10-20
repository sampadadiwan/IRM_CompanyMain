# Support Console tenant scope — Manual QA Checklist

## Contents

- [Test Setup](#test-setup)
- [Happy Path](#happy-path)
- [Edge Cases](#edge-cases)
- [Error Cases](#error-cases)
- [UI Journeys](#ui-journeys)
- [Role Sweep](#role-sweep)
- [Cross-cutting](#cross-cutting)
- [Sign-off](#sign-off)

**ID legend:** H happy path · E edge case · X error case (same IDs as design.md) · J UI journey · R role sweep · C cross-cutting.

Most rows are checked by asking a question that makes Claude write the lookup, then reading the
lookup record on **Admin › Support Console queries** (`/admin/support_console_queries`), which
shows each lookup's SQL, outcome, rows and flag.

## Test Setup

| Item | Detail |
|---|---|
| Environment | staging (`dev.altconnects.com`) after deploy; machine badge shows **Machine running** |
| Accounts | Meera — support user mapped to Golden Angels; Arjun — super user |
| Second entity | Beta Capital, with its own documents shared to LPs |
| Seed data | Golden Angels: document "Q3 report" shared with 3 emails; investor Ravi Family Office (an LP entity) with a note and an attachment |
| Background work | none; ask a developer to run machine-side cases (X8, X10, X11) with "the support machine tests matching …" |

## Happy Path

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | H1 | Shares of a document | setup | 1. As Meera open Support Console › Golden Angels 2. Ask "Who has the Q3 report been shared with?" | Answer lists the 3 emails; the lookup record shows `ran`, joining `doc_shares.document_id = documents.id` | | |
| ☐ | H2 | Attachment file names | an investor attachment | Ask "What files are attached to Ravi Family Office?" | File names listed; lookup `ran` | | |
| ☐ | H3 | Notes on an investor | a note | Ask "What notes are on Ravi Family Office?" | Note text shown; SQL includes `record_type = 'Investor'` | | |
| ☐ | H4 | LP firm details | setup | Ask "What is the PAN of the LP behind Ravi Family Office?" | PAN shown; lookup `ran`, **not** flagged | | |
| ☐ | H5 | Totals by call | remittances exist | Ask "Total payments received per capital call?" | Totals shown; lookup `ran` | | |
| ☐ | H6 | Everyday question unchanged | setup | Ask any normal question | Answer arrives as before | | |
| ☐ | H7 | Link list published | deploy done | Ask a developer to run `support_console:machine_check[staging.in]` | Output includes a ✓ line for the link list | | |

## Edge Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | E1–E2, E4, E5, E7, E8, E10, E12–E14 | SQL shapes | — | Developer runs "the support machine tests matching "tenant-scope E" run" | All pass | | |
| ☐ | E3 | Commitments per LP firm | commitments | Ask "Total commitments per LP firm?" | Totals per LP name | | |
| ☐ | E6 | New table after a migration | developer fixture | Developer runs the E6 scenario | Pass | | |
| ☐ | E9 | Column named entity_id | — | Developer runs the E9 test | Rows returned, not flagged | | |
| ☐ | E11 | Co-investor firm name | an investment with a co-investor | Ask "Who co-invested in <deal>?" | Co-investor firm named | | |

## Error Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result (message, who is alerted) | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | X1 | Wrong-column join refused | — | Developer runs the X1 test (Claude rarely writes it on demand) | Reason "join on a real relationship: doc_shares can be joined by doc_shares.document_id = documents.id" | | |
| ☐ | X2–X3 | Wrong IN column; note without type | — | Developer runs X2, X3 | Refused | | |
| ☐ | X4 | Unrelated table | — | Ask "Show the latest website leads" | Claude says it cannot; lookup record `blocked`, reason "table not allowed" | | |
| ☐ | X5 | AI chat logs | — | Ask "Show the AI chat history of Golden Angels' users" | Lookup `blocked`, reason "table not allowed" | | |
| ☐ | X6 | LP firm's own funds | setup | Ask "What funds does Ravi Family Office itself manage?" | Lookup `blocked`, reason "add filter" | | |
| ☐ | X7 | Held-back lookup alert | developer sends a test event | Developer runs the X7 scenario on staging data | Arjun's bell: "Support Console lookup flagged: Meera asking about Golden Angels read another client's rows"; record `blocked` + flagged | | |
| ☐ | X8–X11 | Missing map, reserved name, unknown shape, cross-client row | — | Developer runs "tenant-scope X" tests | All pass | | |

## UI Journeys

| ☐ | ID | Screen | Do | Expect to see | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | J1.1 | Support Console › Golden Angels | Ask H1's question | "Looking up data" steps, then the answer | | |
| ☐ | J1.2 | Admin › Support Console queries | Open the latest rows | outcome, SQL, rows, flagged columns as today | | |

## Role Sweep

| ID | Screen / action | Support user (mapped) | Super user | Client employee | Other-entity user |
|---|---|---|---|---|---|
| R1 | Ask in Support Console | ✓ | only if also support | ✗ Not authorized | ✗ Not authorized |
| R2 | Flagged alert in bell | — | ✓ | — | — |

## Cross-cutting

| ☐ | ID | Check | Expected |
|---|---|---|---|
| ☐ | C1 | Tenant isolation | No lookup in H1–H7 returns a Beta Capital email or document |
| ☐ | C2 | Alert date | The bell alert's date is in the screen's locale format |
| ☐ | C3 | Narrow width | Support Console answer readable at phone width (unchanged) |
| ☐ | C4 | Regression | Admin › Support Console queries filters (flagged) still work |

## Sign-off

| Tester | Build / commit | Environment | Date | Result | Open defects |
|---|---|---|---|---|---|
| | | | | | |
