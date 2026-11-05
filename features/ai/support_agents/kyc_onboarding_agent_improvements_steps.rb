# frozen_string_literal: true

# Step definitions for KYC Onboarding Agent improvements feature.
# Covers PAN/Tax ID filter, AML entity guard, and dual-format parser.
#
# Reuses shared steps from kyc_onboarding_agent_steps.rb (Background,
# agent config, agent execution, report assertions) and
# investor_kyc_journey_steps.rb (AML entity setting toggles).

# ── PAN / Tax ID filter steps ────────────────────────────────────────────

# Stubs LlmService.ruby_llm_chat so the agent sees matches:true.
# Mirrors the inverse stub in kyc_onboarding_agent_steps.rb ("LLM will flag").
Given("the LLM will confirm the document matches its label") do
  match_json = '{"matches": true, "explanation": "Document matches the specified label."}'
  mock_chat = double("chat", ask: match_json)
  allow(LlmService).to receive(:ruby_llm_chat).and_return(mock_chat)
end

# Asserts that the document validity step produced an entry for this doc.
# After the MySQL JSON round-trip, hash keys are strings.
Then("the report should have a document validity issue for {string}") do |doc_name|
  document_issues = @report.json_fields["document_issues"] || []
  validity_types = %w[info mismatched_document llm_parse_error document_unavailable]
  matching = document_issues.select do |issue|
    issue["name"] == doc_name && validity_types.include?(issue["type"])
  end
  expect(matching).not_to be_empty,
    "Expected a document validity issue for '#{doc_name}' but got: #{document_issues.inspect}"
end

# Asserts that the document validity step produced NO entry for this doc.
# A skipped (non-PAN) document should have zero validity-related issues.
Then("the report should have no document validity issue for {string}") do |doc_name|
  document_issues = @report.json_fields["document_issues"] || []
  validity_types = %w[info mismatched_document llm_parse_error document_unavailable]
  matching = document_issues.select do |issue|
    issue["name"] == doc_name && validity_types.include?(issue["type"])
  end
  expect(matching).to be_empty,
    "Expected no document validity issue for '#{doc_name}' but got: #{matching.inspect}"
end

# ── Dual-format parser steps ─────────────────────────────────────────────

# Sets up new-format doc_verification_rules in the agent's json_fields.
# The "standard" key mirrors the setup UI's standard documents section.
Given("the agent has new-format doc verification rules mapping {string} to {string} with prompt {string}") do |doc_label, target_field, prompt|
  rules = @support_agent.json_fields["doc_verification_rules"] || {}
  rules["standard"] ||= []
  rules["standard"] << {
    "doc_label" => doc_label,
    "target_field" => target_field,
    "prompt" => prompt
  }
  @support_agent.update!(
    json_fields: @support_agent.json_fields.merge("doc_verification_rules" => rules)
  )
end

# Creates an old-format FormCustomField with meta_data='doc_extraction'
# and stores the corresponding mapping in the agent's json_fields.
# Old format: json_fields[field.name] = "target_field=prompt"
Given("the agent has old-format doc extraction field {string} mapping {string} to {string}") do |doc_label, target_field, prompt|
  form_type = @support_agent.form_type
  FormCustomField.create!(
    form_type: form_type,
    name: doc_label.parameterize(separator: "_"),
    label: doc_label,
    field_type: "TextField",
    meta_data: "doc_extraction",
    position: (form_type.form_custom_fields.maximum(:position) || 0) + 1
  )
  @support_agent.update!(
    json_fields: @support_agent.json_fields.merge(
      doc_label.parameterize(separator: "_") => "#{target_field}=#{prompt}"
    )
  )
end

# Stubs LlmService.ruby_llm_chat to return a plausible JSON extraction response.
# Used by the field-to-document consistency check (extract_fields_from_document).
Given("the LLM will return extracted fields as JSON") do
  extraction_json = '{"PAN": "ABCDE1234F"}'
  mock_chat = double("chat", ask: extraction_json)
  allow(LlmService).to receive(:ruby_llm_chat).and_return(mock_chat)
end

# Asserts that the consistency check produced at least one document_issues entry
# for the given doc — either a match (info), mismatch (field_mismatch), or error.
# This confirms parse_field_document_mappings returned a mapping for this doc.
Then("the field-to-document consistency check should have run for {string}") do |doc_name|
  document_issues = @report.json_fields["document_issues"] || []
  consistency_types = %w[info field_mismatch error]
  matching = document_issues.select do |issue|
    issue["name"] == doc_name && consistency_types.include?(issue["type"])
  end
  expect(matching).not_to be_empty,
    "Expected the consistency check to have run for '#{doc_name}' but found no matching " \
    "document_issues entry. All document_issues: #{document_issues.inspect}"
end
