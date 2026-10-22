# Tasks

> **Phase gate:** each numbered group below is a phase. A phase's last task is always to run its
> Cucumber feature and get it green. Do not start the next phase until that happens — if it fails,
> fix the phase you're on rather than moving forward and coming back later.

> Run every Cucumber command with a fresh `TEST_ENV_NUMBER=$RANDOM` and Redis up on 6379. Every scenario
> carries a comment `# <ID> — <Happy path|Edge case|Error case>: …` matching [business-rules.md](business-rules.md);
> code comments name the IDs of the paths they implement.

## 1. Extract the Support Console's shared pieces (no behaviour change)

- [ ] 1.1 Extract `ClaudeRelayClient` from `SupportConsoleRelayClient` (relay URL and secret injected);
      `SupportConsoleRelayClient` becomes its configuration. Verify: `bundle exec rubocop` clean on both files.
- [ ] 1.2 Extract `ClaudeTurnRunner` (claim / run / handle / finish / stale sweep, with profile hooks for
      unknown events and `on_finish`) from `SupportConsoleTurnJob`; the job delegates to it. Verify: the
      Support Console job file only configures the runner.
- [ ] 1.3 Extract `ClaudeMachineControl` (tag, secret, relay port) from `SupportConsoleMachineControl`;
      the Support Console keeps its tag `irm-support-console-<env>-<site>`. Verify: `support_console:machine_check`
      dry run prints the same instance.
- [ ] 1.4 Move `support_console/_chat`, `_message`, `_composer` and `answer_markdown_html` to
      `shared/claude_chat/*` and a shared helper, with locals for stream name and composer actions.
      Verify: the Support Console page renders unchanged in the browser.
- [ ] 1.5 Regression gate for this phase: run
      `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/support_console/` and confirm every scenario
      passes unchanged (no new feature: this phase must not change behaviour) before starting phase 2.

## 2. Permissions, encrypted key and read-only tokens

- [ ] 2.1 Append `enable_ops_assistant` to the entity `permissions` flags (`EntityEnabled`) and the user
      `permissions` flags (`UserEnabled`); add `User#enable_ops_assistant` = user flag && entity flag (as
      `enable_ai_chat`); show the tick on the super-user Entity permissions screen and the Users › Permissions
      screen. Verify: ticking both in the UI makes `enable_ops_assistant` true in the console of a dev run.
- [ ] 2.2 `encrypts :anthropic_api_key` on `EntitySetting` with `support_unencrypted_data` on; mask it in
      `EntitySettingDashboard`; add `rake ops_assistant:encrypt_keys` (dry run, `EXECUTE=1` re-saves keys).
      Verify: dry run lists entities with keys; `LlmService.ruby_llm_chat(entity:)` still builds with the key.
- [ ] 2.3 Migration: `devise_api_tokens.read_only` boolean, null false, default false; update `schema.rb`
      and `schema_test.rb`. Verify: `bin/rails db:migrate` then `db:rollback` both succeed.
- [ ] 2.4 `WithAuthentication`: a read-only token gets 403 `{"error":"read-only token"}` on any non-GET;
      `OpsAssistantToken.mint(user, read_only:, ttl:)` / `.revoke!`. Verify: curl with a minted read-only
      token: GET 200, POST 403.
- [ ] 2.5 Write `features/api/ops_assistant_tokens.feature` covering E20, E33, X17 and C8 (an ordinary
      token still writes). Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/api/ops_assistant_tokens.feature`
      and confirm it passes before starting phase 3.

## 3. The page, conversations and turns (fake relay)

- [ ] 3.1 Routes, `OpsAssistantController`, `OpsAssistantPolicy` (design card ① role table), menu item;
      the entity's "Ops Assistant" `SupportAgent` record created on switch-on. Verify: Arjun sees the
      page, Ravi gets "Not authorized."
- [ ] 3.2 `AgentChatMessage has_many_attached :files`; attachment validation (5 files, 20 MB, xlsx/xls/csv/pdf),
      download action with policy. Verify: uploading `big.xlsx` shows the size message.
- [ ] 3.3 `OpsAssistantTurnJob` on `ClaudeTurnRunner`: mints a 30-min read-only token, builds the payload
      (question, brief from `OpsAssistantBrief`, file signed URLs, entity key, resume id, model), revokes
      the token in `on_finish`; handles `file` and `api_gap` events; no-key and key-refused messages.
      Verify: with the fake relay, an answer streams into the page.
- [ ] 3.4 `OpsAssistantApiGap` model + upsert from the `api_gap` event (no entity, no data). Verify: a
      fake `api_gap` event creates one row; a second increments `occurrences`.
- [ ] 3.5 Delete conversation: messages, files, waiting cards cancelled, relay transcript delete. Verify:
      the deleted conversation's file URL returns 404.
- [ ] 3.6 Write `features/ops_assistant/access.feature` (X1–X6, X10, E1, R1–R5), `features/ops_assistant/ask.feature`
      (H1, E2, E3, E6, E9, E12, X7–X9, X15) and `features/ops_assistant/files.feature` (E4, E5, E7, E8).
      Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/ops_assistant/access.feature features/ops_assistant/ask.feature features/ops_assistant/files.feature`
      and confirm they pass before starting phase 4.

## 4. Approval cards

- [ ] 4.1 Migration + `OpsAssistantAction` (columns per [lld.md](lld.md#schema-detail)), `propose!` from
      the `action` event (idempotent by event id), statuses per the design's lifecycle. Verify: a fake
      `action` event shows a waiting card.
- [ ] 4.2 `OpsAssistantActionRules`: never-list (DELETE, import undo/delete-data, entities, entity settings,
      permissions), investor-notice registry, async registry. Verify: a DELETE event is stored as refused.
- [ ] 4.3 `OpsAssistantActionPreview#facts` (port `review.rb#describe`: sheets, rows, columns, money totals,
      dates) and `#preconditions_hold?` through `OpsAssistantApiClient` with a read token. Verify: the
      card shows "275 rows · Σ Call Amount ₹91,92,54,680.13" for the fixture file.
- [ ] 4.4 `OpsAssistantActionsController#approve/reject` + `OpsAssistantActionPolicy` (asking user only,
      flags re-checked); approve under `with_lock` (`waiting` → `running` once), expiry at 24 h,
      `OpsAssistantExpiryJob` (cron every 15 min); `_action_card` partial with live updates.
      Verify: double-clicking Approve enqueues one job.
- [ ] 4.5 `OpsAssistantApprovalWaitingNotifier` (in-app + email to the asking user, once per card).
      Verify: one bell item per waiting card.
- [ ] 4.6 Write `features/ops_assistant/approvals.feature` covering H2, H6, E11, E21–E28, X13, X18–X22.
      Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/ops_assistant/approvals.feature` and confirm
      it passes before starting phase 5.

## 5. Action runner, watcher, notifications

- [ ] 5.1 `OpsAssistantApiClient#request` (JSON and multipart, 5-min write token minted and revoked per
      request, `OPS_ASSISTANT_API_BASE_URL`, timeouts per LLD). Verify: a PATCH to the investor endpoint as
      Arjun from a dev console call returns 200 and the audit shows Arjun.
- [ ] 5.2 `OpsAssistantActionJob` (no retries; `executed_at` saved before sending; 2xx → succeeded or
      watching; 4xx/5xx → failed; timeout → unknown). Verify: stubbing a 500 leaves the card failed with
      no second request.
- [ ] 5.3 `OpsAssistantWatchJob` (30 s ×10 then 60 s, limit 2 h; succeeded / partial / failed / unknown;
      touches machine activity; `reported_at`), follow-up system turn re-checking the user's permission.
      Verify: a stubbed import upload moving to Completed posts one follow-up answer.
- [ ] 5.4 `OpsAssistantWorkFinishedNotifier`, `OpsAssistantWorkFailedNotifier` (in-app + email, once via
      `reported_at`; email dates via `EmailDateLocalization`). Verify: the email shows `Oct 22, 2026` style dates.
- [ ] 5.5 Write `features/ops_assistant/runner.feature` covering H3, H5, E10, E29–E32, X16, X23–X27. Run
      `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/ops_assistant/runner.feature` and confirm it
      passes before starting phase 6.

## 6. Knowledge folder

- [ ] 6.1 `OpsAssistantKnowledge#folder`: private `system` folder **Ops Assistant** under
      `entity.root_folder` with Skills/, Learnings/, Proposed/, Reports/, created on switch-on and
      recreated if missing; access per design card ⑧. Verify: Documents shows the tree for Meera, not for Kiran.
- [ ] 6.2 `propose!` from the `learning` event (markdown Document in Proposed/, idempotent per session +
      title), `OpsAssistantLearningProposedNotifier` to company admins. Verify: a fake event creates one document.
- [ ] 6.3 What I've learned page: Confirm (as Skill or Learning → move), Discard / Remove (delete), policy
      `manage?` for company admins. Verify: confirming moves the document.
- [ ] 6.4 `brief` (Skills/ + Learnings/, 50 docs / 200 KB cap with a truncation note) wired into
      `OpsAssistantBrief`; `write_report!` from the runner after a task. Verify: the fake relay receives the
      confirmed learning's text in the next turn's payload.
- [ ] 6.5 Write `features/ops_assistant/knowledge.feature` covering H7, H8, E34–E36, X28, X29. Run
      `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/ops_assistant/knowledge.feature` and confirm it
      passes before starting phase 7.

## 7. One machine per client

- [ ] 7.1 Migration + `OpsAssistantMachine` (encrypted `relay_secret`, unique `entity_id`); switching
      `enable_ops_assistant` on enqueues `OpsAssistantMachineJob(:provision)`, off enqueues `:stop`.
      Verify: ticking the permission in dev (with the EC2 fake) creates a row in `provisioning`.
- [ ] 7.2 `ClaudeMachineControl#provision!` (RunInstances from `irm-ops-assistant-<env>` with `entity_id` tag,
      SSM put of the relay secret), `ensure_running!` per the design's decision flowchart, re-provision on
      terminated; `OpsAssistantMachineFailedNotifier` to super users. Verify: with the EC2 fake, a turn to
      a stopped machine starts it and then answers.
- [ ] 7.3 `OpsAssistantIdleStopJob` (cron every 5 min; ≥ 30 min idle and no running/watching action);
      machine status on the Entity screen. Verify: back-dating `last_activity_at` by 30 min stops it.
- [ ] 7.4 Write `features/ops_assistant/machine.feature` covering H4, E13–E16, E37, E38, X11, X12. Run
      `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/ops_assistant/machine.feature` and confirm it
      passes before starting phase 8.

## 8. Machine side: relay profile, API tool, sandbox

- [ ] 8.1 `claude_command.js` profile `ops` (allowed tools, deny list, `PASS_ENV` + `ANTHROPIC_API_KEY`,
      `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1`, per-entity `CLAUDE_CONFIG_DIR`, `--max-turns 60`);
      `server.js`: per-machine secret from SSM, file download into the session workspace, new events
      (`action`, `learning`, `file`, `api_gap`). Verify: `npm test` in `support_console/machine` passes the
      existing Support Console tests.
- [ ] 8.2 `api-mcp/server.js`: `api_get` (GET only, own host, `.json` paths), `api_propose`,
      `propose_learning`, `report_api_gap`; token only in this process's env. Verify:
      `support_console/machine/test/ops_api_mcp.test.js` (E17, E18) passes.
- [ ] 8.3 `bin/ops-ruby` (bubblewrap: `--unshare-net`, empty env, read-only tools and gems, read-write
      workspace only); onboarding tools published with the code archive. Verify:
      `support_console/machine/test/ops_sandbox.test.js` (E19, X14) passes.
- [ ] 8.4 `claude/ops_brief.md` (API only, propose never write, never-list, report gaps, cite screens not
      code, announce then confirm, write a run report) and S3 sync of the entity prefix at turn start/end in
      `user-data.sh`. Verify: a staging dry run of `user-data.sh` on a scratch instance syncs a test prefix.
- [ ] 8.5 Machine-side gate (node, not Cucumber — the machine has no Rails): run
      `cd support_console/machine && npm test` and confirm all Support Console and ops tests pass before
      starting phase 9.

## 9. Infrastructure, docs, staging pilot

- [ ] 9.1 `rake "ops_assistant:infra[staging.in]"` (dry run, then `EXECUTE=1`; STS account assertion): bucket +
      KMS key, subnet, security group (ingress 4900 from app SG; egress ALB SG, S3 prefix list, 443 via
      NAT), Route 53 DNS Firewall allow-list (`api.anthropic.com`), data-subnet NACL deny, IAM roles (machine
      role with principal-tag prefix; app role limited to the template, tag and PassRole), launch template.
      Verify: the dry run prints every resource; `EXECUTE=1` creates them.
- [ ] 9.2 `rake "ops_assistant:check[staging.in]"`: every tenant machine's health, code revision, no
      credentials in the code copy, flow-log/DNS alarms present. Verify: it reports Orion Test's machine.
- [ ] 9.3 Docs: `docs/user_guides/ops_assistant_user_guide.md` (FAQ standard, lint with `UserGuideLint`),
      `docs/modules/ai/ops_assistant/technical_guide.md` with mermaid diagrams. Verify: `UserGuideLint` passes.
- [ ] 9.4 Staging pilot on Orion Test (1548): encrypt keys, switch on, tick Meera and Arjun, run
      [qa-checklist.md](qa-checklist.md) including S1–S8 from [security.md](security.md#security-checks-before-go-live),
      record the sign-off. Verify: QA sign-off row filled with no open blocking defects.
- [ ] 9.5 Final gate: run the whole suite for this change —
      `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/ops_assistant/ features/api/ops_assistant_tokens.feature features/support_console/`
      — and confirm it passes before any production rollout.
