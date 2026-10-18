# Design decisions (agreed with the user, 2026-10-18)

| # | Question | Decision | Why |
|---|---|---|---|
| 1 | Who runs it | CapHive ops staff | Trusted operator; the agent acts as that ops user, so Pundit + audit apply as in the UI. |
| 2 | Action surface | Fixed MCP tools first; later Claude may write code, but only code that calls those tools/APIs | Keeps "never write to the DB directly" enforceable: the agent has no DB credentials or Rails process. |
| 3 | Transform | Claude does it — by writing and running a transform script, then a mechanical reconcile | Script output is repeatable and auditable; reconcile catches dropped or invented rows. |
| 4 | Where it runs | Terminal Claude Code now; Support Console chat later | Tools are an MCP server, so both front ends reuse them unchanged. |
| 5 | Approvals | Reads automatic; writes approved; ops can waive per type (e.g. all KYCs) | Claude Code's built-in "always allow" is per tool, not per import type, so a PreToolUse hook reads `approvals.yml`. Undo never waivable. |
| 6 | Undo / partial failure | Human in the loop | Agent stops on errors, shows per-row fixes; ops picks re-import or undo (`ImportUploadDeleteAllJob` deletes one upload's data via app code). |
| 7 | Target | Fresh entity only | Mistakes stay contained; no merging into live data. |
| 8 | Transport | HTTP to existing website `.json` endpoints with a bearer token, via an agent-side MCP server | No Rails change; same path for dev, staging, prod. |
| 9 | APIs | Do not modify (another agent is upgrading the fund APIs); log gaps in api-gaps.md | Avoid colliding with that workstream. |
| 10 | Emails | Entity always in sandbox during onboarding | `ApplicationMailer` routes all notifications to `sandbox_emails`/`sandbox_numbers`. |
| 11 | Entity creation | Ops creates the bare entity in the UI | Creating entities needs broad rights; the agent's token then only has rights on that one entity. |
| 12 | Investor access | Always last | Even in sandbox, access creates real logins; investors must never see a half-imported fund. |
| 13 | Custom fields | Derived from the data, per import step | Extra columns otherwise become text-only fields or none (see importer-behaviour.md). |
| 14 | Agent audit log | v1: `journal.md` + the app's `audits` table. Support Console stage: an append-only `agent_actions` table (agent, run, entity, action, target, upload id, status, approved_by/at), written by the app, not the agent | One operator + one agent needs no shared store; a console does. Memories stay in skill files (reviewed via git, not injected unreviewed). Agent-to-agent comms deferred until a second agent exists. |
| 15 | Client team users/roles | Ops sets them up manually | Not an agent step. |
| 17 | Where the agent runs | A Docker container on the dev box: client workspace + templates + skill, network only to the app's HTTP port, no DB credentials or route to MySQL | Nobody reviews the agent's scripts, so "never write the DB" must hold structurally, not via hooks (the dev box's `database.yml` has root credentials any `rails runner` would use). |
| 17a | v1 delivery (2026-10-18) | Local on the dev box, no Docker: Ravi's own Claude Code login; Claude Code's Bash sandbox (no network, writes only in the workspace); Claude reads the IRM checkout with Edit/Write and secrets' Read denied. Container + snapshot become stage 2 | User: "lets do docker later, for now lets get it working locally". Intended: shell commands cannot reach MySQL or the app. **Spike 2026-10-18: Claude Code's Bash sandbox fails on this Ubuntu (AppArmor userns restriction), so this is not yet true** — see design.md Risks for the options. |
| 18 | App code access | Read-only snapshot (`git archive` of the running commit) mounted `:ro`, excluding `config/database.yml`, `config/credentials/*.key`, `config/master.key`, `.env*`; app gems not installed | Lets the agent diagnose failures and drive onboarding autonomously; it can read but neither change nor run the app. App-side causes are written up (file:line + suggested fix) and the step pauses — never patched. |
| 19 | Transform language | Ruby with roo/caxlsx/activesupport in a workspace Gemfile; scripts are disposable internals nobody reviews | Same reader and header rules as the importer, so fewer failed rows; correctness is proven by reconcile + import results, not code review. |
| 16 | Agent identity | Reuse the ops user ops already adds to the client entity; the agent uses that user's devise-api token. No dedicated agent user | Matches current practice; the user's `entity_id` still confines Pundit to the one client. Consequence: `audits` rows name the ops person, so `journal.md` (later `agent_actions`) carries agent-vs-human attribution (G6). `login_as` impersonation is session-only and unusable over a bearer token (G7). |

## Shape

```
Claude Code ──stdio──▶ onboarding MCP server (agent side, thin HTTP client)
                         │  Authorization: Bearer <ops user's token>
                         ▼
                       Rails app (unchanged): Pundit, audits, ImportUploadJob, callbacks
```

## Open (not yet decided)

- How the ops user's devise-api token reaches the container (and its expiry/refresh).
- Exact tool list for the MCP server.
