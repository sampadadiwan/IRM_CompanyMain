# PRD: Model Validation Rule Engine

## 1. Overview

A configurable rule engine that evaluates warnings and blockers against model records before save. Rules fire in real-time (on field change) and on explicit save. A modal surfaces all triggered rules at once. Initially targets `Valuation`, extensible to `AllocationRun` and `FundRatio`.

---

## 2. Goals

- Allow `company_admin` users to configure per-entity validation rules via UI
- Ship default rules per model, seeded per-entity via idempotent rake task
- Support multi-field AND/OR conditions with configurable thresholds
- Two severity levels: **Warning** (user must confirm to proceed) and **Blocker** (user must fix before saving)
- Do not break existing save flows — rules are additive

---

## 3. Core Concepts

| Concept | Description |
|---|---|
| **Rule** | Named definition: model target, condition tree, severity, message template |
| **RuleOverride** | Entity-scoped override: disables a rule or replaces threshold params |
| **RuleEvaluation** | Transient result of running rules against a record — not persisted |

---

## 4. Data Model

### `validation_rules` table

| Column | Type | Notes |
|---|---|---|
| `id` | bigint PK | |
| `entity_id` | bigint FK | NULL = global default rule |
| `target_model` | string | `"Valuation"`, `"AllocationRun"`, `"FundRatio"` |
| `name` | string | Human-readable, unique per entity+model |
| `description` | text | Shown in admin UI |
| `condition_tree` | jsonb | AND/OR tree of field conditions (see below) |
| `severity` | string | `"warning"` or `"blocker"` |
| `message_template` | string | ERB-style, e.g. `"Date %{valuation_date} is not quarter-end"` |
| `enabled` | boolean | Default `false`; rules with `true` fire for all entities; entities opt out via an override with `enabled: false` |
| `is_default` | boolean | `true` if seeded by rake task |
| `created_by_id` | bigint FK → users | |
| `created_at` / `updated_at` | datetime | |

### `validation_rule_overrides` table

| Column | Type | Notes |
|---|---|---|
| `id` | bigint PK | |
| `validation_rule_id` | bigint FK | Points to the global default rule |
| `entity_id` | bigint FK | The tenant overriding it |
| `enabled` | boolean | Can disable a default rule |
| `param_overrides` | jsonb | Replaces specific threshold values (e.g. `{ "pct_threshold": 100 }`) |
| `message_override` | string | Optional custom message |
| `created_by_id` | bigint FK → users | |
| `created_at` / `updated_at` | datetime | |

### `condition_tree` jsonb schema

```json
{
  "op": "AND",
  "conditions": [
    {
      "field": "valuation_cents",
      "op": "pct_change_gt",
      "param": "pct_threshold",
      "compare_to": "context.prev_valuation_cents"
    },
    { "field": "valuation_date", "op": "not_quarter_end" }
  ]
}
```

Fields prefixed with `context.` are resolved from the ContextProvider output. Fields without a prefix are resolved directly from the record's attributes.

Supported `op` values (first pass):

| Op | Description |
|---|---|
| `not_quarter_end` | Date is not last day of Mar/Jun/Sep/Dec |
| `pct_change_gt` / `pct_change_lt` | % change vs comparison field exceeds threshold |
| `lt` / `gt` / `eq` / `blank` | Simple scalar comparisons |
| `AND` / `OR` | Node-level nesting |

---

## 5. Rule Resolution Order

When evaluating rules for a record with `entity_id = E`:

1. Load all global default rules for `target_model` where `entity_id IS NULL`
2. For each, check if a `ValidationRuleOverride` exists for entity E:
   - If override exists → use `override.enabled` (entity can enable or disable)
   - If no override → use `rule.enabled` (rules with `enabled: true` fire for all entities automatically)
   - If override has `param_overrides` → merge params into condition evaluation
3. Load entity-specific rules where `entity_id = E` (custom rules, not overrides)
4. Evaluate all active rules — collect results

---

## 6. Condition Evaluation Context

### Context Providers

Each `target_model` registers a **ContextProvider** class responsible for building the evaluation context. Rules reference named context keys in their `condition_tree`; the provider knows how to compute them. Complexity lives in Ruby code — rules stay declarative in the database.

```ruby
class ValuationRuleContextProvider
  # Returns a hash of named context values available to condition_tree fields
  def call(record:, entity:)
    {
      prev_valuation_cents:  fetch_prev_valuation(record),
      rolling_avg_4q_cents:  compute_rolling_avg(record, quarters: 4),
      fund_nav_cents:        fetch_fund_nav(record)
    }
  end
end
```

The registry maps model names to provider classes:

```ruby
CONTEXT_PROVIDERS = {
  "Valuation"     => ValuationRuleContextProvider,
  "AllocationRun" => AllocationRunRuleContextProvider,
  "FundRatio"     => FundRatioRuleContextProvider
}.freeze
```

To support a new context key for a model, add it to that model's provider class and deploy — no schema changes required.

### Context object passed to each rule evaluator

| Key | Description |
|---|---|
| `record` | The record being saved (unsaved changes applied) |
| `context` | Hash returned by the model's ContextProvider |
| `params` | Resolved params (rule defaults merged with any override) |
| `entity` | The tenant record |

### Built-in context keys by model

**Valuation**

| Key | Description |
|---|---|
| `prev_valuation_cents` | Most recent valuation for same `investment_instrument_id` where `valuation_date < current` |
| `rolling_avg_4q_cents` | Average of last 4 quarterly valuations for the same instrument |

**AllocationRun**

| Key | Description |
|---|---|
| `prev_run_date` | Date of the most recent prior allocation run for the same fund |

**FundRatio**

| Key | Description |
|---|---|
| `prev_ratio_value` | Most recent prior `FundRatio.value` for the same fund and form type |

---

## 7. Default Rules (seeded via rake task)

### Valuation

| Name | Condition | Default Severity | Default Params |
|---|---|---|---|
| `valuation_date_not_quarter_end` | `valuation_date` not quarter-end | Warning | — |
| `valuation_large_increase` | % increase vs prev > threshold | Warning | `pct_threshold: 50` |
| `valuation_large_decrease` | % decrease vs prev > threshold | Warning | `pct_threshold: 50` |

### AllocationRun

| Name | Condition | Default Severity |
|---|---|---|
| `allocation_run_date_not_quarter_end` | Run date not quarter-end | Warning |
| `allocation_run_locked` | Record already locked | Blocker |

### FundRatio

| Name | Condition | Default Severity |
|---|---|---|
| `fund_ratio_date_not_quarter_end` | `created_at` date not quarter-end | Warning |
| `fund_ratio_value_out_of_range` | Absolute value < min or > max | Warning |

---

## 8. Rake Task

```bash
rails rules:seed_defaults[entity_id]   # seed one tenant
rails rules:seed_defaults              # seed all entities
```

Behaviour:
- Upserts global default rules keyed on `name` + `is_default: true` + `entity_id: nil`
- Syncs the `enabled` flag on every run so `DEFAULT_RULES` stays the authoritative source
- Does **not** touch existing `validation_rule_overrides` (respects tenant customisation)
- Idempotent — safe to re-run on deploy

---

## 9. Backend: Service & API

### `ValidationRuleEvaluator` service

```ruby
ValidationRuleEvaluator.call(record:, entity:, context: {})
# => [{ rule:, severity:, message: }, ...]
```

- Called from controller before save (explicit save endpoint)
- Called from a dedicated `POST /validation_rules/evaluate` endpoint for real-time checks

### Real-time endpoint

```
POST /api/v1/validation_rules/evaluate
Body:    { target_model: "Valuation", record_id: null|123, attributes: { ... } }
Returns: { warnings: [...], blockers: [...] }
```

Frontend calls this on field blur (debounced 400ms). `record_id` is null for new records.

### Save flow (controller)

1. Build/update record from params (do not save yet)
2. Call `ValidationRuleEvaluator`
3. If blockers present AND `force_save` param not set → return 422 with rule results
4. If warnings present AND `force_save` param not set → return 200 with `{ requires_confirmation: true, results: [...] }`
5. Frontend shows modal; user confirms → re-POST with `force_save: true`
6. With `force_save: true` → skip warnings, still enforce blockers

---

## 10. Frontend UX

### Real-time

- On field blur (debounced 400ms): call evaluate endpoint
- Inline field-level indicators under affected fields (yellow = warning, red = blocker)
- Non-blocking — user can continue editing

### On Save modal

Single modal collects all triggered rules:

| State | Modal content | Actions |
|---|---|---|
| Blockers only | Red list with explanations | "Go Back" only |
| Warnings only | Yellow list with explanations | "Confirm & Save" / "Cancel" |
| Both | Red blockers first, then yellow warnings | "Go Back" only (must fix blockers first) |

---

## 11. Admin UI (company_admin)

Route: **Settings > Validation Rules**

Features:
- List rules for the entity — globals shown with "Default" badge, entity-specific with "Custom" badge
- Toggle enabled/disabled on default rules
- Edit threshold params on default rules (stored as `param_overrides`)
- Override message text on default rules
- Create new custom rules with a condition builder (field → operator → value, AND/OR grouping)
- Set severity (warning/blocker) and message per custom rule

---

## 12. Extensibility Contract

To add rules for a new model:

1. Add entries to the `DEFAULT_RULES` registry (constant or YAML) for that model
2. Implement a `ContextProvider` class for that model and register it in `CONTEXT_PROVIDERS`
3. Add any new context keys to the provider and any new `op` types to the condition evaluator if needed
4. Add the model to the rake task model list
5. Wire the evaluate call into that model's controller save action

No schema changes required for new models.

---

## 13. Out of Scope (v1)

- Rule change audit log
- Rule-level notification / email triggers
- Cross-entity rule templates
- Scheduled / batch rule evaluation (not on save)
