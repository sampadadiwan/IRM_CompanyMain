# Tasks

> **Phase gate:** each numbered group below is a phase. A phase's last task is always to run its
> Cucumber feature and get it green. Do not start the next phase until that happens — if it fails,
> fix the phase you're on rather than moving forward and coming back later.
>
> Every Cucumber run uses a fresh `TEST_ENV_NUMBER=$RANDOM` and needs Redis up on 6379. Never run
> `db:migrate` under `RAILS_ENV=test` (see LLD › Schema Detail). Section names below refer to
> [lld.md](lld.md); worked-example IDs refer to [design.md › Worked examples](design.md#worked-examples).
>
> **Pull requests:** delivery is two code PRs, a docs PR and a follow-up (phase 8). Each code PR changes at most 15 **application files**
> (not counting `openspec/` or `features/`); the `.feature` files and step definitions ship in the PR of the code they
> test — see [design.md › Delivery](design.md#delivery-pull-requests) for the files in each. Phases 2–4 → **PR 1**,
> phases 5–6 → **PR 2**, phase 7 → **PR 3** (`openspec/` only), phase 8 → **PR 4**. Before opening a PR, run
> `git diff --name-only origin/main...HEAD -- . ':(exclude)openspec' ':(exclude)features' | wc -l` (must be 15 or less)
> and rubocop on its Ruby files; put the verified worked-example IDs and the run result in its description. Keep the
> entity flag off in every environment until PR 2 is merged and QA has signed off.

## 1. Sandbox spike (no repo code)

Resolves the sandbox-only unknowns in [design.md › Risks](design.md#risks-and-open-questions) before the page is built.
Uses a throwaway page outside the repo (scratchpad directory), not application code.

- [x] 1.1 Send a test document for eSignature in dev/staging (Digio sandbox, `ext.digio.in`) to a mailbox you control, then
      build a throwaway HTML page that loads `https://ext.digio.in/sdk/v11/digio.js` with `is_iframe: true`, an
      `event_listener` and a `callback` that log everything, and calls `init()` from a button then
      `submit(<provider_doc_id>, <signer email>)`. Verify: the panel opens and the console logs events.
- [x] 1.2 Record, in design.md › Risks (one line each, with the outcome): (a) overlay or in-container rendering; (b) whether
      `submit(docId, email)` makes Digio send its own one-time code, and to which channel; (c) Aadhaar, electronic and DSC
      inside the iframe; (d) phone-width viewport; (e) the exact `event` names and fields on completion and on closing the
      panel; (f) whether `digio.js` loads under staging response headers. Verify: every item has a recorded outcome.
      **Recorded in design.md › Risks.** (f) checked on 2026-10-30. (c) Aadhaar stays open: no credits on staging, so it is
      carried as a QA item (E40) and must pass before the switch is turned on for an entity that signs with Aadhaar.
- [x] 1.3 Decision gate: if 1.2(b) shows Digio performs **no** signer verification in this mode, stop and take the
      findings back to review (the identity guarantee in design decision 2 changes); otherwise note "gate passed" in
      design.md. Verify: the gate outcome is written in design.md before phase 2 starts.

## 2. Eligibility and banner (boxes ①②⑧)

- [x] 2.1 Append `enable_embedded_esign` as the **last** entry of the `permissions` flag list in
      `app/packs/core/entities/models/concerns/entity_enabled.rb` (LLD › Configuration and Rollout). Verify:
      `RAILS_ENV=test bin/rails runner 'p Entity.permissions.pairs'` shows the new flag last and every earlier flag's value
      unchanged, and the admin entity page shows "Enable Embedded Esign".
- [x] 2.2 Add `ESignature#signable_by?` and `#signing_state` (LLD › Method Contracts › `ESignature`). Verify: with
      `bin/rails runner` on factory data, the shared setup returns `:ready`, `:waiting_turn`, `:signed`, `:closed` as in
      design card ②.
- [x] 2.3 Add the `rejected` → `danger` badge and make `rejected` sticky in `ESignature#new_status?` except against
      `signed` (LLD › Method Contracts › `ESignature`; design card ⑧). Verify: via runner, a `signed` signer ignores
      `failed`/`rejected`, a `rejected` signer ignores `requested` but accepts `signed`.
- [x] 2.4 Add `ESignaturePolicy#sign?` and `#sign_result?` (LLD › Method Contracts › `ESignaturePolicy`; Security Review).
      Verify: runner checks for each condition — switch off, provider not Digio, no `provider_doc_id`, email mismatch,
      impersonation (`support_user_id` present) — each returns false; the matching case returns true.
- [x] 2.5 Add the two member routes (`get :sign`, `post :sign_result`) under `resources :e_signatures` in
      `config/routes/core.rb` (LLD › File Map ③; both land in PR 1 so PR 2 stays within the file budget). Verify:
      `bin/rails routes | grep -i sign_result` and `sign_e_signature`.
- [x] 2.6 Add `documents/_embedded_sign_banner.html.erb` (ready and waiting-turn variants) and render it in
      `documents/show.html.erb`; the link uses `data-turbo="false"` (design card ①). Verify: load a document as the signer
      in dev for each state and see the right text, with no button when waiting.
- [x] 2.7 Add **Sign now** on the viewer's own row in `e_signatures/_e_signature.html.erb`, preloading
      `document → entity → entity_setting` on the Signatures tab (LLD › Queries and Indexes). Done by ordering the checks
      in `ESignaturePolicy#sign?` instead: the cheap email match runs first, so only the viewer's own row loads the
      entity and settings and no preload (and no extra file) is needed. Verify: the tab shows the button on that row
      only (E7).
- [x] 2.8 Write `features/documents/embedded_esign_eligibility.feature` and the supporting steps in
      `features/step_definitions/embedded_esign_steps.rb`, covering H1 and E1–E10, E16 (spec scenarios: eligibility, signing
      order, rollout switch). Run it with
      `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/documents/embedded_esign_eligibility.feature` and confirm it
      passes before starting phase 3. Commit the feature file with this phase's code in PR 1.

## 3. Signing page (box ③)

- [x] 3.1 Add `DigioSdkConfig` (`.base_url`, `.script_url`, `.environment`) in
      `app/packs/core/documents/services/digio_sdk_config.rb` (LLD › Method Contracts › `DigioSdkConfig`). Verify: via
      runner with `DIGIO_BASE_URL=https://ext.digio.in:444` → sandbox + `https://ext.digio.in/sdk/v11/digio.js`; with
      `https://api.digio.in` → production + `https://app.digio.in/...`; with `DIGIO_SDK_BASE_URL` set → the override.
- [x] 3.2 Add `DigioSdkErrors` with the full code table, both "not ready" spellings, `completed?` and the two client
      pseudo-events (LLD › Method Contracts › `DigioSdkErrors`; design card ⑤ table). Verify: a runner loop over every code
      in `public/digio docs/error codes.txt` (plus the correctly-spelled variant) returns a group, only the five
      "ours" codes alert, an unknown code returns `:ours`, and both spellings return the same message.
- [x] 3.3 Add `ESignaturesController#set_signing_e_signature` and `#sign` with the unified refusal (redirect to root
      with the alert) and state-driven rendering (LLD › Controllers, Params and Responses). Verify: GET the page in dev as a
      matching signer, an out-of-turn signer, a signed signer, a non-signer and a closed document — texts match the
      proposal's Behavior Rules.
- [x] 3.4 Add `e_signatures/sign.html.erb` with the state partials and data attributes (`provider-doc-id`,
      `signer-email`, `sdk-url`, `environment`, `result-url`, `fallback-message`, `panel-unavailable-message`),
      rendered inside the normal layout. Verify: view source shows no token and only those identifiers.
- [x] 3.5 Add `app/javascript/controllers/digio_esign_controller.js`: inject the SDK on `connect`, call `init()` and
      `submit(providerDocId, email)` from the **Start signing** click handler, show the panel-unavailable message and
      **Try again** when the script fails or `window.Digio` is missing, `cancel()` on `disconnect` (design card ③ build
      notes). Result posting is added in phase 5. Verify: in dev against the sandbox, **Start signing** opens the panel
      inside the page and navigating away leaves no orphan overlay. (Covered against a stub `digio.js` by H3/E13/E14/E19;
      the real sandbox run belongs to the phase 1 spike, 1.1–1.3, still open.)
- [x] 3.6 Update `docs/user_guides/esigning_user_guide.md` with a short, business-level section: where **Sign now**
      appears, that the email link still works, the signing order, and the ask-the-sender cases. Verify: the guide
      renders and mentions the **Enable Embedded Esign** requirement.
- [x] 3.7 Write `features/documents/embedded_esign_page.feature` (`@javascript`, Playwright route serving a stub
      `digio.js`), covering H2, H3, E11–E15, E19 (spec scenarios: signing page, no shortcut token, environment). Run it with
      `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/documents/embedded_esign_page.feature` and confirm it passes
      before starting phase 4. Commit the feature file with this phase's code in PR 1.

## 4. Webhook events (box ⑦)

- [x] 4.1 Route `DigioEsignHelper#update_signature_progress` on the payload `event` (`doc.signed`, `doc.sign.failed`,
      `doc.sign.rejected`) with the legacy `error_code.blank?` rule as the fallback for blank or unknown events (LLD ›
      Method Contracts › `DigioEsignHelper`; design card ⑦). Verify: runner with five payload shapes — signed, failed,
      rejected, no event, unknown event — each takes the expected branch.
- [x] 4.2 Add `process_esign_rejected` (signer by `signer_identifier` lower-cased, `update_esign_response("rejected")`,
      `webhook_data` append, `ErrorReport.notify` always) in
      `app/packs/core/investor_kycs/models/concerns/digio_esign_helper.rb` (LLD › Method Contracts). Verify: runner — a
      rejection for a known signer sets `rejected` and reports; for an unknown email it only reports.
- [x] 4.3 Guard `process_esign_success` against nil/empty `signing_parties` (report and skip) (LLD › Error Mapping).
      Verify: a rejected-shaped payload without an `event` no longer raises.
- [x] 4.4 Add Digio payload builders (`digio_callback_failed`, `digio_callback_rejected`,
      `digio_callback_rejected_no_parties`, `digio_callback_unknown_event`, `digio_callback_no_event`) to
      `features/step_definitions/embedded_esign_steps.rb`, posted through an in-process integration session (the existing
      `hit_signature_progress` needs a running browser server, and an in-process post also lets the scenario assert the
      200 response). Verify: each builder's JSON matches the shapes in `public/digio docs/webhook.txt`.
- [x] 4.5 Run the existing regression that exercises Digio callbacks:
      `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/doc_gen.feature` and confirm no new failures.
      **Run with Elasticsearch up:** 26 scenarios, 25 passed, 1 failed (`doc_gen.feature:529`, "Bulk Generate Investor
      Statement for all but first commitments", an investor-statement scenario that does not touch e-signing). Re-run on
      its own it passes (1/1), so the failure did not reproduce; treat as a flake of the long full run.
- [x] 4.6 Write `features/documents/esign_webhook_events.feature` covering H6–H8 and E21–E28 (spec scenarios: all of
      `esign-webhook-events`). Run it with
      `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/documents/esign_webhook_events.feature` and confirm it
      passes before starting phase 5. Commit the feature file with this phase's code in PR 1.

> **PR 1** — open it once this phase's feature is green: phases 2–4, 15 application files plus the three feature files and
> `embedded_esign_steps.rb` (design.md › Delivery).

## 5. Result handler and audit trail (boxes ⑤⑥)

- [x] 5.1 Add migration `db/migrate/20261012100000_add_sdk_events_to_esign_logs.rb` (nullable `json`
      `sdk_events`), update `db/schema.rb`, then `ruby bin/sync_schema_test.rb` and
      `RAILS_ENV=test bin/rails db:test:load_schema` (LLD › Schema Detail). Verify: the column is in both `schema.rb` and
      `schema_test.rb`, and `RAILS_ENV=test bin/rails runner 'p EsignLog.column_names'` lists `sdk_events`.
- [x] 5.2 Add `EsignLog#append_event(column, payload)` with `with_lock` and a column whitelist (LLD › Method Contracts ›
      `EsignLog`; Transactions). Verify: runner — two appends keep both entries; a non-whitelisted column raises
      `ArgumentError`.
- [x] 5.3 Add `ESignaturesController#sign_result`: permitted params truncated to 100 chars, `sign_result?`, code
      mapping, `sdk_events` append (log created if absent), `DocumentEsignUpdateJob.perform_later` only when the
      result asks for a check, `ErrorReport.notify` only for the "ours" group, JSON `{message, action}`, 403 JSON on refusal,
      and **no write to any status column** (LLD › Controllers, Params and Responses; Error Mapping). Verify: POST each
      group's sample code in dev and see the JSON, the log entry, and the enqueue/alert exactly as in the LLD.
- [x] 5.4 Extend `digio_esign_controller.js` to post `{event, error_code, txn_id}` to `result-url` (via
      `@rails/request.js`, CSRF included), render the returned message and action (**Try again**, none, done), use
      `fallback-message` if the POST fails, and report `client.cancelled` / `client.panel_unavailable`. Verify: in dev
      against the sandbox, completing shows the thank-you message and an `sdk_events` entry exists.
- [x] 5.5 Write `features/documents/embedded_esign_result.feature` covering H4, H5, E17, E18, E20, X1–X11 (spec
      scenarios: confirmation with Digio, error messages, audit trail), using a Scenario Outline for the code groups. Run
      it with `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/documents/embedded_esign_result.feature` and confirm
      it passes before starting phase 6. Commit the feature file with this phase's code in PR 2.
      **Note:** the code-group Scenario Outline posts to `sign_result` through an in-process session (fast, every
      code); H4, E18, E20, X1 and X8 drive the real page with the stubbed SDK. The page offers "Start signing" again
      after a close (the spec wording), and "Try again" for an error the signer can fix.

## 6. Signer notifications (box ⑨)

- [x] 6.1 Add migration `db/migrate/20261012110000_add_signing_notified_at_to_e_signatures.rb` (nullable `datetime`
      `signing_notified_at`), update `db/schema.rb`, then `ruby bin/sync_schema_test.rb` and
      `RAILS_ENV=test bin/rails db:test:load_schema` (LLD › Schema Detail). Verify: the column is in both
      `schema.rb` and `schema_test.rb`, and `RAILS_ENV=test bin/rails runner 'p ESignature.column_names'` lists it.
      Never run `db:migrate` under `RAILS_ENV=test`.
- [x] 6.2 Add `ESignature#claim_signing_notification!` and make `ResendDocumentForEsign#reset_doc_esignature` clear
      `signing_notified_at` with the statuses (LLD › Method Contracts › `ESignature`, `ResendDocumentForEsign`). Verify:
      via runner, the first claim returns true and the second false; after the reset the claim returns true again.
- [x] 6.3 Add `EsignSigningNotifier` (`message`, `url`, `mailer_name`, `email_method`, `email_data`) and
      `EsignSigningMailer#signature_requested` with its view, using the exact wording in the proposal's Behavior Rules
      (LLD › File Map ⑨, Method Contracts). Verify: via runner, the mail's subject and body match the proposal, the
      button points to `sign_e_signature_url`, and `EsignSigningNotifier.new.respond_to?(:custom_notification)` is false.
- [x] 6.4 Add `Document#notify_ready_signers` (LLD › Method Contracts › `Document`). Verify: via runner on the shared
      setup, an ordered document with Priya ready notifies only Priya, a second call notifies nobody, and an unordered
      document notifies every pending platform-user signer.
- [x] 6.5 Call `notify_ready_signers` from `DigioEsignHelper#update_document` (success branch),
      `process_esign_success` (after its signer loop) and `update_esign_status` (after its loop), each inside
      `rescue StandardError` → `ErrorReport.notify` (LLD › Error Mapping). Verify: with the notifier forced to raise,
      the send, the status updates and the webhook's `200 Ok` are unaffected and `ErrorReport` is called.
- [x] 6.6 Confirm the notification paragraph already added to `docs/user_guides/esigning_user_guide.md` with task 3.6
      (PR 1 carries the whole guide update so PR 2 stays within the file budget) still matches what shipped: when
      it is sent, who gets the email, that the Digio link still works. Verify: the guide mentions it and the
      **Enable Embedded Esign** requirement.
- [x] 6.7 Write `features/documents/embedded_esign_notifications.feature` covering H9, H10, E29–E35 and X12 (spec
      scenarios: *Signers are notified when it is their turn*), reusing the shared setup and Digio status stubs. Run it
      with `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/documents/embedded_esign_notifications.feature` and
      confirm it passes before starting phase 7. Commit the feature file with this phase's code in PR 2.
      **Note:** `BaseNotifier` applies the `email_enabled` gate only outside the test environment, so E34 asserts
      `Noticed::Notification#email_enabled` (the production predicate) for the investor rather than a missing email;
      H9 asserts it is open for an investor whose access has email on.

> **PR 2** — open it once this phase's feature is green: phases 5–6, 14 application files plus two feature files and the
> extended step file.

## 7. Hardening and sign-off

- [x] 7.1 Run `bundle exec rubocop` on every Ruby file created or modified (including `IRM/RelationBlankPresent`) and fix
      offences. Verify: zero offences.
- [x] 7.2 Run `bundle exec brakeman` (controllers and params changed). Verify: no new warnings against the baseline.
- [x] 7.3 Update design.md › Risks with the outcomes recorded in phase 1 and the production response-header check (LLD ›
      Configuration and Rollout). Verify: no sandbox-only unknown is left unrecorded.
- [x] 7.4 Run all five new features and the regression together on the merged `main`, each with a fresh `TEST_ENV_NUMBER=$RANDOM`:
      `features/documents/embedded_esign_eligibility.feature`, `embedded_esign_page.feature`,
      `embedded_esign_result.feature`, `esign_webhook_events.feature`, `embedded_esign_notifications.feature`, and `features/core/doc_gen.feature`. Confirm all
      are green before QA. **Run 2026-10-30, rebased on `main` at f903c2febe, with the Zoho suites and `esign_audit_trail`: 215 scenarios, 215 passed.**
- [ ] 7.5 Open the final PR (PR 3, docs only): add `openspec/changes/embedded-esign-digio/` (including the Risks updates
      from task 7.3). Verify: the diff contains only paths under `openspec/`.
- [ ] 7.6 QA: run [qa-checklist.md](qa-checklist.md) on a deployed staging build and record the sign-off (this task is
      for QA, not for the apply agent).

## 8. Audit trail and log clean-up (PR 4)

- [x] 8.1 Add `DigioEsignHelper#download_audit_trail` and `#attach_audit_trail`, and `DigioAuditTrailJob` (six attempts,
      support alerted at the end), enqueued only by the call that completed the document. Verify: sandbox returns a PDF for a
      completed document and 403 otherwise (design.md › Risks); H11, E36, E37, X13.
- [x] 8.2 `DigioEsignHelper#signature_completed` leaves the document as it was when the signed copy cannot be downloaded.
      Verify: X14.
- [x] 8.3 Give the signed copy and supplementary documents the source folder when the document has no owner. Verify: E38
      fails without it (`undefined method 'owner' for nil`).
- [x] 8.4 Stop writing `api_updates` for Digio; `ESignature#update_esign_response` takes the payload as optional for Zoho and
      Docusign. Verify: E39.
- [x] 8.5 Correct `DIGIO_CLIENT_URL` in `.env.staging.in` and `.env.staging.us` to `https://ext.digio.in`.
- [x] 8.6 Write `features/documents/esign_audit_trail.feature` and run it with the regression (task 7.4).
