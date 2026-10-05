# Tasks

> **Phase gate:** each numbered group below is a phase. A phase's last task is always to run its
> Cucumber feature and get it green. Do not start the next phase until that happens — if it fails,
> fix the phase you're on rather than moving forward and coming back later.

## 1. Share the call journey's panel, setup and email-edit (no behaviour change)

- [x] 1.1 Move `CapitalCallJourneyHelper` to `core/workflow_templates/helpers/journey_helper.rb` as `JourneyHelper` and update references (LLD File Map ⑦). Verify: `grep -rn CapitalCallJourneyHelper app` is empty.
- [x] 1.2 Extract the body of `capital_calls/_journey.html.erb` into `workflow_instances/_journey_panel.html.erb` with locals `frame_id`, `warnings`, `warning_tip`; the call's `_journey` becomes a wrapper (LLD ⑦). Verify: rendered call page HTML for a call with a journey is identical before/after (diff via `rails runner` render).
- [x] 1.3 Create `JourneySetup` base with `KINDS` and `.rollout`; make `CapitalCallJourneySetup` a subclass; point `capital_call_journeys.rake` at `JourneySetup.rollout("capital_call")` (LLD Method Contracts). Verify: dry run prints the same output as before.
- [x] 1.4 Replace `setup_capital_call_journeys` with `setup_journeys(kind)` (route, controller, policy `setup_journeys?`, view looping kinds, ids `setup_<kind>_journeys_btn`) (LLD Controllers). Verify: rubocop clean; the call button still renders.
- [x] 1.5 Move `CapitalCallJourneyEmailEdit` to `JourneyEmailEdit` with `CONFIGS` (call only for now) and update `CustomNotificationsController` (LLD Method Contracts). Verify: grep empty for the old name.
- [x] 1.6 Regression gate: run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/fund/capital_call_journey.feature features/fund/capital_call_journey_ui.feature features/fund/capital_call_journey_rollout.feature` and confirm green before starting phase 2.

## 2. Fixes to distribution approval, completion, wording and jobs

- [x] 2.1 `CapitalDistributionPolicy#approve?` requires the approver role; `payments_completed?` requires approval; remove `mark_payments_completed?` and use `payments_completed?` in the view (design ③ Fixes). Verify: rubocop; grep for `mark_payments_completed` empty.
- [x] 2.2 Correct the Send Notification hint in `_form.html.erb` (proposal Behavior Rules). Verify: text on the new form.
- [x] 2.3 `CapitalDistributionJob`: nil-safe error path (`User.find_by`, skip email, log); pass `user_id` from callers that know it (LLD Background Jobs). Verify: `rails runner` with a forced error and nil user does not raise.
- [x] 2.4 `CapitalDistributionPaymentRecomputeFeesJob`: load the distribution before the first message (LLD Background Jobs). Verify: message names the distribution.
- [x] 2.5 Replace `payments.each` with `find_each` in `CapitalDistributionsController#payments_completed` (LLD Queries). Verify: rubocop.
- [x] 2.6 Give the approver role in existing distribution step definitions where scenarios approve; write `features/fund/capital_distribution_fixes.feature` covering X1, X2, X4, X5, E23, and run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/fund/capital_distribution_fixes.feature features/fund/capital_distributions.feature` until green before starting phase 3.

## 3. Checks, setup and launch

- [x] 3.1 `CapitalDistribution` includes `Workflowable`; add to `WORKFLOWABLE_TYPE_OPTIONS` and `ALLOWED_WORKFLOWABLE_TYPES`; `workflow_default_owner`, `journey_progress_for` (LLD Method Contracts; `broadcast_journey_change` lands with the journey route in 4.1). Verify: `rails runner` shows `CapitalDistribution.new.respond_to?(:journey_progress!)`.
- [x] 3.2 Write `WorkflowChecks::CapitalDistribution::Support`, the 9 task checks and 5 skip checks, and `CapitalDistributionWarnings`; register in `config/initializers/workflow_checks.rb` (design ④⑤, LLD Queries). Verify: `rails runner` runs every check against 5 prod-dump distributions (port 33066) without error and with sensible messages.
- [x] 3.3 `CapitalDistributionJourneySetup` (keys, steps, Light names, rule condition `manual_generation eq true`), `capital_distribution_journeys.rake`, `SetupCompany` step, `KINDS` entry (design ①). Verify: dry run on the prod dump lists fund entities.
- [x] 3.4 Write `features/fund/capital_distribution_journey_rollout.feature` (H1, H10, E20, X3) and `features/fund/capital_distribution_journey.feature` scenarios for H2, H9, E1–E5, E7, E19; run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/fund/capital_distribution_journey_rollout.feature features/fund/capital_distribution_journey.feature` until green before starting phase 4.

## 4. Distribution page: panel, live updates, notices link

- [x] 4.1 `CapitalDistribution#broadcast_journey_change`; `capital_distributions/_journey.html.erb` wrapper; `journey` route, action and `journey?`; evaluate in `show` on the writing role; `turbo_stream_from` (design ⑦). Verify: page renders the panel for a new distribution.
- [x] 4.2 DOM ids on Approve, Generate Documents, Mark Payments Completed, Send Payment Notifications, Redeem Units; new "View Generated Notices To Approve" link (`target: _blank`); Workflow tab with `assign_workflow?` (design ③). Verify: ids present in rendered HTML.
- [x] 4.3 `Document` `capital_distribution_id` ransacker + ransackable attribute; approval hint covers distribution notices (LLD File Map ③). Verify: Documents list filtered by `capital_distribution_id_eq` returns only that distribution's notices.
- [x] 4.4 Write `features/fund/capital_distribution_journey_ui.feature` covering H3, H4, H5, E6, E22, X6 (E16, E17 need phase 5's hooks, so they are added in 5.4) and run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/fund/capital_distribution_journey_ui.feature` until green before starting phase 5.

## 5. Progress and undo hooks

- [x] 5.1 Progress hooks: `CapitalDistributionJob`, `ImportCapitalDistributionPaymentsFixCountsJob` (new), payments `#create`, `#payments_completed` (both), `#approve`, `#send_notification`, `CapitalDistributionPaymentNotificationJob`, `FundUnitsJob` (design ⑧). Verify: spy logs one evaluation per action in `rails runner`.
- [x] 5.2 Notice hooks: `CapitalDistributionPaymentDocJob#evaluate_journey`; `Document.distribution_ids_for_notices`; `DocumentsController`, `DocumentApprovalJob`, `DocumentsBulkActionJob` distribution branches (LLD Background Jobs). Verify: approving one CDP notice evaluates its distribution once.
- [x] 5.3 Undo hooks: payments `#update` (invalidate on figure change) and `#destroy`; recompute job (invalidate + undo with `started_at`); date-change job passes `started_at`; `FundUnitsBulkActionJob` delete; `JourneyEmailEdit` distribution config (LLD Method Contracts). Verify: `rails runner` recompute on a journeyed distribution writes a "regressed" history row.
- [x] 5.4 Extend `features/fund/capital_distribution_journey.feature` with H6, H7, H8, E8–E15, E18, E21 and `capital_distribution_journey_ui.feature` with E16, E17 (live updates) and run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/fund/capital_distribution_journey.feature` until green; then run the neighbouring features `features/fund/capital_distributions.feature features/fund/fund_unit.feature features/fund/fund_import.feature features/core/custom_notifications.feature features/core/doc_gen.feature features/fund/kyc_level_doc_gen.feature` and the three call journey features until green before starting phase 6.

## 6. Documentation

- [x] 6.1 User guide: "Tracking a Distribution: the Journey Step Bar" section (marks, task table with done / n/a / moves back when, mermaid diagrams), the corrected Send Notification text, Approver-role note, and FAQs (why no step bar, why notice tasks are n/a, why it moved back, how to set it up, does it update without refresh) (design Part 1). Verify: content checked against code.
- [x] 6.2 Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/user_guide_lint.feature` until green.
- [x] 6.3 QA runs `qa-checklist.md` on a deployed build and records the sign-off (for QA, not the apply agent).
