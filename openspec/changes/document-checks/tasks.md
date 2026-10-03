# Tasks

> **Phase gate:** each numbered group below is a phase. A phase's last task is always to run its
> Cucumber feature and get it green. Do not start the next phase until that happens — if it fails,
> fix the phase you're on rather than moving forward and coming back later.

> Every Cucumber run uses a fresh `TEST_ENV_NUMBER=$RANDOM` with Redis up on 6379. Inline comments
> in new method bodies cite the worked-example IDs and link `openspec/changes/document-checks/design.md#worked-examples`.

## 1. Engine: schema, registry, reader, judge, run

- [ ] 1.1 Create the migration for `doc_check_sets`, `doc_checks`, `doc_check_runs`, `doc_check_results` with every column, limit, default, FK and index in [lld Schema Detail](lld.md#schema-detail). Update `db/schema.rb` and `db/schema_test.rb`, then run `db:clean_schema`. Verify: `bin/rails db:migrate` and `db:rollback` both succeed, and `git diff db/schema*.rb` shows only the four tables
- [ ] 1.2 Add models `DocCheckSet`, `DocCheck`, `DocCheckRun`, `DocCheckResult` with enums, associations, snapshots, `set_for`, `reply_key`, `accept!` validations and `Entity has_many :doc_check_sets` ([lld Method Contracts](lld.md#method-contracts)). Verify: `bin/rails runner` creates a set and a check, and is refused a duplicate set and a duplicate label
- [ ] 1.3 Extract `required_document_names` and the name/owner-tag matcher from `WorkflowChecks::InvestorKyc::Support` / `InvestorKycConcern` into one shared method used by both. Verify: `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/investor_kyc_journey*.feature` features still green
- [ ] 1.4 Implement `DocChecks::Registry` and `DocChecks::Kyc` (variants, `documents_for`, `fields_for` with the `COLUMNS` allowlist plus non-File custom fields, `read`/`write` with date parsing, `record_documents`, `find_document`, `on_assessed`, `can_view?`/`can_update?`). Verify: runner prints `fields_for` for a seeded entity, and the list contains no control column
- [ ] 1.5 Implement `DocChecks::DocumentReader < DocLlmBase` (prompt keyed by `c<id>`, JSON mode per provider, fence-stripping parse, known-key filter, failures `:unsupported_file` / `:unreadable_reply` / `:no_llm`, provider errors wrapped as `DocChecks::ProviderError`), with an overridable `llm_call` seam. Verify: a runner call against one dev KYC document returns readings keyed by check ids
- [ ] 1.6 Implement `DocChecks::Judge` (decision flowchart in [design ⑥](design.md#⑥-judge), `normalise`, loose token sort, date compare, Rule yes/true). Verify: covered by 1.10
- [ ] 1.7 Implement `DocChecks::StartRun` (record lock, active guard, stuck-run expiry, `AlreadyRunning`) and `DocChecks::RunJob` (status guard, per-document isolation, run-level failure without writes, finish transaction with `current` flip, `on_assessed`, `journey_progress!`, alert, acceptance carry-over), per [lld Transactions](lld.md#transactions-locking-and-concurrency) and [Background Jobs](lld.md#background-jobs). Verify: covered by 1.10
- [ ] 1.8 Implement `DocChecks::Assessment` (`groups`, `counts`, `problems`, `stale?`, `settled?`, `last_failed_attempt`, `fresh_at`). Verify: covered by 1.10
- [ ] 1.9 Add `features/support/doc_checks_fake_reader.rb` (the `@doc_checks_fake_ai` hook, readings per document, call counter, provider-error and garbage modes), the `doc_check_set`/`doc_check` factories, and the steps in `features/step_definitions/doc_checks_steps.rb` ([lld Test Plumbing](lld.md#test-plumbing))
- [ ] 1.10 Write `features/core/doc_check_runs.feature` covering H2, E1, E2, E3, E4, E5, E6, E7, E8, E10, E13, E17, E18, X1, X2, X3, X5. Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/doc_check_runs.feature` and confirm it passes before starting phase 2

## 2. Setup screens and presets

- [ ] 2.1 Add `config/doc_check_presets.yml` (CML, PAN card, Aadhaar, Passport: label, hint, kind, field candidates) and `DocChecks::Presets.apply`. Verify: runner applies CML twice to a set and the count stays 9
- [ ] 2.2 Add `DocCheckSetPolicy` and `DocCheckSetsController` (index/new/create/edit/update/destroy/apply_preset), with routes in `config/routes/core.rb` ([lld Controllers](lld.md#controllers-params-and-responses)). Verify: `bin/rails routes -g doc_check_sets` lists all actions
- [ ] 2.3 Build the views (`index`, `_form`, `_document_group`, `_check_row`), with the server-rendered field dropdown from `fields_for`, the "This field no longer exists — pick another" and "Pick a field before saving" row messages, the Add document picker from `documents_for` minus existing, and the empty state "No Document Checks set up yet — Add set". Verify: in dev, create the Individual set and apply CML
- [ ] 2.4 Add the `doc-check-row` Stimulus controller (show/hide Field / Fill / Expect by Kind) and the Settings menu link behind `enable_doc_llm_validation`. Verify: in dev, switching Kind toggles the inputs (J3.1, J3.2)
- [ ] 2.5 Write `features/core/doc_check_setup.feature` covering H1, H10, E11, E12, X4, X10. Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/doc_check_setup.feature` and confirm it passes before starting phase 3

## 3. Triggers, results panel, accept, results list, test run

- [ ] 3.1 Add `DocCheckRunPolicy`, `DocCheckRunsController#create/#show` (with the `record_type` allowlist), the routes, and remove `InvestorKycsController#validate_docs_with_ai` and its route. Change the KYC page button to "Run Document Checks", keeping DOM id `investor_kyc_validate_docs_with_ai_btn`. Verify: clicking it in dev creates a queued run
- [ ] 3.2 Change `InvestorKycsBulkActionJob#validate_docs_with_ai` to `StartRun` + `RunJob.perform_now`, keeping the verified-KYC refusal and `sleep(2)`, and relabel the bulk buttons. Verify: covered by 3.7 (H6)
- [ ] 3.3 Build the `doc_check_runs/_panel`, `_group` and `_result` partials (header counts with `l(...)`, Running state, Last attempt failed line, test-run banner, Accept/Fix/Retry). Render the panel in `investor_kycs/_details` `#docs-validation-tab` with `turbo_stream_from [record, :doc_checks]`, hidden for investor users, and keep "Earlier AI answers" collapsed when `doc_question_answers` has content. Broadcast `replace` from `RunJob` and accept. Verify: in dev the panel updates without reload after a run
- [ ] 3.4 Add `DocCheckResultPolicy` and `DocCheckResultsController#accept` (reason required, current-run and status guards, then `on_assessed`, `journey_progress!` and broadcast). Verify: covered by 3.7 (H4, X8)
- [ ] 3.5 Add `DocCheckResultsController#index` (ransack filters, `current: true` join, `includes` for the KYC name, Pagy, per-page out-of-date filter, empty state "No problems found") and `#rerun`, with a KYC menu link. Verify: covered by 3.7 (H7)
- [ ] 3.6 Add `DocCheckSetsController#test_run` (KYC picker reusing the KYC search select, `StartRun` with `test_run: true` and the given set, result shown in a frame via `DocCheckRunsController#show`). Verify: covered by 3.7 (H3)
- [ ] 3.7 Write `features/core/doc_check_results.feature` covering H3, H4, H6, H7, X6, X7, X8. Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/doc_check_results.feature` and confirm it passes before starting phase 4

## 4. KYC journey and `all_docs_valid`

- [ ] 4.1 Rewrite `WorkflowChecks::InvestorKyc::ValidateDocuments#call` on `DocChecks::Assessment`, using the four outcomes and messages in [design ⑧](design.md#⑧-screens-and-journey), and delete `Support#ai_answer_counts` / `#ai_validated_at`. Verify: covered by 4.3
- [ ] 4.2 Confirm the existing document-change invalidation still resets the step, and that `on_assessed` re-sets `all_docs_valid` after a re-upload (assessment re-run from `InvestorKycConcern#document_changed`). Update the comments' worked-example references (E9). Verify: covered by 4.3
- [ ] 4.3 Write `features/core/kyc_doc_checks_journey.feature` covering H5, E9, E14, E15, E19. Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/kyc_doc_checks_journey.feature`, then the existing `features/core/investor_kyc_journey*.feature` features, and confirm both pass before starting phase 5

## 5. Converting legacy Doc Questions

- [ ] 5.1 Implement `DocChecks::LegacyConverter` (mapping table in [design Legacy removal and conversion](design.md#legacy-removal-and-conversion), `find_or_create_by` on `legacy_doc_question_id`, report hash). Verify: covered by 5.3
- [ ] 5.2 Add `lib/tasks/doc_checks.rake` `doc_checks:convert_doc_questions` (`ENTITY_ID` optional, dry run unless `EXECUTE=1`, per-entity table on stdout). Verify: a dry run against the dev prod dump (port 33066) prints a report for the 6 entities and creates nothing (`DocCheck.count` unchanged)
- [ ] 5.3 Write `features/core/doc_checks_conversion.feature` covering H8, H9, X9. Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/doc_checks_conversion.feature` and confirm it passes before starting phase 6

## 6. Retire Doc Questions, document, verify

- [ ] 6.1 Delete `DocQuestionsController` with its views, policy and route, plus `DocLlmValidationJob`, `DocLlmValidator`, `DocLlmQnaJob`, `VariableInterpolation`, `ImportDocQuestion`, `ImportDocQuestionService` and `WithDocQuestions`. Remove the includes from `InvestorKyc`, `Investor` and `AggregatePortfolioInvestment` (KYC keeps `attribute :doc_question_answers, :json`). Remove the DocQuestion references in `import_upload.rb`, `import_uploads/show.html.erb`, `user_guide_helper.rb` and `ai_data_manager.rb`, and the menu link. Delete `features/ai/kyc_validation.feature`, `features/core/doc_question_import.feature` and their step files. Verify: `grep -rn "DocLlmValidat\|DocLlmQna\|VariableInterpolation\|WithDocQuestions\|doc_questions_path" app config lib features` is empty, and `bin/rails zeitwerk:check` passes
- [ ] 6.2 Write the user guide `docs/user_guides/document_checks_user_guide.md`: Where to find it, setup, presets, test run, reading results, Accept, results list, conversion FAQ in the `**Q?**` + answer format, with mermaid diagrams. Link it from `investor_kyc_user_guide.md` and `ai_features_user_guide.md` Related Guides, and remove their Doc Questions sections. Verify: `UserGuideLint` passes on the file
- [ ] 6.3 Run `bundle exec rubocop` on all new and changed files (including `IRM/RelationBlankPresent`) and fix offences. Verify: exit 0
- [ ] 6.4 Re-run all five Document Checks features and the `features/core/investor_kyc_journey*.feature` features: `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/doc_check_runs.feature features/core/doc_check_setup.feature features/core/doc_check_results.feature features/core/kyc_doc_checks_journey.feature features/core/doc_checks_conversion.feature features/core/investor_kyc_journey.feature features/core/investor_kyc_journey_ui.feature`. Confirm all pass after the removal
- [ ] 6.5 (QA, not the apply agent) After support has run the conversion on staging, run [qa-checklist.md](qa-checklist.md) on a deployed build and record the sign-off
