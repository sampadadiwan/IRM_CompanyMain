# Client Ops Assistant — Manual QA Checklist

> **Audience:** Testers running the feature by hand on a deployed build. No code knowledge needed.
> **Companion documents:** [Proposal](proposal.md) · [Design](design.md) · [Business rules](business-rules.md) · [Security](security.md)

> **How to use:** work top to bottom. Tick ☐ → ☑ and write Pass or Fail for each row. For a Fail, put
> the defect link in Notes. Row IDs match [business-rules.md](business-rules.md) (H/E/X) and the UI
> journeys (J), so a failure maps straight to the automated test that should have caught it.

**ID legend:** **H** = Happy path · **E** = Edge case · **X** = Error case · **J** = UI journey step
(J2.3 = journey 2, step 3) · **R** = Role sweep · **C** = Cross-cutting check · **S** = Security check

---

## Contents

- [Test Setup](#test-setup)
- [Happy Path](#happy-path)
- [Edge Cases](#edge-cases)
- [Error Cases](#error-cases)
- [UI Journeys](#ui-journeys)
- [Role Sweep](#role-sweep)
- [Cross-cutting Checks](#cross-cutting-checks)
- [Security Checks](#security-checks)
- [Sign-off](#sign-off)

---

## Test Setup

| Item | Detail |
|---|---|
| Environment | staging, `https://dev.altconnects.com` |
| Accounts | Priya (CapHive super user); Meera (Orion Test company admin, Ops Assistant ticked); Arjun (Orion Test employee, Ops Assistant ticked, access to Demo Fund 2, **no** access to Orios Fund I); Ravi (Orion Test employee, Ops Assistant **not** ticked); Kiran (investor user in Demo Fund 2) |
| Second entity | Golden Angels with its own admin, Ops Assistant switched on, its own Anthropic key |
| Seed data | Orion Test (1548) with Demo Fund 2 (275 commitments, ₹18,38,50,93,602.71) and Orios Fund I; Orion Test's Anthropic key in Entity Settings; files `call16.xlsx`, `bank_oct.pdf`, `big.xlsx` (25 MB), `tool.exe` |
| Background work | Uploads finish on their own (watch the card). Idle stop: wait 30 minutes or ask a developer to run the idle-stop job. Card expiry: ask a developer to run the expiry job after back-dating a card. Rows marked "Needs a developer" are checked by a developer on the machine or with a token |

---

## Happy Path

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | H1 | Ask a question, get a sourced answer | Arjun, machine running | 1. he asks "Who still owes money on Demo Fund 2?"; the assistant works 2. Watch the page / card | progress lines appear live, then the answer with 11 investors, ₹44,33,53,987.54 and a link to the fund's remittances; no card | |  |
| ☐ | H2 | A write becomes a waiting card | Arjun asks to prepare Call 16 | 1. the assistant prepares the call 2. Watch the page / card | card "Waiting for your approval" with CapHive's facts; Demo Fund 2 still has 15 calls | |  |
| ☐ | H3 | Approve, run, watch, report | card from H2 + upload card for 275 remittances | 1. Arjun approves the upload card; API returns upload 2850; background check sees 275/275 2. Watch the page / card | card "Done", follow-up answer with the check table; one bell + one email to Arjun | |  |
| ☐ | H4 | Switch on prepares a machine and folder | Golden Angels has no machine | 1. Priya ticks Ops Assistant 2. Watch the page / card | Entity screen shows the assistant machine Ready (stopped); Documents › Ops Assistant with Skills, Learnings, Proposed, Reports | |  |
| ☐ | H5 | Change history shows the approver | an approved card PATCHes investor "Ravi K" email | 1. the action runs 2. Watch the page / card | the investor's audit shows Arjun as the user | |  |
| ☐ | H6 | Reject | waiting card | 1. Arjun clicks Reject 2. Watch the page / card | card "Rejected by Arjun"; nothing written; no job enqueued | |  |
| ☐ | H7 | Task report saved | H3 completed | 1. the runner reports 2. Watch the page / card | "2026-10-22 Call 16 Demo Fund 2.md" in Ops Assistant › Reports with steps, checks, results | |  |
| ☐ | H8 | Propose, confirm, use | Arjun's conversation proposes a learning "Bank statements — folio after FOLIO-" | 1. Meera confirms it as a Learning; Arjun starts a new chat 2. Watch the page / card | document moved Proposed → Learnings; the next turn's brief contains it; Meera got one notification | |  |

## Edge Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | E1 | Company admin reads a colleague's chat | Arjun's conversation | 1. Meera opens it 2. Watch the page / card | shown read-only: no ask box, no approve buttons | |  |
| ☐ | E2 | One question at a time | Arjun's turn running | 1. he submits again (or posts directly) 2. Watch the page / card | ask box disabled; direct POST refused, no second job | |  |
| ☐ | E3 | Stop | turn running | 1. Arjun presses Stop 2. Watch the page / card | "Stopped."; no approval card appears afterwards | |  |
| ☐ | E4 | Exactly 5 attachments, 20 MB | five files, one exactly 20 MB | 1. Arjun asks 2. Watch the page / card | accepted; all five listed on his message | |  |
| ☐ | E5 | Sixth attachment | six files | 1. Arjun asks 2. Watch the page / card | refused "Up to 5 files per question"; nothing sent | |  |
| ☐ | E6 | Question of exactly 4,000 characters | 4,000-char text | 1. Arjun asks 2. Watch the page / card | accepted; 4,001 refused with the limit | |  |
| ☐ | E7 | Produced file downloadable | the assistant produces remittances_call16.xlsx | 1. Arjun clicks it in the answer and on the card 2. Watch the page / card | same file downloads from both | |  |
| ☐ | E8 | Delete a conversation with a waiting card | Arjun's chat has a waiting card | 1. Meera deletes the chat 2. Watch the page / card | chat gone; files no longer downloadable; card cancelled (approve → not found); | |  |
| ☐ | E9 | Key changed mid-turn | turn running with key A | 1. Meera saves key B 2. Watch the page / card | running turn finishes on A; next turn sends B | |  |
| ☐ | E10 | Follow-up turn re-checks permission | H3's background check finishes; Arjun's user permission was unticked meanwhile | 1. follow-up turn starts 2. Watch the page / card | turn refused; card still shows the result; no answer generated; Arjun not notified by the assistant | |  |
| ☐ | E11 | Two cards from one turn | the assistant prepares two changes in one answer | 1. Developer runs the machine test 2. Read the result | two cards in order, each with its own Approve | |  |
| ☐ | E12 | Stale turn swept | an answer that has been "Working" for 21 minutes | 1. ask a developer to run the stale-turn sweep 2. Watch the page / card | the answer shows it was interrupted | | Needs a developer (machine or token level) |
| ☐ | E13 | Question to a stopped machine | machine stopped | 1. Arjun asks 2. Watch the page / card | "Starting your assistant (about 2 minutes)", start!, health, then answer | |  |
| ☐ | E14 | Idle at exactly 30 minutes | last activity 30:00 ago, nothing running | 1. ask a developer to run the idle-stop job (or wait) 2. Watch the page / card | stopped (≥ 30 min stops; 29:59 does not) | |  |
| ☐ | E15 | Watching keeps it running | an upload still being checked in the background, last question 45 minutes ago | 1. ask a developer to run the idle-stop job (or wait) 2. Watch the page / card | not stopped | |  |
| ☐ | E16 | Second entity isolated | Orion Test and Golden Angels machines | 1. A Golden Angels user asks a question 2. Watch the page / card | sent to its own relay URL with its own secret; Orion's secret refused by Golden's relay | | Needs a developer (machine or token level) |
| ☐ | E17 | api_get refuses a non-GET | Claude calls api_get with a POST-like path or another host | 1. Developer runs the machine test 2. Read the result | refused by api-mcp; nothing sent | | Needs a developer (machine or token level) |
| ☐ | E18 | Claude never sees the token | turn running | 1. Claude reads env / `/proc` 2. Watch the page / card | token absent from Claude's env; `/proc` denied | | Needs a developer (machine or token level) |
| ☐ | E19 | Transform with no network | `ops-ruby build.rb` reading call16.xlsx | 1. script writes out.xlsx and tries `Net::HTTP` 2. Watch the page / card | file written in the workspace; network call fails, reported | | Needs a developer (machine or token level) |
| ☐ | E20 | Read token cannot write | (developer) a token made for a question | 1. (developer) try to create a call with it 2. Watch the page / card | refused "read-only token"; reading works | | Needs a developer (machine or token level) |
| ☐ | E21 | Investor notice flagged | card to approve Drawdown 16 | 1. shown 2. Watch the page / card | "This sends notices to investors" above Approve | |  |
| ☐ | E22 | Double click | waiting card | 1. two approve POSTs at once 2. Watch the page / card | one job, one API call; second returns the current state | |  |
| ☐ | E23 | Expiry at exactly 24 h | card created 24:00 ago | 1. Arjun approves 2. Watch the page / card | "Expired"; 23:59 still approves | |  |
| ☐ | E24 | Preconditions changed | precondition "commitments = 275"; Meera adds the 276th | 1. Arjun approves 2. Watch the page / card | "The data changed since this was prepared…"; status stale; nothing written | |  |
| ☐ | E25 | Preconditions equal, money as text | expected "18385093602.71", API returns 18385093602.71 | 1. approve 2. Watch the page / card | holds; runs | |  |
| ☐ | E26 | Card with a file shows CapHive's facts | upload card with remittances_call16.xlsx | 1. shown 2. Watch the page / card | "275 rows · Σ Call Amount ₹91,92,54,680.13", columns listed, labelled "Checked by CapHive" | |  |
| ☐ | E27 | Zero-row upload | proposed file with headers only | 1. proposed 2. Watch the page / card | card refused "The file has no rows" | |  |
| ☐ | E28 | Investor access card allowed | card POSTs investor access for a new LP | 1. Arjun approves 2. Watch the page / card | runs (investor access is not on the never-list), flagged as notifying | |  |
| ☐ | E29 | Partial upload | upload 272/275 | 1. background check finishes 2. Watch the page / card | card "Partly done"; follow-up turn lists 3 failed rows and offers a new card; no retry | |  |
| ☐ | E30 | Not notified twice | background check already reported | 1. watch job runs again (retry/duplicate) 2. Watch the page / card | no second notification, no second follow-up | |  |
| ☐ | E31 | Synchronous 201 | card PATCH investor email | 1. runs 2. Watch the page / card | 201 → succeeded straight away, no background check | |  |
| ☐ | E32 | Watcher back-off | upload processing 10 minutes | 1. background check 2. Watch the page / card | polls every 30 s for 5 min then 60 s; each poll touches machine activity | |  |
| ☐ | E33 | Write token lifetime | an action runs | 1. after the request 2. Watch the page / card | write token revoked; reuse → 401 | | Needs a developer (machine or token level) |
| ☐ | E34 | Discard | proposed learning | 1. Meera discards 2. Watch the page / card | document deleted; not in the next brief | |  |
| ☐ | E35 | Admin-written skill | Meera uploads "Raise a capital call.md" into Skills | 1. Arjun's next turn 2. Watch the page / card | brief includes it | |  |
| ☐ | E36 | Brief cap | 60 documents in Learnings | 1. turn starts 2. Watch the page / card | 50 documents sent + "truncated: 10 more" note | |  |
| ☐ | E37 | Machine replaced | conversation with history; machine terminated | 1. Arjun continues it 2. Watch the page / card | the machine is rebuilt (about 10 minutes); the assistant remembers the earlier conversation | |  |
| ☐ | E38 | Switch off keeps data | Orion Test switched off | 1. Priya unticks 2. Watch the page / card | machine stopped; menu hidden; conversations and the Ops Assistant folder kept; switching on again starts the same machine | |  |

## Error Cases

| ☐ | ID | What to check | Preconditions | Steps | Expected result (message, who is alerted) | Pass / Fail | Notes |
|---|---|---|---|---|---|---|---|
| ☐ | X1 | Entity permission off | Golden Angels permission off | 1. its admin opens /ops_assistant 2. Watch the page / card | no menu item; "Not authorized." | |  |
| ☐ | X2 | User permission off | Ravi | 1. opens /ops_assistant 2. Watch the page / card | "Not authorized."; nothing enqueued | |  |
| ☐ | X3 | User on, entity off | Arjun's flag on; Orion switched off | 1. Arjun opens it 2. Watch the page / card | menu hidden; "Not authorized." | |  |
| ☐ | X4 | Investor user | Kiran | 1. opens /ops_assistant 2. Watch the page / card | "Not authorized." | |  |
| ☐ | X5 | Colleague's chat | Arjun's chat | 1. Ravi (if permitted) or another employee opens it 2. Watch the page / card | "Not authorized." | |  |
| ☐ | X6 | No key | Orion key blank | 1. Arjun opens the page 2. Watch the page / card | "Add your Anthropic API key in Entity Settings…"; ask disabled; CapHive key never used | |  |
| ☐ | X7 | Key refused | the Anthropic key is wrong (ask a developer to set an invalid key) | 1. Ask a question 2. Watch the page / card | "Your Anthropic key was refused…"; no retry with another key | |  |
| ☐ | X8 | Fund the user cannot see | Arjun asks about Orios Fund I | 1. the API returns 403/empty 2. Watch the page / card | answer "You don't have access to that fund." with no figures | |  |
| ☐ | X9 | Relay unreachable | machine running, relay down | 1. Ask a question 2. Watch the page / card | "Your assistant is unavailable right now"; turn failed; token revoked | |  |
| ☐ | X10 | Only super user switches on | Meera | 1. edits Orion's permissions to tick Ops Assistant 2. Watch the page / card | refused; flag unchanged | |  |
| ☐ | X11 | Provision fails | EC2 launch error | 1. Priya ticks it on 2. Watch the page / card | the Entity screen shows the machine failed; super users get a bell notification; the page says "unavailable" | |  |
| ☐ | X12 | Start times out | machine never healthy in 5 min | 1. Ask a question 2. Watch the page / card | turn failed "unavailable"; one retry only | |  |
| ☐ | X13 | Asked to delete | Arjun asks to delete Call 3 | 1. Ask a question 2. Watch the page / card | no card; "I can't do that — please use the Capital Calls screen." | |  |
| ☐ | X14 | Script reaches for the API | `ops-ruby` script calls CapHive | 1. Developer runs the machine test 2. Read the result | connection refused; no token in env | | Needs a developer (machine or token level) |
| ☐ | X15 | API gap | Arjun asks for something no endpoint does | 1. the assistant reports a missing API 2. Watch the page / card | answer "CapHive doesn't let me do this through its API yet" with screen steps; a developer confirms the gap was recorded without client data | |  |
| ☐ | X16 | Permission refused by the API | Arjun's role cannot approve calls | 1. card approved 2. Watch the page / card | API 403 → card failed with the screen's message; nothing written | |  |
| ☐ | X17 | Token after the turn | turn finished | 1. its token used 2. Watch the page / card | 401 | | Needs a developer (machine or token level) |
| ☐ | X18 | Forbidden at proposal | the assistant is asked (developer-forced) to propose deleting a call | 1. Developer runs the machine test 2. Read the result | stored as refused; no buttons; assistant told | | Needs a developer (machine or token level) |
| ☐ | X19 | Forbidden at approve | a waiting card whose path is `/entity_settings/4.json` (rules changed since) | 1. approve 2. Watch the page / card | refused; nothing written | | Needs a developer (machine or token level) |
| ☐ | X20 | Another user approves | Arjun's waiting card | 1. Meera POSTs approve 2. Watch the page / card | 403; card unchanged | |  |
| ☐ | X21 | Permission removed while waiting | Arjun's waiting card; Meera unticks his permission | 1. Arjun approves 2. Watch the page / card | "Not authorized."; nothing written | |  |
| ☐ | X22 | Undo upload forbidden | the assistant is asked (developer-forced) to propose undoing an upload | 1. Developer runs the machine test 2. Read the result | refused | | Needs a developer (machine or token level) |
| ☐ | X23 | API 5xx | approved card; API 500 | 1. runs 2. Watch the page / card | card failed with the error; no retry; Arjun notified (failed) | |  |
| ☐ | X24 | Timeout after send | API does not answer in 60 s | 1. runs 2. Watch the page / card | card "unknown — check on the screen" with link; Arjun notified; never re-sent | |  |
| ☐ | X25 | Upload job failed | import upload outcome failed | 1. background check 2. Watch the page / card | card failed; follow-up turn explains; notified once | |  |
| ☐ | X26 | Watch limit | upload still processing after 2 h | 1. background check 2. Watch the page / card | card unknown; notified; machine may idle-stop | |  |
| ☐ | X27 | Entity switched off mid-run | action running | 1. Priya switches off 2. Watch the page / card | the in-flight request completes; no follow-up turn; result kept on the card | |  |
| ☐ | X28 | Employee cannot confirm | proposed learning | 1. Arjun POSTs confirm 2. Watch the page / card | refused; still in Proposed | |  |
| ☐ | X29 | Other client's knowledge | Orion's Learnings has 3 documents | 1. A Golden Angels user asks a question 2. Watch the page / card | Golden's brief contains none of them; Golden's machine cannot read Orion's S3 prefix | | Needs a developer (machine or token level) |
---

## UI Journeys

| ☐ | ID | Screen | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | J1.1 | Entity › Orion Test › Permissions (Priya) | Tick **Ops Assistant**, save | "Ops Assistant switched on. The assistant machine is being prepared (about 10 minutes)." | | |
| ☐ | J1.2 | Entity › Orion Test (Priya) | Wait, refresh | Machine status **Ready (stopped)** | | |
| ☐ | J1.3 | Ops Assistant page (Meera), key removed | Open it | "Add your Anthropic API key in Entity Settings to use the Ops Assistant." with a link | | |
| ☐ | J1.4 | Entity Settings › AI (Meera) | Paste the key, save; reopen Entity Settings | key shown masked; Ops Assistant page opens | | |
| ☐ | J1.5 | Users › Arjun › Edit › Permissions (Meera) | Tick **Ops Assistant**, save | Arjun sees **Ops Assistant** in his menu | | |
| ☐ | J2.1 | Ops Assistant (Arjun) | Type "Prepare Call 16 on Demo Fund 2: 5% of commitment, due 15 Nov, notice 31 Oct", press Enter | "Starting your assistant (about 2 minutes)" if stopped, then progress lines | | |
| ☐ | J2.2 | Same | Wait | Approval card: ① action line, ② "Checked by CapHive" facts (275 rows, Σ ₹91,92,54,680.13), ③ no investor warning on the remittance card, ④ Approve / Reject / Ask for a change | | |
| ☐ | J2.3 | Card | Click **Download file** | `remittances_call16.xlsx` downloads, 275 rows | | |
| ☐ | J2.4 | Card | Click **Approve** | "Approved by Arjun <time> — running"; Arjun can close the page | | |
| ☐ | J2.5 | Bell + email | Wait for the upload | Bell + email "Ops Assistant: Call 16 is ready to approve."; result table in the chat | | |
| ☐ | J2.6 | Second card | Card says "This sends notices to investors"; click Approve | "Call 16 approved — 275 investors notified." | | |
| ☐ | J3.1 | Ops Assistant (Arjun) | Ask "Who still owes money on Demo Fund 2?" | 11 investors, ₹44,33,53,987.54, table, link to the fund's remittances; no card | | |
| ☐ | J4.1 | Bank recon conversation | Attach `bank_oct.pdf`, ask to reconcile | Answer + "I've suggested this to your admin for next time" | | |
| ☐ | J4.2 | Ops Assistant › What I've learned (Meera) | See the proposal; click **Confirm** as Learning | moved to Learnings; also visible in Documents › Ops Assistant › Learnings | | |
| ☐ | J4.3 | Documents › Ops Assistant › Skills (Meera) | Upload "Raise a capital call.md" | listed in Skills; used in Arjun's next chat | | |
| ☐ | J5.1 | Conversation list | Create 6 chats | grouped Today / Yesterday / Previous 7 days / Older; **Search chats** appears | | |
| ☐ | J5.2 | A running answer | Click **Stop** | "Stopped." | | |
| ☐ | J5.3 | Conversation menu (Meera) | Delete Arjun's conversation | gone from the list; its files no longer download | | |

---

## Role Sweep

| ☐ | ID | Role | Open page | Ask | See own chats | See others' chats | Approve own card | Approve others' card | Confirm learnings | Switch on for entity |
|---|---|---|---|---|---|---|---|---|---|---|
| ☐ | R1 | Employee, Ops Assistant ticked (Arjun) | yes | yes | yes | "Not authorized." | yes | no (read-only) | no | no |
| ☐ | R2 | Company admin, ticked (Meera) | yes | yes | yes | read-only | yes | no (read-only) | yes | no |
| ☐ | R3 | Employee, not ticked (Ravi) | "Not authorized." | no | — | — | — | — | — | no |
| ☐ | R4 | Investor (Kiran) | "Not authorized." | no | — | — | — | — | — | no |
| ☐ | R5 | Golden Angels admin | own entity only; Orion's chats "Not authorized." | own entity | own | — | own | no | own entity | no |
| ☐ | R6 | CapHive super user (Priya) | — (no conversations visible) | no | — | no | no | no | no | yes |

---

## Cross-cutting Checks

| ☐ | ID | What to check | Steps | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|---|
| ☐ | C1 | Email dates | Open the "Call 16 is ready" email | dates as `Oct 22, 2026` | | |
| ☐ | C2 | Screen dates | Look at card and conversation times as an `en` user | `22/10/2026` style | | |
| ☐ | C3 | Narrow / mobile width | Open the page at 390 px | chat, cards and buttons usable, no sideways scroll | | |
| ☐ | C4 | Tenant isolation | As Golden Angels admin, paste Orion's conversation, card and file URLs | "Not authorized." for each | | |
| ☐ | C5 | Support Console regression | As a support user, ask the Support Console a question | answers as before (shared chat code) | | |
| ☐ | C6 | Entity Settings regression | Save Entity Settings with and without a key; use an existing in-app AI agent | agents still work with the (now encrypted) key | | |
| ☐ | C7 | Users › Permissions regression | Tick/untick other permissions | unchanged behaviour | | |
| ☐ | C9 | Empty question and attachment rules | Press Enter with an empty box; attach `big.xlsx`; attach `tool.exe` | "Please type a question."; both files refused with the allowed types (xlsx, xls, csv, pdf) and size (20 MB) | | |
| ☐ | C8 | API regression | Use an existing API token to create a record | works (only assistant tokens are read-only) | | |

---

## Security Checks

Run with a developer; they mirror [security.md](security.md#security-checks-before-go-live).

| ☐ | ID | What to check | Expected result | Pass / Fail | Notes |
|---|---|---|---|---|---|
| ☐ | S1 | From the machine, reach the database, Redis, Elasticsearch | times out | | |
| ☐ | S2 | From the machine, reach `example.com` / `api.anthropic.com` | blocked / works | | |
| ☐ | S3 | From the machine, list another entity's storage | AccessDenied | | |
| ☐ | S4 | Question token: read / write / after the question | 200 / refused "read-only token" / 401 | | |
| ☐ | S5 | Relay call signed with another machine's secret | refused | | |
| ☐ | S6 | Code copy on the machine | no credentials or key files | | |
| ☐ | S7 | Transform script | no network, no environment, cannot read outside its folder | | |
| ☐ | S8 | Flow-log and DNS alarms | fire on a test violation | | |

---

## Sign-off

| Tester | Build / commit | Environment | Date | Result | Open defects |
|---|---|---|---|---|---|
| | | staging | | | |
