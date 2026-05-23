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
  DESCRIPTION = "Extracts field values from uploaded KYC documents and pre-populates the form.".freeze

  LONG_DESCRIPTION = <<~DESC.freeze
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

  private

  def initialize_agent(ctx, target:, **)
    super
    ctx[:investor_kyc] = target
    ctx[:results] = []
    true
  end

  # For each extraction rule matching this KYC's form_type, find the uploaded
  # document with the matching label, send it to the LLM, and write the result.
  def extract_and_populate(ctx, investor_kyc:, **)
    rules = rules_for(investor_kyc)

    if rules.empty?
      ctx[:results] << { status: :skipped, message: "No extraction rules configured for this form type." }
      return true
    end

    overwrite = (@support_agent.json_fields["overwrite_mode"] || "blank_only") == "always"
    llm       = ctx[:llm]

    rules.each do |rule|
      doc_label    = rule["doc_label"].to_s.strip
      prompt_text  = rule["prompt"].to_s.strip
      target_field = rule["target_field"].to_s.strip

      next if doc_label.blank? || prompt_text.blank? || target_field.blank?

      doc = investor_kyc.documents.find { |d| d.name.to_s.strip == doc_label }

      unless doc&.file.present?
        ctx[:results] << { status: :skipped, field: target_field, message: "Document '#{doc_label}' not uploaded." }
        next
      end

      # Skip if overwrite_mode is blank_only and field already has a value
      unless overwrite
        existing = read_field(investor_kyc, target_field)
        if existing.present?
          ctx[:results] << { status: :skipped, field: target_field, message: "Field already has a value." }
          next
        end
      end

      begin
        raw = llm.ask(prompt_text, with: [doc.file.url])
        value = extract_plain_text(raw)

        write_field(investor_kyc, target_field, value)
        ctx[:results] << { status: :extracted, field: target_field, value: value }
        Rails.logger.info("[KycDocExtractorAgent] Extracted #{target_field}=#{value.inspect} from '#{doc_label}'")
      rescue StandardError => e
        ctx[:results] << { status: :error, field: target_field, message: e.message }
        Rails.logger.warn("[KycDocExtractorAgent] Error extracting #{target_field} from '#{doc_label}': #{e.message}")
      end
    end

    # Persist all extracted values in one save
    investor_kyc.save(validate: false) if ctx[:results].any? { |r| r[:status] == :extracted }
    true
  end

  # Returns extraction rules array for the KYC's form_type_id.
  def rules_for(investor_kyc)
    extraction_rules = (@support_agent.json_fields["extraction_rules"] || {})
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
