# Tasks

> **Phase gate:** each numbered group below is a phase. A phase's last task is always to run its
> Cucumber feature and get it green. Do not start the next phase until that happens — if it fails,
> fix the phase you're on rather than moving forward and coming back later.

> **Approvals (given 2026-10-16):** adding `SupportConsoleAgent` to `SupportAgent::AGENT_TYPES` — approved;
> the security-group rule from the support machine into the replica — approved; Bedrock budget —
> **$10 per month per environment, alert only** (an AWS Budgets alarm, questions keep working).

## 1. Access and the console page

- [x] 1.1 Add `SupportConsoleAgent` to `SupportAgent::AGENT_TYPES` and create `SupportConsoleAgent.record`
      (finds/creates the CapHive-owned `SupportAgent`) — LLD [Schema Detail](lld.md#schema-detail). Verify:
      `rails runner 'p SupportConsoleAgent.record.agent_type'` prints `SupportConsoleAgent`.
- [x] 1.2 Create `SupportConsolePolicy` with `index?`, `ask?`, `pickable_entities` (resolve_admin + end-date
      check), with ID comments (H2, E5, E6, E7, X1, X2) — LLD [Method Contracts](lld.md#method-contracts).
      Verify: `rails runner` with Meera returns only Golden Angels.
- [x] 1.3 Add routes, `SupportConsoleController#index` and `#show`, the picker / empty state / conversation
      list views and the left-menu entry for `:support` — LLD [Controllers](lld.md#controllers-params-and-responses),
      [Queries](lld.md#queries-and-indexes). Verify: page renders locally for a support user; dates via `l(...)`.
- [x] 1.4 Write `features/support_console/access.feature` (header links to design.md#worked-examples) covering
      H2, E1, E5, E6, E7, X1, X2, each with its `# ID — …` comment. Run
      `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/support_console/access.feature` until green
      before starting phase 2.

## 2. Asking: turn job, relay client and streaming (relay stubbed)

- [x] 2.1 Add the `support_console` capsule (concurrency 3) in `config/initializers/sidekiq.rb` — LLD
      [Background Jobs](lld.md#background-jobs). Verify: Sidekiq boots and lists the capsule.
- [x] 2.2 Add Rails credentials keys `SUPPORT_CONSOLE_RELAY_URL` / `SUPPORT_CONSOLE_RELAY_SECRET` (dev/test
      values only) and the "not configured" state — LLD [Configuration](lld.md#configuration-and-rollout).
      Verify: page shows "not configured" when the URL is absent.
- [x] 2.3 Implement `SupportConsoleClientBrief` and `SupportConsoleRelayClient` (HMAC, streaming NDJSON,
      stop, delete transcript, error classes) with ID comments — LLD [External Integrations](lld.md#external-integrations).
      Verify: `rails runner` against a local stub server prints parsed events.
- [x] 2.4 Implement `#create_turn` and `#stop_turn` (validation 1–4,000 chars, session lock, running-turn
      refusal, session lookup by `(id, support_agent, chattable)`) — LLD
      [Transactions](lld.md#transactions-locking-and-concurrency). Verify: a POST creates the user and queued
      assistant messages.
- [x] 2.5 Implement `SupportConsoleTurnJob` (re-authorize, queued→running guard, resume id from metadata,
      chunked Turbo broadcasts, timeouts, stop, error mapping, stale-`running` sweep on page load) — LLD
      [Background Jobs](lld.md#background-jobs), [Error Mapping](lld.md#error-mapping-and-logging).
      Verify: with the stub, an answer streams into the page.
- [x] 2.6 Add `_message.html.erb` and `support_console_controller.js` (Ask/Stop toggling, keep the question
      on failure, lag warning above 60 s, code version footer). Verify: manual run in the browser.
- [x] 2.7 Add `SupportConsoleRelayStub` (WebMock streaming body of scripted NDJSON) and step definitions —
      LLD [Test Plumbing](lld.md#test-plumbing).
- [x] 2.8 Write `features/support_console/ask.feature` covering H1, H3, H4, H6, E2, E3, E4, E9, E10, E11, E12,
      E18, E21, X4, X5, X7, X9, X11, X12, X13, and extend `access.feature` with E8 and X3. Run
      `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/support_console/ask.feature features/support_console/access.feature`
      until green before starting phase 3.

## 3. Query record, alerts and retention

- [x] 3.1 Migration `create_support_console_queries` with every column and index from LLD
      [Schema Detail](lld.md#schema-detail) (incl. unique `(agent_chat_message_id, event_seq)`); update
      `db/schema.rb` and `db/schema_test.rb`; run `db:clean_schema`. Verify: `bin/rails db:migrate:redo` succeeds.
- [x] 3.2 Implement `SupportConsoleQuery` (validations, `readonly?` after create, `record_event!` rescuing
      `RecordNotUnique`) and call it from the job for each `query` event — LLD [Method Contracts](lld.md#method-contracts).
      Verify: a stubbed turn creates rows.
- [x] 3.3 Implement `SupportConsoleQueryFlaggedNotifier` (in-app to `:super` users, once per row) — design
      [Notifications](design.md#notifications). Verify: a flagged row creates one notification per super user.
- [x] 3.4 Add the `:super`-only admin list with flagged / user / client filters — LLD [Queries](lld.md#queries-and-indexes).
      Verify: page lists rows newest first.
- [x] 3.5 Implement `SupportConsoleRetentionJob` (90-day purge via `find_each`, relay transcript delete,
      query FKs nullified, stale-`running` sweep) and register it with sidekiq-cron in
      `config/initializers/sidekiq.rb`. Verify: `rails runner 'SupportConsoleRetentionJob.perform_now'` purges a seeded old session.
- [x] 3.6 Write `features/support_console/query_record.feature` covering H5, E13, E14, E15, E16, E17, E19, X10,
      X14, and `features/support_console/retention.feature` covering E20. Run
      `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/support_console/query_record.feature features/support_console/retention.feature`
      until green before starting phase 4.

## 4. The support machine: relay, Claude Code session, scope guard, data tool

- [x] 4.1 Scaffold `support_console/machine/` (plain Node scripts, no build step; `@modelcontextprotocol/sdk` and
      `mysql2` pinned; the Claude Code CLI is the only harness — no Agent SDK; excluded from Rails autoload and
      from the code archive) — LLD [File Map](lld.md#file-map). Verify: `npm --prefix support_console/machine ci` succeeds.
- [x] 4.2 Implement `relay/server.js` and `relay/claude_command.js`: HMAC + 60 s window, one turn per
      `session_key` (409), spawn `claude -p … --output-format stream-json` in `/clients/<entity_id>` (binary from
      `CLAUDE_BIN`, default `claude`), translate `stream-json` to relay NDJSON, tail the turn's events file,
      `SIGTERM` on Stop, transcript delete, private-interface bind. ID comments X6, X8, E11. Verify:
      `npm --prefix support_console/machine test` with a fake `claude` script.
- [x] 4.3 Write `claude/settings.json` (`permissions.allow`/`deny`, `hooks.PreToolUse` → `scope_guard.js`),
      `claude/mcp.json` and `claude/support_brief.md` (support brief; not `CLAUDE.md`, which `.gitignore` ignores everywhere) — design [card ⑤](design.md#⑤-claude-code-session).
      Verify: running the card's `claude -p` command by hand in a client folder answers a code-only question and
      a Bash attempt is denied (X9).
- [x] 4.4 Implement `hooks/scope_guard.js` (reads hook JSON on stdin; exit 2 + stderr to block; appends a
      `blocked` event) with the rules in LLD [Security Review](lld.md#security-review), ID comments E13, E14, E16,
      X10. Verify: `npm test` table of allow/deny cases.
- [x] 4.5 Implement `db-mcp/server.js`: `read_only`/`super_read_only` check plus refused write probe (probe only
      under `SUPPORT_CONSOLE_LOCAL=1`), 30 s `max_execution_time`, 200-row cap with `total_rows`, lag from
      `SHOW REPLICA STATUS`, result flagging, `describe_tables`, `query` events to `SUPPORT_EVENTS_FILE`. ID
      comments E15, E17, E18, E19, E22, X11, X12. Verify: `npm test` against the local MySQL with a SELECT-only and
      a writable account.
- [x] 4.6 Add `support_console:local_setup` and `support_console:local_check` (local SELECT-only `support_ro`,
      `tmp/support_console/machine.env`, local code archive, `npm run dev` relay in local mode) and the development
      fallback that reads the relay URL/secret from `machine.env` — design
      [Local development](design.md#local-development). Verify: `local_check` passes and a question at
      `localhost:3000/support_console` gets a real answer about a local client, end to end.
- [x] 4.7 Port `sandbox:provision_db_access` as `support_console:provision_db_access[<env>]` (dry run,
      `EXECUTE=1`, STS account assertion, `'support_ro'@'<machine IP>'`, ceilings, SG rule to the replica's
      address only, verify reads + refused write) — LLD [Configuration](lld.md#configuration-and-rollout).
      Verify: dry run against staging.in prints the plan.
- [x] 4.8 Add `support_console:publish_code[<env>]` (git archive minus credentials, `.env*`, `docs/incidents`,
      `support_console/machine`; writes `tables_with_entity_id.json` from `db/schema.rb`) and the Capistrano
      after-deploy hook. Verify: the archive contains no file under `config/credentials/`.
- [ ] 4.9 Add `support_console:machine[<env>]` and `support_console:machine_check[<env>]` (instance with Node and
      the Claude Code CLI, role with Bedrock + S3 read + SSM parameter read, SG inbound from app SG only, outbound
      replica/S3/Bedrock; systemd unit for the relay; `machine_check` fails if `SUPPORT_CONSOLE_LOCAL` is set; an
      AWS Budgets alarm on Bedrock spend at $10/month for the environment, alert only, to `SUPPORT_CONSOLE_BUDGET_EMAIL="ausang@caphive.com,thimmaiah@gmail.com"`). Verify: dry run prints the
      plan; the budget exists in the environment's account.
- [x] 4.10 Write `features/support_console/relay.feature` covering X6, X8 and E22 (runs the Node relay with a fake
      `claude` script). Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/support_console/relay.feature`
      until green before starting phase 5.

## 5. Staging rollout, coverage and QA

> **Staging state (2026-10-17, parked):** machine `i-02e01902551c2721a` (10.0.3.40) created and **stopped**;
> `support_ro` granted and verified; bundles at `98b6eca43`; relay settings in staging credentials;
> `machine_check` passes. **Blocked on Bedrock:** the subscription to Claude Sonnet 5.5 / Opus 5.5 is refused with
> `INVALID_PAYMENT_INSTRUMENT` — the staging account needs a valid payment method for AWS Marketplace (design
> open question 4). To resume: fix the payment method → `EXECUTE=1 rake "support_console:machine_start[staging.in]"`
> → re-test both models on the machine → ask in the staging console.

- [ ] 5.1 Provision staging.in: `provision_db_access`, `machine`, `publish_code`, credentials; run
      `machine_check` until all lines pass. Verify: a real question about a staging client is answered end to end.
- [ ] 5.2 Confirm the Bedrock model id/region and whether the replica is the DR standby (design open
      questions 1–2); record answers in design.md.
- [x] 5.3 Add the Support Console user guide under `docs/user_guides/` with FAQs (UserGuideLint clean) and
      update `docs/modules/ai/support_console/design.md` to point at this change.
- [x] 5.4 Coverage check: list every H/E/X ID in design.md and every `# ID —` comment in
      `features/support_console/`; confirm the sets are equal; any new edge case gets a design.md row and a scenario.
- [x] 5.5 Run all Support Console features together:
      `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/support_console/` and `bundle exec rubocop` clean.
- [ ] 5.6 (QA) Run [qa-checklist.md](qa-checklist.md) on the staging build and record the sign-off.

## 6. Review fixes (2026-10-19)

Code review of the branch before staging; worked examples X16–X27 in [design.md](design.md).

- [x] 6.1 Scope check parses SQL as MySQL (`node-sql-parser`), checks every SELECT, refuses denied tables and
      other schemas, and runs the SQL rebuilt from the checked parse (X16–X20). Verify: `npm test` in
      `support_console/machine`.
- [x] 6.2 Data tool refuses an account holding more than SELECT / SHOW VIEW / REPLICATION CLIENT (X21).
- [x] 6.3 Relay passes Claude an allow-listed environment (no relay secret), denies the read tools the
      machine's secret paths and the clients folder, keeps one Claude config folder per client, caps
      `--max-turns`, sends the Claude session id first, and survives a torn events line (X22, X25).
- [x] 6.4 Code archive is an allow-list; no deploy key or credentials reach the machine (X27).
- [x] 6.5 Rails: follow-ups are re-checked, recorded and labelled for the asker (X23); answers use a strict
      cleaner with no img/id/class/data-* (X24); the Claude session id is stored on arrival (X25); stale
      turns count from `started_at` (X26).
- [x] 6.6 Provisioning: `'support_ro'@'<machine IP>'` (the old `10.%` account dropped), parameter restored
      when a new password never reaches the account, KMS decrypt limited to the two parameters, Bedrock to
      the two models, no `aws-marketplace:Subscribe`, SG rule refused on production when the writer shares
      the replica's group. Docs corrected (shared IN/US account, global profiles, archive contents).
- [x] 6.7 Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/support_console/` and `bundle exec rubocop`
      on the changed files until green.
- [x] 6.8 Staging: re-run `provision_db_access` (creates the per-IP account, drops `10.%`), `machine` (new
      policy, `SUPPORT_CONSOLE_CLAUDE_DIR`), `publish_code`; `machine_check` all ✓. Done 2026-10-20 under 7.5;
      the Marketplace step no longer applies (subscription token).

## 7. Subscription token instead of Bedrock (2026-10-19)

Worked examples E32, X28, X29 in [design.md](design.md); open question 5.

- [x] 7.1 `SUPPORT_CONSOLE_AUTH=subscription|bedrock` (default subscription): user-data writes
      `CLAUDE_CODE_OAUTH_TOKEN` from `/irm/support-console/<env>/claude-token`; models are the `sonnet` / `opus`
      aliases; the role reads and decrypts the token and has no Bedrock or Marketplace access; no budget alarm.
- [x] 7.2 `support_console:claude_token[<env>]` stores or rotates the token (read hidden) and its expiry in
      `/irm/support-console/<env>/claude-token-expires-at` (a plain String: operators cannot read or write tags);
      `machine` and `machine_check` report it and warn 30 days before expiry.
- [x] 7.3 Relay sends `usage_limit` / `auth_failed`; the turn job shows the usage-limit message (X28) or reports
      the dead token (X29); `machine_check` runs one tiny prompt to prove the token signs in.
- [x] 7.4 Run `features/support_console/` and rubocop until green.
- [x] 7.5 Staging: `claude setup-token`, `claude_token[staging.in]`, then `machine_down` + `machine` (the
      auth mode is baked in at launch), `publish_code`, `machine_check` all ✓.
      Done 2026-10-20: machine at 10.0.3.88 on `613032142023`; the staging app user cannot GRANT, so an admin ran
      `CREATE USER 'support_ro'@'10.0.3.88'` (stored password) + `GRANT SELECT, SHOW VIEW` and
      `DROP USER 'support_ro'@'10.%'`, then `SKIP_ACCOUNT=1 provision_db_access` opened 3306;
      `SUPPORT_CONSOLE_RELAY_URL` in staging credentials → `http://10.0.3.88:4900`. Remaining: deploy and ask a
      real question (5.1).
- [x] 7.6 `machine_down` with `EXECUTE=1` refuses unless `TERMINATE=1` is also set: terminating releases the
      machine's private IP, which `SUPPORT_CONSOLE_RELAY_URL` and `'support_ro'@'<IP>'` are tied to;
      `machine_stop` / `machine_start` keep it.

## 8. Closing the old chat door and the REGION trap (2026-10-19)

- [x] 8.1 `SupportAgentPolicy#show?` refuses the `SupportConsoleAgent`, so the generic AI-agent chat routes
      cannot create, read or delete console conversations (X30, X31).
- [x] 8.2 `SupportConsoleDbAccess.region` refuses a `REGION` override on production unless it is the
      environment's own region; the account check prints the region on every run (X32).
- [x] 8.3 Run `features/support_console/` until green.

## 9. Machine control and conversation usage (2026-10-20)

Worked examples H7–H11, E33–E35, X34 in [design.md](design.md).

- [x] 9.1 `SupportConsoleMachineControl`: finds this environment's machine through `SUPPORT_CONSOLE_RELAY_URL`
      (private IP + `irm-support-console-*` tag), the app's own AWS keys and `AWS_REGION` (as `DbRestoreService`);
      status from EC2 first, then the relay's `/health`. Stop / start only — never terminate.
- [x] 9.2 Header badge (lazy frame, live via `:support_console_machine`) with Start / Stop popups for `:support`
      users (`SupportConsolePolicy#machine?`); `SupportConsoleMachineJob` follows the machine up or down.
- [x] 9.3 A question while the machine is stopped starts it and waits (turn job `wake_machine`, once).
- [x] 9.4 `SupportConsoleIdleStopJob` every 10 minutes (sidekiq-cron); `SUPPORT_CONSOLE_IDLE_STOP_MINUTES`, default 15 (was 60 until 2026-10-20).
- [x] 9.5 Relay sends token `usage`; the composer footer totals the conversation's tokens and approximate cost.
- [x] 9.6 `support_console:app_machine_check[env]` — EC2 DryRun with the app's keys; staging.in ✓.
- [ ] 9.7 Run `app_machine_check` for production.in and production.us before deploying there.
