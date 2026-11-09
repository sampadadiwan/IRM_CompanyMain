# Tasks

> **Phase gate:** each numbered group below is a phase. A phase ends with three tasks, in order:
> (a) **UI review** — when the phase adds or changes screens: screenshot each one next to the
> reference screen named in design.md's *Screen standards* and apply the UI self-review checklist
> (breadcrumbs, lazy tabs, Turbo streams, stats cards, filters, Actions dropdown, tooltips/help,
> full width); (b) **N+1 check** — run the phase's features under Prosopite and fix every N+1 in
> this change's code; (c) run the phase's Cucumber features green. Do not start the next phase
> until all three pass — fix the phase you're on rather than coming back later.

> **Before starting:** the "Key changes needing approval" table (design.md K1–K18) and open questions 1–5 must be
> answered by the user. Test runs: `TEST_ENV_NUMBER=$RANDOM`, Redis on 6379, wait on the run's PID (never a pgrep
> loop), no app-code edits while a run is in progress. Every scenario has `# <ID> — <path>` above it; code comments
> name the IDs of the branches they implement.

## 1. Clear on change and protected fields (no schema)

- [ ] 1.1 Add `BankDetailChangeGuard` with `PAYOUT_FIELDS`, `normalised`, and `before_save :guard_bank_details` (flag clear + unverify only; no record yet) and include it in `InvestorKyc` with `attr_accessor :bank_change_actor, :bank_change_source` (LLD › Method Contracts › BankDetailChangeGuard). Comment IDs H1, E1–E4, E9, E10. Verify: `bin/rails runner` on a test KYC in the test DB shows `bank_verified` false after an account change and unchanged after a branch change.
- [ ] 1.2 `InvestorKycAction#journey_hook`: note "Bank details changed" when the save changed a payout field on a verified KYC (LLD › File Map ②). Comment E10. Verify: `investor_kyc_journey.feature` still green.
- [ ] 1.3 `InvestorKycPolicy`: add `kyc_approver?`; move `generate_new_aml_report?`, `override_aml_status?` and the Audit Trail menu (`show.html.erb:108`) to it; `permitted_attributes` drops `bank_verification_response`, `bank_verification_status`, `pan_verification_response`, `pan_verification_status`; adds `verified` only if `toggle_verified?`, `bank_verified` only if `confirm_bank_details?` (= `kyc_approver?` in this phase); class record → user-level approve flag (LLD › Method Contracts › InvestorKycPolicy). Comment X2–X4, E11, E12. Verify: `features/security/bulk_actions_authorization.feature` and `investor_kyc_aml_override` features still green.
- [ ] 1.4 `InvestorKycsController#investor_kyc_params` uses `policy(@investor_kyc || InvestorKyc)`; set `bank_change_actor` (`current_user || @signed_id_user`) and `bank_change_source` (screen/api by format) in update, create, create_and_send, compare_kyc_datas, assign_kyc_data, toggle_verified (LLD › Controllers). Verify: KYC create/edit features (`investor_kyc_fixes.feature`) green.
- [ ] 1.5 `_form.html.erb`: Bank Verified box only when `policy(investor_kyc).confirm_bank_details?`, with tooltip "Tick only after checking proof of the current account" (design card ⑦). Verify: Priya's edit page has no box.
- [ ] 1.6 Set `bank_change_source` in `DocChecks::Kyc.save_details!` ("document_checks") and `KycDocExtractorAgent#extract_and_populate` ("ai_extraction"); `ImportInvestorKyc#save_kyc` ("import") (LLD › File Map ①). Verify: `kyc_doc_checks_journey.feature` and `kyc_doc_extractor_agent.feature` green.
- [ ] 1.7 Write `features/core/bank_detail_change_reset.feature` (H1–H3, E1–E10, X1) and `features/security/bank_detail_change_fields.feature` (H4, E11–E13, X2–X4), header linking business-rules.md §1–§2.
- [ ] 1.8 UI review: KYC edit bank step (Priya and Ravi) beside `investor_kycs/_form` today — only the box visibility changed.
- [ ] 1.9 N+1 check: `PROSOPITE=1 TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/bank_detail_change_reset.feature features/security/bank_detail_change_fields.feature`; read `log/prosopite.log` (truncate first, never commit); fix N+1s in this change's code.
- [ ] 1.10 Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/bank_detail_change_reset.feature features/security/bank_detail_change_fields.feature` plus `bundle exec rubocop` and Brakeman on changed files; green before phase 2.

## 2. Change record, KYC page note and change emails

- [ ] 2.1 Migration `create_bank_detail_changes` per LLD › Schema Detail; migrate the test DB only; update `db/schema.rb` and `db/schema_test.rb` by hand (do not migrate the shared dev DB from a side branch). Verify: `bin/rails db:schema:load` in test succeeds.
- [ ] 2.2 `BankDetailChange` model (Trackable, `entity_id` attr_readonly, inclusion validations, `awaiting`, `confirm!`, `replace!`, display helpers, `maker_name`) and `InvestorKyc` `has_many`, `latest_bank_change`, `awaiting_bank_change` (memoised) (LLD › Method Contracts). Comment H5, E15, E16, E23.
- [ ] 2.3 Guard `after_save :record_bank_change` (replace + create) and `after_commit :notify_bank_change` with rescue + `notify_exception` (LLD › Transactions). Comment H5, H6, E14–E18, X5. Verify: failed save leaves no row (X5) in a runner check on the test DB.
- [ ] 2.4 `BankDetailChangeNotifyJob` with the two claims, investor recipients (`notification_users(kyc, with_tag: "KYC")` ∩ accesses created before the change), approver recipients (as `notify_kyc`, filtered by `show?` and `kyc_approver?`, minus maker), `investor_recipient_ids` (LLD › Background Jobs, Queries). Comment H7, H8, E24–E28, E30, X6.
- [ ] 2.5 `InvestorKycMailer#notify_bank_details_changed` / `#notify_bank_change_review` + views (masked digits, bare `l(date)`, "View KYC" to the KYC page, no magic link); appear in the custom notification dropdown (design › Notifications). Comment H7, E27, E29. Verify: email preview renders `Nov 09, 2026`.
- [ ] 2.6 `_bank_change_note` (amber while awaiting, grey after; hidden for investors and signed links), render in `_show.html.erb` Contact & Banking; `_bank_verification.html.erb` "Not verified — bank details changed" (design card ⑦). Comment E19, E20.
- [ ] 2.7 Write `features/core/bank_detail_change_record.feature` (H5, H6, E14–E23, X5) and `features/core/bank_detail_change_emails.feature` (H7, H8, E24–E31, X6).
- [ ] 2.8 UI review: KYC page Contact & Banking card beside `mocks/kyc_show_bank_change.html` and today's `investor_kycs/_show`; emails beside an existing KYC email.
- [ ] 2.9 N+1 check under `PROSOPITE=1` for both features; fix N+1s in this change's code.
- [ ] 2.10 Run both features green (`TEST_ENV_NUMBER=$RANDOM bundle exec cucumber …`), plus `investor_kyc_notification_delivery.feature` as regression, before phase 3.

## 3. Second person

- [ ] 3.1 `InvestorKycPolicy`: `bank_change_maker_blocked?`, `bank_change_only_approver?`, `other_kyc_approver?` (memoised, stop at first), direction-aware `toggle_verified?`, `confirm_bank_details?` with maker block (LLD › Method Contracts, Queries). Comment E32, E38, E39, H11.
- [ ] 3.2 Guard confirmation: `@confirming_verify` → `awaiting_bank_change.confirm!(by:, only_approver:)`; same-save bank change + verify stays unverified (LLD › Method Contracts). Comment H9, H10, E45, X12.
- [ ] 3.3 `InvestorKycsController#toggle_verified`: action-local rescue for a blocked maker with the refusal flash / 403 JSON; `intent=verify` no-op when already verified; set `bank_change_only_approver` (LLD › Controllers). Comment X7, X12.
- [ ] 3.4 `show.html.erb` Verify button: popup when an awaiting change exists, greyed with tooltip for a blocked maker, unchanged otherwise; new `_verify_bank_change_modal` copying `_request_updates_modal` (cards: account, second person or only approver, investor told, bank check status when not passed) (design card ⑦, mocks/verify_bank_change_modal.html). Comment E32–E35, H11.
- [ ] 3.5 `InvestorKycsBulkActionJob`: maker-specific error text for "verify" (design card ⑥). Comment E37.
- [ ] 3.6 `ImportInvestorKyc#save_kyc`: bank-change rows never verify; rows by a blocked maker never verify; `warn_row("Bank details changed — the KYC was left unverified for another approver to verify")` (LLD › Security Detail). Comment E40–E43.
- [ ] 3.7 Write `features/core/bank_detail_change_second_person.feature` (H9–H11, E32–E46) and `features/security/bank_detail_change_second_person.feature` (X7–X12).
- [ ] 3.8 UI review: KYC page header buttons and the popup beside `investor_kycs/_request_updates_modal` and `mocks/verify_bank_change_modal.html`; tooltip on the greyed button.
- [ ] 3.9 N+1 check under `PROSOPITE=1` (bulk verify especially); fix N+1s in this change's code.
- [ ] 3.10 Run both features green, plus `investor_kyc_journey*.feature` and `features/security/bulk_actions_authorization.feature` as regression, before phase 4.

## 4. Bank check name rule

- [ ] 4.1 `BankNameMatch` service (normalise, titles, suffix map, both-direction cover rule, initials, ≥ 1 full word, shorter side ≥ 2 words unless both 1) (design card ⑤). Comment H12–H14, E47–E52.
- [ ] 4.2 `VerifyBankJob`: KYC records use `BankNameMatch` (status "Name needs review: the bank has '<name>'"); Offer/Interest keep `check_details`; stale guard with `with_lock` + reload + compare after the HTTP call (LLD › Transactions, External Integrations). Comment E53, E55, X13, X14.
- [ ] 4.3 Extend the `bank_response` stub helper in `features/step_definitions/kyc_verification.rb` with name / fuzzy parameters (LLD › Test Plumbing). Verify: existing `kyc_verification` scenarios still green.
- [ ] 4.4 Write `features/core/bank_detail_name_match.feature` (H12–H14, E47–E56, X13–X14).
- [ ] 4.5 UI review: no screens changed in this phase beyond the existing badge text (check "Name needs review" fits the badge).
- [ ] 4.6 N+1 check under `PROSOPITE=1`; fix N+1s in this change's code.
- [ ] 4.7 Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/bank_detail_name_match.feature` and the secondaries offer verification features green before phase 5.

## 5. Payout flags, journey warnings and docs

- [ ] 5.1 `DistributionReadinessAgent#verify_bank_details`: also fail for awaiting changes with the spec message (one grouped lookup, `unscope(:order)` before `distinct.pluck`; run once on dev MySQL read-only) (LLD › Queries). Comment H16, E57, X15.
- [ ] 5.2 `CapitalDistributionWarnings#bank_change_warning` (design card ⑧). Comment H15, E58, E59.
- [ ] 5.3 Payments `index.xlsx.axlsx`: last column "Unconfirmed Bank Change" from one grouped hash (Date value) (LLD › Queries). Comment H17, E60.
- [ ] 5.4 `InvestorKycWarnings#bank_change_warning` (design card ⑦). Comment E61.
- [ ] 5.5 Update the investor KYC user guide FAQ (user-guide-faqs skill): why Verify is greyed, who gets emailed, what "Name needs review" means, import warning; lint with UserGuideLint. Verify: lint passes.
- [ ] 5.6 Write `features/funds/bank_detail_change_payout_flags.feature` (H15–H17, E57–E62, X15).
- [ ] 5.7 UI review: distribution journey panel and KYC journey panel warnings beside `workflow_instances/_journey_panel` today.
- [ ] 5.8 N+1 check under `PROSOPITE=1` (payments download with many rows); fix N+1s in this change's code.
- [ ] 5.9 Run `features/funds/bank_detail_change_payout_flags.feature` plus the existing capital distribution journey features green (E62 regression).
- [ ] 5.10 Coverage: list every H/E/X ID in business-rules.md and every `# <ID> —` comment in `features/`; confirm the sets are equal (94 IDs); any new edge case gets a business-rules row and a scenario.
- [ ] 5.11 Run all eight new feature files together with `pcuc -n 4` (check no other pcuc run first) and confirm green.
- [ ] 5.12 QA (not the apply agent): run qa-checklist.md on staging_in and record the sign-off.
