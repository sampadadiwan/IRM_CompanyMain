# KYC Onboarding Agent Improvements — Low-Level Design

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

- **Dual-format parser in `parse_field_document_mappings`** — must return identical hash shape for both old and new formats — see [Method Contracts](#method-contracts)
- **PAN/Tax ID name matching** uses substring match on normalized name — see [Method Contracts](#pan_or_tax_id_document)
- **`entity_setting` eager-loaded** via `:entity_setting` added to `targets` includes — see [Queries and Indexes](#queries-and-indexes)
- **No schema changes** — all config stored in existing `json_fields` JSON column
- **Setup UI partial** follows `_kyc_doc_extractor_config.html.erb` pattern — see [File Map](#file-map)

---

## File Map

| File | Status | Card | Purpose |
|---|---|---|---|
| `app/packs/ai/support_agents/views/support_agents/_kyc_onboarding_config.html.erb` | **NEW** | [①](design.md#①-setup-ui) | Structured 3-column setup table partial |
| `app/javascript/controllers/kyc_onboarding_config_controller.js` | **NEW** | [①](design.md#①-setup-ui) | Stimulus controller: syncConfig, addRule, removeRule |
| `app/packs/ai/support_agents/views/support_agents/_form.html.erb` | MODIFIED | [①](design.md#①-setup-ui) | Add conditional render for KycOnboardingAgent config partial |
| `app/packs/ai/support_agents/models/concerns/support_agent_helper.rb` | MODIFIED | [②](design.md#②-mapping-parser) | `parse_field_document_mappings` gains dual-format detection + `parse_new_format_mappings` |
| `app/packs/ai/support_agents/services/kyc_onboarding_agent.rb` | MODIFIED | [③④⑤](design.md#③-document-checks) | `check_document_validity` filter, `trigger_aml_if_complete` guard, description constants, `targets` includes |

**Reviewer checks:**
- [ ] No files outside the `ai/support_agents` pack are modified (except `_form.html.erb` which is in the same pack)
- [ ] New files follow the pack structure: views in `views/support_agents/`, JS in `app/javascript/controllers/`
- [ ] Stimulus controller filename matches controller name: `kyc_onboarding_config_controller.js` → `kyc-onboarding-config`

---

## Schema Detail

N/A — no table or column changes. All config is stored in the existing `support_agents.json_fields` native MySQL JSON column.

**Reviewer checks:**
- [ ] No migration file is created
- [ ] `json_fields` key name `doc_verification_rules` does not conflict with any existing key (check `grep -r "doc_verification_rules" app/`)

---

## Method Contracts

### `parse_field_document_mappings` (SupportAgentHelper) — MODIFIED

**Current signature:** `def parse_field_document_mappings` (no args, returns Hash)

**New behavior:**
1. Check `json_fields["doc_verification_rules"]` — if present and non-empty, call `parse_new_format_mappings`
2. Otherwise, fall back to existing logic (query FormCustomField with `meta_data: "doc_extraction"`, split strings)
3. Both paths return the same shape: `{ "Document Label" => { "attribute_name" => "extraction_prompt" } }`

### `parse_new_format_mappings` (SupportAgentHelper) — NEW

**Signature:** `def parse_new_format_mappings` (private, no args, returns Hash)

**Input:** `json_fields["doc_verification_rules"]` — Hash keyed by form_type_id string, values are arrays of `{doc_label:, prompt:, target_field:}` hashes

**Output:** `{ "Upload PAN" => { "PAN" => "PAN / Tax ID number" } }` — merges all form_type_ids into one flat hash. If the same doc_label appears for multiple form types, entries are merged (last wins per target_field).

**Edge cases:**
- `doc_verification_rules` is `{}` or has empty arrays → returns `{}` → consistency check no-ops
- A rule has blank `doc_label` or `target_field` → skip that rule (matches UI discard behavior)

### `pan_or_tax_id_document?` (KycOnboardingAgent) — NEW

**Signature:** `def pan_or_tax_id_document?(doc)` (private, returns Boolean)

**Input:** Document record with `name` attribute

**Logic:** Normalize the name (strip "Upload"/"Attach your"/"Attach" prefix, downcase, strip whitespace), then check if it matches any of: `pan`, `tax_id`, `taxid`, `tax id`. Match = substring include, not exact match (so "PAN Card" matches).

**Pattern list:** `PAN_TAX_ID_PATTERNS = %w[pan tax_id taxid].freeze` — plus `"tax id"` (with space).

### `trigger_aml_if_complete` (KycOnboardingAgent) — MODIFIED

**New guard clause** inserted after `enabled?("trigger_aml")` and before the employee check:

Check `investor_kyc.entity&.entity_setting&.aml_enabled`. If falsy → `mark_step_skipped(report, :trigger_aml_if_complete, message: "AML not enabled for entity")` and return true.

**Reviewer checks:**
- [ ] `parse_field_document_mappings` returns identical hash shape for both formats — verify with test data
- [ ] `parse_new_format_mappings` skips rules with blank doc_label or target_field
- [ ] `pan_or_tax_id_document?` pattern list covers both Indian (PAN) and US (Tax ID) naming
- [ ] AML guard uses safe navigation (`&.`) on both `entity` and `entity_setting`
- [ ] AML guard is placed before employee check (so entity without AML never queries employees)

---

## Controllers, Params and Responses

No new controller actions. The existing `SupportAgentsController#update` handles the form save. The `json_fields` hidden field is serialized by the Stimulus controller and submitted as a JSON string, then parsed by the existing `json_fields` setter.

**Reviewer checks:**
- [ ] The hidden `json_fields` input is serialized as valid JSON by the Stimulus controller
- [ ] The existing `update` action's strong params permit `json_fields` (verify existing allowlist)

---

## Queries and Indexes

### `targets` includes — MODIFIED

**Current:** `InvestorKyc.completed.where(entity_id:).includes(:documents, :investor, :entity)`

**New:** Add `:entity_setting` to the includes chain via the entity association: `.includes(:documents, :investor, entity: :entity_setting)`

This avoids N+1 when `trigger_aml_if_complete` checks `investor_kyc.entity.entity_setting.aml_enabled` for each KYC.

### Setup UI queries (partial render)

Two queries when the partial renders:
1. `FormType.where(entity_id: current_user.entity_id, name: %w[IndividualKyc NonIndividualKyc])` — returns 0-2 records
2. `FormCustomField.where(form_type_id: form_type_ids)` — one query for all fields, filtered in Ruby for dropdown population

**Reviewer checks:**
- [ ] `entity: :entity_setting` in includes does not break existing eager loading
- [ ] Setup UI partial queries are scoped to `current_user.entity_id`
- [ ] No N+1 in `trigger_aml_if_complete` — check with Bullet in test

---

## Transactions, Locking and Concurrency

N/A — no new multi-table writes. The `entity_setting` read is a single `has_one` query. The config save goes through the existing `SupportAgent#update` which is a single-record write.

**Reviewer checks:**
- [ ] No new transaction blocks introduced

---

## Background Jobs

N/A — no new background jobs. The existing `GenerateAmlReportJob` is unchanged; it's just gated by the new entity-level check.

**Reviewer checks:**
- [ ] `GenerateAmlReportJob.perform_later` is NOT called when `aml_enabled` is false

---

## External Integrations

N/A — no new external service calls. The AI calls in `check_document_validity` are reduced (fewer calls), not changed in interface.

**Reviewer checks:**
- [ ] AI calls in `check_document_validity` only fire for PAN/Tax ID documents

---

## Error Mapping and Logging

### Document Validity — skipped documents

When a non-PAN/Tax ID document is skipped in `check_document_validity`, log at DEBUG level: `"[KycOnboardingAgent] Skipping document validity for non-PAN/Tax ID document: #{doc.name}"`

### AML gate — entity setting check

When AML is skipped due to entity settings, log at DEBUG level: `"[KycOnboardingAgent] AML not enabled for entity ID=#{investor_kyc.entity_id}, skipping AML trigger"`

**Reviewer checks:**
- [ ] Skipped documents are logged at DEBUG, not INFO or WARN
- [ ] AML skip is logged with entity_id for debugging

---

## Security Review

- **Tenant isolation:** The setup UI queries `FormType.where(entity_id: current_user.entity_id)` — scoped to current user's entity. Agent runs are scoped by `entity_id` in `targets`. No cross-tenant risk.
- **Input sanitization:** The Stimulus controller serializes dropdown values (not free text for columns 1 and 3). The "Information to pull" column is free text but is only used as an LLM prompt — not rendered as HTML or executed as code.
- **AML billing:** The entity-level check prevents unauthorized AML report generation.

**Reviewer checks:**
- [ ] `current_user.entity_id` used in all setup UI queries
- [ ] Free text from "Information to pull" is only passed to LLM, never rendered unescaped in HTML
- [ ] No `html_safe` or `raw` on user-provided content

---

## Configuration and Rollout

No feature flag needed. Changes are backward-compatible:
- Old agents with text-format config continue working (dual-format parser)
- New agents get the structured UI
- AML gate is additive (skip when not enabled, no change when enabled)

**Rollout:** Deploy normally. No data migration required.

**Reviewer checks:**
- [ ] No feature flag or env var introduced
- [ ] Old-format agents still work after deploy (test with existing agent on staging)

---

## Test Plumbing

### Feature files

| File | Scenarios | Covers |
|---|---|---|
| `features/ai/support_agents/kyc_agent_setup.feature` | H1, H2, E1, E2, E3, E5 | Setup UI rendering, save/reload, edge cases |
| `features/ai/support_agents/kyc_agent_validation.feature` | H3-H7, E4, E6-E9, X1 | Agent run: validity filter, AML gate, description, old format |

### Step files

- **Reused:** `features/step_definitions/support_agent_steps.rb` — agent creation, running, report assertions
- **New:** `features/step_definitions/kyc_agent_setup_steps.rb` — setup table interactions (select dropdown, add row, save, reload)

### Factories

No new factories. Use existing `support_agent` factory with `agent_type: "KycOnboardingAgent"`. Use existing `investor_kyc` factory with `completed_by_investor: true`. Use existing `form_custom_field` factory.

**Reviewer checks:**
- [ ] Every H/E/X row in design.md has exactly one Cucumber scenario
- [ ] Traceability comments in step files reference H/E/X IDs

---

## Project Rules Checklist

| Rule | Applies | Notes |
|---|---|---|
| `# frozen_string_literal: true` on new Ruby files | N/A | No new Ruby files (only ERB and JS) |
| YARD-style comments on classes and methods | Applies | New private methods `pan_or_tax_id_document?`, `parse_new_format_mappings` need `@param`/`@return` |
| ERB header comments on new partials | Applies | `_kyc_onboarding_config.html.erb` needs header comment explaining purpose and locals |
| JSDoc header on new Stimulus controller | Applies | `kyc_onboarding_config_controller.js` needs class-level JSDoc |
| No teammate/client names in docs | Applies | Use "the admin", "the investor" in all docs |
| Tenant scoping (`entity_id`) | Applies | Setup UI scoped to `current_user.entity_id`, agent runs scoped by `targets` |
| No `html_safe` / `raw` on user input | Applies | Free text "Information to pull" is never rendered as HTML |

**Reviewer checks:**
- [ ] All items marked Applies are satisfied in the implementation

---

## Sign-off

| Reviewer | Date | Decision |
|---|---|---|
| | | |
