# Client Ops Assistant — Business rules and worked examples

> **Audience:** Engineering and QA. Companion to [design.md](design.md) (boxes ①–⑨) and the [specs](specs/).
> Every row is exactly one Cucumber scenario (or, for machine-side rows marked *node*, one test in the
> machine's node suite); every spec scenario appears in at least one row.

**ID legend:** **H** = Happy path · **E** = Edge case · **X** = Error (exception) case. The box column
names the design card that owns the row.

## Shared setup

| Record | Name | Key data |
|---|---|---|
| Entity | Orion Test (1548) | `enable_ops_assistant` on; Anthropic key `sk-ant-…orion`; machine `irm-ops-assistant-staging-in-1548` |
| Entity | Golden Angels (18) | `enable_ops_assistant` on; own key and machine |
| Fund | Demo Fund 2 (363) in Orion Test | 275 commitments, committed ₹18,38,50,93,602.71, 15 calls |
| Fund | Orios Fund I (361) in Orion Test | Arjun has **no** access to it (fund access rights) |
| User | Priya | CapHive super user |
| User | Meera | Orion Test company admin, user `enable_ops_assistant` on |
| User | Arjun | Orion Test employee, user `enable_ops_assistant` on, access to Demo Fund 2 |
| User | Ravi | Orion Test employee, user `enable_ops_assistant` **off** |
| User | Kiran | investor user of Orion Test (investor in Demo Fund 2) |
| Relay | fake relay | scripted NDJSON events, as the Support Console's features |
| Files | `call16.xlsx` (12 KB), `bank_oct.pdf` (2 MB), `big.xlsx` (25 MB), `tool.exe` | attachments |

## Happy Path

| # | Box | Scenario | Given | When | Then | Spec scenario | Feature |
|---|---|---|---|---|---|---|---|
| H1 | ①②④ | Ask a question, get a sourced answer | Arjun, machine running | he asks "Who still owes money on Demo Fund 2?"; relay streams progress then text | progress lines appear live, then the answer with 11 investors, ₹44,33,53,987.54 and a link to the fund's remittances; no card | access: User permission and entity permission both on; conversations: Live progress | `features/ops_assistant/ask.feature` |
| H2 | ①⑥ | A write becomes a waiting card | Arjun asks to prepare Call 16 | relay emits `action` POST `/capital_calls.json` with preconditions | card "Waiting for your approval" with CapHive's facts; Demo Fund 2 still has 15 calls | actions: Card shown, nothing written | `features/ops_assistant/approvals.feature` |
| H3 | ②⑦ | Approve, run, watch, report | card from H2 + upload card for 275 remittances | Arjun approves the upload card; API returns upload 2850; watcher sees 275/275 | card "Done", follow-up answer with the check table; one bell + one email to Arjun | actions: Approve; conversations: Long upload; conversations: Background work finishes | `features/ops_assistant/runner.feature` |
| H4 | ③ | Switch on prepares a machine and folder | Golden Angels has no machine | Priya ticks Ops Assistant | `ops_assistant_machines` row (status provisioning → stopped); Documents › Ops Assistant with Skills, Learnings, Proposed, Reports | tenant-machine: Prepared on switch-on; learning: Folder created on switch-on | `features/ops_assistant/machine.feature` |
| H5 | ⑤⑦ | Change history shows the approver | an approved card PATCHes investor "Ravi K" email | the action runs | the investor's audit shows Arjun as the user | actions: Change history shows the user | `features/ops_assistant/runner.feature` |
| H6 | ⑥ | Reject | waiting card | Arjun clicks Reject | card "Rejected by Arjun"; nothing written; no job enqueued | actions: Reject | `features/ops_assistant/approvals.feature` |
| H7 | ⑦⑧ | Task report saved | H3 completed | the runner reports | "2026-10-22 Call 16 Demo Fund 2.md" in Ops Assistant › Reports with steps, checks, results | learning: Task report kept | `features/ops_assistant/knowledge.feature` |
| H8 | ⑧ | Propose, confirm, use | Arjun's turn emits `learning` "Bank statements — folio after FOLIO-" | Meera confirms it as a Learning; Arjun starts a new chat | document moved Proposed → Learnings; the next turn's brief contains it; Meera got one notification | learning: Proposed learning; learning: Confirmed learning used | `features/ops_assistant/knowledge.feature` |

## Edge Cases

| # | Box | Scenario | Given | When | Then | Spec scenario | Feature |
|---|---|---|---|---|---|---|---|
| E1 | ① | Company admin reads a colleague's chat | Arjun's conversation | Meera opens it | shown read-only: no ask box, no approve buttons | conversations: Company admin reads a conversation | `features/ops_assistant/access.feature` |
| E2 | ① | One question at a time | Arjun's turn running | he submits again (or posts directly) | ask box disabled; direct POST refused, no second job | conversations: One question at a time | `features/ops_assistant/ask.feature` |
| E3 | ① | Stop | turn running | Arjun presses Stop | "Stopped."; relay DELETE sent; a later `action` event from the killed turn is ignored | conversations: Stop | `features/ops_assistant/ask.feature` |
| E4 | ① | Exactly 5 attachments, 20 MB | five files, one exactly 20 MB | Arjun asks | accepted; all five listed on his message | conversations: Produced file | `features/ops_assistant/files.feature` |
| E5 | ① | Sixth attachment | six files | Arjun asks | refused "Up to 5 files per question"; nothing sent | conversations: Attachment refused | `features/ops_assistant/files.feature` |
| E6 | ① | Question of exactly 4,000 characters | 4,000-char text | Arjun asks | accepted; 4,001 refused with the limit | conversations: Live progress | `features/ops_assistant/ask.feature` |
| E7 | ① | Produced file downloadable | relay emits `file` remittances_call16.xlsx | Arjun clicks it in the answer and on the card | same file downloads from both | conversations: Produced file | `features/ops_assistant/files.feature` |
| E8 | ① | Delete a conversation with a waiting card | Arjun's chat has a waiting card | Meera deletes the chat | chat gone; files no longer downloadable; card cancelled (approve → not found); relay transcript delete sent | conversations: Delete a conversation | `features/ops_assistant/files.feature` |
| E9 | ② | Key changed mid-turn | turn running with key A | Meera saves key B | running turn finishes on A; next turn sends B | access: No key | `features/ops_assistant/ask.feature` |
| E10 | ② | Follow-up turn re-checks permission | H3's watcher finishes; Arjun's user permission was unticked meanwhile | follow-up turn starts | turn refused; card still shows the result; no answer generated; Arjun not notified by the assistant | access: Permission removed while a card is waiting | `features/ops_assistant/runner.feature` |
| E11 | ② | Two cards from one turn | relay emits two `action` events | — | two cards in order, each with its own Approve | actions: Card shown, nothing written | `features/ops_assistant/approvals.feature` |
| E12 | ② | Stale turn swept | a turn `running` for 21 minutes | retention sweep runs | turn closed as interrupted; its token revoked | tenant-machine: Token expires with the question | `features/ops_assistant/ask.feature` |
| E13 | ③ | Question to a stopped machine | machine stopped | Arjun asks | "Starting your assistant (about 2 minutes)", start!, health, then answer | tenant-machine: Question to a stopped machine | `features/ops_assistant/machine.feature` |
| E14 | ③ | Idle at exactly 30 minutes | last activity 30:00 ago, nothing running | idle job | stopped (≥ 30 min stops; 29:59 does not) | tenant-machine: Idle stop | `features/ops_assistant/machine.feature` |
| E15 | ③ | Watching keeps it running | an action `watching`, last turn 45 min ago, watcher polled 1 min ago | idle job | not stopped | tenant-machine: Background work keeps it running | `features/ops_assistant/machine.feature` |
| E16 | ③ | Second entity isolated | Orion Test and Golden Angels machines | Golden Angels' turn | sent to its own relay URL with its own secret; Orion's secret refused by Golden's relay | tenant-machine: Second entity | `features/ops_assistant/machine.feature` |
| E17 | ④ | api_get refuses a non-GET | Claude calls api_get with a POST-like path or another host | — | refused by api-mcp; nothing sent | actions: Card shown, nothing written | *node* `support_console/machine/test/ops_api_mcp.test.js` |
| E18 | ④ | Claude never sees the token | turn running | Claude reads env / `/proc` | token absent from Claude's env; `/proc` denied | tenant-machine: Token expires with the question | *node* `ops_api_mcp.test.js` |
| E19 | ④ | Transform with no network | `ops-ruby build.rb` reading call16.xlsx | script writes out.xlsx and tries `Net::HTTP` | file written in the workspace; network call fails, reported | actions: Script tries the network | *node* `ops_sandbox.test.js` |
| E20 | ⑤ | Read token cannot write | a turn's read-only token | `POST /capital_calls.json` with it | 403 "read-only token"; GET with it 200 | tenant-machine: Token expires with the question | `features/api/ops_assistant_tokens.feature` |
| E21 | ⑥ | Investor notice flagged | card to approve Drawdown 16 | shown | "This sends notices to investors" above Approve | actions: Investor notification is flagged | `features/ops_assistant/approvals.feature` |
| E22 | ⑥ | Double click | waiting card | two approve POSTs at once | one job, one API call; second returns the current state | actions: Double click | `features/ops_assistant/approvals.feature` |
| E23 | ⑥ | Expiry at exactly 24 h | card created 24:00 ago | Arjun approves | "Expired"; 23:59 still approves | actions: Card expires | `features/ops_assistant/approvals.feature` |
| E24 | ⑥ | Preconditions changed | precondition "commitments = 275"; Meera adds the 276th | Arjun approves | "The data changed since this was prepared…"; status stale; nothing written | actions: Data changed since prepared | `features/ops_assistant/approvals.feature` |
| E25 | ⑥ | Preconditions equal, money as text | expected "18385093602.71", API returns 18385093602.71 | approve | holds; runs | actions: Approve | `features/ops_assistant/approvals.feature` |
| E26 | ⑥ | Card with a file shows CapHive's facts | upload card with remittances_call16.xlsx | shown | "275 rows · Σ Call Amount ₹91,92,54,680.13", columns listed, labelled "Checked by CapHive" | actions: Card shown, nothing written | `features/ops_assistant/approvals.feature` |
| E27 | ⑥ | Zero-row upload | proposed file with headers only | proposed | card refused "The file has no rows" | actions: Forbidden request slipped into a card | `features/ops_assistant/approvals.feature` |
| E28 | ⑥ | Investor access card allowed | card POSTs investor access for a new LP | Arjun approves | runs (investor access is not on the never-list), flagged as notifying | actions: Investor notification is flagged | `features/ops_assistant/approvals.feature` |
| E29 | ⑦ | Partial upload | upload 272/275 | watcher finishes | card "Partly done"; follow-up turn lists 3 failed rows and offers a new card; no retry | actions: Three rows fail | `features/ops_assistant/runner.feature` |
| E30 | ⑦ | Not notified twice | watcher already reported | watch job runs again (retry/duplicate) | no second notification, no second follow-up | conversations: Not sent twice | `features/ops_assistant/runner.feature` |
| E31 | ⑦ | Synchronous 201 | card PATCH investor email | runs | 201 → succeeded straight away, no watcher | actions: Approve | `features/ops_assistant/runner.feature` |
| E32 | ⑦ | Watcher back-off | upload processing 10 minutes | watcher | polls every 30 s for 5 min then 60 s; each poll touches machine activity | tenant-machine: Background work keeps it running | `features/ops_assistant/runner.feature` |
| E33 | ⑦ | Write token lifetime | an action runs | after the request | write token revoked; reuse → 401 | tenant-machine: Token expires with the question | `features/api/ops_assistant_tokens.feature` |
| E34 | ⑧ | Discard | proposed learning | Meera discards | document deleted; not in the next brief | learning: Discarded learning not used | `features/ops_assistant/knowledge.feature` |
| E35 | ⑧ | Admin-written skill | Meera uploads "Raise a capital call.md" into Skills | Arjun's next turn | brief includes it | learning: Admin writes a skill | `features/ops_assistant/knowledge.feature` |
| E36 | ⑧ | Brief cap | 60 documents in Learnings | turn starts | 50 documents sent + "truncated: 10 more" note | learning: Confirmed learning used | `features/ops_assistant/knowledge.feature` |
| E37 | ⑨ | Machine replaced | conversation with history; machine terminated | Arjun continues it | re-provisioned; history synced from S3; `--resume` works | tenant-machine: Machine replaced | `features/ops_assistant/machine.feature` |
| E38 | ⑨ | Switch off keeps data | Orion Test switched off | Priya unticks | machine stopped; menu hidden; conversations and the Ops Assistant folder kept; switching on again starts the same machine | tenant-machine: Switched off | `features/ops_assistant/machine.feature` |

## Error Cases

| # | Box | Scenario | Given | When | Then (what the user sees, who is alerted) | Spec scenario | Feature |
|---|---|---|---|---|---|---|---|
| X1 | ① | Entity permission off | Golden Angels permission off | its admin opens /ops_assistant | no menu item; "Not authorized." | access: Permission off hides the assistant | `features/ops_assistant/access.feature` |
| X2 | ① | User permission off | Ravi | opens /ops_assistant | "Not authorized."; nothing enqueued | access: User permission off is refused | `features/ops_assistant/access.feature` |
| X3 | ① | User on, entity off | Arjun's flag on; Orion switched off | Arjun opens it | menu hidden; "Not authorized." | access: User permission on but entity permission off | `features/ops_assistant/access.feature` |
| X4 | ① | Investor user | Kiran | opens /ops_assistant | "Not authorized." | access: Investors and advisors never get it | `features/ops_assistant/access.feature` |
| X5 | ① | Colleague's chat | Arjun's chat | Ravi (if permitted) or another employee opens it | "Not authorized." | conversations: Another employee's conversation | `features/ops_assistant/access.feature` |
| X6 | ② | No key | Orion key blank | Arjun opens the page | "Add your Anthropic API key in Entity Settings…"; ask disabled; CapHive key never used | access: No key | `features/ops_assistant/access.feature` |
| X7 | ② | Key refused | relay emits error `auth_failed` | turn | "Your Anthropic key was refused…"; no retry with another key | access: Key refused by Anthropic | `features/ops_assistant/ask.feature` |
| X8 | ② | Fund the user cannot see | Arjun asks about Orios Fund I | the API returns 403/empty | answer "You don't have access to that fund." with no figures | conversations: Fund the user cannot see | `features/ops_assistant/ask.feature` |
| X9 | ② | Relay unreachable | machine running, relay down | turn | "Your assistant is unavailable right now"; turn failed; token revoked | tenant-machine: Question to a stopped machine | `features/ops_assistant/ask.feature` |
| X10 | ③ | Only super user switches on | Meera | edits Orion's permissions to tick Ops Assistant | refused; flag unchanged | access: Only a super user can switch it on | `features/ops_assistant/access.feature` |
| X11 | ③ | Provision fails | EC2 launch error | Priya ticks it on | machine row `failed`; super users get `OpsAssistantMachineFailedNotifier`; page says "unavailable" | tenant-machine: Prepared on switch-on | `features/ops_assistant/machine.feature` |
| X12 | ③ | Start times out | machine never healthy in 5 min | turn | turn failed "unavailable"; one retry only | tenant-machine: Question to a stopped machine | `features/ops_assistant/machine.feature` |
| X13 | ④ | Asked to delete | Arjun asks to delete Call 3 | turn | no card; "I can't do that — please use the Capital Calls screen." | actions: Asked to delete | `features/ops_assistant/approvals.feature` |
| X14 | ④ | Script reaches for the API | `ops-ruby` script calls CapHive | — | connection refused; no token in env | actions: Script tries the network | *node* `ops_sandbox.test.js` |
| X15 | ④ | API gap | Arjun asks for something no endpoint does | relay emits `api_gap` | answer with screen steps; `ops_assistant_api_gaps` row has method + pattern, no entity, no data | actions: No API for it | `features/ops_assistant/ask.feature` |
| X16 | ⑤ | Permission refused by the API | Arjun's role cannot approve calls | card approved | API 403 → card failed with the screen's message; nothing written | actions: Permission refused by the API | `features/ops_assistant/runner.feature` |
| X17 | ⑤ | Token after the turn | turn finished | its token used | 401 | tenant-machine: Token expires with the question | `features/api/ops_assistant_tokens.feature` |
| X18 | ⑥ | Forbidden at proposal | relay emits `action` DELETE `/capital_calls/9.json` | — | stored as refused; no buttons; assistant told | actions: Forbidden request slipped into a card | `features/ops_assistant/approvals.feature` |
| X19 | ⑥ | Forbidden at approve | a waiting card whose path is `/entity_settings/4.json` (rules changed since) | approve | refused; nothing written | actions: Forbidden request slipped into a card | `features/ops_assistant/approvals.feature` |
| X20 | ⑥ | Another user approves | Arjun's waiting card | Meera POSTs approve | 403; card unchanged | actions: Another user cannot approve | `features/ops_assistant/approvals.feature` |
| X21 | ⑥ | Permission removed while waiting | Arjun's waiting card; Meera unticks his permission | Arjun approves | "Not authorized."; nothing written | access: Permission removed while a card is waiting | `features/ops_assistant/approvals.feature` |
| X22 | ⑥ | Undo upload forbidden | relay emits PATCH `/import_uploads/2850/undo.json` | — | refused | actions: Forbidden request slipped into a card | `features/ops_assistant/approvals.feature` |
| X23 | ⑦ | API 5xx | approved card; API 500 | runs | card failed with the error; no retry; Arjun notified (failed) | actions: Approve | `features/ops_assistant/runner.feature` |
| X24 | ⑦ | Timeout after send | API does not answer in 60 s | runs | card "unknown — check on the screen" with link; Arjun notified; never re-sent | actions: Double click | `features/ops_assistant/runner.feature` |
| X25 | ⑦ | Upload job failed | import upload outcome failed | watcher | card failed; follow-up turn explains; notified once | actions: Three rows fail | `features/ops_assistant/runner.feature` |
| X26 | ⑦ | Watch limit | upload still processing after 2 h | watcher | card unknown; notified; machine may idle-stop | conversations: Long upload | `features/ops_assistant/runner.feature` |
| X27 | ⑦ | Entity switched off mid-run | action running | Priya switches off | the in-flight request completes; no follow-up turn; result kept on the card | tenant-machine: Switched off | `features/ops_assistant/runner.feature` |
| X28 | ⑧ | Employee cannot confirm | proposed learning | Arjun POSTs confirm | refused; still in Proposed | learning: Employee cannot confirm | `features/ops_assistant/knowledge.feature` |
| X29 | ⑧⑨ | Other client's knowledge | Orion's Learnings has 3 documents | Golden Angels' turn | Golden's brief contains none of them; Golden's machine cannot read Orion's S3 prefix | learning: Other client | `features/ops_assistant/knowledge.feature` |

## Coverage check

All 52 spec scenarios appear above (access 9, conversations 12, actions 15, learning 8, tenant-machine 8).
