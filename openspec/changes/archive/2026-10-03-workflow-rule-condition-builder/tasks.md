# Tasks

> **Phase gate:** each numbered group below is a phase. A phase's last task is always to run its
> Cucumber feature and get it green. Do not start the next phase until that happens — if it fails,
> fix the phase you're on rather than moving forward and coming back later.

## 1. Field list and Ransack matching (boxes ①②③⑤⑦)

- [x] 1.1 Add the `workflow_rule_fields(extra:, except:, form_type_names:)` macro to `Workflowable`.
      It prepends the `ransackable_attributes(:workflow_rule)` override
      (lld [Method Contracts](lld.md#method-contracts)). Verify in `bin/rails runner`:
      `InvestorKyc.ransackable_attributes(:workflow_rule)` includes `form_type_id` and `json_fields`,
      and `InvestorKyc.ransackable_attributes` does not.
- [x] 1.2 Declare `workflow_rule_fields` on the 7 models with the extras and exclusions in lld
      [File Map](lld.md#file-map). Give `Approval` its base `ransackable_attributes` /
      `ransackable_associations`. Verify `Approval.ransack({title_eq: "x"}).result.to_sql` has the
      predicate.
- [x] 1.3 Add the `json_field_number` ransacker to `WithCustomField`, branching on the adapter
      (lld [Queries and Indexes](lld.md#queries-and-indexes)). Verify `to_sql` on MySQL shows
      `CAST(... AS DECIMAL(20,4))`. Check how `DateField` values are stored in `json_fields`
      (design [Risks](design.md#risks-and-open-questions)); if they are not ISO, add a date cast
      the same way.
- [x] 1.4 Create `WorkflowRuleFields` (`fields`, `field`, `errors_for`, `describe`,
      `to_builder_json`) per design [card ③](design.md#-field-list) and lld
      [Method Contracts](lld.md#method-contracts). Verify with `bin/rails runner` that
      `WorkflowRuleFields.for("InvestorKyc", entity).fields.map(&:label)` lists the expected fields
      for a dev entity.
- [x] 1.5 Create `WorkflowRuleMatcher` with the dropped-condition guard (design
      [card ⑦](design.md#-matcher)). Make `WorkflowAutoAssignmentRule#matches?(record, fields: nil)`
      delegate to it. Remove `evaluate_condition` and `OPERATORS`. Pass one `WorkflowRuleFields` per
      call from `WorkflowAutoAssignmentService` and `WorkflowTemplate#eligible_for?`. Verify that
      `features/core/workflow_auto_assignment.feature` still passes:
      `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/workflow_auto_assignment.feature`.
- [x] 1.6 Replace `conditions_are_valid_json_array` with `conditions_fit_field_list` on
      `WorkflowAutoAssignmentRule` (design [card ⑤](design.md#-save-check)). Verify that the journey
      setup features still seed valid rules:
      `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/investor_kyc_journey_rollout.feature features/fund/capital_call_journey*.feature features/fund/capital_distribution_journey*.feature`.
      Keep `KYC_FORM_TYPE_NAMES` / `kyc_form_type_id` until phase 2 removes the picker.
- [x] 1.7 Write `features/core/workflow_rule_conditions.feature` and
      `features/step_definitions/workflow_rule_conditions_steps.rb` covering **H1, H2, H3, H4, E2,
      E3, E7, E8, X6** (rules set up through model-level `Given` steps; H1's builder part is in phase 2).
      Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/workflow_rule_conditions.feature`
      (Redis up on 6379) and confirm it passes before starting phase 2.

## 2. Rule form builder and rules table (boxes ④⑧)

- [x] 2.1 Controller: drop `kyc_form_type_id`, `with_kyc_form_type` and `kyc_form_types`; set
      `@rule_fields`; turn `JSON::ParserError` into the rule error and keep the raw JSON for
      re-render (lld [Controllers](lld.md#controllers-params-and-responses)). Remove
      `KYC_FORM_TYPE_NAMES` and `kyc_form_type_id` from the model (moved into `WorkflowRuleFields`).
      Verify that `grep -rn "kyc_form_type_id\|KYC_FORM_TYPE_NAMES" app features` lists only
      feature steps to be rewritten in 2.5.
- [x] 2.2 Create `app/javascript/controllers/workflow_rule_conditions_controller.js`: rows, kind-aware
      value inputs (locale-date pair for dates via `locale_date_format.js`), unknown-field rows,
      View as JSON toggle, and serialisation into `conditions_json` (design
      [card ④](design.md#-rule-form)). Verify by hand on `localhost:3001` that a KYC rule built from
      rows saves and reloads.
- [x] 2.3 Rewrite `_form.html.erb`: builder container with
      `data-workflow-rule-conditions-fields-value`, hidden `conditions_json`, help text, and the
      picker removed. Verify that the form renders for a KYC, a capital call and a folder template.
- [x] 2.4 Make `workflow_templates/show.html.erb` describe conditions with one `WorkflowRuleFields`
      (design [card ⑧](design.md#-rules-table)). Verify that the template page shows words, not
      `<code>`.
- [x] 2.5 Update `investor_kyc_journey_rollout.feature` and `investor_kyc_journey_steps.rb`: move the
      E25/E27 rule steps and the "picker + JSON" scenario to the builder. Verify with
      `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/investor_kyc_journey_rollout.feature`.
- [x] 2.6 Write `features/core/workflow_rule_conditions_ui.feature` (`@javascript`) covering **H1
      (builder part), H5, E1, E4, E5, E6, X1, X2, X3, X4, X5**. Run
      `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/workflow_rule_conditions_ui.feature features/core/workflow_rule_conditions.feature`
      and confirm both pass before starting phase 3.

## 3. Docs, project checks and QA

- [x] 3.1 Update `docs/user_guides/workflow_templates_user_guide.md` and
      `docs/user_guides/investor_kyc_user_guide.md`. Replace the JSON / KYC form type picker
      instructions with the builder, and add FAQs (which fields appear, custom fields, amounts in
      currency units, deleted fields, View as JSON) per the user-guide-faqs standard. Verify that
      the UserGuideLint check passes.
- [x] 3.2 Run the MCP ontology drift guard (Approval gained `ransackable_attributes`):
      `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/ai/mcp_server/mcp_ontology.feature`.
      Run `bundle exec rubocop` on the changed Ruby files. Both must be clean.
- [x] 3.3 Run every touched feature together and confirm it is green:
      `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/workflow_rule_conditions.feature features/core/workflow_rule_conditions_ui.feature features/core/workflow_auto_assignment.feature features/core/investor_kyc_journey_rollout.feature`.
- [ ] 3.4 (QA, not the apply agent) Run [qa-checklist.md](qa-checklist.md) on a deployed staging
      build and record the sign-off.
