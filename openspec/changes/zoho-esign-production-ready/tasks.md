# Tasks

> **Phase gate:** each numbered group below is a phase. A phase's last task is always to run its
> Cucumber feature and get it green. Do not start the next phase until that happens — if it fails,
> fix the phase you're on rather than moving forward and coming back later.

> **Phases vs pull requests.** Phases are the build order; every phase writes and runs its own
> feature scenarios locally. The three PRs ([design](design.md#delivery-three-pull-requests),
> [lld File Map](lld.md#file-map)) only decide which files ship where: PR 1 = code from phases 2–4,
> PR 2 = code from phases 5–6, PR 3 = all feature/step/support/factory files, docs, env cleanup and
> these OpenSpec files (phase 7 packages them). Commit each phase separately so the PR branches can be
> cut cleanly. Keep every existing step-definition text working until PR 3 (PR 1 and PR 2 run the
> original 8 Zoho scenarios in CI).

> **Traceability.** Every scenario has a comment line `# <ID> — <path in plain words>` directly above
> it; feature headers link to `openspec/changes/zoho-esign-production-ready/design.md#worked-examples`.
> Code comments name the IDs whose path runs through each guard, refusal, fallback or branch.

## 1. Setup and baseline

- [x] 1.1 Create a git worktree for branch `zoho-esign-production-ready` off `zohosign-2` (or off
      `main` if the POC PRs have merged) — the main checkout has the user's uncommitted work and must
      not be switched. Verify: `git -C <worktree> log -1` shows the zohosign-2 tip (or main).
      _Done in place: the user moved the checkout back to `zohosign-2` (only untracked files), so the
      branch was created there with `git switch -c`; tip d11b1ea0ee._
- [x] 1.2 If the POC branches are still unmerged, ask the user whether to add `if_not_exists: true` to
      the four POC `add_column` migrations on those branches ([design risks](design.md#risks-and-open-questions));
      do nothing if they have merged. Verify: user's answer recorded in the PR description draft.
      _User chose to add the guards (committed on this branch, ships with PR 1)._
- [x] 1.3 Run the existing Zoho scenarios as the baseline:
      `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/zoho_esign.feature features/core/zoho_esign_webhook.feature`
      (Redis up on 6379) and confirm 8 scenarios pass before starting phase 2.

## 2. Zoho caller, platform account and send/poll hardening (PR 1)

- [x] 2.1 Add `ZohoSignClient` with the region table, timeouts, token cache keyed by
      `token_cache_key`, 401-refresh-once, and the `AuthError` / `RateLimited` / `TransientError` /
      `RequestError` classes ([lld Method Contracts](lld.md#method-contracts),
      [External Integrations](lld.md#external-integrations)); no `debug_output`. Verify:
      `bin/rails runner 'p ZohoSignClient::REGIONS.keys'` prints the ten keys.
- [x] 2.2 Add `ZohoSignAccount` (`Data.define`) with `.platform` (credentials + `ENV["ZOHO_REGION"]`,
      default `in`) and `.for_document` / `.for_entity` returning the platform account for now
      ([lld Method Contracts](lld.md#method-contracts)). Verify: `bin/rails runner 'p ZohoSignAccount.platform.region'` prints `"in"`.
- [x] 2.3 Rewrite `ZohoEsignHelper` HTTP calls to go through `ZohoSignClient` on
      `ZohoSignAccount.for_document`, remove `include HTTParty`, the class-level credential constants
      and the Redis refresh-token override; replace `ExceptionNotifier` with `ErrorReport.notify`
      ([lld Error Mapping](lld.md#error-mapping-and-logging)). Verify: `grep -n -E 'HTTParty|ExceptionNotifier|REFRESH_TOKEN_REDIS_KEY' zoho_esign_helper.rb` returns nothing.
- [x] 2.4 Add the status mapping table (request and action statuses) to `ZohoEsignHelper`; unknown values
      are written to `EsignLog` and change nothing; `signatures_failed` only on `RequestError`
      ([design ⑤](design.md#-esign-engine)). Code comments name X23, E30, H9.
- [x] 2.5 Harden sending in `ZohoEsigning`: `validate_signer_count` (25), rescue
      `ZohoSignClient::Error` and `PDF::Reader::MalformedPDFError` into the Failed path, best-effort
      `delete_request` when create succeeded and submit failed ([design ⑤ Send](design.md#-esign-engine)).
      Code comments name X12, E17, X13, X14, X15.
- [x] 2.6 Add `retry_on` / `discard_on` for Zoho errors to `EsignUpdateJob`
      ([lld Background Jobs](lld.md#background-jobs)). Code comments name X9, X10.
- [x] 2.7 Add `@zoho-http` to `features/support/webmock_toggle.rb` (`@sync-http or @zoho-http`), create
      `features/support/zoho_sign_stub.rb` (token, create, submit, get, pdf, certificate, recall,
      remind, extend, delete per region; request-body capture), and move the existing
      `zoho_esign_steps.rb` stubs from `allow_any_instance_of` to WebMock while keeping every existing
      step text ([lld Test Plumbing](lld.md#test-plumbing)). Verify: the phase-1 baseline command
      still shows 8 passing scenarios.
- [x] 2.8 Extend `features/core/zoho_esign.feature` with H6, H7, H9, E13, E17, E18, E19, E20, E25, E30,
      X9, X10, X12, X13, X14, X15, X23 (each with its ID comment). Run
      `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/zoho_esign.feature` and confirm it
      passes before starting phase 3.

## 3. Shared webhook gate, events and completion (PR 1)

- [x] 3.1 Change `ZohoEsignHelper.verify_signature(raw_body, signature, secret)`: missing signature =
      false; blank secret = true only when `Rails.env.local?`
      ([design ⑥](design.md#-webhook-gate)). Code comments name X19, X22, E34.
- [x] 3.2 In `DocumentsController#signature_progress`, detect Zoho payloads (header, or
      `notifications.operation_type` + `requests.request_id`), verify with the platform secret, enqueue
      `ZohoWebhookJob.perform_later(nil, request.raw_post)` and answer 200; leave the Digio/Docusign
      path unchanged; drop the Zoho branch from `EsignHelper.update_signature_progress`
      ([lld Controllers](lld.md#controllers-params-and-responses)). Verify: posting an unsigned Zoho
      payload in a staging-like env returns 401 (X22 scenario below).
- [x] 3.3 Add `ZohoWebhookJob` (platform scope: document found by `provider_doc_id` and
      `ZohoSignAccount.for_document(doc).platform?`, else log and stop) with the retries from
      [lld Background Jobs](lld.md#background-jobs). Code comments name E33, E32.
- [x] 3.4 Rework `ZohoEsignHelper#update_signature_progress(doc, payload)` per the event table: submitted
      updates blank (`""` or NULL) signers, rejected fails signer and document, viewed/other logged,
      recalled/expired/completed as designed; certificate failure logged with `ErrorReport`
      ([design ⑤ Webhook events](design.md#-esign-engine)). Code comments name H15, X24, E31, E35, X26, H10, E28.
- [x] 3.5 Extend `features/core/zoho_esign_webhook.feature` with H10, H15, E27, E28, E31, E33, E34,
      E35, X19, X22, X24, X26 (shared address, platform-account documents; HMAC helper
      `zoho_signed_post`). Run
      `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/zoho_esign_webhook.feature` and
      confirm it passes before starting phase 4.

## 4. Capabilities, validations, extend / remind / cancel (PR 1)

- [x] 4.1 Add `EntitySetting::ESIGN_CAPABILITIES` and `#esign_supports?`; replace the `"Zoho"` literals
      in `DocumentPolicy#extend_esign_expiry?` / `#send_esign_reminder?`, `documents/_form` and
      `documents/show` ([design ⑦](design.md#-screens-and-alerts)). Verify:
      `git grep -n '"Zoho"' app/packs/core/documents` returns nothing. Code comments name E2, E26.
- [x] 4.2 Add `Document` validations: `esign_expiration_days` 1..99, `esign_reminder_period` 1..30, both
      allow nil. Code comments name E14, E15, E16.
- [x] 4.3 Move extend-date validation into `ZohoEsignHelper#extend_expiry` (real date, tomorrow or later,
      no upper limit; remove the POC's `clamp` to `MAX_EXPIRATION_DAYS`; refusal message with `l(date)`),
      return `ZohoResult`; drop the `max:` on the `e_signatures/_index` date picker; `DocumentsController#extend_esign_expiry`
      shows its message; `EsignHelper#extend_expiry` passes it through
      ([lld Method Contracts](lld.md#method-contracts)). Code comments name E21–E24, X16, X17, H11.
- [x] 4.4 Switch screen dates in `documents/show` and the `e_signatures/_index` extend modal to `l(date)`
      and add the "Allowed:" window line ([lld Project Rules](lld.md#project-rules-checklist)). Verify:
      `git grep -n 'strftime' app/packs/core/documents/views` shows no Zoho date.
- [x] 4.5 Extend `features/core/zoho_esign.feature` with H11, H12, H13, E2, E14, E15, E16, E21, E22,
      E23, E24, E26, X16, X17, X25. Run
      `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/zoho_esign.feature features/core/zoho_esign_webhook.feature`
      and confirm both pass, then commit and tag the commit `pr-1-cut` before starting phase 5.

## 5. Company connections: model, setup, panel, notifier (PR 2)

- [x] 5.1 Write the migration `db/migrate/20261029120000_create_zoho_sign_connections.rb` (table,
      unique indexes, `e_signatures.provider_signer_id`, online index on `documents.provider_doc_id`)
      per [lld Schema Detail](lld.md#schema-detail); `bin/rails db:migrate`; then
      `ruby bin/sync_schema_test.rb` and `RAILS_ENV=test bin/rails db:test:load_schema` (never
      `db:migrate` in test). Verify: `db/schema.rb` and `db/schema_test.rb` both show the table.
- [x] 5.2 Add `ZohoSignConnection` (`encrypts`, `audited except:` secrets, `has_secure_token
      :webhook_token`, `mark_needs_reauth!`, `mark_connected!`, `documents_out_for_signature`,
      reveal/regenerate secret) ([lld Method Contracts](lld.md#method-contracts)). Code comments name
      X8, X6, H3, E7.
- [x] 5.3 Add `ZohoSignConnectionSetup` (connect / reconnect / verify / disconnect with the message
      mapping) and `ZohoSignClient.exchange_grant_code`
      ([lld Error Mapping](lld.md#error-mapping-and-logging)). Code comments name H2, X3, X4, X5, H4,
      X7, H16, X6, E5, E6.
- [x] 5.4 Add `ZohoSignConnectionPolicy` (delegates to `EntityPolicy#update?`),
      `ZohoSignConnectionsController` and the nested singular routes in `config/routes/core.rb`
      ([lld Controllers](lld.md#controllers-params-and-responses)). Verify: `bin/rails routes -g zoho_sign_connection` lists the six actions. Code comments name X1, X2, E4.
- [x] 5.5 Add `zoho_sign_connections/_panel.html.erb` (connect/reconnect form, connected state, secret
      show-once, verify/regenerate/disconnect with confirmations; dates via `l(...)`) and render it in
      `entities/show.html.erb` when `esign_supports?(:connection)` and the policy allows
      ([design ⑦](design.md#-screens-and-alerts)). Code comments name H1, E1.
- [x] 5.6 Add `ZohoSignConnectionNotifier` (`BaseNotifier`), `EntityMailer#zoho_sign_needs_reconnect`
      and its template (dates via `EmailDateLocalization`); recipients
      `entity.employees.active.company_admins` ([design Notifications](design.md#notifications)).
- [x] 5.7 Add `grant_code` to `config/initializers/filter_parameter_logging.rb`. Code comment names E8.
- [x] 5.8 Add `spec/factories/zoho_sign_connections.rb`; write `features/core/zoho_sign_connections.feature`
      and `features/step_definitions/zoho_sign_connection_steps.rb` with H1, H2, H3, H4, H14, H16, E1,
      E3, E4, E5, E6, E8, X1, X2, X3, X4, X5, X6, X7. Run
      `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/zoho_sign_connections.feature` and
      confirm it passes before starting phase 6.

## 6. Cutover, company webhook address, signer ids (PR 2)

- [x] 6.1 Implement the cutover in `ZohoSignAccount.for_document` / `.for_entity` and
      `ZohoSignConnection#account` ([design ②③](design.md#-platform-account-and--account-chooser)).
      Code comments name E9, E10, E11, H5, E12.
- [x] 6.2 Make `ZohoSignClient` call `mark_needs_reauth!` on `AuthError` for company accounts, and add
      the `check_account` step to `ZohoEsigning` ([design ④](design.md#-zoho-caller)). Code comments
      name X8, X11.
- [x] 6.3 Store `provider_signer_id` from the create response; match webhook and poll events by
      `action_id` with email fallback; handle `RequestForwarded` ([design ⑤](design.md#-esign-engine)).
      Code comments name E29.
- [x] 6.4 Add `ZohoSignWebhooksController#create` and its route (unknown token → 404, HMAC with the
      connection secret, `update_column(:last_webhook_at)`, enqueue) and company scoping in
      `ZohoWebhookJob` (entity + cutover) ([design ⑥](design.md#-webhook-gate)). Code comments name
      H8, X18, X20, X21, E32, E7.
- [x] 6.5 Extend `features/core/zoho_esign.feature` with H5, E9, E10, E11, E12, X8, X11 and
      `features/core/zoho_esign_webhook.feature` with H8, E7, E29, E32, X18, X20, X21. Run
      `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/zoho_esign.feature features/core/zoho_esign_webhook.feature features/core/zoho_sign_connections.feature`
      and confirm all pass before starting phase 7.

## 7. Docs, cleanup, coverage and PR packaging (PR 3)

- [x] 7.1 Write `docs/operations/zoho_sign.md`: per-client setup (Option A steps A1–A8 from the
      proposal, scopes, region table), Option B as a future alternative, platform rollout checklist
      ([lld Configuration and Rollout](lld.md#configuration-and-rollout)), dev-assisted QA commands
      (signed/unsigned webhook posts), troubleshooting (needs reconnect, webhook disabled by Zoho
      after 20 failures, rate limits). Verify: every QA row marked dev-assisted has a command in it.
- [x] 7.2 Remove `ZOHO_SIGN_URL` / `ZOHO_ACCOUNTS_URL` from `.env.development` and `.env.staging.in`.
      Verify: `git grep -n 'ZOHO_SIGN_URL\|ZOHO_ACCOUNTS_URL'` returns nothing.
- [x] 7.3 Coverage check: list every H/E/X ID in design.md and every `# <ID> —` comment in
      `features/core/zoho_*.feature`; confirm the sets are equal (77 IDs: H1–H16, E1–E35, X1–X26). Any
      new case found during apply gets a design.md row and a scenario.
- [x] 7.4 Run `bundle exec rubocop` on every changed Ruby file and `bundle exec brakeman`; fix findings.
      Verify: both exit clean.
- [x] 7.5 Cut the PR branches: `pr-1` = code files from tag `pr-1-cut` (lld File Map PR 1 rows, 15
      files); `pr-2` stacked on `pr-1` = PR 2 rows (20 files); `pr-3` stacked on `pr-2` = feature,
      step, support, factory, docs, env and OpenSpec files (19 files). Recount with
      `git diff --name-only <base>..<branch> | wc -l` (each ≤ 20). Verify each branch's CI subset:
      `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/zoho_esign.feature features/core/zoho_esign_webhook.feature`
      on `pr-1` and `pr-2` (original 8 scenarios) and all three Zoho features on `pr-3`, and confirm
      they pass.
      _Done: pr-1 = 19 files (the 14 code files, the 4 POC migration guards from 1.2, and a slim
      `zoho_esign_steps.rb` that stubs ZohoSignClient so the original 8 scenarios run unchanged);
      pr-2 = 20 files; pr-3 = 19 files (full Cucumber suite, runbook, env cleanup, OpenSpec).
      The WebMock-based steps need the new support files and feature changes, so they ship in
      pr-3 rather than pr-1._
- [ ] 7.6 (QA, not the apply agent) Run [qa-checklist.md](qa-checklist.md) on India staging with PR 1–3
      deployed, including the pre-release Zoho checks P1–P3, and record the sign-off.
