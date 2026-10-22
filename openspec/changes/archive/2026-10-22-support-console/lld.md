# Support Console — Low-Level Design

> **Audience:** The developer who reviews the implementation plan before coding starts.
> **Companion documents:** [Design](design.md) · [Spec](specs/support-console/spec.md) · [Tasks](tasks.md)

> **Planning phase — no code changes.** This document adds to [design.md](design.md); it links to its
> diagrams and worked examples rather than repeating them.

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

- **One change to an existing model (approved 2026-10-16):** `SupportAgent::AGENT_TYPES` gains `SupportConsoleAgent`; the
  console's sessions are owned by one `SupportAgent` on the `CAPHIVE_ENTITY_ID` entity — see
  [Schema Detail](#schema-detail).
- **Turn state lives in `agent_chat_messages.metadata`** (no new column on existing tables); the
  "one running turn per session" rule is enforced with a row lock on the session — see
  [Transactions](#transactions-locking-and-concurrency).
- **The job holds an HTTP stream for up to 15 min** on a dedicated single-purpose capsule of 3 threads —
  see [Background Jobs](#background-jobs).
- **HMAC over `timestamp.body`, 60 s window** is the relay's only authentication beyond the security
  group — see [External Integrations](#external-integrations).
- **Scope guard is text-based** (best effort, v1) — its exact rules and known gaps are in
  [Security Review](#security-review).

---

## File Map

| Boundary | File | New / Modified | Responsibility |
|---|---|---|---|
| ① Console page | `app/packs/ai/support_console/controllers/support_console_controller.rb` | New | `index`, `show`, `create_turn`, `stop_turn` |
| ① | `app/packs/ai/support_console/views/support_console/index.html.erb` | New | Client picker / empty state |
| ① | `app/packs/ai/support_console/views/support_console/show.html.erb` | New | Conversation list + chat |
| ① | `app/packs/ai/support_console/views/support_console/_message.html.erb` | New | One message, `data-turn-status` |
| ① | `app/javascript/controllers/support_console_controller.js` | New | Ask/Stop toggling, keep question on failure |
| ① | `config/routes/ai.rb` | Modified | `support_console` routes |
| ① | left-menu partial (admin section) | Modified | "Support Console" entry for `:support` |
| ② Access check | `app/packs/ai/support_console/policies/support_console_policy.rb` | New | `index?`, `ask?(entity)`, `pickable_entities` |
| ③ Turn job | `app/packs/ai/support_console/jobs/support_console_turn_job.rb` | New | Post turn, consume NDJSON, write, broadcast |
| ③ | `app/packs/ai/support_console/services/support_console_relay_client.rb` | New | HMAC signing, streaming POST, stop, delete transcript |
| ③ | `app/packs/ai/support_console/services/support_console_client_brief.rb` | New | Per-client system-prompt text |
| ③ | `app/packs/ai/support_console/services/support_console_agent.rb` | New | Finds/creates the `SupportConsoleAgent` record |
| ③ | `config/initializers/sidekiq.rb` | Modified | `support_console` capsule, concurrency 3 |
| ④ Relay | `support_console/machine/relay/server.js` | New | HTTP service, HMAC, per-session lock, spawns `claude -p`, translates `stream-json`, tails the events file, `SIGTERM` on Stop |
| ⑤ Session | `support_console/machine/relay/claude_command.js` | New | Builds the `claude -p` argument list and per-turn environment |
| ⑤ | `support_console/machine/claude/support_brief.md` | New | Support brief (named so `.gitignore`'s `CLAUDE.md` rule does not drop it from the bundle) |
| ⑤ | (generated per turn by `claude_command.js`) | New | `settings.json` (permissions, `hooks.PreToolUse` → `scope_guard.js`) and `mcp.json` (the single `db` stdio server) |
| ⑥⑦ | `support_console/machine/lib/{sql_rules,db,events,tables}.js` | New | Scope rules shared by hook and data tool; replica checks and lookups; events file; tables with `entity_id` |
| — | `support_console/machine/scripts/check.js` | New | The ✓/✗ machine check used by `local_check` and `machine_check` |
| — | `lib/support_console_code_archive.rb` | New | `git archive` minus secrets + `REVISION` + `tables_with_entity_id.json` |
| ⑤ | `lib/tasks/support_console_code.rake` | New | `support_console:publish_code[<env>]` |
| ⑤ | `lib/capistrano/tasks/support_console.rake` | New | After-deploy hook |
| ⑥ Scope guard | `support_console/machine/hooks/scope_guard.js` | New | Claude Code `PreToolUse` command hook: exit 0 allow, exit 2 block |
| ⑥ | `lib/tasks/support_console_code.rake` (same) | New | Writes `tables_with_entity_id.json` into the archive |
| ⑦ Data tool | `support_console/machine/db-mcp/server.js` | New | stdio MCP: `query`, `describe_tables`; appends `query` events to `SUPPORT_EVENTS_FILE` |
| ⑦ | `lib/tasks/support_console/db_access.rake` | New | `support_console:provision_db_access[<env>]` (ported) |
| ⑦ / infra | `lib/tasks/support_console/machine.rake` | New | `support_console:machine[<env>]`, `machine_check` |
| Local | `lib/tasks/support_console/local.rake` | New | `support_console:local_setup`, `local_check` |
| ⑧ Record | `app/packs/ai/support_console/models/support_console_query.rb` | New | Audit row |
| ⑧ | `db/migrate/<ts>_create_support_console_queries.rb` | New | Table + indexes |
| ⑧ | `app/packs/ai/support_console/mailers/support_console_query_flagged_notifier.rb` | New | In-app alert to `:super` |
| ⑧ | `app/packs/ai/support_console/jobs/support_console_retention_job.rb` | New | 90-day purge |
| ⑧ | `config/initializers/sidekiq.rb` | Modified | Daily retention via sidekiq-cron (the app moved its crons there from `config/schedule.rb`) |
| ⑧ | admin dashboard for `SupportConsoleQuery` (`app/packs/core/base/controllers/admin/…`) | New | `:super` review list |
| — | `app/packs/ai/support_agents/models/support_agent.rb` | Modified | `AGENT_TYPES` += `SupportConsoleAgent` |
| Tests | `features/support_console/*.feature`, `features/step_definitions/support_console_*_steps.rb` | New | See [Test Plumbing](#test-plumbing) |

**Reviewer checks**
- [ ] Every class in the design's class diagram has a file here, and nothing here is missing from it
- [ ] Ruby files follow `app/packs/<domain>/<sub_domain>/...`; machine code lives under `support_console/machine/` and is excluded from the Rails autoload paths
- [ ] `support_console/machine/` is excluded from the code archive's credential strip list only for secrets, not for itself (the machine does not need its own source in `/code`)

---

## Schema Detail

**`support_console_queries`** (new): one row per lookup the assistant attempted, kept beyond conversation purge as the audit trail.

| Column | Change | Type | Limit | Null | Default | Index / FK | Why it's needed |
|---|---|---|---|---|---|---|---|
| `user_id` | Added | bigint | — | no | — | FK users; `(user_id, created_at)` | Who asked; never null — every turn has a user |
| `entity_id` | Added | bigint | — | no | — | FK entities; `(entity_id, created_at)` | The conversation's client |
| `agent_chat_session_id` | Added | bigint | — | yes | — | FK `on_delete: :nullify`; index | Nulled when the conversation is purged |
| `agent_chat_message_id` | Added | bigint | — | yes | — | FK `on_delete: :nullify` | Which turn; nulled on purge |
| `sql_text` | Added | text | 64 KB | no | — | — | Statements can be long; text, not string |
| `outcome` | Added | string | 10 | no | — | — | `ran`/`blocked`/`failed`; validated inclusion |
| `reason` | Added | string | 255 | yes | — | — | Short block/failure reason; truncated to 255 |
| `flagged` | Added | boolean | — | no | false | `(flagged, created_at)` | Foreign rows seen; filter for review |
| `row_count` | Added | integer | — | yes | — | — | Total rows (not capped count); null when not run |
| `duration_ms` | Added | integer | — | yes | — | — | Replica load review |
| `lag_seconds` | Added | integer | — | yes | — | — | Freshness; null if unknown |
| `code_rev` | Added | string | 40 | no | — | — | Full git sha |
| `event_seq` | Added | integer | — | no | — | unique `(agent_chat_message_id, event_seq)` | Sequence of the `query` event within its turn; stops a re-read stream inserting twice |
| `created_at` | Added | datetime | — | no | — | in composite indexes | — |

No `updated_at`: rows are append-only (`readonly?` true after create).

**Migration safety:** new empty table; no lock on existing tables; reversible (`create_table`).
Update `db/schema.rb` and `db/schema_test.rb`; run `db:clean_schema` (per the local migrate drift rule).

**Existing model:** `SupportAgent::AGENT_TYPES` gains `SupportConsoleAgent` — no column change.
GET requests run on a read-only connection in this app, so reads use `SupportConsoleAgent.existing` (`find_by`, nil before the first question) and only `create_turn` calls `SupportConsoleAgent.record`, which does `SupportAgent.find_or_create_by!(entity_id: ENV.fetch("CAPHIVE_ENTITY_ID"), agent_type: "SupportConsoleAgent")` with `name: "Support Console"`, `enabled: true`.

**Reviewer checks**
- [ ] Every new column and index has a "why", and none is unjustified
- [ ] Every foreign key has an index (`entity_id`, `user_id` via composites; `agent_chat_session_id` own index; `agent_chat_message_id` — add an index if purge nullification is slow)
- [ ] `outcome` and `reason` limits match validations
- [ ] Migration is reversible
- [x] Approval recorded for the `AGENT_TYPES` change (2026-10-16)

---

## Method Contracts

**`SupportConsolePolicy`** (Policy; record = `Entity`)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `index?` | — | `user.has_cached_role?(:support)` | — | — | Yes |
| `ask?` | record `Entity` | `index? && pickable_entities.exists?(id: record.id)` | — | — | Yes |
| `pickable_entities` | — | `EntityPolicy::Scope.new(user, Entity).resolve_admin.merge(SupportClientMapping.where("end_date IS NULL OR end_date >= ?", Time.zone.today))` | — | — | Yes |

**`SupportConsoleRelayClient`** (Service)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `#post_turn(request, &on_event)` | `TurnRequest` hash; block per parsed event | final `result` event hash | `RelayUnavailable`, `RelayBusy` (409), `RelayTimeout` | HTTP stream | No |
| `#stop(session_key)` | String | `true` | `RelayUnavailable` | aborts machine query | Yes (404 = already done → true) |
| `#delete_transcript(entity_id, claude_session_id)` | Integer, String | `true` | `RelayUnavailable` | deletes file on machine | Yes (404 → true) |

**`SupportConsoleClientBrief`** (Service)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `.call(entity)` | `Entity` | String ≤ 4 KB: name, id, up to 50 funds `name (id)`, rules | — | one `pluck(:id, :name)` on funds | Yes |

**`SupportConsoleTurnJob`** (Job)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `#perform(assistant_message_id)` | Integer | — | none escape (all mapped) | message updates, `SupportConsoleQuery` inserts, broadcasts | Guarded: no-op unless `turn_status == "queued"` |

**`SupportConsoleQuery`** (Model)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `.record_event!(event, message:)` | `query` event hash | record | `ActiveRecord::RecordInvalid` | insert; `after_create_commit` notifies when `flagged` | Unique on `(agent_chat_message_id, event["seq"])` — see below |

**Reviewer checks**
- [ ] Every raised error is handled in the job or listed in [Error Mapping](#error-mapping-and-logging)
- [ ] `record_event!` cannot double-insert for the same event (unique `(agent_chat_message_id, event_seq)`; `RecordNotUnique` is rescued as a no-op)

---

## Controllers, Params and Responses

| Action | Permitted params | Policy method | Success response | Failure response |
|---|---|---|---|---|
| `SupportConsoleController#index` | — | `authorize :support_console, :index?` | HTML picker | redirect `/`, "Not authorized." |
| `#show` | `:entity_id`, `:session_id` | `authorize entity, :ask?, policy_class: SupportConsolePolicy` | HTML | redirect, "Not authorized." |
| `#create_turn` | `:entity_id`, `:session_id` (optional), `:question` (String) | same `ask?` | `turbo_stream` append user + assistant (queued) | 422 turbo_stream with validation message; 409 if a turn is running |
| `#stop_turn` | `:entity_id`, `:session_id` | same `ask?` | `turbo_stream` replace assistant (stopping) | 404 when nothing running |

The session is looked up as `AgentChatSession.find_by!(id: session_id, support_agent: agent, chattable: entity)` — never by id alone.

**Reviewer checks**
- [ ] No action without `authorize`; `verify_authorized` not skipped
- [ ] No param sets `entity_id` on a record except through the authorized `entity`; `analyst_id` always `current_user.id`
- [ ] A session id from another client returns 404 (X3)

---

## Queries and Indexes

| Where | Query shape | Index used | Rows expected | Preload / batching |
|---|---|---|---|---|
| `pickable_entities` | `entities JOIN support_client_mappings … WHERE user_id = ? AND enabled AND (end_date …)` + permission bit | `index_support_client_mappings_on_user_id` | ≤ 50 | — |
| Conversation list | `AgentChatSession.where(support_agent:, chattable: entity).order(updated_at: :desc).limit(50)` | `index_agent_chat_sessions_lookup` | ≤ 50 | `includes(:analyst)`; first user message via one `where(agent_chat_session_id: ids, role: "user").group(:agent_chat_session_id).minimum(:id)` |
| Running-turn check | `session.agent_chat_messages.where(role: "assistant").where("JSON_EXTRACT(metadata, '$.turn_status') IN ('queued','running')").exists?` | `index_agent_chat_messages_on_agent_chat_session_id` | ≤ 200 per session | — |
| Resume id | last completed assistant message's `metadata->claude_session_id` | same | 1 | `order(id: :desc).limit(1)` |
| Retention | `AgentChatSession.where(support_agent: agent).where("updated_at < ?", 90.days.ago)` | `index_agent_chat_sessions_on_support_agent_id` | small | `find_each` |
| Admin list | `SupportConsoleQuery.where(flagged:).order(created_at: :desc)` | `(flagged, created_at)` | paginated 50 | `includes(:user, :entity)` |

Session `updated_at` is touched on every message (`belongs_to :agent_chat_session, touch: true` is not
present today — the job touches the session explicitly), so retention can use it.

**Reviewer checks**
- [ ] Every query is scoped by the authorized entity or the console's `SupportAgent`
- [ ] No N+1 on the conversation list; no unbounded loads

---

## Transactions, Locking and Concurrency

| Operation | Transaction scope | Lock | Race it prevents | Idempotency key |
|---|---|---|---|---|
| `create_turn` | create user + assistant(queued) messages | `session.lock!` then running-turn check | double click / two tabs starting two turns (E4) | — |
| Job start | set `turn_status` queued → running | `message.with_lock` | job re-delivery running a turn twice | `turn_status` guard |
| Stop | set `metadata.stop_requested = true` | `message.with_lock` | Stop racing completion | final status written once under lock |
| Query events | none (one insert per event) | — | duplicate event on reconnect | `(agent_chat_message_id, event_seq)` unique |

The relay call happens **outside** any transaction.

**Reviewer checks**
- [ ] No HTTP call inside a transaction
- [ ] Lock order: session before message, everywhere

---

## Background Jobs

| Job | Queue | Trigger | Retry / backoff | Discard on | Concurrency guard | Timeout |
|---|---|---|---|---|---|---|
| `SupportConsoleTurnJob` | `support_console` (own capsule, concurrency 3) | `create_turn` | `sidekiq_options retry: false` | `ActiveRecord::RecordNotFound` | `turn_status` + message lock | idle 120 s, total 15 min (client-side) |
| `SupportConsoleRetentionJob` | `low` | sidekiq-cron daily `0 21 * * *` (`config/initializers/sidekiq.rb`) | 3 | — | sidekiq-cron enqueues once per tick | — |
| `SupportConsoleQueryFlaggedNotifier` delivery | Noticed default | `after_create_commit` when `flagged` | Noticed default | — | one per row | — |

A Sidekiq restart mid-turn leaves the message `running`: on boot nothing resumes it; a sweep in
`SupportConsoleRetentionJob` (and on page load) marks `running` messages older than 20 minutes as
`failed` with "The answer was interrupted. Please ask again."

**Reviewer checks**
- [ ] A turn job delivered twice is harmless (second sees `running`, exits)
- [ ] The `support_console` capsule is added in `config/initializers/sidekiq.rb` and not to the default capsule's queues
- [ ] The retention cron is registered with sidekiq-cron in `config/initializers/sidekiq.rb`

---

## External Integrations

| Call | Method + path | Auth | Timeouts | Rate limit handling | Error → exception |
|---|---|---|---|---|---|
| Start turn | `POST {relay}/turns` (NDJSON response) | `X-Timestamp`, `X-Signature: hex(HMAC_SHA256(secret, "#{ts}.#{body}"))` | open 5 s; read idle 120 s; total 15 min | 409 → `RelayBusy` | connect/5xx → `RelayUnavailable`; idle/total → `RelayTimeout`; 401 → `RelayUnavailable` + error report |
| Stop | `DELETE {relay}/turns/current?session_key=` | same | 5 s / 10 s | — | 404 → ok |
| Delete transcript | `DELETE {relay}/clients/:entity_id/sessions/:id` | same | 5 s / 10 s | — | 404 → ok |
| Model (machine side) | `claude` CLI → Bedrock via instance role (`CLAUDE_CODE_USE_BEDROCK=1`); local mode: developer's `claude` login | IAM / login | Claude Code defaults | Claude Code retries | non-zero exit or `result.is_error` → `{type: "error"}` event |
| Replica (machine side) | MySQL 3306 as `support_ro` | password file mode 0400 | connect 5 s; `max_execution_time` 30 s | `MAX_USER_CONNECTIONS 4` → error event | error event `db_unavailable` / `not_a_replica` / `timeout` |

`session_key` = `"#{entity_id}:#{agent_chat_session.id}"`. Relay rejects `|now − ts| > 60 s`.

**NDJSON events** (one per line): `{"type":"progress","text":…}`, `{"type":"text","delta":…}`,
`{"type":"query","seq":n,"sql":…,"outcome":…,"reason":…,"row_count":…,"duration_ms":…,"lag_seconds":…,"flagged":…}`,
`{"type":"result","claude_session_id":…,"code_rev":…,"lag_seconds":…}`, `{"type":"error","code":…,"message":…}`.

**Reviewer checks**
- [ ] The HMAC secret and `support_ro` password are never logged; request bodies are logged at debug only, truncated
- [ ] Every non-2xx maps to a named exception

---

## Error Mapping and Logging

| Exception / event | Raised in | Handled by | User sees | Logged / alerted |
|---|---|---|---|---|
| `Pundit::NotAuthorizedError` | controller | `ApplicationController` | "Not authorized." | info |
| access fails in job | job | job → `turn_status refused` | "Your support access to <client> has ended." | info |
| `RelayUnavailable` | `RelayClient` | job → `failed` | "The Support Console is unavailable right now…" | `ErrorReport.notify` with entity, session, message ids |
| `RelayBusy` | `RelayClient` | job → `failed` | "Already working on a question in this conversation." | warn |
| `RelayTimeout` | `RelayClient` | job → stop + `failed` | "That took too long. Try a narrower question." | warn |
| event `not_a_replica` | db MCP | job → `failed` | unavailable message | `ErrorReport.notify` (must be fixed) |
| event `db_unavailable` | db MCP | job → `failed` | unavailable message | `ErrorReport.notify` |
| any other `StandardError` | job | job → `failed` | unavailable message | `ErrorReport.notify` |

**Reviewer checks**
- [ ] No bare rescue without `ErrorReport.notify` or a named mapping
- [ ] Log lines carry `entity_id`, `agent_chat_session_id`, `agent_chat_message_id`

---

## Security Review

| Concern | Decision |
|---|---|
| Authorization | `SupportConsolePolicy` on every action and again in the job; `pickable_entities` = `resolve_admin` + end-date check |
| Tenant isolation (app) | Sessions looked up by `(id, support_agent, chattable)`; URLs carry `entity_id` checked by `ask?` |
| Tenant isolation (data, v1) | Best effort: brief; PreToolUse rules — (1) statement must start `SELECT`/`WITH` after stripping comments, no `;`; (2) any `entity_id\s*(=|IN)\s*\(?\s*\d+` literal must equal the session id; (3) each table from `FROM`/`JOIN` that is in `tables_with_entity_id.json` requires `entity_id = <id>` (optionally alias-qualified) somewhere in the statement; result check flags foreign `entity_id` values. Known gap: `OR` clauses and loose joins (X10) |
| Machine | No production credentials; Bash denied; deny paths outside `/code/<rev>` and `/clients/<id>`; SG inbound app SG only; outbound replica IP, S3 code bucket, Bedrock |
| Secrets | HMAC secret in Rails credentials per env (`SUPPORT_CONSOLE_RELAY_SECRET`) and on the machine in SSM SecureString; `support_ro` password in SSM SecureString → file 0400 owned by the relay user |
| Input / output | Answers rendered as Markdown through the app's existing sanitizer (no raw HTML); question length ≤ 4,000 |
| Mass assignment | Only `question`, `entity_id`, `session_id` permitted |

**Reviewer checks**
- [ ] A support user cannot reach another client's session through any route or job (X3)
- [ ] The code archive excludes `config/credentials/*`, `config/master.key`, `.env*`, `docs/incidents/`
- [ ] Claude's `Read` cannot reach `/etc/support-console/` (secrets) — deny path covers it

---

## Configuration and Rollout

| Item | Value / location |
|---|---|
| Rails credentials (per env) | `SUPPORT_CONSOLE_RELAY_URL`, `SUPPORT_CONSOLE_RELAY_SECRET`; `CAPHIVE_ENTITY_ID` (existing) |
| Machine (per env) | SSM: `/irm/support-console/<env>/replica` (host, db, user, pass), `/irm/support-console/<env>/relay-secret`; env `CLAUDE_CODE_USE_BEDROCK=1`, `AWS_REGION`, `SUPPORT_CONSOLE_MODEL_SONNET` / `SUPPORT_CONSOLE_MODEL_OPUS` |
| Local mode | `SUPPORT_CONSOLE_LOCAL=1` on the relay only: the data tool requires the write probe to be refused instead of `read_only`/`super_read_only`; `claude` uses the developer's own login; `rake support_console:local_setup` / `local_check`; in development Rails reads `SUPPORT_CONSOLE_RELAY_URL`/`SECRET` from `tmp/support_console/machine.env` when credentials lack them. `machine_check` fails if the flag is set on a deployed machine |
| Feature flag | Menu entry and routes require `:support`; additionally `SUPPORT_CONSOLE_RELAY_URL` present — absent ⇒ page shows "not configured" |
| Cron | Retention daily via sidekiq-cron |
| Bedrock budget | AWS Budgets, $10/month per environment on Bedrock, alert only (approved 2026-10-16); created by `support_console:machine[<env>]` |
| Deploy order | migration → app code (page hidden until relay URL set) → machine provisioning → publish code → set credentials |
| Rollback | Remove `SUPPORT_CONSOLE_RELAY_URL`; machine can be stopped; table can stay |
| IN / US | Separate credentials, machines, SSM parameters, Bedrock regions; nothing shared |

**Reviewer checks**
- [ ] Safe to deploy with the feature unconfigured, and safe to roll back

---

## Test Plumbing

| Feature file | Stubs / fixtures | Factories | New step definitions |
|---|---|---|---|
| `features/support_console/access.feature` | relay stub | existing user/entity/support mapping factories | `Given Meera is mapped to "Golden Angels"…` (reuse mapping steps where present) |
| `features/support_console/ask.feature` | `SupportConsoleRelayStub` scripted NDJSON via WebMock streaming body | — | `Given the relay will answer with …`, `When I ask "…"`, `Then I should see the answer …` |
| `features/support_console/query_record.feature` | relay stub with `query` events | — | `Then a support console query should be recorded as …` |
| `features/support_console/retention.feature` | time travel; relay stub for delete | sessions with message dates | `Given a support console conversation last active N days ago` |
| `features/support_console/relay.feature` | runs `support_console/machine/relay` with `CLAUDE_BIN` pointing at a fake `claude` script replaying recorded `stream-json` | — | `When I send a turn signed with …` |

---

## Project Rules Checklist

| Rule | Applies? | How it is met |
|---|---|---|
| No `blank?`/`present?` on relations; use `exists?`/`none?` | Applies | Running-turn check and picker empty state use `exists?` |
| Dedup in SQL (`distinct.pluck`), batch bulk operations (`find_each`/`in_batches`) | Applies | Retention uses `find_each`; first-message lookup grouped in SQL |
| Select only needed columns when loading many `account_entries`; no speculative `includes` of big associations | Applies (brief) | The brief tells Claude to aggregate and filter on indexed columns; app code never loads `account_entries` |
| Screen dates via `l(...)`; emails `Mon dd, yyyy`; no human-format `strftime` | Applies | Conversation list dates via `l(date)`; no emails |
| Date inputs use `f.date_field` / `date_field_tag`; JS dates via `locale_date_format.js` | N/A | No date inputs; JS renders no dates |
| Every query entity-scoped; Pundit on every action | Applies | See Security Review |
| MCP tool surfaces changed only via the ontology YAML | N/A | The client-facing MCP server is untouched; the machine's db tool is separate |
| Cucumber only; `TEST_ENV_NUMBER=$RANDOM` | Applies | Features above; no RSpec |
| `bundle exec rubocop` clean incl. `IRM/RelationBlankPresent` | Applies | — |

---

## Sign-off

| Reviewer | Date | Decision | Notes |
|---|---|---|---|
| | | | |
