# Tasks

> **Phase gate:** each numbered group below is a phase. A phase's last task is always to run its
> Cucumber feature and get it green. Do not start the next phase until that happens — if it fails,
> fix the phase you're on rather than moving forward and coming back later.

> **Traceability:** every scenario has a `# <ID> — <Happy path|Edge case|Error case>: …` comment, each feature header links to `openspec/changes/report-builder-starting-points/business-rules.md`, and code comments name the IDs they implement. Redis must be up on 6379.

## 1. Spec validator, applier and fund target (④ ⑤)

- [x] 1.1 `ReportBuilderFundTarget.for(config)`; switch guided setup's `wizard_fund_targets` to it ([design ⑤](design.md#-spec-applier)); verify `features/core/report_builder/wizard.feature` stays green
- [x] 1.2 `ReportSpecValidator.errors_for` over the catalog and column types ([LLD Method Contracts](lld.md#method-contracts))
- [x] 1.3 `ReportSpecApplier.apply!` (transaction, fund placement, joins' model/fk, aggregates, formula keys, GVP rows with formula/pivot positions) and `spec_from`; verify the round trip on report "LPs" in `bin/rails runner` (test env)

## 2. Template file and the template check (② ⑦)

- [x] 2.1 `config/report_builder_templates.yml` with the ten templates ([LLD Template file](lld.md#template-file)); `ReportBuilderTemplates` (load, `available_for`, `find`, `reset!`); `pack_enabled_for?` public; cache reset in the initializer
- [x] 2.2 Write `features/core/report_builder/templates_check.feature` (H12, X1) with `report_builder_starting_steps.rb`. Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/report_builder/templates_check.feature` and fix any template it names before phase 3

## 3. New report menu, template page and create (① ③)

- [x] 3.1 `ReportBuilder::Starting#templates` and `#create_from_template`, routes, `templates.html.erb`, `_template_card`, `_template_modal` ([design ③](design.md#-template-page)); naming rule; refusals and messages from [LLD Controllers](lld.md#controllers-params-and-responses)
- [x] 3.2 Reports page **New report** dropdown; remove "New Custom Report" and "Builder Report"; card menu "Guided setup"; titles "Guided setup" / "New report" (ST2)
- [x] 3.3 Remove `apply_template`, `report_templates`, the route, the builder's Templates button and `#templateModal`, `apply_template_summary`, and the trust Apply Template scenarios and steps (H23, E26 of report-builder-trust)
- [x] 3.4 Write `features/core/report_builder/templates.feature` (H2–H8, E1, E2, E3, E6, E8, X2, X3, X5) and `starting_points.feature` (H1, H11, E7). Run both and confirm they pass before phase 4

## 4. Duplicate (⑥)

- [x] 4.1 `ReportBuilder::Starting#duplicate` (update? on the original, unique "Copy of" name, description, no schedule/undo), route; **Duplicate** on the report card menu and the report page
- [x] 4.2 Write `features/core/report_builder/duplicate.feature` (H9, H10, E4, E5, X4). Run it and confirm it passes before phase 5

## 5. Report check note for fund rows (⑧)

- [x] 5.1 `ReportBuilderHealthCheck#mixed_currencies`: root `Fund` → one info item "The totals row adds funds in INR and USD"
- [x] 5.2 Add E9 to `templates.feature`; run `features/core/report_builder/editor_health.feature` and `templates.feature` and confirm they pass

## 6. Docs and wrap-up

- [x] 6.1 Update `docs/user_guides/report_builder_user_guide.md` (New report, templates and what each answers, fund on create, Duplicate, naming; FAQs per the user-guide standard); run `features/core/user_guide_lint.feature` green
- [x] 6.2 Coverage check: every H/E/X ID in `business-rules.md` has exactly one `# <ID> —` scenario under `features/core/report_builder/`, none without an ID
- [x] 6.3 `bundle exec rubocop` on every touched Ruby file is clean; screenshots of the Reports menu, the template page, the popup (required and optional fund), a created report and a duplicate reviewed against the UI self-review checklist
- [x] 6.4 Run the whole folder `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/report_builder/` and confirm it passes
- [ ] 6.5 (QA, not the apply agent) Run [qa-checklist.md](qa-checklist.md) on a deployed build and record the sign-off
