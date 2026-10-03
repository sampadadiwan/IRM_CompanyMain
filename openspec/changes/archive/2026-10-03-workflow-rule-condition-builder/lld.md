# Workflow Rule Condition Builder — Low-Level Design

> **Audience:** The developer who reviews the implementation plan before coding starts.
> **Companion documents:** [Design](design.md) · [Spec](specs/) · [Tasks](tasks.md)

> **Planning phase — no code changes.** This document records the implementation-level decisions
> a reviewing developer must check. It adds to [design.md](design.md): link to its diagrams and
> worked examples rather than repeating them.

---

## Contents

- [Review Summary](#review-summary)
- [File Map](#file-map)
- [Schema Detail](#schema-detail)
- [Method Contracts](#method-contracts)
- [Controllers, Params and Responses](#controllers-params-and-responses)
- [Queries and Indexes](#queries-and-indexes)
- [Transactions, Locking and Concurrency](#transactions-locking-and-concurrency)
- [Background Jobs](#background-jobs)
- [External Integrations](#external-integrations)
- [Error Mapping and Logging](#error-mapping-and-logging)
- [Security Review](#security-review)
- [Configuration and Rollout](#configuration-and-rollout)
- [Test Plumbing](#test-plumbing)
- [Project Rules Checklist](#project-rules-checklist)
- [Sign-off](#sign-off)

---

## Review Summary

- **Matching moves from Ruby to a one-row Ransack `exists?`.** Correctness depends on the
  dropped-condition guard; see [Method Contracts → WorkflowRuleMatcher](#method-contracts) and
  design [card ⑦](design.md#-matcher).
- **Rule-only fields use Ransack's `auth_object`** (`:workflow_rule`) through a prepended
  `ransackable_attributes` override. Check that the override calls `super` with the auth object,
  and that list search never passes `:workflow_rule`. See [Security Review](#security-review).
- **`json_field_number` ransacker** casts per adapter. Check that the MySQL SQL is exactly
  `CAST(json_fields ->> '$.key' AS DECIMAL(20,4))`. See [Queries and Indexes](#queries-and-indexes).
- **Validation moves onto the model** and applies to seeds and Cucumber `Given` steps too. Any
  existing step that writes `gte` / `lte` or an unknown attribute will now fail. See
  [Test Plumbing](#test-plumbing).
- **Removed public API:** `WorkflowAutoAssignmentRule::OPERATORS`, `KYC_FORM_TYPE_NAMES`,
  `#kyc_form_type_id`, and the controller's `kyc_form_types` helper. Grep before deleting.

---

## File Map

| Boundary | File | New / Modified | Responsibility |
|---|---|---|---|
| ① | `app/packs/core/workflow_templates/models/concerns/workflowable.rb` | Modified | `workflow_rule_fields(extra:, except:, form_type_names:)` macro; prepends `ransackable_attributes(auth_object)` override |
| ① | `app/packs/core/investor_kycs/models/investor_kyc.rb` | Modified | `workflow_rule_fields extra: %w[form_type_id], except: %w[PAN bank_account_number ifsc_code address committed_amount call_amount collected_amount distribution_amount], form_type_names: %w[IndividualKyc NonIndividualKyc InvestorKyc]` |
| ① | `app/packs/funds/capital_calls/models/capital_call.rb` | Modified | `workflow_rule_fields extra: %w[manual_generation], except: %w[call_amount collected_amount capital_fee other_fee]` (rollups) |
| ① | `app/packs/funds/capital_distributions/models/capital_distribution.rb` | Modified | `workflow_rule_fields extra: %w[manual_generation], except: %w[updated_at distribution_amount gross_amount]` (rollups) |
| ① | `app/packs/funds/capital_commitments/models/capital_commitment.rb` | Modified | `workflow_rule_fields extra: %w[form_type_id], except: %w[investor_id investor_kyc_id folio_id esign_emails updated_at units_amount_minus_collected foreign_currency_commitment call_amount collected_amount distribution_amount total_units_amount]` |
| ① | `app/packs/misc/approvals/models/approval.rb` | Modified | base `ransackable_attributes` (`approved due_date locked owner_type response_status title`), `ransackable_associations` `[]`, `workflow_rule_fields` |
| ① | `app/packs/core/investors/models/investor.rb` | Modified | `workflow_rule_fields except: %w[investor_access_count unapproved_investor_access_count]` |
| ① | `app/packs/core/folders/models/folder.rb` | Modified | `workflow_rule_fields` (no custom fields) |
| ② | `app/packs/misc/form_custom_fields/models/concerns/with_custom_field.rb` | Modified | `json_field_number` ransacker |
| ③ | `app/packs/core/workflow_templates/services/workflow_rule_fields.rb` | New | Field list, `errors_for`, `describe`, `to_builder_json` |
| ④ | `app/packs/core/workflow_templates/controllers/workflow_auto_assignment_rules_controller.rb` | Modified | Drop picker code; `@rule_fields`; JSON parse error → rule error |
| ④ | `app/packs/core/workflow_templates/views/workflow_auto_assignment_rules/_form.html.erb` | Modified | Builder container + hidden `conditions_json`; picker removed |
| ④ | `app/javascript/controllers/workflow_rule_conditions_controller.js` | New | Row editor, JSON toggle |
| ⑤⑦ | `app/packs/core/workflow_templates/models/workflow_auto_assignment_rule.rb` | Modified | `conditions_fit_field_list`; `matches?(record, fields: nil)` delegates |
| ⑦ | `app/packs/core/workflow_templates/services/workflow_rule_matcher.rb` | New | Ransack translation, guard, `exists?` |
| ⑦ | `app/packs/core/workflow_templates/services/workflow_auto_assignment_service.rb` | Modified | Build one `WorkflowRuleFields` per call, pass `fields:` to `matches?` |
| ⑦ | `app/packs/core/workflow_templates/models/workflow_template.rb` | Modified | `eligible_for?` passes one `fields:` |
| ⑧ | `app/packs/core/workflow_templates/views/workflow_templates/show.html.erb` | Modified | `describe` per condition |
| Docs | `docs/user_guides/workflow_templates_user_guide.md`, `docs/user_guides/investor_kyc_user_guide.md` | Modified | Builder instead of JSON / KYC form type picker; FAQ per user-guide-faqs standard |
| Tests | `features/core/workflow_rule_conditions.feature`, `features/core/workflow_rule_conditions_ui.feature`, `features/step_definitions/workflow_rule_conditions_steps.rb` | New | H/E/X rows |
| Tests | `features/core/investor_kyc_journey_rollout.feature`, `features/step_definitions/investor_kyc_journey_steps.rb` | Modified | E25/E27/picker scenarios use the builder |

**Reviewer checks**
- [ ] Every class in the design's class diagram has a file here, and nothing here is missing from it
- [ ] Files follow the pack layout (`app/packs/<domain>/<sub_domain>/...`) and Packwerk boundaries
- [ ] `grep -rn "kyc_form_type_id\|KYC_FORM_TYPE_NAMES\|WorkflowAutoAssignmentRule::OPERATORS"` is empty after the change

---

## Schema Detail

N/A — no tables or columns change. `workflow_auto_assignment_rules.conditions` keeps `text` + `serialize coder: JSON`.

**Reviewer checks**
- [ ] `db/schema.rb` and `db/schema_test.rb` are untouched by this change

---

## Method Contracts

**`Workflowable.workflow_rule_fields`** (Concern class macro)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `workflow_rule_fields(extra: [], except: [], form_type_names: [name])` | arrays of strings | nil | — | defines `workflow_rule_extra`, `workflow_rule_excluded`, `workflow_rule_form_type_names` class attributes; prepends `ransackable_attributes(auth = nil)` returning `super + extra + JSON_RANSACKERS` when `auth == :workflow_rule` (`JSON_RANSACKERS` only if the model includes `WithCustomField`) | Yes (declared once per class) |

**`WorkflowRuleFields`** (Service)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `.for(workflowable_type, entity)` | `String` (base class name), `Entity` | instance | `ArgumentError` if type not in `WorkflowTemplate::WORKFLOWABLE_TYPE_OPTIONS` | none | Yes |
| `#fields` | — | `Array<Field>` (model group, then Custom fields; each sorted by label) | — | 2 queries, memoised | Yes |
| `#field(key)` | `String` | `Field` or nil | — | — | Yes |
| `#errors_for(conditions)` | any | `Array<String>` ("Condition N: …" or the JSON-shape message) | — | ≤1 `exists?` per reference value | Yes |
| `#describe(condition)` | `Hash` | `String` | — | — | Yes |
| `#to_builder_json` | — | `Hash` (see design contracts) | — | loads reference options | Yes |

`Field = Struct(:key, :label, :kind, :group, :operators, :options, :custom, :ransack_name)`.
`kind ∈ text number date boolean reference option`. `ransack_name` is the attribute for model fields,
`"json_fields"` or `"json_field_number"` for custom ones.

Model-field kind inference: `columns_hash[attr].type` → `:string/:text` text, `:integer/:decimal/:float`
number, `:date/:datetime` date, `:boolean` boolean; a name in `_ransackers` uses
`ransackers[attr].type` (`RansackerAmounts` → number); `form_type_id` / `fund_id` → reference. Any other
`*_id` is excluded.

**`WorkflowRuleMatcher`** (Service)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `.call(rule, record, fields: nil)` | rule, persisted workflowable, optional `WorkflowRuleFields` | `Boolean` | never (rescues `StandardError` → log, false) | 1 `SELECT 1 … LIMIT 1`; log on skip | Yes |

Query shape:

```ruby
search = record.class.base_class.where(id: record.id)
               .ransack(q, auth_object: :workflow_rule)
return false unless search.base.conditions.size == conditions.size # guard
search.result.exists?
```

`q` merges plain keys (`"form_type_id_eq" => "412"`) with `"c" => [...]` groupings built by the same
shape as `WithCustomField.json_fields_query` (attribute name swapped to `json_field_number` for number
kind). `in` / `not_in` values are arrays.

**`WorkflowAutoAssignmentRule`** (Model)

| Method | Arguments | Returns | Raises | Side effects | Idempotent? |
|---|---|---|---|---|---|
| `#matches?(record, fields: nil)` | workflowable | `Boolean` | — | delegates to matcher | Yes |
| validation `conditions_fit_field_list` | — | — | — | `errors.add(:base, msg)` per message | Yes |

**Reviewer checks**
- [ ] Every raised error is handled by a caller or listed in Error Mapping
- [ ] `errors_for` returns the JSON-shape message alone (no per-row messages) when the shape is wrong
- [ ] The guard compares against the number of conditions translated, including grouped `c` entries
- [ ] Anything a retry can repeat is idempotent

---

## Controllers, Params and Responses

| Action | Permitted params | Policy method | Success response | Failure response |
|---|---|---|---|---|
| `WorkflowAutoAssignmentRulesController#new/#edit` | — | `new?` / `edit?` (unchanged) | form with `@rule_fields = WorkflowRuleFields.for(type, current_user.entity)` | — |
| `#create` / `#update` | `workflow_auto_assignment_rule: [:workflowable_type, :priority, :auto_launch, :conditions_json]` | `create?` / `update?` (unchanged) | redirect to template, notice unchanged | 422, form re-rendered with errors and the submitted JSON |

`conditions_json` parse: `JSON.parse` rescue `JSON::ParserError` → keep the raw string for
re-render and add "The JSON is not a valid list of conditions." The same message comes from
`errors_for` when the parsed value is not an array of hashes.

**Reviewer checks**
- [ ] No action without `authorize` / `policy_scope`
- [ ] Permitted params can't set `entity_id`, `user_id` or other ownership fields
- [ ] A 422 re-render keeps the rows the user built (the submitted JSON seeds the builder)

---

## Queries and Indexes

| Where | Query shape | Index used | Rows expected | Preload / batching |
|---|---|---|---|---|
| `WorkflowRuleFields#fields` | `entity.form_types.where(name: names).includes(:form_custom_fields)` | `form_types.entity_id`, `form_custom_fields.form_type_id` | ≤ 10 form types, ≤ 200 fields | `includes` |
| `WorkflowRuleFields` reference validation | `entity.form_types.where(name:, id: ids).count == ids.size`; `entity.funds.where(id: ids).count` | PK + entity | ≤ few | — |
| `WorkflowRuleFields#to_builder_json` | `entity.form_types.where(name:)`, `entity.funds.select(:id, :name)` | entity_id | ≤ 50 funds | — |
| `WorkflowRuleMatcher` | `SELECT 1 FROM <table> WHERE deleted_at IS NULL AND id = ? AND <predicates> LIMIT 1` | PK | 0–1 | — |
| `json_field_number` | MySQL `CAST(json_fields ->> '$.<key>' AS DECIMAL(20,4))`; SQLite `CAST(json_fields ->> '$.<key>' AS REAL)` | none needed (PK-bounded) | — | — |

**Reviewer checks**
- [ ] Every query is scoped by `entity_id` or by the record's PK
- [ ] No `present?` / `blank?` on relations (`IRM/RelationBlankPresent`)
- [ ] The show page builds one `WorkflowRuleFields`, not one per rule

---

## Transactions, Locking and Concurrency

| Operation | Transaction scope | Lock | Race it prevents | Idempotency key |
|---|---|---|---|---|
| Matching in `after_create` / `after_update` | the workflowable's save transaction (existing) | none | — | read-only |

**Reviewer checks**
- [ ] The matcher uses the default connection (sees the uncommitted row)
- [ ] No external HTTP call or email inside a transaction (none added)

---

## Background Jobs

N/A — no jobs or cron entries.

---

## External Integrations

N/A — none.

---

## Error Mapping and Logging

| Exception | Raised in | Handled by | User sees | Logged / alerted |
|---|---|---|---|---|
| `JSON::ParserError` | `rule_params` | controller rescue → rule error | "The JSON is not a valid list of conditions." | — |
| Invalid condition at match time | `WorkflowRuleMatcher` | returns false | record gets the next rule's journey | `warn "[WorkflowRuleMatcher] Rule #{id} skipped for #{Class}##{id}: #{errors.join('; ')}"` |
| Ransack dropped a condition | `WorkflowRuleMatcher` guard | returns false | same | `error "[WorkflowRuleMatcher] Rule #{id}: Ransack applied #{n} of #{m} conditions"` |
| `StandardError` during search | `WorkflowRuleMatcher` | rescue → false | same | `error` with class + message + rule id |
| `ArgumentError` unknown type | `WorkflowRuleFields.for` | validation adds "Workflowable type is not valid" (existing inclusion validation runs first) | form error | — |

**Reviewer checks**
- [ ] No bare `rescue => e` that swallows errors without a log line carrying rule id and record id
- [ ] Log lines carry the ids needed to debug (entity, rule, record)

---

## Security Review

| Concern | Decision |
|---|---|
| Authorization | Unchanged `WorkflowAutoAssignmentRulePolicy` on every action |
| Tenant isolation | Field list built from `current_user.entity` (form) / `rule.entity` (save, match); reference ids validated with `entity.form_types` / `entity.funds` |
| Secrets | none |
| Input / output sanitisation | Labels and values rendered via ERB escaping / `textContent` in JS (never `innerHTML` with values); custom-field keys reach SQL only via quoted ransacker nodes, and only keys present on the entity's forms pass validation |
| Mass assignment | `conditions_json` only; no `entity_id` / `workflow_template_id` permitted (unchanged) |
| Search surface | `:workflow_rule` auth object only passed by `WorkflowRuleMatcher`; `BaseList` and grids call `ransack` without it |

**Reviewer checks**
- [ ] A user from another entity cannot reference that entity's form type, fund or custom field
- [ ] `grep -rn "workflow_rule" app` shows `:workflow_rule` used only by the matcher and the macro

---

## Configuration and Rollout

| Item | Value / location |
|---|---|
| Credentials / env vars | none |
| Feature flag | none (rules sit behind the existing `enable_workflow_templates` permission) |
| Cron / schedules | none |
| Deploy order | code only |
| Rollback | revert the code; stored conditions are the same shape, so old code reads them (Ransack predicate names `gteq` / `lteq` would be unknown to the old matcher; acceptable, since rules are not in production use) |

**Reviewer checks**
- [ ] Safe to deploy with the feature unused, and safe to roll back
- [ ] IN and US need no per-environment config

---

## Test Plumbing

| Feature file | Stubs / fixtures | Factories | New step definitions |
|---|---|---|---|
| `features/core/workflow_rule_conditions.feature` | Redis on 6379 (fund creation) | existing entity, fund, form_type, form_custom_field, investor_kyc, capital_call factories | `Given the KYC forms have the custom field {string} of type {string}`, `Given a rule on {string} with conditions:` (docstring JSON), `When a KYC is created on {string} with {string} = {string}`, `Then the log should mention {string}` |
| `features/core/workflow_rule_conditions_ui.feature` (`@javascript`) | — | same | `When I add the condition {string} {string} {string}`, `When I toggle View as JSON`, `Then the field list should include/exclude {string}`, `Then the rules table should read {string}` |
| `features/core/investor_kyc_journey_rollout.feature` | — | — | E27 step reads the builder's Form type options instead of the picker select; picker+JSON scenario rewritten as builder+JSON |
| `features/core/workflow_auto_assignment.feature` | — | — | none; existing `name eq` / `not_eq` / `category` conditions stay valid. Verify every `Given … with conditions` still passes model validation |

---

## Project Rules Checklist

| Rule | Applies? | How it is met |
|---|---|---|
| No `blank?`/`present?` on relations; use `exists?`/`none?` | Applies | reference checks use `count`/`exists?`; cop run |
| Dedup in SQL (`distinct.pluck`), batch bulk operations (`find_each`/`in_batches`) | N/A | no bulk operations |
| Select only needed columns when loading many `account_entries`; no speculative `includes` of big associations | N/A | `account_entries` untouched; only `form_custom_fields` preloaded |
| Screen dates via `l(...)`; emails render `Mon dd, yyyy` via `EmailDateLocalization`; no human-format `strftime` | Applies | `describe` renders date values with `l(Date.parse(v))` |
| Date inputs use `f.date_field` / `date_field_tag`; JS dates via `locale_date_format.js` | Applies | builder renders the `locale-date` pair (display + hidden ISO) and uses `formatLocaleDate` / `parseDate` |
| Every query entity-scoped; Pundit `authorize`/`policy_scope` on every action | Applies | see Security Review |
| MCP tool surfaces changed only via the ontology YAML (run the ontology drift feature) | Applies (check) | `ransackable_attributes` without auth object is unchanged except `Approval` (no MCP tool for approvals); run `features/ai/mcp_server/mcp_ontology.feature` once |
| Cucumber only (no RSpec); `TEST_ENV_NUMBER=$RANDOM` on every run | Applies | two new features |
| `bundle exec rubocop` clean, including the `IRM/RelationBlankPresent` cop | Applies | run on changed files |

---

## Sign-off

| Reviewer | Date | Decision | Notes |
|---|---|---|---|
| | | | |
