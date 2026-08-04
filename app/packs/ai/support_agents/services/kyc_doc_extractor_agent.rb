# frozen_string_literal: true

# KycDocExtractorAgent — document-first KYC wizard support agent.
#
# Reads extraction_rules from json_fields, keyed by form_type_id, and for each rule
# sends the matching uploaded document to the LLM with the configured prompt.
# Extracted values are written back to the InvestorKyc record:
#   - As a DB column attribute if InvestorKyc.column_names includes the target_field
#   - Otherwise as json_fields[target_field]
#
# Overwrite behaviour is controlled by json_fields["overwrite_mode"]:
#   "blank_only" (default) — only write if the current field value is blank
#   "always"               — overwrite regardless of existing value
#
# Configuration in SupportAgent.json_fields:
#   {
#     "overwrite_mode": "blank_only",
#     "extraction_rules": {
#       "FORM_TYPE_ID": [
#         { "doc_label": "PAN Card", "prompt": "Extract the PAN number", "target_field": "PAN" }
#       ]
#     }
#   }
class KycDocExtractorAgent < SupportAgentService
  DESCRIPTION = "Extracts field values from uploaded KYC documents and pre-populates the form."

  LONG_DESCRIPTION = <<~DESC
    Document-first KYC wizard agent. When an investor uploads documents before filling the form,
    this agent reads each document with the configured extraction rules, asks the LLM to extract
    specific field values, and writes them back into the InvestorKyc record so the form is
    pre-populated for the investor to review and complete.

    Configuration per form_type defines which document label to read, what prompt to send, and
    which field (DB column or json_field) to write the result into.
    Overwrite mode: "blank_only" (default) or "always".
  DESC

  step :initialize_agent
  step :extract_and_populate

  # Extraction operates on a single InvestorKyc record.
  def targets(entity_id)
    InvestorKyc.where(entity_id: entity_id)
  end

  # Setup health check. With no extraction_rules the agent "succeeds" while
  # extracting nothing, and it persists no report — this banner is the only
  # place the gap becomes visible.
  def self.config_issues(support_agent)
    issues = []
    rules  = (support_agent.json_fields || {})["extraction_rules"] || {}

    if rules.blank?
      issues << "No extraction rules configured — the agent will run but extract nothing. Re-run the support agent setup or add rules on the agent edit page."
    else
      # Rules are keyed by KYC FormType id; keys pointing at deleted form types extract nothing
      known_ids = support_agent.entity.form_types.where(id: rules.keys.map(&:to_i)).pluck(:id)
      stale     = rules.keys.map(&:to_i) - known_ids
      issues << "Extraction rules reference form type id(s) #{stale.join(', ')} that no longer exist for this entity — re-run the support agent setup." if stale.any?
    end

    issues
  end

  private

  def initialize_agent(ctx, target:, **)
    super
    ctx[:investor_kyc] = target
    ctx[:results] = []
    true
  end

  # Groups rules by document label and sends one LLM call per document,
  # extracting all fields for that document in a single JSON-structured response.
  def extract_and_populate(ctx, investor_kyc:, **)
    rules = rules_for(investor_kyc)

    if rules.empty?
      ctx[:results] << { status: :skipped, message: "No extraction rules configured for this form type." }
      return true
    end

    overwrite    = (@support_agent.json_fields["overwrite_mode"] || "blank_only") == "always"
    llm          = ctx[:llm]
    rules_by_doc = rules.group_by { |r| r["doc_label"].to_s.strip }

    rules_by_doc.each do |doc_label, doc_rules|
      next if doc_label.blank?

      doc = investor_kyc.documents.find { |d| d.name.to_s.strip == doc_label }

      if doc&.file.blank?
        # All fields for this doc are skipped together
        doc_rules.each do |rule|
          target_field = rule["target_field"].to_s.strip
          ctx[:results] << { status: :skipped, field: target_field, message: "Document '#{doc_label}' not uploaded." }
        end
        next
      end

      # Drop rules whose field already has a value when in blank_only mode
      extractable_rules = doc_rules.reject do |rule|
        target_field = rule["target_field"].to_s.strip
        next false if overwrite

        existing = read_field(investor_kyc, target_field)
        if existing.present?
          ctx[:results] << { status: :skipped, field: target_field, message: "Field already has a value." }
          true
        else
          false
        end
      end

      next if extractable_rules.empty?

      # Build field_map: { target_field => prompt } for all extractable rules
      field_map = extractable_rules.each_with_object({}) do |rule, h|
        tf = rule["target_field"].to_s.strip
        pr = rule["prompt"].to_s.strip
        h[tf] = pr unless tf.blank? || pr.blank?
      end

      begin
        extracted = extract_json_from_document(llm, doc, field_map)

        extractable_rules.each do |rule|
          target_field = rule["target_field"].to_s.strip
          value        = extracted[target_field].to_s.strip

          write_field(investor_kyc, target_field, value)
          ctx[:results] << { status: :extracted, field: target_field, value: value }
          Rails.logger.info("[KycDocExtractorAgent] Extracted #{target_field}=#{value.inspect} from '#{doc_label}'")
        end
      rescue JSON::ParserError => e
        extractable_rules.each do |rule|
          ctx[:results] << { status: :error, field: rule["target_field"].to_s.strip, message: "JSON parse error: #{e.message}" }
        end
        Rails.logger.warn("[KycDocExtractorAgent] JSON parse error for '#{doc_label}': #{e.message}")
      rescue StandardError => e
        extractable_rules.each do |rule|
          ctx[:results] << { status: :error, field: rule["target_field"].to_s.strip, message: e.message }
        end
        Rails.logger.warn("[KycDocExtractorAgent] Error extracting from '#{doc_label}': #{e.message}")
      end
    end

    # Persist all extracted values in one save
    investor_kyc.save(validate: false) if ctx[:results].any? { |r| r[:status] == :extracted }
    true
  end

  # Returns extraction rules array for the KYC's form_type_id.
  def rules_for(investor_kyc)
    extraction_rules = @support_agent.json_fields["extraction_rules"] || {}
    form_type_id     = investor_kyc.form_type_id&.to_s
    return [] if form_type_id.blank?

    extraction_rules[form_type_id] || []
  end

  # Reads field value from DB column or json_fields.
  def read_field(investor_kyc, field)
    if InvestorKyc.column_names.include?(field)
      investor_kyc.public_send(field)
    else
      investor_kyc.json_fields&.dig(field)
    end
  end

  # Writes extracted value to DB column or json_fields.
  def write_field(investor_kyc, field, value)
    if InvestorKyc.column_names.include?(field)
      investor_kyc.public_send(:"#{field}=", value)
    else
      investor_kyc.json_fields ||= {}
      investor_kyc.json_fields[field] = value
      investor_kyc.json_fields_will_change!
    end
  end

  # Sends one LLM call with a JSON prompt covering all fields in field_map,
  # then parses and returns the resulting Hash. Raises JSON::ParserError on bad output.
  def extract_json_from_document(llm, doc, field_map)
    prompt = <<~PROMPT
      Extract the following fields from the document:
      #{field_map.map { |field, extraction_prompt| "#{field}: #{extraction_prompt}" }.join("\n")}

      Reply strictly in JSON with the format:
      {"field1": "value1", "field2": "value2", ...}
    PROMPT

    raw     = llm.ask(prompt, with: [doc.file.url])
    content = extract_plain_text(raw)
    # Strip markdown code fences the LLM may wrap around the JSON block
    content = content.sub(/\A```(?:json)?/i, "").sub(/```$/, "").strip
    JSON.parse(content)
  end

  # Unwrap RubyLLM::Message or plain string response.
  def extract_plain_text(raw)
    text = if raw.is_a?(RubyLLM::Message)
             raw.content.is_a?(RubyLLM::Content) ? raw.content.text : raw.content.to_s
           else
             raw.to_s
           end
    text.strip
  end
end
