# Tasks

> **Phase gate:** each numbered group below is a phase. A phase's last task is always to run its
> Cucumber feature and get it green. Do not start the next phase until that happens — if it fails,
> fix the phase you're on rather than moving forward and coming back later.

> Every Cucumber run uses a fresh `TEST_ENV_NUMBER=$RANDOM` and needs Redis on 6379. "LLD →" names the
> [lld.md](lld.md) section or File Map rows (by box ①–⑨) a task implements.

## 1. Engine foundation: step kinds, registry, schema

- [x] 1.1 Run the existing workflow features as a baseline before any change:
      `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/workflow_*.feature features/core/investor_kyc_send_workflow.feature features/startup/portco_kpi_workflow.feature`.
      Record the result; this is the regression guard for human-only behaviour.
- [x] 1.2 Migration adding `workflow_steps.{kind, check_key, skip_key, owner_user_id, unlocks, keep_on_regress}`,
      `workflow_templates.system_key` + unique `[entity_id, system_key]`, `workflow_instances.{evaluated,
      step_results, current_step_since, completed_at}` + `[evaluated, status]`, and the
      `workflow_state_changes` composite index. Update `db/schema.rb` and `schema_test.rb` by hand.
      Verify: `bin/rails db:migrate` then `db:rollback` both succeed (LLD → Schema Detail).
- [x] 1.3 `WorkflowChecks::Registry`, `Result` (`passed, message, action_label, action_path, passed_since,
      fresh_since`) and `Base` in the engine pack; `config/initializers/workflow_checks.rb`; test-only
      `test.flag` check in `features/support/workflow_test_checks.rb`. Verify:
      `bin/rails runner 'p WorkflowChecks::Registry.keys_for("CapitalCall")'` runs (LLD → File Map ③).
- [x] 1.4 `WorkflowStep`: `kind` enum (prefix `kind`), validations (check required for system/ack; check and
      skip keys registered for the template's workflowable type; owner in the template's entity),
      `evaluated?`. `WorkflowTemplate#journey?`. Verify: in `rails runner`, a system step without a check
      is invalid with "Check must be a Capital Call check" (LLD → File Map ①).
- [x] 1.5 `WorkflowInstanceLaunch`: snapshot the six new step fields, set `instance.evaluated`, no
      evaluation at launch, no activation mail when the first step is not human. Verify: launch a
      test template in `rails runner` and inspect `template_snapshot` and `evaluated` (LLD → File Map ①).
- [x] 1.6 Step editor: permit the new params in `WorkflowStepsController#step_params`; the form shows Kind,
      Check and Skip (lists from the registry for the template's type), Owner, Unlocks and Keep sign-off,
      and hides human-only fields for system/ack. Verify by hand on the edit screen (LLD → Controllers).
- [x] 1.7 Write `features/core/workflow_step_kinds.feature` covering **E1, X1, X2**, then run it and the
      1.1 baseline set: `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/workflow_step_kinds.feature features/core/workflow_*.feature`.
      All green, with the baseline unchanged, before starting phase 2.

## 2. The evaluator

- [x] 2.1 `WorkflowEvaluator` (Trailblazer): guard on `instance.evaluated` and status; `lock!` + reload;
      walk steps (skip → n/a; system via registry with `fresh_since` vs last `invalidated`/`recomputed`;
      acknowledge via active `Reviewed` response newer than invalidation; human via `WorkflowStepResolver`);
      per-step rescue → `status: "error"` and stop; compare with `step_results`; `regressed`/`passed`/
      `skipped`/`reopened` state changes; stamping rules for `passed_at` and `current_step_since`
      (from `passed_since`, clamped, set once); `complete`/`completed_at`; persist only on change; queue
      activation mails for a newly current human step after commit. Verify: `rails runner` walk of a
      test template moves forward and back as the `test.flag` value changes (LLD → Method Contracts).
- [x] 2.2 Sign-off reset for `cause: :undo`: archive active responses on steps after the current one that
      were given before `undo_started_at`, unless `keep_on_regress`; `invalidated` change per step; queue
      `sign_off_reset` for human-step approvers only. Verify with a `rails runner` scenario where a passive
      evaluation runs first (LLD → Transactions).
- [x] 2.3 `Workflowable#journey_undo(note:, actor:)` (captures the start time, yields, evaluates with `undo`,
      rescues + Sentry), `WorkflowStepInvalidate` (with `only_if_not_passed:`), and
      `WorkflowEvaluator.for(record, …)`. Verify: invalidating a key on a record without a journey is a no-op
      (LLD → Method Contracts).
- [x] 2.4 `WorkflowAcknowledge` + `post :acknowledge` route + `WorkflowInstancesController#acknowledge`
      (instance `show?` and workflowable `update?`); evaluate after `advance` and `reset` on evaluated
      instances. Verify: the route appears in `bin/rails routes | grep acknowledge` (LLD → Controllers).
- [x] 2.5 `WorkflowAdvancer` for evaluated instances: rejection archives the step's votes, writes
      `rejected_step` with the note, keeps the step current and never sets `rejected`; evaluate after any
      move. Human-only instances unchanged. Verify: 1.1 baseline still green (LLD → File Map ⑦).
- [x] 2.6 `Workflowable` gate methods: `workflow_gated?` returns false for evaluated instances;
      `workflow_step_unlocked?`, `workflow_default_owner` (`workflow_outstanding_before` was added, then removed with 5.3). Verify in
      `rails runner` against a test template that sets `unlocks` (LLD → Method Contracts).
- [x] 2.7 `WorkflowStateChange.channel` adds `system: 3`; instance page presenter shows system/ack status
      and the new history entries, including the rejection note. Verify by hand on a test instance.
- [x] 2.8 Write `features/core/workflow_evaluated_steps.feature` covering **H4, H8, E9, E10c, E11, E26, X3,
      X6**, and extend `features/core/workflow_button_gating.feature` with **E2**. Run
      `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/workflow_evaluated_steps.feature features/core/workflow_button_gating.feature`
      and confirm green before starting phase 3.

## 3. Ticks and reminders

- [x] 3.1 `WorkflowEvaluateJob` (queue `:default`, `retry: 0`): `find_each` over `evaluated: true` instances
      that are active, or complete within 30 days; evaluate each with `cause: :progress`; skip
      `RecordNotFound`. Add the `workflow_evaluate` `*/15 * * * *` cron next to the reminder entry in
      `config/initializers/sidekiq.rb`. Verify: `bin/rails runner 'WorkflowEvaluateJob.perform_now'`
      (LLD → Background Jobs).
- [x] 3.2 `WorkflowAutoReminderJob`: for evaluated instances, evaluate first; remind the owner of a stalled
      system/ack step (live template step owner → snapshot → `workflow_default_owner`; skip if inactive);
      time both owner and human reminders from `current_step_since` and the last reminder for that step;
      write `owner_reminded`. Human-only instances unchanged. Verify with `travel_to` in `rails runner`
      (LLD → Background Jobs).
- [x] 3.3 `WorkflowMailer#owner_reminder` and `#sign_off_reset` with views (bare `l(...)` dates). Verify by
      previewing both mails in development.
- [x] 3.4 Write `features/core/workflow_ticks_and_reminders.feature` covering **H9, H15, H16, H17, E16, X4**.
      Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/workflow_ticks_and_reminders.feature`
      plus the 1.1 baseline, and confirm green before starting phase 4.

## 4. Capital call checks, seeded journeys and launch

- [x] 4.1 `CapitalCommitment.skip_doc_gen_ids(scope)` (Ruby filter over `pluck(:id, :json_fields)`,
      reusing `skip_doc_gen?`) and `CapitalCall#workflow_default_owner`. Verify in `rails runner` on the
      dev database (LLD → Queries).
- [x] 4.2 The 11 task checks and 3 skip checks under `app/packs/funds/capital_calls/workflow_checks/capital_call/`,
      each returning messages from the design (e.g. "12 of 40 remittances created", "The fund has no call
      notice template", "2 investors have unverified KYC — notices are not generated for them",
      "Remittance upload in progress"), with `passed_since`/`fresh_since` as in the LLD query table.
      Register all keys. Verify: `rails runner` prints each check's result for a dev call (LLD → Queries).
- [x] 4.3 `CapitalCallWarnings` (subscribers via `CapitalCallRuleContextProvider`; skip_doc_gen count; only
      before Send notices passes). Verify in `rails runner`.
- [x] 4.4 `CapitalCallJourneySetup` (Full and Light by `system_key` with step descriptions, owners null,
      `unlocks` on Approve call and Send notices; two rules:
      priority 200 `manual_generation eq true` → Light, priority 100 catch-all → Full; flag on; dry-run
      report) and the `SetupCompany` hook for fund-type entities. Verify: running it twice in
      `rails runner` creates nothing the second time (LLD → Method Contracts).
- [x] 4.5 Write `features/fund/capital_call_journey.feature` covering **H2, H5, H6, H7, E3, E4, E5, E19,
      E20, E21, E22, E23, E25, E28, X5** (journey state asserted through the evaluator results, no UI yet).
      Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/fund/capital_call_journey.feature` and
      confirm green before starting phase 5.

## 5. The call page

- [x] 5.1 `CapitalCallsController#show` assigns `@journey`; `capital_calls/_journey.html.erb` renders the
      step bar (task names with ✓ ● ○ ↺ n/a, current in bold, n/a reasons on hover), the panel (task,
      position, owner, "current for N days", message, action link or **Mark reviewed**), readiness
      warnings, the moved-back banner and "Journey complete"; inserted after `_capital_call_stats` in a
      `turbo_frame_tag "capital_call_journey"`. Calls without a journey render nothing new. Verify by hand
      on a dev call (LLD → File Map ⑤).
- [x] 5.2 Mark reviewed responds with a Turbo Stream replacing the journey frame. Verify by hand.
- [x] 5.3 *(Removed after review: the dialog no longer repeats the journey — the panel is on the page.)* Outstanding-task list inside `#capital_call_approve_confirm_msg` (steps before Approve call) and
      `#capital_call_notify_confirm_msg` (steps before Send notices) from `workflow_outstanding_before`;
      the existing unapproved-notice blocker untouched. Verify by hand with the rule-validation dialog.
- [x] 5.4 Write `features/fund/capital_call_journey_ui.feature` covering **H3, H12, E6, E27** (H13 dropped with 5.3). Run
      `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/fund/capital_call_journey_ui.feature` and
      confirm green before starting phase 6.

## 6. Undoing actions

- [x] 6.1 `CapitalCallUnapprove` wrapped in `journey_undo("Unapproved")`. Verify: `rails runner` unapprove
      writes a `regressed` change with the actor (LLD → File Map ⑧).
- [x] 6.2 `CapitalCallAction#invalidate_if_figures_changed` for percentage, amount, closes and call date:
      invalidate `create_remittances` and `generate_notices` inside `journey_undo`. Verify in `rails runner`.
- [x] 6.3 `CapitalRemittancesRecomputeFeesJob`: at the end, if no row failed, write `recomputed` and
      invalidate `generate_notices` inside `journey_undo` (covers Recompute Call and `CapitalCallDateChangeJob`).
      Verify by running the job in `rails runner` on a dev call.
- [x] 6.4 `CapitalRemittanceDocJob`: at the end of a call-level or single-remittance run, evaluate with
      `undo` if any notice was replaced, else `progress`. `DocumentsController`: approved → unapproved on a
      generated call notice → `journey_undo("Notice unapproved")`. Verify in `rails runner` and by hand.
- [x] 6.5 `CapitalRemittanceVerify` → `journey_undo` only when un-verifying and not inside the bulk job;
      `CapitalRemittancesBulkActionJob` suppresses per-record hooks and evaluates each affected call once
      after Toggle Verify / Mark Notification Unsent. Verify: a bulk unverify of 40 rows writes one
      evaluation per call.
- [x] 6.6 `CustomNotificationsController` create/update/destroy of a CapitalCall notification → invalidate
      `review_email` and `check_preview` on the call, or on the fund's calls whose Send notices hasn't
      passed (`only_if_not_passed:`). Verify in `rails runner`.
- [x] 6.7 Write `features/fund/capital_call_journey_undo.feature` covering **E7, E8, E10, E10b, E12, E13,
      E17, E18, E24**. Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/fund/capital_call_journey_undo.feature`
      plus phases 4–5 features, and confirm green before starting phase 7.

## 7. Rollout

- [x] 7.1 `lib/tasks/capital_call_journeys.rake` → `capital_call_journeys:rollout`: per entity (or
      `ENTITY_ID`) run `CapitalCallJourneySetup` with `execute: ENV["EXECUTE"] == "1"`, one transaction
      per entity, a printed per-entity report and a summary of failures. No code path touches existing
      calls. Verify: dry run against the dev database prints a report and writes nothing (LLD → Configuration and Rollout).
- [x] 7.2 Write `features/fund/capital_call_journey_rollout.feature` covering **H1, H10, H11, E14, E15**.
      Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/fund/capital_call_journey_rollout.feature`
      and confirm green before starting phase 8.

## 8. Documentation, full regression and QA

- [x] 8.1 `docs/user_guides/capital_calls_user_guide.md`: a Capital Call Journey section for Full and
      Light. Each task gets what it checks, when it is n/a, what moves it back, who is reminded and how to
      resolve it. Add a mermaid diagram per journey and FAQs in the `**Q?**` format.
      `docs/user_guides/workflow_templates_user_guide.md`: step kinds, owners, unlocks, Keep sign-off,
      rejection in journeys. Verify **H14** with the UserGuideLint check.
- [x] 8.2 Run `bundle exec rubocop` on every changed file (including `IRM/RelationBlankPresent`) and fix
      offences.
- [x] 8.3 Full regression: `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/workflow_*.feature features/fund/capital_call*.feature features/fund/capital_distributions.feature features/core/investor_kyc_send_workflow.feature`
      green.
- [x] 8.4 (QA, not the apply agent) Run [qa-checklist.md](qa-checklist.md) on a deployed staging build in
      IN and US and record the sign-off table.

## 9. Fixes found on review

- [x] 9.1 A confirmed review must survive the skip (**E29**): in `WorkflowEvaluator#judge`, an acknowledge
      step with a valid confirmation stays `passed` instead of flipping to n/a once its skip check applies
      (notices sent, or the call set not to notify). The skip still covers a review nobody did.
- [x] 9.2 Audit trail: `WorkflowStateChange` rows written by the evaluator now carry `from_state` (the
      step's previous evaluated status) and, for a step passed by a person, that person as `actor` with
      their own `channel` instead of `system`.
- [x] 9.3 The journey card's View button opens the workflow instance in a new tab.
- [x] 9.4 The panel's action drives the real control on the call page (**H18**, design Decision 21):
      `action_target` on `WorkflowChecks::Result`, DOM ids in `WorkflowChecks::CapitalCall::Support`,
      and `app/javascript/controllers/journey_action_controller.js`. Verify with
      `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/fund/capital_call_journey_ui.feature`.
- [x] 9.5 Re-run the phase 8.3 regression after 9.1–9.4.
