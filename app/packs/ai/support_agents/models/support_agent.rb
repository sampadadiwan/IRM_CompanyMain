class SupportAgent < ApplicationRecord
  # SupportAgent represents an AI-driven entity responsible for
  # validating consistency between structured fields on a model
  # and extracted values from uploaded documents. It leverages LLMs
  # (Large Language Models) to parse and extract content for verification.
  #
  # Includes:
  #   - WithCustomField: adds support for attaching custom metadata/fields
  #   - WithFolder: provides organization of agents into folders
  #
  # Validations enforce constraints on agent identity and type to ensure
  # consistent naming and classification.
  include WithCustomField
  include WithFolder

  AGENT_TYPES = ["SupportAgent"].freeze

  belongs_to :entity

  validates :name, presence: true
  validates :name, length: { maximum: 30 }
  validates :agent_type, presence: true
  validates :agent_type, length: { maximum: 20 }

  # Returns the human-readable representation of the SupportAgent
  # In this case, simply the name string.
  #
  # @return [String] the name of the agent
  def to_s
    name
  end

  # Performs consistency checks between expected model attribute values
  # and values automatically extracted from associated documents by the LLM.
  #
  # @param ctx [Hash] execution context containing :llm (the language model instance)
  #                   and :issues (collection of issues found during checks)
  # @param model [ActiveRecord::Base] the record whose attributes are validated
  # @return [void]
  def check_field_to_document_consistency(ctx, model)
    mappings = parse_field_document_mappings

    binding.pry
    llm = ctx[:llm]
    return if mappings.blank?

    # For each mapping between documents and model fields,
    # locate the document and extract its values for comparison.
    mappings.each do |doc_name, field_map|
      doc = model.documents.find { |d| d.name.downcase == doc_name.downcase }
      next if doc.nil?

      Rails.logger.debug { "[SupportAgent] Starting field-to-document consistency check for #{doc.name} (#{field_map.keys.join(', ')}) #{model.class.name} ID=#{model.id}" }

      extracted = extract_fields_from_document(ctx, llm, doc, field_map)
      Rails.logger.debug { "Extracted fields from document #{doc.name}: #{extracted.inspect}" }
      next unless extracted

      compare_extracted_with_model(ctx, doc, model, extracted, field_map)
    end
  end

  # Builds a mapping of model field names to document extraction prompts.
  # Each field is defined under custom fields with meta_data = 'doc_extraction'.
  #
  #     {
  #       "Document Label" => { "json_field" => "Prompt string", ... }
  #     }
  #
  # @return [Hash{String => Hash{String => String}}]
  def parse_field_document_mappings
    doc_extraction_fields = form_custom_fields.where(meta_data: 'doc_extraction')
    document_field_map = {}

    doc_extraction_fields.each do |field|
      Rails.logger.debug { "[SupportAgent] Document extraction field: #{field.name}" }
      field_mappings = json_fields[field.name]
      next if field.name.blank? || field_mappings.blank?

      # Each extraction mapping is stored as a semicolon-separated list of "json_key=prompt"
      document_field_map[field.label] = field_mappings.split(";").to_h { |f| f.split("=") }
    end

    document_field_map
  end

  # Extracts specific fields from a given document using the LLM.
  # Builds a JSON prompt based on defined field mappings and attempts to parse
  # the LLM response. Handles errors gracefully and records issues when parsing fails.
  #
  # @param ctx [Hash] the context object containing logging and issues arrays
  # @param llm [RubyLLM::Client] the language model instance to contact
  # @param doc [Document] the document from which fields should be extracted
  # @param field_map [Hash] mapping of JSON keys to extraction instructions
  # @return [Hash, nil] parsed JSON of extracted field values, or nil on failure
  def extract_fields_from_document(ctx, llm, doc, field_map)
    # Build a prompt instructing the LLM to extract exact fields from the document.
    prompt = <<~PROMPT
      Extract the following fields from the document:
      #{field_map.map { |json_key, extraction_prompt| "#{json_key}: #{extraction_prompt}" }.join("\n")}

      Reply strictly in JSON with the format:
      {"field1": "value1", "field2": "value2", ...}
    PROMPT

    # Send prompt along with the document URL
    raw = llm.ask(prompt, with: [doc.file.url])

    # Clean and normalize the LLM response
    content = if raw.is_a?(RubyLLM::Message)
                raw.content.is_a?(RubyLLM::Content) ? raw.content.text : raw.content
              else
                raw.to_s
              end
    # Strip potential ```json fences from content
    if content.is_a?(String)
      content = content.strip
      content = content.sub(/\A```(?:json)?/i, "").sub(/```$/, "").strip
    end
    JSON.parse(content)
  rescue JSON::ParserError
    # Record issue if LLM output cannot be parsed
    ctx[:issues][:document_issues] << { type: :llm_parse_error, name: doc.name, severity: :warning, raw: raw }
    Rails.logger.warn("[SupportAgent] LLM parse error for document #{doc.name}, raw=#{raw.inspect}")
    nil
  end

  # Compares values extracted from the document with existing model attributes.
  # Logs matches/mismatches and appends blocking issues when discrepancies are detected.
  #
  # @param ctx [Hash] execution context with :issues hash
  # @param doc [Document] the source document
  # @param model [ActiveRecord::Base] the record being validated
  # @param extracted [Hash{String => String}] field values extracted by the LLM
  # @param field_map [Hash] mapping of model attributes to extraction prompts
  # @return [void]
  def compare_extracted_with_model(ctx, doc, model, extracted, field_map)
    field_map.each_key do |attribute_name|
      extracted_val = extracted[attribute_name]
      model_val = model[attribute_name]

      # Perform type-specific comparisons to reduce false mismatches.
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
                  extracted_val.to_d == model_val.to_d
                else
                  extracted_val.to_s == model_val.to_s
                end

      if matched
        Rails.logger.debug { "[SupportAgent] Field matched: #{doc.name} matches #{attribute_name}" }
      else
        # Record mismatch issue for later reporting/handling
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
