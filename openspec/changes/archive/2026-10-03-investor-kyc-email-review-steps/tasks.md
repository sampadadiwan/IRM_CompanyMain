# Tasks

> **Phase gate:** each numbered group below is a phase. A phase's last task is always to run its
> Cucumber feature and get it green. Do not start the next phase until that happens — if it fails,
> fix the phase you're on rather than moving forward and coming back later.
>
> Every cucumber run needs a fresh `TEST_ENV_NUMBER` and Redis up on 6379.
> Reference: [design.md](design.md) (boxes ①–⑦, worked examples H/E/X), [lld.md](lld.md) (file map,
> method contracts). Annotate new code with the H/E/X ids and a link to
> `design.md#worked-examples`, as the existing KYC checks do.

## 1. The three checks (boxes ③④⑤)

- [x] 1.1 Add the helpers to `app/packs/core/investor_kycs/workflow_checks/investor_kyc/support.rb`:
      `kyc_required_notification` (exactly `kyc.entity.custom_notification("notify_kyc_required", for_type: "InvestorKyc")`),
      `preview_button_id` (mirroring `email_button_id`), `kyc_notifications_path` and
      `new_kyc_notification_path` (both built with `RansackQueryBuilder.single`, never `.multiple`).
      Verify: `bin/rails runner` prints the resolved notification and the two paths for one KYC id.
- [x] 1.2 Add `review_not_needed.rb` (box ⑤): `FilledByFund` first → "Filled in by the fund", then
      `link_sent_at` present or `submission_status != "not_sent"` → "The KYC form has already been
      sent", else fail. Verify: the class is loadable and `#call` returns the three outcomes for
      KYCs in those states.
- [x] 1.3 Add `review_email.rb` (box ③) returning `WorkflowChecks::Result.review` with the two
      message/button variants from [the spec](specs/kyc/investor-kyc-journey/spec.md). Verify: the
      message quotes the notification's subject when one exists.
- [x] 1.4 Add `check_preview.rb` (box ④) returning `Result.review` with `action_label`
      "Preview KYC Required Notification", `action_target` from `preview_button_id` and
      `action_path` `investor_kyc_path`. Verify: the target id matches the id
      `investor_kycs/_preview_notifications.html.erb` renders for the same KYC.
- [x] 1.5 Register all three classes in `config/initializers/workflow_checks.rb`. Verify:
      `WorkflowChecks::Registry.registered?("investor_kyc.review_email")` and the other two keys
      return true in `bin/rails runner`.
- [x] 1.6 Run `bundle exec rubocop` on the changed files until clean.
- [x] 1.7 Phase gate (no feature file yet — the seeded template does not carry these tasks until
      phase 2, so a journey-level scenario cannot reach them): verify with
      `bundle exec rails runner` that all three keys are registered and that, for a real KYC, the
      three checks return the documented message, action label, action path and `action_target`.
      The scenarios for these checks (H1, H2, E1, E2, E3, E8, E14) land in 2.6, where the template
      has the tasks.

## 2. Seeding and the backfill (boxes ①②)

- [x] 2.1 In `app/packs/core/workflow_templates/services/journey_setup.rb`, extract
      `create_step(template, row, position)` from `find_or_seed` and `shift_positions_from(template, position, by)`
      from `add_cfo_step`, leaving both existing paths behaving identically. Verify: seeding a new
      entity still produces the same template as before (compare step names, kinds, check keys,
      positions for one entity in `bin/rails runner`).
- [x] 2.2 Add `BACKFILL_STEPS = {}.freeze` to `JourneySetup`, `report[:steps]` to `#plan` (missing
      seeded names, anchored by name **or** `check_key`, `[]` when the template is new or the anchor
      is absent) and `insert_missing_steps` to `#apply`, inside the existing per-entity transaction.
      Verify: a dry run on an entity whose template lacks the two tasks reports them and writes
      nothing.
- [x] 2.3 Add the two rows at the head of `InvestorKycJourneySetup::FULL_STEPS` plus
      `BACKFILL_STEPS = { "Send KYC form" => ["Set up KYC email", "Preview the email"] }`, and update
      the class's step-list comment. Verify: a newly seeded entity has an 11-task template in the
      documented order.
- [x] 2.4 Update `JourneySetup.confirm_message` and `.rollout` output to mention the tasks that would
      be added. Verify: the dry-run line for an existing entity names both tasks, and the "Set up
      journeys" confirmation text includes them.
- [x] 2.5 Run `bundle exec rubocop` on the changed files until clean.
- [x] 2.6 Seeding, backfill, dry run and idempotency (H6, H7, H8, E9, E10, E12, E13) go in
      `features/core/investor_kyc_journey_rollout.feature`, where the rollout steps already live
      (9 → 11 task counts updated there too). Phase 1's check scenarios (H1, H2, H3, E1, E2, E3, E8,
      E14) go in `features/core/investor_kyc_journey.feature`, with the company-KYC-email steps added
      to `features/step_definitions/investor_kyc_journey_steps.rb`; the existing "waits for the form
      to be sent" scenario becomes "waits at the email tasks". Run both:
      `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/investor_kyc_journey.feature`
      and confirm it passes before starting phase 3.

## 3. Withdrawing the confirmations when the email changes (box ⑥)

- [x] 3.1 Add `CONFIGS["InvestorKyc"]` to `app/packs/core/workflow_templates/services/journey_email_edit.rb`
      with `review_keys`, `sent_key` and `email_methods: %w[notify_kyc_required]`, and make `.call`
      skip a config whose `email_methods` does not include the notification's method. Verify: editing
      a `kyc_required_reminder` notification reaches no KYC (log or `bin/rails runner`).
- [x] 3.2 Add the `Entity`-owner branch to `.records_for` (`owner_type == "Entity" && for_type == type`),
      with the per-config scope that narrows KYCs to `link_sent_at: nil`. Verify: for one entity the
      returned relation's SQL contains `entity_id` and `link_sent_at IS NULL` and excludes sent KYCs.
- [x] 3.3 Confirm no change is needed in `CustomNotificationsController` (its `after_action` already
      covers create, update and destroy). Verify: `git diff` shows that file untouched.
- [x] 3.4 Run `bundle exec rubocop` on the changed files until clean.
- [x] 3.5 Extend `features/core/investor_kyc_journey.feature` with E4, E5, E6, E7, X1 and X2 (the undo
      and its boundaries). Run
      `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/investor_kyc_journey.feature`
      and confirm it passes before starting phase 4.

## 4. The panel on the KYC page (box ⑦)

- [x] 4.1 Confirm the panel needs no change: both checks return `Result.review`, so
      `WorkflowEvaluator` already emits `review_action_label/_path/_target` and
      `workflow_instances/_journey_panel.html.erb` already renders the second button. Verify:
      `git diff` shows no change under `app/packs/core/workflow_templates/views/`.
- [x] 4.2 Check the 11-task step bar at narrow widths. Verify: `.cc-rail` is a grid that wraps at
      6 / 4 / 3 / 2 columns with the connector suppressed on each row's first pill, and the capital
      call journey already seeds 11 tasks through it — so 11 KYC tasks need no layout change.
- [x] 4.3 Extend `features/core/investor_kyc_journey_ui.feature` with H3 and H4 (confirming both
      tasks in the panel; the preview button clicking the page's own item). Run
      `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/investor_kyc_journey_ui.feature`
      and confirm it passes before starting phase 5.

## 5. End to end, fund user and LP

- [x] 5.1 Add `features/core/investor_kyc_journey_end_to_end.feature` with the two-actor walk (H5)
      and the LP's view (X3), reusing the LP steps in
      `features/step_definitions/investor_kyc_send_workflow_steps.rb` ("I am logged in as the
      investor user", the signed-link visits) and asserting the current task after every handover.
- [x] 5.2 Add the few new steps it needs (the LP submitting with named documents through their link,
      switching back to the fund user) to
      `features/step_definitions/investor_kyc_journey_steps.rb`. Verify: no step definition is
      duplicated across files (`bundle exec cucumber --dry-run` reports no ambiguity).
- [x] 5.3 Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/investor_kyc_journey_end_to_end.feature`
      and confirm it passes before starting phase 6.

## 6. Documentation and rollout

- [x] 6.1 Update `docs/user_guides/investor_kyc_user_guide.md`: the journey task table (11 tasks,
      what each checks, when it is n/a, what moves it back), the two new tasks in the journey mermaid
      diagram, and FAQs — why the journey starts with the email, what "Email template changed after
      review" means, what happens when no KYC email is set up, why a sent KYC shows the tasks as n/a,
      and whether sending is blocked. Verify: every answer checked against the code.
- [x] 6.2 Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/user_guide_lint.feature`
      until green.
- [x] 6.3 Run the whole KYC journey suite together —
      `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/investor_kyc_journey.feature features/core/investor_kyc_journey_ui.feature features/core/investor_kyc_journey_end_to_end.feature` —
      plus `features/core/custom_notifications.feature` and the capital call journey features as a
      regression check (QA rows C5–C8). Confirm all green.
- [x] 6.4 Run `bundle exec rubocop` over the full diff and `bundle exec brakeman`. Verify: no new
      offence or warning.
- [x] 6.5 Note the rollout in the change: `bin/rails investor_kyc_journeys:rollout` (dry run) then
      `EXECUTE=1`, run separately on IN and US, with the release note that a KYC waiting at "Send KYC
      form" moves to "Set up KYC email" (E11). No migration, no new job, no new permission.
- [ ] 6.6 QA runs `qa-checklist.md` on a deployed build and records the sign-off (for QA, not the
      apply agent).
