class KycOnboardingAgent < AgentBaseService
  step :initialize_agent

  # == Triggers ==
  # - Scheduled runs (daily, weekly, etc.)
  # - Event runs (on new InvestorKyc, document upload, field update)

  # == Inputs ==
  # - InvestorKyc record
  # - FormCustomField (mandatory/optional rules)
  # - Uploaded documents (passport, ID, etc.)
  # - Document-to-field mapping
  # - Ad-hoc check prompts
  # - Reminder configuration

  # == Core Functions ==
  # step :check_field_completeness
  # step :check_document_presence
  # step :check_document_validity
  step :check_field_to_document_consistency
  step :perform_ad_hoc_checks
  step :generate_progress_reports
  step :send_reminders
  step :trigger_aml_if_complete

  # == Execution & State ==
  # Runs static sequence of checks in order
  # Maintains task state: completed, skipped, failed, pending review
  # Preserves history for reporting

  # == Success Criteria ==
  # - No investor marked complete with missing fields/docs
  # - Mismatches consistently detected
  # - Reports auto-reflect trends
  # - Reminders correctly triggered and ctxual
  # - AML checks auto-triggered on completion

  private

  def initialize_agent(ctx, investor_kyc:, **)
    super
    # Initialize execution ctx with a single investor_kyc
    # Setup history, logging, or state tracking for this run
    Rails.logger.debug { "[KycOnboardingAgent] Initializing agent for InvestorKyc ID=#{investor_kyc.id}" }
    ctx[:investor_kyc] = investor_kyc
    ctx[:issues] = { field_issues: [], document_issues: [] }
    # We only process completed kycs
    investor_kyc.completed_by_investor
  end

  def check_field_completeness(ctx, investor_kyc:, **)
    Rails.logger.debug { "[KycOnboardingAgent] Starting field completeness check for InvestorKyc ID=#{investor_kyc.id}" }
    # Verify mandatory KYC fields are filled in and valid
    # Conditions to flag:
    # - Value is blank, only spaces, or nil
    # - Value matches known placeholders like "N/A", "NA", "Unknown", "Test", "--"
    # - Value has obviously invalid content (could extend with regex rules)
    #
    # We need to check:
    #   1. All model attributes of investor_kyc
    #   2. Dynamic json_fields hash for additional data
    #
    invalid_tokens = ["N/A", "NA", "UNKNOWN", "UNK", "NONE", "TEST", "--"].map(&:downcase)

    # Determine required DB-backed attributes by schema and presence validators
    required_db_columns = investor_kyc.class.columns.select { |c| !c.null && c.default.nil? }.map(&:name)
    required_validated_fields = investor_kyc.class._validators.select do |_, validators|
      validators.any?(ActiveModel::Validations::PresenceValidator)
    end.keys.map(&:to_s)
    required_attrs = (required_db_columns | required_validated_fields)

    required_attrs.each do |attr|
      value = investor_kyc.public_send(attr)
      next unless value.is_a?(String)
      next if value.nil?

      str_val = value.strip
      if str_val.empty? || invalid_tokens.include?(str_val.downcase)
        Rails.logger.debug { "[KycOnboardingAgent] Invalid required field detected: #{attr}=#{value.inspect}" }
        ctx[:issues][:field_issues] << { type: :invalid_field_value, field: attr, value: value, severity: :blocking }
      end
    end

    # Figure out the required custom fields from the form type
    investor_kyc.required_fields_for.each do |fcf|
      # Get the value from json_fields
      value = investor_kyc.json_fields[fcf.name]
      str_val = value.to_s.strip

      # If it's a select field, ensure the value is one of the options
      if fcf.field_type == "Select"
        options = fcf.meta_data.split(",").map(&:strip).compact_blank
        unless options.include?(str_val) || str_val.empty?
          ctx[:issues][:field_issues] << { type: :invalid_select_field_value, field: fcf.name, value: value, severity: :blocking }
          Rails.logger.debug { "[KycOnboardingAgent] Invalid select field value for #{fcf.name}: #{value.inspect}" }
        end
        next
      end

      # For other field types, just check for blank or invalid tokens
      if str_val.empty? || invalid_tokens.include?(str_val.downcase)
        ctx[:issues][:field_issues] << { type: :invalid_json_field_value, field: fcf.name, value: value, severity: :blocking }
        Rails.logger.debug { "[KycOnboardingAgent] Invalid JSON field detected: #{fcf.name}=#{value.inspect}" }
      end
    end

    Rails.logger.debug { "[KycOnboardingAgent] Field completeness check completed. Issues found: #{ctx[:issues][:field_issues].count}" }
    ctx
  end

  def check_document_presence(ctx, investor_kyc:, support_agent:, **)
    Rails.logger.debug { "[KycOnboardingAgent] Starting document presence check for InvestorKyc ID=#{investor_kyc.id}" }
    # Get the list of required File fields for the form type
    # We may also get additional required docs from the support_agent fields
    required_docs += support_agent.json_fields["required_docs"].to_s.split(",").map(&:strip)
    required_docs.uniq!

    Rails.logger.debug { "Required documents: #{required_docs.inspect}" }

    # Get the uploaded documents for this investor_kyc
    uploaded_docs = investor_kyc.documents.pluck(:name).uniq

    # Check for missing documents
    required_docs.each do |name|
      unless uploaded_docs.include?(name)
        ctx[:issues][:document_issues] << { type: :missing_document, name: name, severity: :blocking }
        Rails.logger.debug { "[KycOnboardingAgent] Missing document detected: #{name}" }
      end
    end

    Rails.logger.debug { "[KycOnboardingAgent] Document presence check completed. Issues found: #{ctx[:issues][:document_issues].count}" }
  end

  def check_document_validity(ctx, investor_kyc:, **)
    # Here we send each document and its label to the LLM and get it to judge if the document matches the label
    #
    # We instruct the LLM to validate whether each uploaded document’s content matches its expected label.
    llm = ctx[:llm]

    investor_kyc.documents.each do |doc|
      Rails.logger.debug { "[KycOnboardingAgent] Starting document #{doc.name} consistency check for InvestorKyc ID=#{investor_kyc.id}" }

      label = doc.name
      prompt = <<~PROMPT
        The document is labeled as "#{label}".
        Based on its contents, does it match this label?
        Reply strictly in JSON with the format:
        {"matches": true/false, "explanation": "<short reason>"}
      PROMPT

      raw = llm.ask(prompt, with: [doc.file.url])
      begin
        content = if raw.is_a?(RubyLLM::Message)
                    raw.content.is_a?(RubyLLM::Content) ? raw.content.text : raw.content
                  else
                    raw.to_s
                  end
        result = JSON.parse(content)
        if result["matches"]
          Rails.logger.debug { "[KycOnboardingAgent] Document validated successfully: #{label}" }
        else
          ctx[:issues][:document_issues] << { type: :mismatched_document, name: label, severity: :blocking, explanation: result["explanation"] }
          Rails.logger.debug { "[KycOnboardingAgent] Document mismatch detected: #{label}, explanation=#{result['explanation']}" }
        end
      rescue JSON::ParserError
        ctx[:issues][:document_issues] << { type: :llm_parse_error, name: label, severity: :warning, raw: raw }
        Rails.logger.warn("[KycOnboardingAgent] LLM parse error for document #{label}, raw=#{raw.inspect}")
      end
    end

    Rails.logger.debug { "[KycOnboardingAgent] Document label consistency check finished. Issues found: #{ctx[:issues][:document_issues].count}" }
  end

  def check_field_to_document_consistency(ctx, investor_kyc:, support_agent:, **)
    mappings = parse_field_document_mappings(support_agent)
    llm = ctx[:llm]

    mappings.each do |doc_name, field_map|
      process_document_consistency(ctx, llm, investor_kyc, doc_name, field_map)
    end

    Rails.logger.debug { "[KycOnboardingAgent] Field-to-document consistency check finished. Issues found: #{ctx[:issues][:document_issues].count}" }
  end

  def parse_field_document_mappings(support_agent)
    validate_fields_with_documents = support_agent.json_fields["validate_fields_with_documents"].to_s
    document_field_map = {}
    validate_fields_with_documents.split(";").each do |doc_mapping|
      doc_name, field_mappings = doc_mapping.split("=")
      next if doc_name.blank? || field_mappings.blank?

      document_field_map[doc_name] = field_mappings.split(",").to_h { |f| f.split(":") }
    end
    document_field_map
  end

  def process_document_consistency(ctx, llm, investor_kyc, doc_name, field_map)
    doc = investor_kyc.documents.find { |d| d.name == doc_name }
    return if doc.nil?

    Rails.logger.debug { "[KycOnboardingAgent] Starting field-to-document consistency check for #{doc.name} (#{field_map.keys.join(', ')}) InvestorKyc ID=#{investor_kyc.id}" }

    extracted = extract_fields_from_document(llm, doc, field_map.keys)
    return unless extracted

    compare_extracted_with_kyc(ctx, doc, investor_kyc, extracted, field_map)
  end

  def extract_fields_from_document(llm, doc, fields)
    prompt = <<~PROMPT
      Extract the following fields from the document:
      #{fields.join(', ')}
      Reply strictly in JSON with the format:
      {"field1": "value1", "field2": "value2", ...}
    PROMPT

    raw = llm.ask(prompt, with: [doc.file.url])
    content = if raw.is_a?(RubyLLM::Message)
                raw.content.is_a?(RubyLLM::Content) ? raw.content.text : raw.content
              else
                raw.to_s
              end
    JSON.parse(content)
  rescue JSON::ParserError
    ctx[:issues][:document_issues] << { type: :llm_parse_error, name: doc.name, severity: :warning, raw: raw }
    Rails.logger.warn("[KycOnboardingAgent] LLM parse error for document #{doc.name}, raw=#{raw.inspect}")
    nil
  end

  def compare_extracted_with_kyc(ctx, doc, investor_kyc, extracted, field_map)
    field_map.each do |doc_field, kyc_field|
      if extracted[doc_field] == investor_kyc[kyc_field]
        Rails.logger.debug { "[KycOnboardingAgent] Field matched: #{doc_field} matches #{kyc_field}" }
      else
        ctx[:issues][:document_issues] << {
          type: :field_mismatch,
          name: doc.name,
          severity: :blocking,
          explanation: "#{doc_field} (#{extracted[doc_field]}) does not match #{kyc_field} (#{investor_kyc[kyc_field]})"
        }
        Rails.logger.debug { "[KycOnboardingAgent] Field mismatch in #{doc.name}: #{doc_field}=#{extracted[doc_field].inspect}, expected #{kyc_field}=#{investor_kyc[kyc_field].inspect}" }
      end
    end
  end

  def perform_ad_hoc_checks(ctx, investor_kyc:, support_agent:, **)
    Rails.logger.debug { "[KycOnboardingAgent] Performing ad-hoc checks if configured for InvestorKyc ID=#{investor_kyc.id} for #{support_agent.id}" }
    # Run optional additional checks based on provided prompts
    # - E.g., source of funds, jurisdiction-specific restrictions
    # - Record output as informational, warning, or blocking issues
    ctx
  end

  def generate_progress_reports(ctx, investor_kyc:, support_agent:, **)
    Rails.logger.debug { "[KycOnboardingAgent] Generating progress report for InvestorKyc ID=#{investor_kyc.id} for #{support_agent.id}" }
    # Generate per-investor and per-fund reports
    # - InvestorKycCompletionReport: field/doc status, consistency, ad-hoc results
    # - FundCompletionReport: daily summaries, % completion, bottlenecks, trends

    report = SupportAgentReport.new(owner: investor_kyc, support_agent: support_agent, json_fields: ctx[:issues])
    report.save
    Rails.logger.debug { "[KycOnboardingAgent] Report generated and saved (Report ID=#{report.id})" }
  end

  def send_reminders(ctx, investor_kyc:, support_agent:, **)
    # Schedule or send reminders via Reminder API
    # - Trigger reminders on configured dates or unresolved blocking issues
    # - Tailor reminder content to missing items (e.g., “Please upload proof of address”)
    Rails.logger.debug { "[KycOnboardingAgent] Preparing reminders for InvestorKyc ID=#{investor_kyc.id}, support_agent=#{support_agent.id}, blocking issues=#{ctx[:issues].inspect}" }
    ctx
  end

  def trigger_aml_if_complete(ctx, investor_kyc:, support_agent:, **)
    # Once verification is marked complete:
    # - Trigger existing AML function automatically
    # - Record AML status in investor’s completion report
    Rails.logger.debug { "[KycOnboardingAgent] Checking AML trigger condition for InvestorKyc ID=#{investor_kyc.id} for #{support_agent.id}" }
    ctx
  end
end
