# Tasks

> **Phase gate:** each numbered group below is a phase. A phase's last task is always to run its
> Cucumber feature and get it green. Do not start the next phase until that happens — if it fails,
> fix the phase you're on rather than moving forward and coming back later.

## 1. Shared engine: STI type name, review results, closing check, setup generalisation (no behaviour change for calls/distributions)

- [x] 1.1 Add `Workflowable#workflowable_type_name` (base class) and use it at every `class.name` site in the workflow pack (auto-assignment service, `WorkflowTemplate`, `WorkflowInstancesController` ×2, `WithJourneyPanel`, `_workflow_tab` ×2, `WorkflowMailer`, `apply_workflow_auto_assignment_on_update`); base-class `journey_frame_id` and journey path in `broadcast_journey_change` (LLD Method Contracts → Workflowable). Verify: `grep -rn "class\.name" app/packs/core/workflow_templates` shows only log/exception strings; `rails runner` auto-assigns an `IndividualKyc` to an `InvestorKyc` rule.
- [x] 1.2 `WorkflowChecks::Result` gains `review` (`confirmed`, `review` factories); `WorkflowChecks::Base` gains `closes_journey` / `closing_note`; `WorkflowEvaluator` closing pre-pass and `judge_acknowledge` handling; `WorkflowStepInvalidate` `only_if_passed:` (LLD Method Contracts → Result, Base, WorkflowEvaluator, WorkflowStepInvalidate). Verify: rubocop clean.
- [x] 1.3 Shared panel renders a secondary review button when `review_action_label` is present (design ⑦). Verify: call page HTML unchanged for a call at Review email.
- [x] 1.4 `JourneySetup`: optional `LIGHT_KEY`, `ENTITY_TYPES`, sign-off constants with CFO defaults; rollout filters by `ENTITY_TYPES`; `setup_journeys?(kind)` policy, controller and menu confirm text per kind (LLD File Map ①). Verify: call and distribution rollout dry runs print the same as before.
- [x] 1.5 Regression gate: run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/fund/capital_call_journey.feature features/fund/capital_call_journey_ui.feature features/fund/capital_call_journey_undo.feature features/fund/capital_call_journey_rollout.feature features/fund/capital_distribution_journey.feature features/fund/capital_distribution_journey_ui.feature features/fund/capital_distribution_journey_rollout.feature features/core/investor_kyc_workflow_auto_assignment.feature` (covers E24) and confirm green before starting phase 2.

## 2. KYC checks, setup and launch

- [x] 2.1 `InvestorKyc`: `has_journey`, `workflow_default_owner` override (LLD Method Contracts → InvestorKyc). Verify: `rails runner` `IndividualKyc.new.journey_frame_id == "investor_kyc_journey"`.
- [x] 2.2 `WorkflowChecks::InvestorKyc::Support`, the 8 task checks (Verify closing), 4 skip checks, `InvestorKycWarnings`; register in `config/initializers/workflow_checks.rb` (design ④⑤, LLD Queries). Verify: `rails runner` runs every check against 10 prod-dump KYCs (port 33066) without error.
- [x] 2.3 `InvestorKycJourneySetup`, `KINDS["investor_kyc"]`, `lib/tasks/investor_kyc_journeys.rake`, `SetupCompany#setup_investor_kyc_journeys` (design ①). Verify: dry run lists Investment and Angel Fund entities.
- [x] 2.4 Write `features/core/investor_kyc_journey_rollout.feature` (H1, H11, E19, E20, X3, X4) and `features/core/investor_kyc_journey.feature` scenarios for H2, H5, H10, E1, E2, E4, E6, E7, E8, E9, E18, E21, E23, X6; run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/investor_kyc_journey_rollout.feature features/core/investor_kyc_journey.feature` until green before starting phase 3.

## 3. KYC page: panel and live frame

- [x] 3.1 `investor_kycs/_journey.html.erb` wrapper; `journey` route and action (`WithJourneyPanel`); evaluate in `show` for non-investors; `turbo_stream_from` (design ⑦). Verify: page renders the panel for a new KYC as a fund user and not as the investor.
- [x] 3.2 Write `features/core/investor_kyc_journey_ui.feature` covering H3, E22, X1, X2, X5 (live-update rows H4, H6, E3, E15 need phase 4's hooks and are added in 4.4); run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/investor_kyc_journey_ui.feature` until green before starting phase 4.

## 4. Fixes and hooks

- [x] 4.1 Fixes: fund "complete" tick → completed in `InvestorKycAction#save`; bulk Unverify → completed in `InvestorKycsBulkActionJob` (design ③ Fixes). Verify: `rails runner` on a test KYC.
- [x] 4.2 Progress / undo / invalidate hooks: `InvestorKycCreate`, `InvestorKycUpdate`, `InvestorKyc#send_kyc_form`, controller `toggle_verified`, `request_updates`, `override_aml_status`, `extract_docs_data`, `InvestorKycsBulkActionJob`, `InvestorKycConcern#document_changed`, `DocLlmValidationJob`, `AmlReportAsyncDownloadJob` (design ⑧, LLD Background Jobs). Verify: spy logs one evaluation per action in `rails runner`.
- [x] 4.3 Write `features/core/investor_kyc_fixes.feature` (H9, E16, E17) and extend `investor_kyc_journey.feature` with H7, H8 (non-UI), E5, E10, E11, E12, E13, E14 and `investor_kyc_journey_ui.feature` with H4, H6, H8, E3, E15.
- [x] 4.4 Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/investor_kyc_fixes.feature features/core/investor_kyc_journey.feature features/core/investor_kyc_journey_ui.feature` until green; then the neighbours `features/misc/kyc.feature features/core/kyc_doc_first_wizard.feature features/core/investor_kyc_send_workflow.feature features/ai/kyc_validation.feature` until green before starting phase 5.

## 5. Per-form-type journeys: Duplicate and the form type picker

- [x] 5.1 `WorkflowTemplatesController#duplicate` + route + `duplicate?` + Duplicate button (design ① Duplicate). Verify: duplicating in `rails runner` copies steps and actors.
- [x] 5.2 Rule form "KYC form type" select + controller merge into `conditions` (design ① Form type picker). Verify: rule saved with `form_type_id eq <id>`.
- [x] 5.3 Extend `features/core/investor_kyc_journey_rollout.feature` with E25, E26, E27 and run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/investor_kyc_journey_rollout.feature features/core/investor_kyc_workflow_auto_assignment.feature` until green before starting phase 6.

## 6. Documentation

- [x] 6.1 User guide `docs/user_guides/investor_kyc_user_guide.md`: "Tracking a KYC: the Journey Step Bar" (marks, task table with done / n/a / moves back when, mermaid diagrams), the two fixes, per-form-type journeys, and FAQs (why no step bar, why a task is n/a, why it moved back, why a review was reset, how to set it up, does it update without refresh, documents-first) (design Part 1). Verify: content checked against code.
- [x] 6.2 Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/user_guide_lint.feature` until green.
- [ ] 6.3 QA runs `qa-checklist.md` on a deployed build and records the sign-off (for QA, not the apply agent).
