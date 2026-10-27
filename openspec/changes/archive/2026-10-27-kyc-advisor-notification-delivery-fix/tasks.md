# Tasks

## 1. Clean up WIP debugging instrumentation

- [x] 1.1 Remove the `byebug` breakpoints from `notify_kyc_updated`/`notify_kyc_submitted` in `app/packs/core/investor_kycs/mailers/investor_kyc_mailer.rb` and verify `bundle exec rubocop app/packs/core/investor_kycs/mailers/investor_kyc_mailer.rb` passes clean
- [x] 1.2 Remove the temporary `puts` debug lines from the investor-advisor loop in `InvestorKyc#notify_kyc` (`app/packs/core/investor_kycs/models/investor_kyc.rb`) and verify the method body matches its intended pre-debugging form (no stray output)
- [x] 1.3 Remove the temporary debug logging (delivery dump) from the `Then ... receives a KYC updated notification email` step in `features/step_definitions/investor_kyc_send_workflow_steps.rb` and verify `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/investor_kyc_send_workflow.feature --tags "@kyc_notification"` still passes

## 2. Fix email delivery for switched-away GP-side advisors

- [x] 2.1 Add the additive third OR-branch (`investor_advisor_show_enabled`) to `NotificationExtensions#email_enabled` in `config/initializers/noticed.rb` per design.md Decision 1 (`has_cached_role?(:investor_advisor)` gate + `Pundit.policy(recipient, model).show?`, rescued to `false` on `Pundit::NotDefinedError`/`NoMethodError`)
- [x] 2.2 Add a Cucumber scenario that builds an `InvestorKycNotifier`/`Noticed::Notification` for a recipient who holds an authorized investor-advisor grant on the KYC's entity but is currently switched into a different entity, and asserts `notification.email_enabled` is `true` by calling it directly (not via `ActionMailer::Base.deliveries`, since `BaseNotifier` bypasses `email_enabled` entirely in `Rails.env.test?` — see design.md Context) — confirm this scenario fails on `main` (pre-fix) and passes after 2.1
- [x] 2.3 Add a Cucumber scenario asserting `email_enabled` for a recipient with no investor-advisor grant on the model's entity is unchanged (still governed only by the two pre-existing checks), to guard the additive-only property of the fix
- [x] 2.4 Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber` for the feature file(s) touched in 2.2/2.3 and confirm all scenarios pass

## 3. Move the notification fan-out into a background job

- [x] 3.1 Create `app/packs/core/investor_kycs/jobs/notify_kyc_job.rb` following the `SendKycFormJob` pattern (design.md Decision 2): `perform(investor_kyc_id, email_method:, msg:)`, re-fetch the `InvestorKyc`, wrap in `Chewy.strategy(:sidekiq)`, call `notify_kyc`
- [x] 3.2 Update `InvestorKyc#updated_notification` and `#updates_requested_notification` to enqueue `NotifyKycJob` instead of calling `notify_kyc` directly; leave `notify_kyc` itself unchanged as the method the job invokes
- [x] 3.3 Run the existing Cucumber scenarios in `features/core/investor_kyc_send_workflow.feature` (`--tags "@kyc_notification"`, scenarios 14-15) and confirm they still pass unchanged (`config.active_job.queue_adapter = :inline` in test should make `perform_later` run synchronously, so no scenario changes are expected)
- [x] 3.4 Run `bundle exec rubocop` on the new job file and the changed model file and fix any offenses

## 4. Final verification

- [x] 4.1 Run `bundle exec brakeman` (mailers/initializer were touched) and confirm no new findings
- [x] 4.2 Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/investor_kyc_send_workflow.feature` in full and confirm every scenario passes, including the pre-existing ones (1-13) unaffected by this change
- [x] 4.3 Run `git status`/`git diff` and confirm no leftover debugging instrumentation (byebug, temporary puts/logging) remains anywhere in the diff

## 5. Fix `email_enabled`'s gate (review finding: overrides opt-out / leaks into unrelated notifiers)

- [x] 5.1 Change `investor_advisor_show_enabled` in `config/initializers/noticed.rb` from the `recipient.has_cached_role?(:investor_advisor)` gate to `model.entity.investor_advisors.exists?(user_id: recipient.id)` (guarded by `model.respond_to?(:entity) && model.entity.present?`), per design.md Decision 1 (revised)
- [x] 5.2 Add `Rails.logger.warn` logging of the rescued exception (class, model, recipient) in the same method's rescue clause, per design.md Decision 3
- [x] 5.3 Add a Cucumber (or direct-call, matching 2.2/2.3's pattern) scenario: a recipient who holds an `InvestorAdvisor` grant on a *different* entity than a public `Document`'s own entity does not get `email_enabled == true` via this branch, even though `DocumentPolicy#show?` would return `true` for that document's `public_visibility` — confirms the entity-scoped gate prevents the cross-notifier leak found in review
- [x] 5.4 Re-run the scenarios from task 2.2/2.3 and confirm they still pass under the revised gate (a grant on the KYC's *own* entity should behave identically to before)
- [x] 5.5 Run `bundle exec rubocop config/initializers/noticed.rb` and fix any offenses

## 6. Fix `InvestorKycPolicy#show?` branch bugs (review findings: exclusive elsif, employee-role ordering, company_admin grant)

- [x] 6.1 Add `InvestorAdvisor#is_company_admin?` and fix `#is_employee?` to compare against stringified `allowed_roles` (`Array(allowed_roles).map(&:to_s).include?(...)`), per design.md Decision 6
- [x] 6.2 Restructure `InvestorKycPolicy#show?` per design.md Decision 5: the investor-advisor-grant branch becomes additive (`return true if ...` instead of an exclusive `elsif`) and accepts `is_employee? || is_company_admin?`; the investor-owns-this-KYC check and the `:employee`-role fund-access check are combined with `||` under one final branch instead of being ordered `elsif`s
- [x] 6.3 Add a Cucumber scenario: a user whose entity is typed `"Company"` (or `is_fund?`) and who is the KYC's own investor (so they also carry the `:employee` role per `User#setup_defaults`) can still view/access their own KYC
- [x] 6.4 Add a Cucumber scenario: a user holding an `InvestorAdvisor` grant on the KYC's entity with `allowed_roles: ["investor"]` (no `"employee"`) still gets `show?` via the `for_investor_advisor` or investor-owns-this-KYC path, rather than being denied outright
- [x] 6.5 Add a Cucumber scenario: a switched-away user holding an `InvestorAdvisor` grant with `allowed_roles: ["company_admin"]` (no `"employee"`) gets `show? == true`
- [x] 6.6 Add a Cucumber scenario covering a legacy symbol-serialized `allowed_roles` grant (e.g. `[:employee]`) still satisfying `is_employee?`/`show?`
- [x] 6.7 Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber` for the feature file(s) touched in 6.3-6.6 and confirm all scenarios pass, including the pre-existing show?-related scenarios
- [x] 6.8 Run `bundle exec rubocop` on `investor_kyc_policy.rb` and `investor_advisor.rb` and fix any offenses

## 7. Fix `notify_kyc`'s loops (review findings: zero-commitment regression, duplicate emails, inconsistent `enable_kycs` gate)

- [x] 7.1 Update `InvestorKyc#notify_kyc` per design.md Decision 4: both loops fall back to `enable_kycs`-only (skipping the `show?`/fund-access requirement) when `capital_commitments.none?`; both loops gate consistently on `user.enable_kycs`; track notified user ids across both loops and skip a user already notified by the first
- [x] 7.2 Add a Cucumber scenario: a KYC with zero capital commitments still notifies an active entity employee with `enable_kycs` on update/updates-requested (the regression this fixes — the existing scenarios in `investor_kyc_send_workflow.feature` all set up a capital commitment first, per design.md Context, so they can't catch this)
- [x] 7.3 Add a Cucumber scenario: a user whose own `advisor_entity_id` is `nil` but who holds an `InvestorAdvisor` grant on the entity they're currently switched into receives exactly one notification email, not two
- [x] 7.4 Add a Cucumber scenario: a switched-in advisor granted `company_admin` (bypassing `show?`'s `permissioned_employee?` branch) with their `InvestorAdvisor` grant's `enable_kycs` permission off does not receive a notification
- [x] 7.5 Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber` for the feature file(s) touched in 7.2-7.4, plus the pre-existing scenarios 14-15, and confirm all pass
- [x] 7.6 Run `bundle exec rubocop app/packs/core/investor_kycs/models/investor_kyc.rb` and fix any offenses

## 8. Fix the in-app notification body regression (review finding, pre-existing commit on this branch)

- [x] 8.1 Restore `msg: "KYC submitted by investor: #{investor_kyc.full_name}"` in `InvestorKycsController` (the call this change's design.md Decision 7 describes), removing the commented-out line
- [x] 8.2 Update `app/packs/core/investor_kycs/views/investor_kyc_mailer/notify_kyc_submitted.html.erb` to stop branching on `@message.present?` and always render its own default body text, per design.md Decision 7
- [x] 8.3 Add or update a Cucumber scenario asserting the in-app "KYC submitted" notification has a non-blank message, and that the email body still reads the intended default text
- [x] 8.4 Run `bundle exec rubocop` on the touched controller and view, and the relevant Cucumber scenario, and confirm both pass

## 9. Final verification (review-fix round)

- [x] 9.1 Run `bundle exec brakeman` and confirm no new findings
- [x] 9.2 Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/investor_kyc_send_workflow.feature features/core/investor_kyc_notification_delivery.feature` in full and confirm every scenario passes
- [x] 9.3 Run `bundle exec rubocop` across the full diff and confirm no offenses
- [x] 9.4 Re-read `config/initializers/noticed.rb`, `investor_kyc_policy.rb`, `investor_kyc.rb`, and `investor_advisor.rb` end to end and confirm each matches design.md's current Decisions 1 and 3-7

## 10. Document the change's blast radius (pre-review)

- [x] 10.1 Trace and verify the actual reach of each change by grep rather than assumption: callers of `is_employee?`/`is_company_admin?`, callers of `updated_notification`/`updates_requested_notification`, the gating in `InvestorKycAction#updated_notification`, the count of `BaseNotifier` subclasses, and whether any policy's `show?` takes a required argument (`ArgumentError` is not rescued)
- [x] 10.2 Correct design.md's and proposal.md's overstated claim that the entity-scoped gate confines the new `email_enabled` branch to `InvestorKyc` — it is scoped to the model's *entity*, so any record owned by a grant entity reaches its own policy's `show?`
- [x] 10.3 Add an "Impact Analysis" section to design.md covering reach, behavior-change direction, failure points, rollback, and known test gaps for each of the five changed areas
- [x] 10.4 Add a Cucumber scenario pinning the same-entity public-document behavior (a switched-away advisor *does* get email for a public document on an entity they hold a grant on), since it is a real behavior change beyond KYC notifications and was previously untested
- [x] 10.5 Re-run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber` for both feature files and confirm all scenarios pass

## 11. Close the robustness gaps the impact analysis surfaced

- [x] 11.1 Fix `InvestorKycNotifier#url` to compare `params[:email_method]` as a String (`%w[]` + `.to_s`), so a method name that crossed a job boundary still resolves to the editable KYC form
- [x] 11.2 Add a Cucumber scenario asserting a String `notify_kyc_required`/`kyc_required_reminder` links to the editable form while other methods link to the read-only page, and confirm it fails on the symbol-only comparison
- [x] 11.3 Guard the `notify_kyc` advisor loop against a grant whose user row is gone (`next if user.nil?`), so one bad row cannot abort the remaining advisors' notifications
- [x] 11.4 Change `notified_user_ids` to a `Set` so dedup is a hash lookup rather than a linear Array scan
- [x] 11.5 Update design.md's Impact Analysis and test-gap list to reflect 11.1-11.4, and re-run both feature files plus `bundle exec rubocop` on the touched files

## 12. Stop the final submit sending two notifications (review finding, pre-existing on main)

- [x] 12.1 Add `InvestorKyc#submitted_notification` enqueuing `NotifyKycJob` with `email_method: "notify_kyc_submitted"`, so the submitted notification resolves recipients through `notify_kyc` like the other two, per design.md Decision 8
- [x] 12.2 Derive `submitted` in `InvestorKycsController#update` from the condition that already guarded `notify_fund_on_submission` (`status_attrs[:submission_status] == "completed" && !was_already_completed`) and pass it into `InvestorKycUpdate.call`
- [x] 12.3 Route `InvestorKycAction#updated_notification` on `ctx[:submitted]`, keeping it outside the `investor_user && validate` guard (the submission notification never depended on the acting user), and confirm `InvestorKycCreate` — which shares the step and never sets the key — is unaffected
- [x] 12.4 Delete `InvestorKycsController#notify_fund_on_submission` and its call site; carry its `msg:` rationale comment onto `submitted_notification`
- [x] 12.5 Assert in the existing browser-driven submit scenario (5) that the fund admin no longer also receives a "KYC updated" email
- [x] 12.6 Add a scenario covering the other half of the fix: an investor advisor with access receives exactly one submitted notification on a final submit, and no updated notification
- [x] 12.7 Update design.md (Decision 8, Impact Analysis area 6, test gaps) and proposal.md scope, then re-run both feature files plus `bundle exec rubocop` on the touched files

## KYC visibility rule (2026-10-07)

- [x] Add `InvestorKycPolicy.staff_visible_kycs` (enable_kycs AND company admin / Kyc Read / Kyc Update / fund access / no commitment) and use it in `Scope`
- [x] `show?`: entity staff via `policy_scope`; advisor grant judged by the grant's own `enable_kycs` and toggles; investor-side paths unchanged
- [x] `notify_kyc`: gate every recipient on `show?`; drop the separate zero-commitment fallback; advisors use the grant's `enable_kycs`
- [x] `investor_advisor_show_enabled`: report non-`NotDefinedError` failures through `ExceptionNotifier`
- [x] Cucumber: `investor_kyc_visibility_rule.feature` (V1–V9 + job boundary), rescue scenarios in `investor_kyc_notification_delivery.feature`, scenario 15 flipped for Kyc Read
- [x] User guides: KYC (matrix section + FAQs), investor advisor, user role management; `UserGuideLint` clean
- [ ] Sync guide FAQs to FAQ Manager after merge: `bin/rails guide_faqs:import_markdown REFRESH=1` then `bin/rails guide_search:reindex`
- [x] Run the KYC Cucumber features (44/44 after fixing the STI table-name crash in `entity_staff_can_see?`)
