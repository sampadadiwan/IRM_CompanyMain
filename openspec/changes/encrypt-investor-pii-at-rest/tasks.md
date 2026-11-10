# Tasks

> **Phase gate:** each numbered group below is a phase. A phase ends with three tasks, in order:
> (a) **UI review** — when the phase adds or changes screens: screenshot each one next to the
> reference screen named in design.md's *Screen standards* and apply the UI self-review checklist
> (breadcrumbs, lazy tabs, Turbo streams, stats cards, filters, Actions dropdown, tooltips/help,
> full width); (b) **N+1 check** — run the phase's features under Prosopite and fix every N+1 in
> this change's code; (c) run the phase's Cucumber features green. Do not start the next phase
> until all three pass — fix the phase you're on rather than coming back later.

> **Before phase 1:** decisions Q1–Q9 and the 12 [key changes needing approval](proposal.md#key-changes-needing-approval)
> are approved by the user. Every feature file links to
> [business-rules.md](business-rules.md); every scenario carries `# <ID> — <path>`; code comments
> name the IDs of the branches they implement.

## 0. Approval

- [ ] 0.1 Record the user's answers to Q1–Q9 in design.md's Risks and open questions table (Status
      column) and correct any decision (D1–D15) they change; verify: no row says "Awaiting approval".

## 1. Storage, conversion and history (lld: Schema Detail, Method Contracts, Transactions, Configuration and Rollout)

- [ ] 1.1 Write the migration widening the 13 string columns to 255 and converting the 5 JSON columns
      to mediumtext, with a `down` that refuses once ciphertext exists (lld Schema Detail); run it on
      a scratch DB and hand-edit `db/schema.rb` + `db/schema_test.rb`; verify with `git diff db/`
      that only these columns changed.
- [ ] 1.2 Add `attribute … :json` to `KycData` and `AmlReport`, then `encrypts` (deterministic PAN /
      ifsc_code, randomized rest, `support_unencrypted_data: true`) and `normalizes` on `InvestorKyc`,
      `Offer`, `Interest`, `Fee`, `KycData`, `AmlReport`, after the existing `serialize` lines (lld
      Method Contracts); set `extend_queries = true` and fix the "never rotate" comment in
      `config/application.rb`; verify in `rails console` (test env) that a saved KYC's
      `ciphertext_for(:PAN)` differs from its PAN and reads back.
- [ ] 1.3 Add `PiiEncryption::Registry`, `Preflight` and `Conversion` (encrypt / verify / decrypt,
      `with_deleted`, batches read `FOR UPDATE`, `normalize_attribute` before `encrypt`, skip
      already-encrypted values) and `lib/tasks/pii_encryption.rake` with the region guard and
      `EXECUTE` (lld Method Contracts, Transactions); verify a dry run in development prints counts and
      changes nothing.
- [ ] 1.4 Add `PiiEncryption::AuditScrubber` (id slices of 1,000 per auditable type, `select(:id,
      :audited_changes)`) and the `scrub_audits` task; make `AuditTrail` render a `[FILTERED]` pair as
      "<Field> changed (value hidden)" (lld Queries and Indexes); verify on a seeded audit row.
- [ ] 1.5 Write `features/security/investor_pii_encryption.feature` (+ steps in
      `features/step_definitions/investor_pii_encryption_steps.rb`) covering H1–H11, E1–E22, X1–X2
      ([business-rules §1–3](business-rules.md#1-storage-and-tidying--phase-1)).
- [ ] 1.6 UI review: History panel (`AuditTrail`) beside today's History panel on the KYC page; no
      other screen changed in this phase.
- [ ] 1.7 N+1 check: `PROSOPITE=1 TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/security/investor_pii_encryption.feature`,
      then read `log/prosopite.log` (truncate first; never commit); fix every N+1 in this change's code.
- [ ] 1.8 Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/security/investor_pii_encryption.feature`
      (Redis up on 6379; wait on the run's PID, never a pgrep loop) until green before starting phase 2.

## 2. Exact lookups, search guard, search box and reports (lld: Method Contracts, Controllers, Queries and Indexes, External Integrations)

- [ ] 2.1 Add `EncryptedAttributeSearch` and the `ApplicationRecord.ransack` / `ransack!` wrapper;
      `rescue_from EncryptedAttributeSearch::Refused` in `ApplicationController` (HTML redirect without
      `q` + flash, turbo flash stream, JSON 422) and the `generate_all_docs` redirect (lld Controllers,
      Error Mapping); verify `/investor_kycs?q[PAN_cont]=A` shows the PAN message.
- [ ] 2.2 Return `:encrypted_exact` / `:encrypted_presence` from `ransack_filter_attribute_types` and
      limit predicate options in `filter_controller.js`; add "(exact match only)" in
      `ReportPrompt.all_ransackable_attributes`; set `searchable: false` on PAN / bank / IFSC in
      `offer_dashboard.rb` and `interest_dashboard.rb`; verify by picking PAN in the KYC filter panel.
- [ ] 2.3 Add `PiiSearchFingerprint`; replace `PAN` / `bank_account_number` fields with keyword
      `pan_fp` / `bank_fp` in `InvestorKycIndex` and `OfferIndex`; add the fingerprint `term`s in
      `KycSearch`, `OfferSearchService` and `OffersController#search`; add the ⓘ hint via
      `SearchComponent` on KYCs and Offers (lld External Integrations); verify after
      `InvestorKycIndex.reset!` that a full PAN finds the KYC in development.
- [ ] 2.4 Report builder: `ReportBuilderColumnType#encrypted?` / `#allowed_aggregates`;
      `ReportBuilderChildAggregator#read_value` uses `deserialize` for encrypted attributes and renders
      a stored min/max/sum/avg/list as Value; exclude encrypted columns from pivot categories and
      `ReportBuilderQueryEngine#apply_sort`; tooltip in `_column_menu` and `wizard/aggregates` (lld
      Method Contracts); verify a commitments report with related PAN shows plaintext.
- [ ] 2.5 Write `features/core/investor_kyc_pii_lookups.feature` covering H12–H23, E23–E42, X3–X6
      ([business-rules §4–6](business-rules.md#4-exact-lookups--phase-2)) and
      `features/core/report_builder/encrypted_columns.feature` covering H24–H25, E43–E48, X7
      ([§7](business-rules.md#7-reports--phase-2)).
- [ ] 2.6 UI review: KYC list filter panel + flash, Offers search ⓘ, report builder column menu —
      each beside its current screen (design *Screen standards*); no layout differences besides the
      message and tooltips.
- [ ] 2.7 N+1 check: `PROSOPITE=1 TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/investor_kyc_pii_lookups.feature features/core/report_builder/encrypted_columns.feature`;
      read `log/prosopite.log`; fix every N+1 in this change's code.
- [ ] 2.8 Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/investor_kyc_pii_lookups.feature features/core/report_builder/encrypted_columns.feature`
      until green, then re-run the existing `features/core/report_builder/` and
      `features/security/secondaries_isolation.feature` to confirm no regression, before starting phase 3.

## 3. Raw readers, regions and developer copies (lld: Background Jobs, Security Detail, Configuration and Rollout)

- [ ] 3.1 `FmQueryScope`: explicit column list minus `encrypted_attributes` for allowed tables;
      `FmRunQueryTool#validate` refuses SQL naming an encrypted column with the not-available message;
      one prompt line in `FmCsChatProvider` (lld Security Detail); verify the existing
      `features/customer_support_agent/fm_user_chat.feature` still passes.
- [ ] 3.2 Add `PiiEncryption::SqliteDecryptor` and call it from `EntityDbDumpJob#process_entity_dump`
      after the script (lld Background Jobs); verify `features/misc/entity_db_dump.feature` still passes.
- [ ] 3.3 Add `PiiEncryption::DevCopyScrubber` + `scrub_dev_copy` task (refuses outside a development
      DB); add the pre-flight `OTHER_REGION_FP` check; verify a dry run in development prints counts.
- [ ] 3.4 Docs: `docs/operations/prod_restore.md` step 4b (scrub), `docs/operations/dr/dr_guide.md`
      (verify + re-run conversion after restore), and a rollout runbook section (pre-flight → deploy 1 →
      encrypt → verify → purge binlogs → reindex → +7 d scrub_audits → deploy 2; rollback with
      `decrypt`) (lld Configuration and Rollout); verify every command in the runbook exists in
      `pii_encryption.rake`.
- [ ] 3.5 Write `features/security/investor_pii_raw_readers.feature` covering H26–H30, E49–E53,
      X8–X12 ([business-rules §8–9](business-rules.md#8-raw-database-readers--phase-3)).
- [ ] 3.6 UI review: no screens changed in this phase (chatbot reply text only).
- [ ] 3.7 N+1 check: `PROSOPITE=1 TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/security/investor_pii_raw_readers.feature`;
      read `log/prosopite.log`; fix every N+1 in this change's code.
- [ ] 3.8 Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/security/investor_pii_raw_readers.feature`
      until green before starting phase 4.

## 4. Coverage, close-window code and hand-over

- [ ] 4.1 Prepare deploy 2 as a separate commit/branch: drop `support_unencrypted_data: true` from
      every `encrypts` and `extend_queries` from `config/application.rb`; verify X2 still passes with
      the window closed and all four features pass.
- [ ] 4.2 Coverage: list every H/E/X ID in business-rules.md (95) and every `# <ID> —` comment in
      F1–F4; confirm the two sets are equal; every spec scenario appears in a Spec scenario cell.
- [ ] 4.3 Run `bundle exec rubocop` on changed files, `bundle exec brakeman -q` and
      `bundle exec bundle-audit check`; verify no new findings.
- [ ] 4.4 Run all four features together with `pcuc -n 4` (or serially) and confirm green.
- [ ] 4.5 Hand over the per-region rollout (ops, not the apply agent): staging.in rehearsal, then
      production.in, then production.us, each per design [Rollout per region](design.md#rollout-per-region),
      recording key fingerprints, counts and timings in the rollout log; confirm US EBS / S3 encryption
      status with `aws:ebs_status[production.us]`.
- [ ] 4.6 QA runs [qa-checklist.md](qa-checklist.md) on staging.in after deploy 1 and again after
      deploy 2, and records the sign-off (QA task, not for the apply agent).
