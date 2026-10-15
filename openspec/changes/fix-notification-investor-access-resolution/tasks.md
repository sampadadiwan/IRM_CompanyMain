# Tasks

> **Reproduce first.** Phase 1 writes the Cucumber scenarios from the report's Verification
> table that fail against the CURRENT code, and runs them to watch them fail. A bug fix that
> was never seen failing might be fixing nothing.

> **Phase gate:** each numbered group below is a phase. A phase's last task is always to run its
> Cucumber feature and get it green. Do not start the next phase until that happens.

> **Every cucumber run needs a fresh `TEST_ENV_NUMBER`** (unset, runs share one sqlite DB and
> corrupt each other) and **local Redis up on 6379**.

## 1. Reproduce

- [x] 1.1 Write `features/core/notification_investor_access_resolution.feature` with step defs in
      `features/step_definitions/notification_investor_access_resolution_steps.rb`. Build the
      notifications directly and assert on `email_enabled` / `whatsapp_enabled`, reusing the
      pattern in `investor_kyc_notification_delivery_steps.rb` (report: Verification). Cover
      H1–H3, E1–E5 and X1–X3. Each scenario gets an `# ID — Edge case: …` comment. The shared
      Background creates access **a** before **b** so a has the lower id. Verify: the file
      parses with `bundle exec cucumber --dry-run features/core/notification_investor_access_resolution.feature`.
- [x] 1.2 Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/notification_investor_access_resolution.feature`
      and confirm **H1, H3, E1, E3, X1, X3 fail** and H2, E5 pass. Record the failure output in this task.
      **Result (pre-fix):** 11 scenarios: 9 failed, 2 passed (H2, E5). Failures are assertions,
      not errors: H1, E1, E2, E4, X2 expected truthy got false; H3, X1 expected falsey got true;
      E3 and X3 failed on the WhatsApp delivery and missing log line. Setup needed the contact to
      hold the `investor_advisor` role (InvestorAccess#ensure_entity_id), as user 2564 does in prod.

## 2. Fix

- [x] 2.1 Add `NotificationExtensions#notification_investor`: `params[:investor_id]` (found,
      not deleted) → `model.investor` → owner's `investor`, or the owner itself when it is an
      `Investor` → `nil`. Comment each step with its V-table ID (report: Fix, row 1). Verify:
      H1, E1, E4, X2 resolve the expected investor in the feature.
- [x] 2.2 Rewrite `#investor_access` to return that folio's access for the recipient, or `nil`
      when there is no folio. Add `#recipient_entity_accesses` for the no-folio case. Remove the
      `.first` fallback (report: Fix, row 2). Verify: X1 returns no access instead of a's.
- [x] 2.3 Update `#email_enabled` and `#whatsapp_enabled` so a known folio uses that access, and
      no folio means "any of the recipient's accesses in this fund enabled" via `exists?`, never
      `present?` (report: Fix, rows 3–4). Verify: E2, E3, H3.
- [x] 2.4 Make `DeliveryMethods::WhatsApp#deliver` use `notification.folio_channel_enabled?(:whatsapp_enabled)` in place of
      its own `investor_accesses.where(email:).first` lookup, keeping the recipient and entity
      permission checks (report: Fix, row 5). Verify: E3 and the existing WhatsApp scenarios.
- [x] 2.5 Log one `Rails.logger.info` line when `email_enabled` returns false for an LP recipient.
      It names the notification id, resolved investor id and access id (report: Fix, row 6). Verify: X3.
- [x] 2.6 Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/notification_investor_access_resolution.feature`
      and confirm H1–H3, E1–E5, X1–X3 all pass before starting phase 3.
      **Result:** 11 scenarios (11 passed), 108 steps (108 passed).

## 3. Regression and cleanup

- [x] 3.1 Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/investor_kyc_notification_delivery.feature features/core/notification_investor_access_resolution.feature`
      and confirm both are green (Blast Radius: `email_enabled`, advisor `show?` path).
- [x] 3.2 Run the Blast Radius callers' features and confirm they are green:
      `features/step_definitions/email_bounce_tracking_steps.rb`'s feature, the capital call and
      capital distribution notification features, and the document send / data room cc features
      (`grep -rl "DocumentNotifier\|send_document\|WhatsApp" features/` to list them).
- [x] 3.3 Run `bundle exec rubocop config/initializers/noticed.rb app/packs/core/notifications/delivery_methods/whats_app.rb features/step_definitions/notification_investor_access_resolution_steps.rb`
      and confirm it is clean, including `IRM/RelationBlankPresent`.
- [x] 3.4 Re-run the report's probe against the prod dump (port 33066, read-only): user 2564 +
      Document 113791 now resolve to access 4097 with `email_enabled` true; user 1865 + a
      Folio 5683 document resolves to access 3711 with `email_enabled` false.
