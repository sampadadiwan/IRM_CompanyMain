# Tasks

> **Phase gate:** each numbered group below is a phase. A phase's last task is always to run its
> Cucumber feature and get it green. Do not start the next phase until that happens — if it fails,
> fix the phase you're on rather than moving forward and coming back later.

## 1. Setup UI — Structured Config Partial + Stimulus Controller

- [x] 1.1 Create `app/javascript/controllers/kyc_onboarding_config_controller.js` — Stimulus controller with targets `jsonField` (hidden input), `rulesBody` (tbody per form_type). Methods: `syncConfig()` iterates `rulesBodyTargets`, reads `data-form-type-id`, collects rows via `querySelectorAll("tr[data-rule-row]")`, maps to `{doc_label, prompt, target_field}`, filters blanks, merges into existing json_fields preserving other keys, writes JSON to hidden field. `addRule(event)` clones `<template>` by `data-template-id`, appends to tbody, calls syncConfig. `removeRule(event)` removes closest `tr[data-rule-row]`, calls syncConfig. Include JSDoc class header. Follow the pattern in `kyc_doc_extractor_config_controller.js`. Verify: controller loads without JS errors on agent edit page.

- [x] 1.2 Create `app/packs/ai/support_agents/views/support_agents/_kyc_onboarding_config.html.erb` — Partial renders one card per KYC form type (`FormType.where(entity_id: current_user.entity_id, name: %w[IndividualKyc NonIndividualKyc])`). Each card has a table with 3 columns: Document (dropdown of File-type FormCustomFields), Information to pull (text input), Field to verify (dropdown of non-File/non-Header FormCustomFields). "+ Add Rule" button per card. `<template>` element for row cloning with `<select>` dropdowns. Hidden `json_fields` input wired to Stimulus controller. Reads existing `doc_verification_rules` from `support_agent.json_fields` to pre-populate rows on load. Include ERB header comment. Follow the structure of `_kyc_doc_extractor_config.html.erb`. Verify: partial renders without errors in browser on the agent edit page.

- [x] 1.3 Modify `app/packs/ai/support_agents/views/support_agents/_form.html.erb` — Add conditional render: when `@support_agent.agent_type == "KycOnboardingAgent"`, render `_kyc_onboarding_config` partial passing `support_agent` and `form` locals. Place alongside existing KycDocExtractorAgent / CashFlowAssistantAgent conditionals. Verify: the setup table appears on the KYC Onboarding Agent edit page but NOT on other agent type edit pages.

- [x] 1.4 Write `features/ai/support_agents/kyc_agent_setup.feature` covering H1 (table renders with dropdowns), H2 (save and reload preserves config), E1 (empty row discarded), E2 (same document in multiple rows), E3 (no File-type fields). Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/ai/support_agents/kyc_agent_setup.feature` and confirm green before starting phase 2.

## 2. Dual-Format Mapping Parser

- [x] 2.1 Add `parse_new_format_mappings` private method to `SupportAgentHelper` (`app/packs/ai/support_agents/models/concerns/support_agent_helper.rb`). Reads `json_fields["doc_verification_rules"]` (Hash keyed by form_type_id string, values are arrays of `{doc_label, prompt, target_field}`). Returns `{ "Document Label" => { "target_field" => "prompt" } }` — same shape as existing parser output. Skips rules with blank `doc_label` or `target_field`. Merges across form_type_ids into one flat hash. Include YARD `@return` comment.

- [x] 2.2 Modify `parse_field_document_mappings` in `SupportAgentHelper` — Add format detection at the top: if `json_fields["doc_verification_rules"]` is present and non-empty, call `parse_new_format_mappings` and return early. Otherwise fall through to existing old-format logic (FormCustomField `meta_data: "doc_extraction"` query + string splitting). Both paths return identical hash shape. Verify in `rails c`: create a SupportAgent with `doc_verification_rules` in json_fields, call `parse_field_document_mappings`, confirm correct hash output.

- [x] 2.3 Write scenarios for E4 (old format still works) and E5 (re-save migrates) into `features/ai/support_agents/kyc_agent_setup.feature`. Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/ai/support_agents/kyc_agent_setup.feature` and confirm green before starting phase 3.

## 3. Document Validity — PAN/Tax ID Filter

- [x] 3.1 Add `PAN_TAX_ID_PATTERNS` constant to `KycOnboardingAgent` — `%w[pan tax_id taxid].freeze` plus `"tax id"` (with space). Add private method `pan_or_tax_id_document?(doc)` — normalizes `doc.name` (strip "Upload"/"Attach your"/"Attach" prefix, downcase, strip whitespace), checks if normalized name includes any pattern from the list. Returns Boolean. Include YARD comment.

- [x] 3.2 Modify `check_document_validity` in `KycOnboardingAgent` — Replace `investor_kyc.documents.each do |doc|` with a filtered iteration: `investor_kyc.documents.select { |doc| pan_or_tax_id_document?(doc) }.each do |doc|`. Add DEBUG log for skipped documents: `"Skipping document validity for non-PAN/Tax ID document: #{doc.name}"`. Verify in `rails c`: run agent on a KYC with 3 documents, confirm only PAN/Tax ID doc gets AI call.

- [x] 3.3 Write `features/ai/support_agents/kyc_agent_validation.feature` covering H4 (PAN validated), H5 (presence check), E6 (PAN Card name matched), E7 (validate_documents OFF), X1 (AI call fails). Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/ai/support_agents/kyc_agent_validation.feature` and confirm green before starting phase 4.

## 4. AML Entity-Level Gate + Descriptions

- [x] 4.1 Modify `targets` in `KycOnboardingAgent` — Change `.includes(:documents, :investor, :entity)` to `.includes(:documents, :investor, entity: :entity_setting)` to eager-load entity_setting. Verify: no N+1 warning from Bullet when running agent.

- [x] 4.2 Add entity-level AML guard to `trigger_aml_if_complete` in `KycOnboardingAgent` — Insert after the `enabled?("trigger_aml")` check and before the employee check: if `!investor_kyc.entity&.entity_setting&.aml_enabled` then `mark_step_skipped(report, :trigger_aml_if_complete, message: "AML not enabled for entity")`, log at DEBUG, return true. Verify in `rails c`: run agent on a KYC where entity AML is disabled, confirm step skipped with correct message.

- [x] 4.3 Update description constants in `KycOnboardingAgent` — Replace "passport, ID, etc." with "Tax ID, Address Proof, Bank Details" in `DESCRIPTION`, `LONG_DESCRIPTION`, and `SINGLE_LONG_DESCRIPTION`. Also update Step 2 line in `LONG_DESCRIPTION` from "verifies required document types (passport, ID, etc.)" to "verifies required document types (Tax ID, Address Proof, etc.)". Verify: no mention of "passport" in the file.

- [x] 4.4 Add scenarios H3 (new format consistency), H6 (AML skipped), H7 (description text), E8 (AML enabled triggers), E9 (entity_setting nil) to `features/ai/support_agents/kyc_agent_validation.feature`. Run `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/ai/support_agents/kyc_agent_validation.feature` and confirm green before starting phase 5.

## 5. Final Verification

- [x] 5.1 Verify traceability: every H/E/X ID from design.md's worked examples has exactly one Cucumber scenario in the feature files. Every scenario has a comment naming its H/E/X ID. List any gaps and fill them.

- [x] 5.2 Run `bundle exec rubocop` on all new/modified files — clean, no offenses.

- [x] 5.3 Run full feature suite: `TEST_ENV_NUMBER=$RANDOM bundle exec cucumber features/ai/support_agents/kyc_agent_setup.feature features/ai/support_agents/kyc_agent_validation.feature` — all scenarios green.

- [x] 5.4 Run qa-checklist.md on a deployed build and record the sign-off in the checklist's Sign-off table.
