class KycOnboardingAgent < SupportAgentService
  # KycOnboardingAgent orchestrates a multi-step verification pipeline
  # for InvestorKYC records. It checks fields, validates documents
  # against expected content/labels, ensures consistency, creates reports,
  # sends necessary reminders, and triggers AML screening if complete.
  #
  # This service inherits from AgentBaseService, leveraging Trailblazer's
  # `step` construct to define a linear pipeline of operations with
  # shared execution context.
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
  step :check_field_completeness
  step :check_document_presence
  step :check_document_validity
  step :check_field_to_document_consistency
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
  # - Reminders correctly triggered and contextual
  # - AML checks auto-triggered on completion

  def targets(entity_id)
    InvestorKyc.completed.where(entity_id: entity_id).includes(:documents, :investor)
  end

  private

  # Initializes the agent with the investor_kyc under review.
  # Sets up the shared context including issue tracking hashes.
  #
  # @param ctx [Hash] Trailblazer execution context
  # @param investor_kyc [InvestorKyc] record under verification
  # @return [Boolean] truthy if KYC is completed and eligible for processing
  def initialize_agent(ctx, target:, **)
    super
    investor_kyc = target
    # Initialize execution ctx with a single investor_kyc
    # Setup history, logging, or state tracking for this run
    Rails.logger.debug { "[KycOnboardingAgent] Initializing agent for InvestorKyc ID=#{investor_kyc.id}" }
    ctx[:investor_kyc] = investor_kyc
    ctx[:issues] = { field_issues: [], document_issues: [], aml_report: [] }
    # Only process if completed by investor and agent is enabled
    investor_kyc.completed_by_investor && @support_agent.enabled?
  end

  # Verifies required attributes and custom fields are populated
  # with valid values that are not placeholders (N/A, UNKNOWN, etc.).
  #
  # @param ctx [Hash] execution context including issues
  # @param investor_kyc [InvestorKyc] record being checked
  # @return [Hash] updated context
  def check_field_completeness(ctx, investor_kyc:, **)
    if enabled?("validate_fields")

      Rails.logger.debug { "[KycOnboardingAgent] Starting field completeness check for InvestorKyc ID=#{investor_kyc.id}" }

      # Common invalid tokens used as placeholders that must be treated as invalid
      invalid_tokens = %w[N/A NA UNKNOWN UNK NONE TEST --].map(&:downcase)

      validate_required_attributes(ctx, investor_kyc, invalid_tokens)
      validate_custom_fields(ctx, investor_kyc, invalid_tokens)

      Rails.logger.debug { "[KycOnboardingAgent] Field completeness check completed. Issues found: #{ctx[:issues][:field_issues].count}" }
      ctx
    else
      Rails.logger.debug { "[KycOnboardingAgent] Field validation is disabled, skipping check." }
      true
    end
  end

  # Validates all required DB attributes (from schema or validators)
  # ensuring they are not empty or invalid tokens.
  #
  # @param ctx [Hash] execution context
  # @param investor_kyc [InvestorKyc]
  # @param invalid_tokens [Array<String>] recognized invalid values
  def validate_required_attributes(ctx, investor_kyc, invalid_tokens)
    required_db_columns = investor_kyc.class.columns.select { |c| !c.null && c.default.nil? }.map(&:name)
    required_validated_fields = investor_kyc.class._validators.select do |_, validators|
      validators.any?(ActiveModel::Validations::PresenceValidator)
    end.keys.map(&:to_s)
    required_attrs = (required_db_columns | required_validated_fields)

    required_attrs.each do |attr|
      value = investor_kyc.public_send(attr)
      next unless value.is_a?(String)

      str_val = value.strip
      if str_val.empty? || invalid_tokens.include?(str_val.downcase)
        Rails.logger.debug { "[KycOnboardingAgent] Invalid required field detected: #{attr}=#{value.inspect}" }
        ctx[:issues][:field_issues] << { type: :invalid_field_value, field: attr, value: value, severity: :blocking }
      end
    end
  end

  # Validates custom form fields according to type-specific logic.
  # For select fields, ensures value belongs to defined options.
  # For text/other, ensures non-empty and not in invalid tokens.
  def validate_custom_fields(ctx, investor_kyc, invalid_tokens)
    investor_kyc.required_fields_for.each do |fcf|
      value = investor_kyc.json_fields[fcf.name]
      str_val = value.to_s.strip

      if fcf.field_type == "File"
        next # Skip file fields here, handled in document presence check
      elsif fcf.field_type == "Select"
        options = fcf.meta_data.split(",").map(&:strip).compact_blank
        unless options.include?(str_val) || str_val.empty?
          ctx[:issues][:field_issues] << { type: :invalid_select_field_value, field: fcf.name, value: value, severity: :blocking }
          Rails.logger.debug { "[KycOnboardingAgent] Invalid select field value for #{fcf.name}: #{value.inspect}" }
        end
      elsif str_val.empty? || invalid_tokens.include?(str_val.downcase)
        ctx[:issues][:field_issues] << { type: :invalid, field: fcf.name, value: value, severity: :blocking }
        Rails.logger.debug { "[KycOnboardingAgent] Invalid JSON field detected: #{fcf.name}=#{value.inspect}" }
      end
    end
  end

  # Verifies all required documents (from form fields and support_agent config)
  # are uploaded by the investor.
  def check_document_presence(ctx, investor_kyc:, support_agent:, **)
    super(ctx, model: investor_kyc, support_agent: support_agent)
  end

  # Uses LLM to validate each uploaded document against its label.
  # Records mismatched or unparsable responses as issues.
  def check_document_validity(ctx, investor_kyc:, **)
    if enabled?("validate_documents")
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

          content = content.sub(/\A```(?:json)?/i, "").sub(/```$/, "").strip
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
    else
      Rails.logger.debug { "[KycOnboardingAgent] Document validation is disabled, skipping check." }
    end
  end

  # Delegates consistency verification between documents and fields
  # to the SupportAgent instance already configured.
  def check_field_to_document_consistency(ctx, investor_kyc:, support_agent:, **)
    if enabled?("validate_documents")
      support_agent.check_field_to_document_consistency(ctx, investor_kyc)
      Rails.logger.debug { "[KycOnboardingAgent] Field-to-document consistency check finished. Issues found: #{ctx[:issues][:document_issues].count}" }
    else
      Rails.logger.debug { "[KycOnboardingAgent] Document validation is disabled, skipping field-to-document consistency check." }
    end
  end

  # Generates per-investor/fund reports summarizing issues and state.
  # Stores report as persisted SupportAgentReport record.
  def generate_progress_reports(ctx, investor_kyc:, support_agent:, **)
    super(ctx, model: investor_kyc, support_agent: support_agent)
  end

  # Schedules reminder notifications when blocking issues are identified.
  # Actual sending handled by external Reminder API integration.
  def send_reminders(ctx, investor_kyc:, support_agent:, **)
    if enabled?("send_reminder")
      Rails.logger.debug { "[KycOnboardingAgent] Preparing reminders for InvestorKyc ID=#{investor_kyc.id}, support_agent=#{support_agent.id}, blocking issues=#{ctx[:issues].inspect}" }
    else
      Rails.logger.debug { "[KycOnboardingAgent] Reminder sending is disabled, skipping." }
    end
  end

  # Triggers AML workflow if KYC process is complete.
  # Invokes external AML check integration logic downstream.
  def trigger_aml_if_complete(ctx, investor_kyc:, support_agent:, **)
    if enabled?("trigger_aml")
      Rails.logger.debug { "[KycOnboardingAgent] Checking AML trigger condition for InvestorKyc ID=#{investor_kyc.id} for #{support_agent.id}" }
      if ctx[:issues][:field_issues].none? { |i| i[:severity] == :blocking } && ctx[:issues][:document_issues].none? { |i| i[:severity] == :blocking }
        Rails.logger.info { "[KycOnboardingAgent] KYC complete with no blocking issues, triggering AML check for InvestorKyc ID=#{investor_kyc.id}" }
        # TODO: - which user should be passed into triggering the AML?
        GenerateAmlReportJob.perform_later(investor_kyc.id, investor_kyc.entity.employees.active.first.id)
        report = ctx[:support_agent_report]
        report.json_fields[:aml_report] << { message: "Triggered", triggered_at: Time.current, type: "completed" }
        report.save
      else
        report = ctx[:support_agent_report]
        report.json_fields[:aml_report] << { message: "Not triggered - KYC incomplete or blocking issues present", type: "skipped" }
        report.save
        Rails.logger.info { "[KycOnboardingAgent] KYC not complete or has blocking issues, skipping AML trigger for InvestorKyc ID=#{investor_kyc.id}" }
      end
    else
      Rails.logger.debug { "[KycOnboardingAgent] AML triggering is disabled, skipping." }
    end
  end
end
