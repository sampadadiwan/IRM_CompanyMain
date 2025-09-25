class SupportAgent < ApplicationRecord
  include WithCustomField
  include WithFolder

  AGENT_TYPES = ["SupportAgent"].freeze

  belongs_to :entity

  validates :name, presence: true
  validates :name, length: { maximum: 30 }
  validates :agent_type, presence: true
  validates :agent_type, length: { maximum: 20 }

  def to_s
    name
  end

  def check_field_to_document_consistency(ctx, model)
    mappings = parse_field_document_mappings
    llm = ctx[:llm]
    return if mappings.blank?

    mappings.each do |doc_name, field_map|
      doc = model.documents.find { |d| d.name == doc_name }
      return if doc.nil?

      Rails.logger.debug { "[SupportAgent] Starting field-to-document consistency check for #{doc.name} (#{field_map.keys.join(', ')}) #{model.class.name} ID=#{model.id}" }

      extracted = extract_fields_from_document(ctx, llm, doc, field_map)
      Rails.logger.debug { "Extracted fields from document #{doc.name}: #{extracted.inspect}" }
      return unless extracted

      compare_extracted_with_model(ctx, doc, model, extracted, field_map)
    end
  end

  def parse_field_document_mappings
    doc_extraction_fields = form_custom_fields.where(meta_data: 'doc_extraction')
    document_field_map = {}

    doc_extraction_fields.each do |field|
      Rails.logger.debug { "[SupportAgent] Document extraction field: #{field.name}" }
      field_mappings = json_fields[field.name]
      next if field.name.blank? || field_mappings.blank?

      document_field_map[field.label] = field_mappings.split(";").to_h { |f| f.split("=") }
    end

    document_field_map
  end

  def extract_fields_from_document(ctx, llm, doc, field_map)
    prompt = <<~PROMPT
      Extract the following fields from the document:
      #{field_map.map { |json_key, extraction_prompt| "#{json_key}: #{extraction_prompt}" }.join("\n")}

      Reply strictly in JSON with the format:
      {"field1": "value1", "field2": "value2", ...}
    PROMPT

    # Rails.logger.debug { "Prompt sent to LLM for document #{doc.name}:\n#{prompt}" }

    raw = llm.ask(prompt, with: [doc.file.url])
    content = if raw.is_a?(RubyLLM::Message)
                raw.content.is_a?(RubyLLM::Content) ? raw.content.text : raw.content
              else
                raw.to_s
              end
    # Strip potential Markdown code fencing like ```json ... ```
    if content.is_a?(String)
      content = content.strip
      content = content.sub(/\A```(?:json)?/i, "").sub(/```$/, "").strip
    end
    JSON.parse(content)
  rescue JSON::ParserError
    ctx[:issues][:document_issues] << { type: :llm_parse_error, name: doc.name, severity: :warning, raw: raw }
    Rails.logger.warn("[SupportAgent] LLM parse error for document #{doc.name}, raw=#{raw.inspect}")
    nil
  end

  def compare_extracted_with_model(ctx, doc, model, extracted, field_map)
    field_map.each_key do |attribute_name|
      extracted_val = extracted[attribute_name]
      model_val = model[attribute_name]

      matched = case model_val
                when String
                  extracted_val.gsub(/\s+/, "").casecmp?(model_val.gsub(/\s+/, ""))
                when Date, Time, DateTime, ActiveSupport::TimeWithZone
                  begin
                    Date.parse(extracted_val.to_s) == model_val.to_date
                  rescue ArgumentError, TypeError
                    false
                  end
                when Numeric, Integer, Float, BigDecimal
                  extracted_val.to_f == model_val.to_f
                else
                  extracted_val.to_s == model_val.to_s
                end

      if matched
        Rails.logger.debug { "[SupportAgent] Field matched: #{doc.name} matches #{attribute_name}" }
      else
        ctx[:issues][:document_issues] << {
          type: :field_mismatch,
          name: doc.name,
          severity: :blocking,
          explanation: "#{attribute_name} (#{extracted_val}) does not match #{model.class.name} (#{model_val})"
        }
        Rails.logger.debug { "[SupportAgent] Field mismatch in #{doc.name}: #{attribute_name}=#{extracted_val.inspect}, expected #{attribute_name}=#{model_val.inspect}" }
      end
    end
  end
end
