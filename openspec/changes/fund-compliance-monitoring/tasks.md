# Tasks

> **Phase gate:** each numbered group below is a delivery phase. A phase's last task is always to
> run its Cucumber features and get them green, then commit that phase as its own commit on
> `feature/fund-compliance-monitoring`. Do not start the next phase until that happens — if it
> fails, fix the phase you're on rather than moving forward and coming back later.

> **How every Cucumber run in this file is launched (read once, applies to every "run" task):**
> - Do **not** use `pcuc` — other sessions run it on workers 1–4 and it cannot be offset.
> - First check nothing else is using our numbers: `ps -eo pid,args | grep "[b]in/parallel_cucumber -n"`
>   (note the workers' numbers) and `ls /dev/shm/test_412*` (stale files from our own earlier runs are fine; a live process using them is not — `fuser /dev/shm/test_412*`).
> - Redis must be up on 6379.
> - Launch up to **4 background processes**, each with its own number from the reserved block
>   **41201–41204** and its own distinct set of feature files:
>   `TEST_ENV_NUMBER=41201 bundle exec cucumber <files A>` · `TEST_ENV_NUMBER=41202 … <files B>` · …
>   (run each with `run_in_background`; read results on notification).
> - **No code edits while a run is live** (test mode loads lazily; mixing old and new code fails scenarios).
> - Phase 1 runs exclude Phase 4 scenarios with `--tags 'not @phase4'`.

> **Traceability (every phase):**
> - Every H/E/X row in [business-rules.md](business-rules.md) has exactly one scenario, with a comment directly above it:
>   `# H20 — Happy path: …` / `# E31 — Edge case: …` / `# X18 — Error case: …`. Feature headers link `openspec/changes/fund-compliance-monitoring/business-rules.md`.
> - Code names the IDs of the paths it implements: `# Worked examples H20, X18 — openspec/changes/fund-compliance-monitoring/business-rules.md`.
> - An edge case found during apply gets a new business-rules row AND a scenario, never a scenario alone.

> **Standing rules:** after any local `db:migrate`, restore `db/schema.rb` / `db/schema_test.rb`
> from git, hand-insert the new tables, run `db:clean_schema` (local DB drifts); `unscope(:order)`
> before any `distinct` (SQLite hides MySQL errors); no `blank?`/`present?` on relations;
> `bundle exec rubocop` clean on touched files.

---

## 1. Phase 1 — Limits, document checks, register, roles, digest, export, SEBI pack

**Schema and models** (LLD › Schema Detail, Method Contracts)

- [ ] 1.1 Create `app/packs/funds/compliance/package.yml` (deps: core, funds) and the pack folders; verify `bin/packwerk validate` passes.
- [ ] 1.2 Migration for the 10 Phase-1 tables (`compliance_packs`, `compliance_pack_versions`, `fund_compliance_packs`, `compliance_entity_setups`, `compliance_requests`, `compliance_runs`, `compliance_results`, `compliance_register_items`, `compliance_duties`, `document_signoffs`) with every index/UK from LLD › Schema Detail; migrate locally, then fix `schema.rb`/`schema_test.rb` per the standing rule; verify `RAILS_ENV=test bin/rails db:schema:load` succeeds.
- [ ] 1.3 Models with associations, validations, `attr_readonly :entity_id`, same-firm parent validations, `Trackable` (not on results), status guards: `CompliancePack`, `CompliancePackVersion` (`publish!`, `applies_to?`, `in_transition?`; edits clear `tested_at`), `FundCompliancePack`, `ComplianceEntitySetup` (`reference_list(key, on:)` honouring inclusive `valid_from`/`valid_to`), `ComplianceRequest`, `ComplianceRun`, `ComplianceResult` (readonly after create except `superseded_reason` once), `ComplianceRegisterItem` (`open_key`), `ComplianceDuty`, `DocumentSignoff`; verify in `bin/rails runner` that a result update raises and a second open item for the same check violates the UK.
- [ ] 1.4 Append `compliance_edit`, `compliance_approve` to `UserEnabled.extended_permissions` (end of list); verify existing flag bit positions unchanged (`User.new.extended_permissions` round-trip in runner).

**Library and engine** (LLD › Definition JSON, Queries and Indexes)

- [ ] 1.5 `ComplianceDataCatalog` with Phase-1 sources (fund, commitments, remittances/payments, distributions, portfolio_investments, valuations, investors, investor_kycs, documents + signature status) and allow-listed fields incl. custom fields; no `account_entries`; verify `ComplianceDataCatalog.field?("portfolio_investments","cost")` true and an unknown field false.
- [ ] 1.6 `ComplianceDefinitionValidator` (unknown key/source/field/op, cycles, limit units/currency, applies_to ⊆ classifications, event duty `from` required, override policy values); verify against the SEBI JSON fixture (valid) and a broken copy (errors name the key).
- [ ] 1.7 `ComplianceMeasureQuery` (sum/count/count_distinct/max/min/expr; group_by; filters; as-of date column; percentages rounded to 2 dp at comparison per decision R14 in decisions-and-assumptions.md; missing input → `missing`) using Arel only; verify on dev MySQL (port 3306 dev DB, read-only queries) that the corpus figure equals `CorpusDetailsJob`'s for one fund.
- [ ] 1.8 `ComplianceDocumentCheckQuery` (record has document by mapped tag/name/folder; signed via e-sign completion or `document_signoffs`; signed date ≤ record date; record filters e.g. buys only; "checks from" date; failing list ≤ 500 + count); verify on MySQL with `EXPLAIN` that it is one query.
- [ ] 1.9 `ComplianceCheckEvaluator` (limit / record_document / manual; overrides; tested `continuous` vs `on_record`; transition → warning; could-not-check reasons incl. missing start date R4; rescue → could_not_check) with ID comments; verify via runner on a seeded fund.
- [ ] 1.10 `ComplianceVersionMover` (A/B/C applicability in the pack's time zone; early adoption; overrides kept/dropped/archived with the strictness boundary; `check_removed` closes; correction versions supersede results and close `pack_corrected`; "Published late"); verify via runner with v1/v2/v2.1 fixtures.
- [ ] 1.11 `ComplianceRunOperation` (`step :` pipeline per LLD, one transaction, repeatable-read snapshot on MySQL, `left :mark_failed`), `ComplianceDutyScheduler` (schedule + event duties, period basis, calendar days, mid-period attach, default owner, bulk `insert_all`), register updates (open/clear/worsen/escalate fix-by); verify a full run on the shared-setup fund produces the dashboard figures in the proposal (26.67%, ₹2.25 cr vs ₹2.10 cr).
- [ ] 1.12 `ComplianceScheduleJob` (hourly; local hour 02 runs, 08 digest; `monitoring_enabled`; deactivated-user returns R12) and `ComplianceFundRunJob` (idempotent nightly UK; Run now waits on in-flight run); register the cron in `config/initializers/sidekiq.rb` beside `WorkflowEvaluateJob`; verify `Sidekiq::Cron::Job.find('ComplianceScheduleJob')` in a non-local env config and a double perform creates one run.

**People, policies, screens** (LLD › Controllers, Security Detail)

- [ ] 1.13 `ComplianceRequestDecide` operation (approver ≠ requester; company admin may approve; single-eligible-user self-approval labelled; payload applied in the same transaction; classification/override/disable/detach/explanation/early adoption); verify each kind via runner.
- [ ] 1.14 Policies (`CompliancePackPolicy`, `CompliancePackVersionPolicy`, `FundCompliancePackPolicy`, `ComplianceEntitySetupPolicy`, `ComplianceRequestPolicy`, `ComplianceRegisterItemPolicy`, `ComplianceDutyPolicy`, `ComplianceRunPolicy`, `DocumentSignoffPolicy`, `ComplianceExportPolicy`) with parent-policy delegation and `Scope` (investors/advisors → `none`); verify `bundle exec rubocop` and that no controller excludes `verify_authorized`.
- [ ] 1.15 Routes (`config/routes/compliance.rb`) and controllers per LLD › Controllers (packs, versions incl. preview/publish, fund packs incl. attach/run now/preview, setup, requests, register, duties, dashboard, signoffs, exports) with strong params from LLD; verify `bin/rails routes | grep compliance` matches the LLD table.
- [ ] 1.16 Views reusing existing styling (stat cards, `badge bg-X-subtle text-X`, ag-grid/tables, Bootstrap modals with action-summary cards, Turbo frames): Compliance home, fund Compliance tab (grouped by pack, run health banner, version banner/preview), register + detail with working, setup (funds grid, inputs, reference lists with dates, owners/roles, monitoring), packs (Rule Library for super admin, entity packs), duties, "Mark signed (wet ink)" on document rows, export; company menu entry; dates via `l(...)`, date inputs via `f.date_field`; verify each screen renders in the dev app with seeded data (screenshot).
- [ ] 1.17 Notifiers `< BaseNotifier` (digest, assignment, approval request, decision, escalation, run failed, version published / coming into effect) + `ComplianceDigestJob` (quiet days send nothing; grouped bulk lines; facts age) + `ComplianceRegisterExportJob` (Excel/PDF; "Computed on data as entered at run time"; access re-checked); recipients from `Compliance` tag / roles only; verify mail previews render with `Mon dd, yyyy` dates.
- [ ] 1.18 SEBI pack content `db/seeds/compliance/sebi_aif_v1.json` (checks 1–6, 8–10 per proposal; check 7 as manual duty until Phase 3; Cat III NAV source unresolved → could-not-check) and `lib/tasks/compliance.rake` `compliance:load_pack[path]` (dry-run default, `EXECUTE=1`); verify a dry-run prints the pack summary and validator result.
- [ ] 1.19 Shared Cucumber setup `features/step_definitions/compliance/compliance_setup_steps.rb` building business-rules › Shared setup (Horizon, Delta, Solo Capital, users, funds, investees, IC notes, reference lists, SEBI v1/v2/v2.1 fixtures); grep existing step text first (dry-run misses ambiguous steps).

**Features** (one scenario per ID, ID comment above each)

- [ ] 1.20 Write `features/compliance/rule_library.feature` — H1–H10; E1–E7; X1–X10.
- [ ] 1.21 Write `features/compliance/fund_pack_setup.feature` — H11–H12, H14–H18; E9–E17; X14–X17 (H13, E8 tagged `@phase4`, added in Phase 4).
- [ ] 1.22 Write `features/compliance/compliance_runs.feature` — H19–H23; E18–E30; X24, X26–X29 (H24, X25 tagged `@phase4`, added in Phase 4).
- [ ] 1.23 Write `features/compliance/compliance_register.feature` — H25–H26; E31–E40; X31–X32.
- [ ] 1.24 Write `features/compliance/manual_duties.feature` — H27–H28; E41–E44; X33.
- [ ] 1.25 Write `features/compliance/notifications_digest.feature` — H29–H31; E45–E47.
- [ ] 1.26 Write `features/compliance/sebi_aif_pack.feature` — H32–H36; E48–E56; X37–X38.
- [ ] 1.27 Write `features/compliance/pack_versions.feature` — H46–H53; E80–E102; X50–X53, X56, X58–X59.
- [ ] 1.28 Write `features/compliance/changes_over_time.feature` — H54–H61; E103–E135; X62–X63, X67.
- [ ] 1.29 Write `features/security/compliance_tenant_isolation.feature` — X11–X13, X18–X23, X30, X34–X36, X54–X55, X57, X60–X61, X64–X66 (other firm refused, owner allowed, direct request refused, investor refused).
- [ ] 1.30 Phase 1 review: re-read the diff against design.md cards ①–⑦ ⑨, LLD Security Detail and Pattern Conformance; run `bundle exec brakeman -q --no-pager` and `bundle exec bundle-audit check` (no new warnings), `bundle exec rubocop` on changed files, `bin/packwerk check`; fix findings; record any decision in decisions-and-assumptions.md.
- [ ] 1.31 Run the Phase 1 features (tasks 1.20–1.29) with the launch rules above, split across `TEST_ENV_NUMBER` 41201–41204 with `--tags 'not @phase4'`, until all are green; then commit Phase 1 as its own commit ("Compliance Phase 1: limits, document checks, register, SEBI pack").

## 2. Phase 2 — Describe in words (AI drafting)

- [ ] 2.1 Migration for `compliance_check_drafts`; schema files per the standing rule; verify `db:schema:load` in test.
- [ ] 2.2 `ComplianceCheckDraft` model + `ComplianceCheckDrafter` (`app/packs/ai/compliance`) using `LlmService.ruby_llm_chat(entity:)` with `with_schema`; prompt sends sentence as quoted data, catalogue field list, entity input names, few-shot from the entity's own checks only; output validated by `ComplianceDefinitionValidator`; unmappable → manual duty; ambiguous → "Assumed" line; verify with a stubbed `LlmService` in runner.
- [ ] 2.3 `ComplianceCheckDraftJob`; drafting switch in `ai_settings` (off → "Describe in words is unavailable — use the form"); provider error/timeout → "Drafting failed — try again or use the form"; verify both paths via runner with stubs.
- [ ] 2.4 `ComplianceCheckDraftPolicy`, routes, `ComplianceCheckDraftsController` (create/update/test/save; Save only when tested since last edit; provenance on save) and the Describe-in-words modal (existing modal styling); verify in the dev app with a stub.
- [ ] 2.5 Write `features/compliance/ai_check_drafting.feature` — H37–H39; E57–E63; X39–X42 (LlmService stubbed); extend `features/security/compliance_tenant_isolation.feature` — E64–E65; X43.
- [ ] 2.6 Phase 2 review (card ⑧ drafting, Security item 8 AI rules, brakeman/rubocop/packwerk), then run the Phase 2 features plus `features/compliance/rule_library.feature` as a regression with the launch rules above until green; commit Phase 2 as its own commit.

## 3. Phase 3 — Document-content checks (AI reading)

- [ ] 3.1 Migration for `document_readings`, `document_facts`; schema files per the standing rule; verify `db:schema:load` in test.
- [ ] 3.2 `DocumentReading`, `DocumentFact` (`confirm!`, edits audited, value types) and `DocumentFactReader` (text via `FolderDocumentExtractor` helpers; `with_schema`; quotes + pages; not-found facts; document text as untrusted data); verify with a stub on a sample PDF.
- [ ] 3.3 `DocumentFactReadJob` triggered on upload/replace of a mapped document and on a version adding a fact (`facts_signature`); opt-in per input and monthly cap (default 200) in `ai_settings`; capped → queued + digest line; verify cap boundary via runner.
- [ ] 3.4 `ComplianceFactSource` in the catalogue (confirmed facts only; unconfirmed → needs review; facts follow the document); `content` check kind in validator/evaluator (amount, dates, quorum against dated IC list, conflicts, company match, excluded sector, associates, land-border, investor groups); move SEBI check 7 from manual duty to a content check in a new SEBI pack version JSON (`sebi_aif_v1_1.json`, applicability all); verify the Orbit Health example gives ₹3.00 cr over.
- [ ] 3.5 `DocumentFactPolicy`, routes, `DocumentFactsController` (index/update/confirm) and the Facts-to-confirm screen; kind-4 duties get AI notes; digest "facts waiting N days"; verify in the dev app with a stub.
- [ ] 3.6 Write `features/compliance/document_content_checks.feature` — H40–H45; E66–E79; X44–X47 (`DocumentFactReader` stubbed); extend `features/security/compliance_tenant_isolation.feature` — X48–X49.
- [ ] 3.7 Phase 3 review (card ⑧ reading, Security items 7–8, prompt-injection fixture in a document, brakeman/rubocop/packwerk), then run the Phase 3 features plus `compliance_runs.feature` and `sebi_aif_pack.feature` as regression with the launch rules above until green; commit Phase 3 as its own commit.

## 4. Phase 4 — IFSCA pack and currency

- [ ] 4.1 Currency in `ComplianceMeasureQuery`/`ComplianceCheckEvaluator`: amount limits carry a currency; convert with `FxRateResolver` at the run date; rate and arithmetic in `working`; missing rate → "Could not check — missing: INR/USD rate for <date>"; verify H24 arithmetic (1,20,00,000 ÷ 83.00 = USD 144,578) via runner.
- [ ] 4.2 IFSCA pack content `db/seeds/compliance/ifsca_fm_v1.json` (Venture Capital / Restricted / Retail Scheme; minimum investment, investor count, manager contribution — figures marked for counsel) loaded with `compliance:load_pack`; verify the dry-run validates.
- [ ] 4.3 Add the `@phase4` scenarios: `fund_pack_setup.feature` — H13; E8; `compliance_runs.feature` — H24; X25.
- [ ] 4.4 Final coverage task: list every H/E/X ID in business-rules.md and every `# <ID> —` comment under `features/`; confirm the two sets are equal (263 IDs) and every code ID comment points at an existing row; fix any gap with a row + scenario.
- [ ] 4.5 Phase 4 review (brakeman/bundle-audit/rubocop/packwerk; decisions log updated), then run **all** compliance features (`features/compliance/*.feature`, `features/security/compliance_tenant_isolation.feature`) split across 41201–41204 with the launch rules above until green; commit Phase 4 as its own commit.
- [ ] 4.6 (QA, not the apply agent) Run [qa-checklist.md](qa-checklist.md) on a deployed staging build and record the sign-off.
