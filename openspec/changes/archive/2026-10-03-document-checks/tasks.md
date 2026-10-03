# Tasks

> **Phase gate:** each numbered group below is a phase. A phase's last task is always to run its
> Cucumber feature and get it green. Do not start the next phase until that happens — if it fails,
> fix the phase you're on rather than moving forward and coming back later.

> Every Cucumber run uses a fresh `TEST_ENV_NUMBER=$RANDOM` with Redis up on 6379. Inline comments in
> new method bodies cite worked-example IDs and link `openspec/changes/document-checks/design.md#worked-examples`.
> Phases 1–5 are **deploy 1**; phase 6 is **deploy 2** (after the conversion has run in production).

## 1. Engine: schema, registry, reader, judge, run

- [x] 1.1 Create the migration for `doc_checks`, `doc_check_runs`, `doc_check_results`, `doc_check_conversion_logs` per [lld Schema Detail](lld.md#schema-detail). Update `db/schema.rb` and `db/schema_test.rb`, then `db:clean_schema`. Verify: migrate and rollback succeed, and `git diff db/schema*.rb` shows only the four tables
- [x] 1.2 Add models `DocCheck`, `DocCheckRun`, `DocCheckResult`, `DocCheckConversionLog`, the `DocChecks::Field` struct and error classes, and `Entity has_many :doc_checks`. Verify: runner creates a check and refuses a duplicate field on the same card
- [x] 1.3 Move `required_document_names` and the name/owner-tag matcher into `InvestorKycConcern` (used by `Support` and the registry), and extract `InvestorKyc#journey_details_changed!` from `InvestorKycAction#journey_hook`. Verify: `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/investor_kyc_journey.feature features/core/investor_kyc_journey_ui.feature` is green
- [x] 1.4 Implement `DocChecks::Registry` and `DocChecks::Kyc` per [lld Method Contracts](lld.md#method-contracts). Verify: runner prints `fields_for` for a seeded entity, with no control column
- [x] 1.5 Implement `DocChecks::DocumentReader < DocLlmBase` (prompt keyed by `c<id>`, JSON mode, parse, failures, `ProviderError`, overridable `llm_call`), and port `AiDataManager#validate_document` to it. Verify: covered by 1.10 (H13)
- [x] 1.6 Implement `DocChecks::Judge` (outcome codes, normalisation, dates). Verify: covered by 1.10
- [x] 1.7 Implement `DocChecks::StartRun` and `DocChecks::RunJob` (guard, expiry, progress, per-document isolation, couldn't-run, finish transaction, `details_changed!`, `on_assessed`, `journey_progress!`, toasts, carry-over). Verify: covered by 1.10
- [x] 1.8 Implement `DocChecks::Assessment`. Verify: covered by 1.10
- [x] 1.9 Add `features/support/doc_checks_fake_reader.rb`, factories and `features/step_definitions/doc_checks_steps.rb`
- [x] 1.10 Write `features/core/doc_check_runs.feature` covering H3, H13, E6, E7, E8, E9, E10, E11, E12, E14, E15, E17, E18, X1, X2, X3, X5. Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/doc_check_runs.feature` and confirm it passes before starting phase 2

## 2. Setup page and presets

- [x] 2.1 Add `config/doc_check_presets.yml` and `DocChecks::Presets`. Verify: runner shows CML mapped rows plus `not_added` [Email, Mobile] for the shared-setup form
- [x] 2.2 Add `DocChecks::CardForm`, `DocCheckPolicy`, `DocChecksController` (index / card / update_card / preset / try) and routes. Verify: `bin/rails routes -g doc_checks`
- [x] 2.3 Build the views (cards, rows, not-added note, missing-field banner and row message, empty state) with `config/locales/doc_checks.en.yml`, and point the Settings menu entry at `doc_checks_path`. Verify: in dev, apply the CML preset and save
- [x] 2.4 Add the `doc-check-row` Stimulus controller (row swap, look-for autofill, used-field greying, dirty state, leave-page guard). Verify: J3.1–J3.4 by hand in dev
- [x] 2.5 Write `features/core/doc_check_setup.feature` covering H1, H2, E1, E2, E3, E4, E5, E16, X4. Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/doc_check_setup.feature` and confirm it passes before starting phase 3

## 3. KYC tab, resolving, attention list, triggers

- [x] 3.1 Add `DocCheckRunPolicy` and `DocCheckRunsController` (create / show) with routes. Change the KYC page buttons to "Check documents" posting to it, keeping the DOM id. Remove `InvestorKycsController#validate_docs_with_ai` and its member route. Verify: clicking in dev queues a run
- [x] 3.2 Change `InvestorKycsBulkActionJob#validate_docs_with_ai` to `StartRun` + `RunJob.perform_now`, and relabel the bulk buttons. Verify: covered by 3.6 (H8)
- [x] 3.3 Build `doc_check_runs/_panel`, `_header`, `_group`, `_result` (progress, couldn't-run banner, trial banner, collapsed OK groups, tab count, Earlier AI answers). Render it in `investor_kycs/_details` `#docs-validation-tab` for fund users only, with broadcasts from `RunJob`. Verify: in dev the tab updates during a run
- [x] 3.4 Add `DocCheckResultPolicy` and `DocCheckResultsController` (use_document_value / mark_ok / undo, with the lock order result → record; index with filters; check_again), plus the KYC menu link. Verify: covered by 3.6
- [x] 3.5 Wire `DocChecksController#try` to a trial run shown in a frame. Verify: covered by 3.6 (H4)
- [x] 3.6 Write `features/core/doc_check_results.feature` covering H4, H5, H6, H8, H9, H12, E19, X6, X7, X8, X10. Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/doc_check_results.feature` and confirm it passes before starting phase 4

## 4. KYC journey

- [x] 4.1 Rewrite `WorkflowChecks::InvestorKyc::ValidateDocuments` on `Assessment`, with the messages from the journey delta spec. Delete `Support#ai_answer_counts` / `#ai_validated_at`. Rewrite the `DocQuestion` / `doc_question_answers` steps in `investor_kyc_journey_steps.rb` (and the scenarios using them) onto `DocCheck`. Verify: covered by 4.2
- [x] 4.2 Write `features/core/kyc_doc_checks_journey.feature` covering H7, E13, E20, E21, E22, E23. Run it, then `features/core/investor_kyc_journey.feature features/core/investor_kyc_journey_ui.feature features/core/investor_kyc_journey_rollout.feature`, all with `TEST_ENV_NUMBER=$RANDOM`, and confirm all pass before starting phase 5

## 5. Conversion and deploy-1 retirements

- [x] 5.1 Implement `DocChecks::LegacyConverter` (with the conversion log) and `lib/tasks/doc_checks.rake` `doc_checks:convert_doc_questions` (`ENTITY_ID`, dry run unless `EXECUTE=1`). Verify: a dry run against the prod dump (port 33066) prints a report for the 6 entities and creates nothing
- [x] 5.2 Deploy-1 retirements: remove the document QnA tab and add `Document.ignored_columns += ["qna"]`; point the `UserGuideHelper` key at the new guide; delete the dead `DocLlmQnaJob` (it wrote the ignored column). (The permission has no separate label to rename — it is listed by its flag name.) Verify: document page renders without the tab
- [x] 5.3 Write `docs/user_guides/document_checks_user_guide.md` (Where to find it, setup, presets, trial, reading results, resolving, attention list, what was retired, FAQ in the `**Q?**` + answer format, mermaid diagrams), and update the Doc Questions sections in `document_management_user_guide.md`, `ai_features_user_guide.md`, `investor_kyc_user_guide.md` and `documents_module_prd.md`. Verify: `UserGuideLint` passes
- [x] 5.4 Write `features/core/doc_checks_conversion.feature` covering H10, H11, X9. Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/doc_checks_conversion.feature` and confirm it passes before starting phase 6
- [x] 5.5 Export and import: `doc_checks/index.xlsx.axlsx` (Export on the setup page), `ImportDocCheck` + `ImportDocCheckService` (ImportUpload type `DocCheck`, sample `public/sample_uploads/doc_checks.xlsx`), migration `add_import_upload_to_doc_checks`, `DocCheckPolicy#import?`. Verify: an exported sheet imports back with every row Success
- [x] 5.6 Write `features/core/doc_check_import.feature` covering H14, H15, E24, E25, X11, X12, and tag every Document Checks feature `@doc_checks`. Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber --tags @doc_checks features/core` and confirm all pass

## 6. Deploy 2: retire Doc Questions

- [x] 6.1 Delete the Doc Questions code (and, since their tables are dropped, `DocChecks::LegacyConverter`, `DocCheckConversionLog`, `lib/tasks/doc_checks.rake` and the conversion feature + steps; keep old DocQuestion import uploads openable via `safe_constantize`): `DocQuestionsController` and its 11 views, `DocQuestionPolicy`, `DocQuestion`, `WithDocQuestions`, `DocLlmValidator`, `DocLlmValidationJob`, `DocLlmQnaJob`, `VariableInterpolation`, `ImportDocQuestion`, `ImportDocQuestionService`. Remove the includes and associations (`InvestorKyc`, `Investor`, `AggregatePortfolioInvestment`, `Entity` incl. the `really_destroy!` loop), the import type and sample map in `ImportUpload` and `import_uploads/show.html.erb`, `resources :doc_questions`, `public/sample_uploads/doc_questions.xlsx` and `kyc_validation_rules.xlsx`. Delete the legacy features and steps. Verify: `grep -rn "DocQuestion\|DocLlmValidat\|DocLlmQna\|VariableInterpolation\|WithDocQuestions\|doc_questions_path" app config lib features` is empty, the only remaining old names are `validate_docs_with_ai?`, `investor_kyc_validate_docs_with_ai_btn`, `ValidateDocsWithAi` and `doc_question_answers`, and `bin/rails zeitwerk:check` passes
- [x] 6.2 Add the guarded `retire_doc_questions` migration (guard, drop `doc_questions` and `doc_check_conversion_logs`, drop `documents.qna` INSTANT on MySQL), remove `ignored_columns`, and update both schema files. Verify: migrate/rollback on dev; the guard aborts when an unconverted row exists
- [x] 6.3 Run `bundle exec rubocop` on all new and changed files. Verify: exit 0
- [x] 6.4 Write `features/core/doc_checks_retirement.feature` covering R1, R2, R3, R4, R5. Tag it `@doc_checks` and run it together with every Document Checks feature and the KYC journey features: `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber --tags @doc_checks features/core && TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/investor_kyc_journey.feature features/core/investor_kyc_journey_ui.feature features/core/investor_kyc_journey_rollout.feature`, and confirm all pass
- [ ] 6.5 (QA, not the apply agent) Run [qa-checklist.md](qa-checklist.md) on staging after each deploy (R rows after deploy 2) and record the sign-off
