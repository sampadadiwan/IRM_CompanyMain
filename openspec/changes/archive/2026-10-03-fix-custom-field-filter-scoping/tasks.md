# Tasks

> **Reproduce first.** Phase 1 writes the Cucumber scenarios from the report's Verification
> table that fail against the CURRENT code, and runs them to watch them fail. A bug fix that
> was never seen failing might be fixing nothing.

> **Phase gate:** each numbered group below is a phase. A phase's last task is always to run its
> Cucumber feature and get it green. Do not start the next phase until that happens.

> **Every cucumber run needs a fresh `TEST_ENV_NUMBER`** (unset, runs share one sqlite DB and
> corrupt each other) and **local Redis up on 6379**.

## 1. Reproduce

- [x] 1.1 Add scenarios H1, E1, E2, E3 and X1 from the report's Verification table to
      `features/core/custom_field_filter_search.feature` (new steps in
      `features/step_definitions/custom_field_filter_search_steps.rb`: a filterable NumberField,
      a second company whose user filters, un-ticking **Show in Filter**, `ransackable_attributes`
      with no current user). Run
      `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/custom_field_filter_search.feature`
      and confirm H1, E1, E2 and E3 fail. Record the failure output.

## 2. Fix

- [x] 2.1 `WithCustomField`: replace `_cf_ransacker_names` / `_cf_ransacker_labels` with per-entity
      hashes (names, labels, field types). Make `register_cf_ransacker` take the entity id and
      **replace** that entity's entry. Point the singleton `ransackable_attributes` /
      `human_attribute_name` at `Current.user&.entity_id`'s entry. Add a reader for the
      current entity's names (report: Fix rows 1–2). Verify in `bin/rails runner`: register for
      two entity ids, set `Current.user` to each, and check `ransackable_attributes` lists only
      that entity's names.
- [x] 2.2 Ransacker block: cast with the same adapter-specific CAST as `json_field_number` when
      the current entity's type for the name is NumberField or Money (report: Fix row 3).
      Verify that `to_sql` for `ticket_size_gt` shows `CAST(... AS DECIMAL(20,4)) > ...`.
- [x] 2.3 `WithCustomFieldFilter#register_filterable_ransackers_for`: pass the entity id and the
      deduped fields with their `field_type` (report: Fix row 4). Verify that
      `features/core/custom_field_filter_search.feature` still loads the filter panel.
- [x] 2.4 `WorkflowRuleFields#model_fields`: subtract the current entity's registered names via the
      new reader (report: Fix row 6). Verify with
      `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/workflow_rule_conditions.feature`.
- [x] 2.5 Remove `BaseList#translate_json_fields_params`, its five call sites and
      `WithCustomField.json_fields_query`. Update the comments that cite them in
      `workflow_rule_matcher.rb`, `with_custom_field.rb` and `custom_field_filter_search_steps.rb`
      (report: Fix rows 5, 7, X2). Verify that
      `grep -rn "json_fields_query\|translate_json_fields_params" app lib features` is empty.
- [x] 2.6 Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/custom_field_filter_search.feature`
      and confirm H1, H2, E1, E2, E3 and X1 pass before starting phase 3.

## 3. Regression and cleanup

- [x] 3.1 Run the features that cover the fix and the rule builder together:
      `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/core/custom_field_filter_search.feature features/core/workflow_rule_conditions.feature features/core/workflow_rule_conditions_ui.feature`
      and confirm they are green (E4).
- [x] 3.2 Run the Blast Radius callers' features and confirm they are green: account entries
      (`features/fund/account_entries.feature`), KYC lists
      (`features/core/investor_kyc*.feature`) and
      `features/ai/mcp_server/mcp_ontology.feature`.
- [x] 3.3 Run `bundle exec rubocop` on the changed files and confirm it is clean, including the
      `IRM/RelationBlankPresent` cop.
- [ ] 3.4 (QA, not the apply agent) Run [qa-checklist.md](qa-checklist.md) on a deployed staging
      build and record the sign-off.
