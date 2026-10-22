# Client Ops Assistant — Low-Level Design

> **Audience:** The developer who reviews the implementation plan before coding starts.
> **Companion documents:** [Design](design.md) · [Spec](specs/) · [Business rules](business-rules.md) · [Security](security.md) · [Tasks](tasks.md)

> **Planning phase — no code changes.** Implementation-level decisions only; diagrams and worked
> examples live in [design.md](design.md).

---

## Contents

- [Review Summary](#review-summary)
- [File Map](#file-map)
- [Schema Detail](#schema-detail)
- [Method Contracts](#method-contracts)
- [Controllers, Params and Responses](#controllers-params-and-responses)
- [Queries and Indexes](#queries-and-indexes)
- [Transactions, Locking and Concurrency](#transactions-locking-and-concurrency)
- [Background Jobs](#background-jobs)
- [External Integrations](#external-integrations)
- [Error Mapping and Logging](#error-mapping-and-logging)
- [Security Review](#security-review)
- [Configuration and Rollout](#configuration-and-rollout)
- [Test Plumbing](#test-plumbing)
- [Project Rules Checklist](#project-rules-checklist)
- [Sign-off](#sign-off)

---

## Review Summary

- **Extracting the Support Console's turn, relay and machine code** into `ClaudeTurnRunner`,
  `ClaudeRelayClient`, `ClaudeMachineControl` — the Support Console must keep passing its features
  unchanged. See [File Map](#file-map) and [Method Contracts](#method-contracts).
- **`devise_api_tokens.read_only`** checked in `WithAuthentication` — an auth-path change for every API
  client (default false). Approved by ops (design open question 1). See [Security Review](#security-review).
- **No retries on `OpsAssistantActionJob`**; `executed_at` set *before* the HTTP call; timeout → `unknown`.
  See [Background Jobs](#background-jobs).
- **Preconditions compared as strings** (money and ids) re-read through the API as the approving user.
  See [Transactions, Locking and Concurrency](#transactions-locking-and-concurrency).
- **`encrypts :anthropic_api_key`** with `support_unencrypted_data` during a one-off backfill rake task;
  `LlmService` unchanged. Approved by ops (design open question 2).
- **Per-entity EC2 from a launch template by the app** — narrow IAM for the app role. See
  [Configuration and Rollout](#configuration-and-rollout) and [security.md](security.md).

---

## File Map

| Boundary | File | New / Modified | Responsibility |
|---|---|---|---|
| ① Page | `app/packs/ai/ops_assistant/controllers/ops_assistant_controller.rb` | New | index / show / ask / stop / destroy / download |
| ① Page | `app/packs/ai/ops_assistant/policies/ops_assistant_policy.rb` | New | access + session scoping |
| ① Page | `app/packs/ai/ops_assistant/views/ops_assistant/{index,show,_action_card,_attachments}.html.erb` | New | page, card, attachments |
| ① Page | `app/views/shared/claude_chat/{_chat,_message,_composer}.html.erb` | New (moved from `support_console/`) | shared chat partials with locals |
| ① Page | `app/packs/ai/support_console/views/support_console/*` | Modified | render the shared partials |
| ① Page | `app/javascript/controllers/ops_assistant_controller.js` | New | attachments, card buttons (reuses `support_console_thread_controller`) |
| ② Turns | `app/packs/ai/base/services/claude_turn_runner.rb` | New (extracted) | claim / run / handle / finish / stale sweep |
| ② Turns | `app/packs/ai/base/services/claude_relay_client.rb` | New (extracted from `SupportConsoleRelayClient`) | signed POST/DELETE, NDJSON reader; URL + secret injected |
| ② Turns | `app/packs/ai/support_console/jobs/support_console_turn_job.rb` | Modified | uses `ClaudeTurnRunner` |
| ② Turns | `app/packs/ai/support_console/services/support_console_relay_client.rb` | Modified | thin subclass/config of `ClaudeRelayClient` |
| ② Turns | `app/packs/ai/ops_assistant/jobs/ops_assistant_turn_job.rb` | New | ops profile: token, brief, events `action`/`learning`/`file`/`api_gap` |
| ② Turns | `app/packs/ai/ops_assistant/services/ops_assistant_brief.rb` | New | client brief + knowledge docs + rules text |
| ③ Machines | `app/packs/ai/base/services/claude_machine_control.rb` | New (extracted from `SupportConsoleMachineControl`) | EC2 by tag, health, start/stop/provision |
| ③ Machines | `app/packs/ai/support_console/services/support_console_machine_control.rb` | Modified | config of `ClaudeMachineControl` |
| ③ Machines | `app/packs/ai/ops_assistant/models/ops_assistant_machine.rb` | New | row per entity |
| ③ Machines | `app/packs/ai/ops_assistant/jobs/{ops_assistant_machine_job,ops_assistant_idle_stop_job}.rb` | New | provision/start/stop; idle sweep |
| ③ Machines | `lib/tasks/ops_assistant/{infra,check,backfill}.rake` | New | launch template + SG + subnet + DNS firewall + IAM per env (dry run / `EXECUTE=1`, STS account assertion); `check`; key backfill |
| ④ Machine | `support_console/machine/relay/claude_command.js` | Modified | `profile: support \| ops` |
| ④ Machine | `support_console/machine/relay/server.js` | Modified | per-machine secret, file download, new events |
| ④ Machine | `support_console/machine/api-mcp/server.js` | New | `api_get`, `api_propose`, `propose_learning`, `report_api_gap` |
| ④ Machine | `support_console/machine/bin/ops-ruby` | New | bubblewrap wrapper, no network, workspace only |
| ④ Machine | `support_console/machine/claude/ops_brief.md` | New | static ops rules for Claude |
| ④ Machine | `config/support_console/user-data.sh` | Modified | profile + SSM secret + S3 sync |
| ④ Machine | `support_console/machine/test/{ops_api_mcp,ops_sandbox,ops_relay}.test.js` | New | node tests (E17–E19, X14) |
| ⑤ API | `app/packs/core/base/controllers/concerns/with_authentication.rb` | Modified | 403 non-GET for `read_only` tokens |
| ⑤ API | `app/packs/ai/ops_assistant/services/ops_assistant_token.rb` | New | mint / revoke |
| ⑥ Cards | `app/packs/ai/ops_assistant/models/ops_assistant_action.rb` | New | propose! / approve! / reject! / expire |
| ⑥ Cards | `app/packs/ai/ops_assistant/services/{ops_assistant_action_rules,ops_assistant_action_preview}.rb` | New | never-list, investor-notice registry, async registry; facts + preconditions |
| ⑥ Cards | `app/packs/ai/ops_assistant/controllers/ops_assistant_actions_controller.rb` + policy | New | approve / reject |
| ⑦ Runner | `app/packs/ai/ops_assistant/jobs/{ops_assistant_action_job,ops_assistant_watch_job}.rb` | New | send; watch |
| ⑦ Runner | `app/packs/ai/ops_assistant/services/ops_assistant_api_client.rb` | New | HTTP to own API as the user (JSON + multipart) |
| ⑦ Runner | `app/packs/ai/ops_assistant/mailers/ops_assistant_*_notifier.rb` | New | 5 notifiers (design › Notifications) |
| ⑧ Knowledge | `app/packs/ai/ops_assistant/services/ops_assistant_knowledge.rb` | New | folder tree, propose/confirm/discard, brief, reports |
| ⑧ Knowledge | `app/packs/ai/ops_assistant/controllers/ops_assistant_knowledge_controller.rb` + policy + views | New | What I've learned page |
| ⑨ Storage | `app/packs/ai/support_agents/models/agent_chat_message.rb` | Modified | `has_many_attached :files` |
| Permissions | `app/packs/core/entities/models/concerns/entity_enabled.rb`, `app/packs/core/users/models/concerns/user_enabled.rb` | Modified | append `enable_ops_assistant`; `User#enable_ops_assistant` |
| Settings | `app/packs/core/entities/models/entity_setting.rb`, `app/packs/core/dashboards/entity_setting_dashboard.rb` | Modified | `encrypts :anthropic_api_key`; masked display |
| Gaps | `app/packs/ai/ops_assistant/models/ops_assistant_api_gap.rb` | New | upsert by method + pattern |
| Routes | `config/routes/ai.rb` | Modified | `/ops_assistant…` |
| Schema | `db/migrate/*_create_ops_assistant_tables.rb`, `*_add_read_only_to_devise_api_tokens.rb` | New | tables + column |
| Docs | `docs/user_guides/ops_assistant_user_guide.md`, `docs/modules/ai/ops_assistant/technical_guide.md` | New | user guide (FAQ standard) + tech guide |

**Reviewer checks**
- [ ] Every class in the design's class diagram has a file here, and nothing here is missing from it
- [ ] Files follow the pack layout (`app/packs/ai/ops_assistant/...`) and Packwerk boundaries
- [ ] The Support Console's files change only to delegate to the extracted classes

---

## Schema Detail

**`ops_assistant_machines`** (new): one per entity; the app's handle on that entity's EC2 machine.

| Column | Change | Type | Limit | Null | Default | Index / FK | Why it's needed |
|---|---|---|---|---|---|---|---|
| `entity_id` | Added | bigint | — | no | — | unique, FK entities | one machine per entity |
| `instance_id` | Added | string | 32 | yes | — | — | null while provisioning; `i-` ids ≤ 19 chars |
| `status` | Added | string | 20 | no | `"provisioning"` | — | cache of EC2 state for the badge |
| `relay_secret` | Added | text | — | no | — | — | `encrypts`; 64 hex chars, text because ciphertext is longer |
| `s3_prefix` | Added | string | 255 | no | — | — | `irm-ops-assistant-<env>/<entity_id>/` |
| `last_activity_at` | Added | datetime | — | yes | — | — | idle stop |
| `provisioned_at` | Added | datetime | — | yes | — | — | shown on the Entity screen |
| `error_text` | Added | text | — | yes | — | — | last provision/start error (no client data) |

**`ops_assistant_actions`** (new): an approval card; the stored request is the only thing ever sent.

| Column | Change | Type | Limit | Null | Default | Index / FK | Why it's needed |
|---|---|---|---|---|---|---|---|
| `entity_id` | Added | bigint | — | no | — | FK, `(entity_id, status)` | tenant scope |
| `agent_chat_session_id` | Added | bigint | — | no | — | FK, index | where the card lives |
| `agent_chat_message_id` | Added | bigint | — | no | — | FK | the answer that proposed it |
| `user_id` | Added | bigint | — | no | — | FK | asking user = only approver |
| `status` | Added | string | 20 | no | `"waiting"` | `(status, created_at)` | lifecycle; 20 fits `refused`… `watching` |
| `http_method` | Added | string | 6 | no | — | — | GET never stored (reads don't need cards); POST/PUT/PATCH |
| `path` | Added | string | 500 | no | — | — | relative path incl. query |
| `body` | Added | json | — | yes | — | — | JSON body; files referenced by ActiveStorage |
| `summary` | Added | text | — | no | — | — | assistant's words (≤ 2,000 chars validated) |
| `preview` | Added | json | — | no | `{}` | — | CapHive-computed facts |
| `preconditions` | Added | json | — | no | `[]` | — | `[{path, pointer, expected}]`, ≤ 10 |
| `notifies_investors` | Added | boolean | — | no | false | — | warning line |
| `result` | Added | json | — | yes | — | — | status code, ids, row errors (capped 200 rows) |
| `approved_by_id` | Added | bigint | — | yes | — | FK users | who approved |
| `approved_at`, `executed_at`, `reported_at` | Added | datetime | — | yes | — | — | single-send and single-report guards |
| `error_text` | Added | text | — | yes | — | — | shown on the card |

**`ops_assistant_api_gaps`** (new): API gaps for CapHive, no client data.

| Column | Change | Type | Limit | Null | Default | Index / FK | Why it's needed |
|---|---|---|---|---|---|---|---|
| `http_method` | Added | string | 6 | no | — | unique with `path_pattern` | one row per gap |
| `path_pattern` | Added | string | 255 | no | — | — | ids replaced by `:id` by the machine and again by Rails |
| `capability` | Added | string | 500 | no | — | — | plain words |
| `occurrences` | Added | integer | — | no | 1 | — | frequency |
| `last_seen_at` | Added | datetime | — | no | — | — | recency |

**`devise_api_tokens`** (existing): add `read_only` boolean, null false, default false — per-turn tokens cannot write.

**`entity_settings`** (existing): no column change; `anthropic_api_key` becomes `encrypts` (text column already).

**Migration safety:** new tables are empty; `devise_api_tokens` is small (thousands of rows) — adding a
boolean with a default is an instant/inplace DDL on MySQL 8. The encryption backfill is a rake task
(`ops_assistant:encrypt_keys`, dry run by default) run after deploy with `support_unencrypted_data = true`,
then a follow-up deploy sets it false. Reversible: drop tables / column. Update `schema.rb` and `schema_test.rb`.

**Reviewer checks**
- [ ] Every new or changed column and index has a "why", and none is unjustified
- [ ] Every foreign key has an index; one-machine-per-entity is a unique index
- [ ] Column limits match validation limits (summary 2,000, path 500, preconditions ≤ 10)
- [ ] Migration is reversible and safe on the production table size

---

## Method Contracts

**`OpsAssistantToken`** (Service)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `.mint(user, read_only:, ttl:)` | User, Boolean, Integer seconds | `Devise::Api::Token` | — | inserts a token row | No (each call a new token) |
| `.revoke!(token)` | token | true | — | sets `revoked_at` | Yes |

**`ClaudeTurnRunner`** (Service, extracted)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `#claim_turn` | — | Boolean | — | queued → running under lock | Yes (second claim false) |
| `#run_turn(payload)` | Hash | — | `Unavailable`, `Busy` | relay POST, event loop | No |
| `#handle(event)` | Hash | — | — | per-event writes, broadcasts; profile hook for unknown types | Yes per event id |
| `#finish(status)` | Symbol | — | — | final save, broadcast, `on_finish` hook (token revoke) | Yes (closed turn untouched) |

**`ClaudeMachineControl`** (Service, extracted)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `.for_tag(tag, secret:)` | String, String | instance | — | — | — |
| `#status` | — | Symbol | — | EC2 describe, `/health` | Yes |
| `#ensure_running!` | — | relay URL | `Unavailable` | start + wait ≤ 5 min | Yes |
| `#provision!(entity)` | Entity | instance id | `ProvisionFailed` | RunInstances from template, SSM put secret | No (guarded by row status) |
| `#stop!` | — | — | — | StopInstances | Yes |

**`OpsAssistantAction`** (Model)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `.propose!(event, session:, message:, user:)` | Hash | action | — | insert (waiting or refused), preview, notify | Yes per `event.id` (unique in `result`/`preview` key) |
| `#approve!(user)` | User | Symbol (`:running`, `:stale`, `:expired`, `:refused`, `:not_waiting`) | `Pundit::NotAuthorizedError` | lock, preconditions, enqueue | Yes (only from waiting) |
| `#reject!(user)` | User | — | NotAuthorized | status | Yes |

**`OpsAssistantActionRules`** (Service)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `.forbidden?(verb, path)` | String, String | `[Boolean, reason]` | — | — | Yes |
| `.notifies_investors?(verb, path)` | | Boolean | — | — | Yes |
| `.async?(verb, path, response)` | | `[Boolean, watch_path]` | — | — | Yes |

**`OpsAssistantActionPreview`** (Service)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `#facts` | — | Hash (request line, file sheets/rows/columns/money totals/dates — ported from `review.rb#describe`) | — | reads attached file | Yes |
| `#preconditions_hold?(user)` | User | `[Boolean, mismatches]` | — | GETs via `OpsAssistantApiClient` with a read token | Yes |

**`OpsAssistantApiClient`** (Service)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `#request(user, verb, path, body:, files:, read_only:)` | | `[status, parsed_body]` | `Timeout` (→ unknown) | mint + revoke token, HTTP | GET yes; others no |

**`OpsAssistantKnowledge`** (Service)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `#folder` | — | Folder | — | creates the system tree if missing | Yes |
| `#propose!(kind, title, body, session:, user:)` | | Document | — | Document in Proposed/, notify admins | Yes per (session, title) |
| `#confirm!(doc, admin, as:)` | Document, User, `:skill`/`:learning` | Document | NotAuthorized | move folder | Yes |
| `#discard!(doc, admin)` | | — | NotAuthorized | destroy document | Yes |
| `#brief` | — | String (≤ 200 KB, ≤ 50 docs) | — | reads docs | Yes |
| `#write_report!(action)` | | Document | — | Document in Reports/ | Yes per action |

**Reviewer checks**
- [ ] Every raised error is handled by a caller or listed in Error Mapping
- [ ] Anything a retry can repeat is idempotent (`propose!` by event id, `write_report!` by action)

---

## Controllers, Params and Responses

| Action | Permitted params | Policy method | Success response | Failure response |
|---|---|---|---|---|
| `OpsAssistantController#index` | — | `index?` | HTML | 403 page "Not authorized." / no-key notice |
| `#ask` | `question` (≤ 4,000), `files[]` (≤ 5, ≤ 20 MB, xlsx/xls/csv/pdf), `model` (sonnet/opus) | `ask?` | turbo_stream (messages, composer) | 422 turbo_stream with the validation message |
| `#stop` | — | `ask?` | turbo_stream | 404 when no running turn |
| `#destroy` | — | `destroy?` | redirect | 403 |
| `#download` | `signed_id` | `show?` on the owning session | 302 to blob | 403 |
| `OpsAssistantActionsController#approve` | — | `approve?` (asking user, same entity, flags on) | turbo_stream card | 403 / turbo_stream card with stale/expired/refused |
| `#reject` | — | `approve?` | turbo_stream card | 403 |
| `OpsAssistantKnowledgeController#index/confirm/discard` | `as` (skill/learning) | `manage?` (company admin + flag) | HTML / turbo_stream | 403 |
| Entity permissions (existing super-user screen) | `enable_ops_assistant` | existing (super only) | — | existing |

**Reviewer checks**
- [ ] No action without `authorize` / `policy_scope`
- [ ] Permitted params can't set `entity_id`, `user_id`, `status`, `path` or `body` (cards are created only from relay events)

---

## Queries and Indexes

| Where | Query shape | Index used | Rows expected | Preload / batching |
|---|---|---|---|---|
| conversation list | `AgentChatSession.where(chattable: entity, user:)` (admin: no user filter) `.order(updated_at: :desc)` | existing chattable index | ≤ hundreds | `includes(:user)` |
| card list in a session | `OpsAssistantAction.where(agent_chat_session_id:)` | `(agent_chat_session_id)` | ≤ dozens | — |
| expiry sweep | `OpsAssistantAction.where(status: "waiting").where(created_at: ...24.hours.ago)` | `(status, created_at)` | small | `find_each` |
| idle sweep | `OpsAssistantMachine.where(status: "running").where(last_activity_at: ...30.minutes.ago)` + `none?` on running/watching actions | unique entity_id; `(entity_id, status)` | ≤ clients | `find_each` |
| knowledge brief | `Document.where(folder: [skills, learnings]).order(:name).limit(50)` | existing folder index | ≤ 50 | select only needed columns |

**Reviewer checks**
- [ ] Every query is scoped by `entity_id` (or by a session already scoped by policy)
- [ ] No N+1 on the conversation list; sweeps use `find_each`

---

## Transactions, Locking and Concurrency

| Operation | Transaction scope | Lock | Race it prevents | Idempotency key |
|---|---|---|---|---|
| approve | action row only | `action.with_lock` for status check + flip; preconditions HTTP **outside** the lock, status re-checked inside | double approve; approve vs expiry | status `waiting` → `running` once |
| action send | — | none (single job) | double send | `executed_at` set and saved before HTTP |
| watch report | action row | `with_lock` | double notify | `reported_at` |
| turn claim / finish | message row | existing Support Console lock | double run; Stop vs finish | `turn_status` |
| machine start | machine row | `with_lock` around EC2 start | two turns starting it | status `starting` |
| propose | insert | unique key on (`agent_chat_message_id`, event id in `preview`) — validated | duplicate events on relay retry | event id |

**Reviewer checks**
- [ ] No external HTTP call or email inside a transaction (preconditions and sends are outside locks)
- [ ] Lock order: action before machine everywhere both are locked

---

## Background Jobs

| Job | Queue | Trigger | Retry / backoff | Discard on | Concurrency guard | Timeout |
|---|---|---|---|---|---|---|
| `OpsAssistantTurnJob` | `ops_assistant` | ask / follow-up | none | `ActiveRecord::RecordNotFound` | `claim_turn` | stale after 20 min (sweep) |
| `OpsAssistantActionJob` | `ops_assistant` | approve | **none** | RecordNotFound | `executed_at` | HTTP 60 s → `unknown` |
| `OpsAssistantWatchJob` | `ops_assistant` | after an async response | self-reschedule 30 s ×10, then 60 s; stop at 2 h | RecordNotFound | `reported_at` | per poll 30 s |
| `OpsAssistantMachineJob` | `ops_assistant` | switch on/off, Start/Stop | none | — | machine row status | 10 min |
| `OpsAssistantIdleStopJob` | `ops_assistant` | sidekiq-cron `*/5 * * * *` | none | — | — | — |
| `OpsAssistantExpiryJob` | `ops_assistant` | sidekiq-cron `*/15 * * * *` | none | — | status | — |

**Reviewer checks**
- [ ] A job that runs twice, or out of order, is harmless
- [ ] Cron entries are registered in the sidekiq-cron initializer for staging/production only

---

## External Integrations

| Call | Method + path | Auth | Timeouts | Rate limit handling | Error → exception |
|---|---|---|---|---|---|
| Relay turn | `POST <relay>/turns` | HMAC per-machine secret | open 5 s, read: streamed with 30 s ping | relay `busy` → turn failed BUSY | conn refused → `Unavailable` (start machine) |
| Relay stop / transcript | `DELETE <relay>/turns/current`, `/transcripts` | HMAC | 5 s / 10 s | — | logged, non-fatal |
| Own API | any verb, `OPS_ASSISTANT_API_BASE_URL` + path | Bearer (user token) | open 5 s, read 60 s | 429 → card failed "busy, try again" | timeout → `unknown`; 4xx/5xx → failed with body message |
| EC2 | Describe/Start/Stop/RunInstances | app IAM role | SDK defaults | SDK retry | `ProvisionFailed`, `Unavailable` |
| SSM | PutParameter (secret) | app role | SDK | SDK | `ProvisionFailed` |
| Anthropic | (from the machine only) | client key | Claude Code's | `usage_limit` event | turn failed with message |

**Reviewer checks**
- [ ] Tokens, keys and relay secrets never logged (Rails `filter_parameters` + relay log redaction)
- [ ] Every non-2xx status maps to a card/turn outcome

---

## Error Mapping and Logging

| Exception / event | Raised in | Handled by | User sees | Logged / alerted |
|---|---|---|---|---|
| `ClaudeMachineControl::Unavailable` | turn | `ClaudeTurnRunner#run_turn` | "Your assistant is unavailable right now" | warn + entity id |
| `ProvisionFailed` | machine job | job | Entity screen: machine failed | `OpsAssistantMachineFailedNotifier` → super users |
| relay `auth_failed` | machine | runner | "Your Anthropic key was refused…" | info |
| relay `usage_limit` | machine | runner | "Your Anthropic usage limit was reached." | info |
| API 403 on send | action job | job | card failed with the API's message | info |
| `Net::ReadTimeout` on send | action job | job | card "unknown — check on the screen" | warn + action id |
| 403 "read-only token" | `WithAuthentication` | API | (machine) refused | error report: entity id, path — no body |
| Precondition mismatch | approve | controller | "The data changed since this was prepared…" | info |

**Reviewer checks**
- [ ] No bare `rescue => e` that swallows errors silently
- [ ] Log lines carry entity id, session id, action id — never question text, file content, tokens or keys

---

## Security Review

| Concern | Decision |
|---|---|
| Authorization | `OpsAssistantPolicy` (index/ask/show/destroy), `OpsAssistantActionPolicy#approve?` (asking user only), knowledge `manage?` (company admin); all require `user.enable_ops_assistant` |
| Tenant isolation | session `chattable == user.entity`; actions/machines/gaps scoped by `entity_id`; API reads/writes as the user (Pundit); per-entity machine, secret, S3 prefix — see [security.md](security.md#part-2--client-data-is-isolated) |
| Secrets | `encrypts` on `anthropic_api_key` and `relay_secret`; read-only 30-min turn tokens, 5-min write tokens, revoked after use; filtered from logs |
| Input / output sanitisation | answers rendered with the Support Console's `answer_markdown_html` (SupportConsoleHelper), moved to a shared helper; attachments type/size-checked; produced files served as downloads with `Content-Disposition: attachment` |
| Mass assignment | cards created only from relay events; no params can set `entity_id`, `user_id`, `status`, `path`, `body` |
| Machine trust | untrusted: no secrets, no DB route, 3-destination egress — [security.md Part 1](security.md#part-1--the-machine-cannot-harm-caphive) |

**Reviewer checks**
- [ ] A user from another entity cannot reach any record through any route, job or relay event
- [ ] A read-only token gets 403 on every non-GET route (feature X17/E20)

---

## Configuration and Rollout

| Item | Value / location |
|---|---|
| Credentials / env vars | `OPS_ASSISTANT_API_BASE_URL`, `OPS_ASSISTANT_BUCKET` per env; AWS via the app's existing keys; IN and US independent (own buckets, templates, KMS keys, SSM paths) |
| Feature flag | entity permission `enable_ops_assistant` (off everywhere) + user flag |
| Cron / schedules | idle stop every 5 min; expiry every 15 min (staging, production) |
| Infra | `rake "ops_assistant:infra[staging.in]"` dry run → `EXECUTE=1` (launch template, SG, subnet, DNS firewall, IAM, KMS, bucket); asserts the STS account |
| Deploy order | migrations → code (Support Console unchanged behaviour) → `ops_assistant:encrypt_keys EXECUTE=1` → infra rake → switch on Orion Test (staging) |
| Rollback | untick the entity permission (stops machines); revert code; tables can stay empty |

**Reviewer checks**
- [ ] Safe to deploy with the feature unused (all flags off), and safe to roll back
- [ ] Support Console features pass on the extracted classes before any ops-assistant code ships

---

## Test Plumbing

| Feature file | Stubs / fixtures | Factories | New step definitions |
|---|---|---|---|
| `features/ops_assistant/access.feature` | fake relay | entity with flag, users per role | `Given the Ops Assistant is switched on for …` |
| `features/ops_assistant/ask.feature` | fake relay NDJSON scripts (progress/text/error) | session | `When the assistant streams …` |
| `features/ops_assistant/files.feature` | fixture xlsx/pdf/exe | — | attachment steps |
| `features/ops_assistant/approvals.feature` | fake relay `action` events; WebMock for preconditions on own API | action | `Then I see an approval card …` |
| `features/ops_assistant/runner.feature` | WebMock/own API via Capybara server; import upload stub | — | `When the action runs` / `When the watcher polls` |
| `features/ops_assistant/knowledge.feature` | — | documents in the folder | knowledge steps |
| `features/ops_assistant/machine.feature` | `ClaudeMachineControl` fake (EC2 state machine) | machine row | machine steps |
| `features/api/ops_assistant_tokens.feature` | — | user, token | `Given a read-only token for …` |
| machine node tests | fake Claude, fake CapHive | — | — |

---

## Project Rules Checklist

| Rule | Applies? | How it is met |
|---|---|---|
| No `blank?`/`present?` on relations; use `exists?`/`none?` | Applies | idle sweep uses `none?`; cop enforced |
| Dedup in SQL (`distinct.pluck`), batch bulk operations (`find_each`/`in_batches`) | Applies | sweeps use `find_each` |
| Select only needed columns when loading many `account_entries`; no speculative `includes` of big associations | N/A | feature never reads `account_entries` in Rails (API-only) |
| Screen dates via `l(...)`; emails render `Mon dd, yyyy` via `EmailDateLocalization`; no human-format `strftime` | Applies | card times via `l(..., format: :abbr_date_time)`; notifier views use bare `l(date)` |
| Date inputs use `f.date_field` / `date_field_tag`; JS dates via `locale_date_format.js` | Applies | conversation timestamps via `formatLocaleDateTime` |
| Every query entity-scoped; Pundit `authorize`/`policy_scope` on every action | Applies | see Security Review |
| MCP tool surfaces changed only via the ontology YAML (run the ontology drift feature) | N/A | the app's MCP server is not changed; `api-mcp` is a machine-side tool |
| Cucumber only (no RSpec); `TEST_ENV_NUMBER=$RANDOM` on every run | Applies | Test Plumbing |
| `bundle exec rubocop` clean, including the `IRM/RelationBlankPresent` cop | Applies | per phase |

---

## Sign-off

| Reviewer | Date | Decision | Notes |
|---|---|---|---|
| | | | |
