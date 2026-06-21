class KycOnboardingAgent < SupportAgentService
  DESCRIPTION = "Orchestrates a multi-step verification pipeline for InvestorKYC records, validating fields and documents.".freeze

  LONG_DESCRIPTION = <<~DESC.freeze
    Orchestrates a complete KYC verification pipeline for each InvestorKYC record in the entity.
    Targets completed KYC records and runs a fixed sequence of validation steps.

    Steps:
    • Field Completeness — checks that all mandatory fields (defined in FormCustomField) are populated.
    • Document Presence — verifies required document types (passport, ID, etc.) have been uploaded.
    • Document Validity — validates document content and labels against expected criteria.
    • Field-to-Document Consistency — ensures field values match the uploaded document data.
    • Expiry Status — flags documents approaching or past their expiry date.
    • Send Reminders — notifies investors about missing or expiring items.
    • Trigger AML — automatically initiates AML screening once all checks pass.

    Supports both scheduled (daily/weekly) and event-driven runs (on new InvestorKyc, document
    upload, or field update). Results are saved as SupportAgentReports with per-step issue tracking.
  DESC

  STEP_LABELS = {
    initialize_agent: "Initialize",
    check_field_completeness: "Field Completeness",
    check_document_presence: "Document Presence",
    check_document_validity: "Document Validity",
    check_field_to_document_consistency: "Field-Doc Consistency",
    check_expiry_status: "Expiry Status",
    send_reminders: "Send Reminders",
    trigger_aml_if_complete: "Trigger AML",
    generate_progress_reports: "Save Report"
  }.freeze

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
  step :check_expiry_status
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
    # Include :entity to avoid an N+1 query when trigger_aml_if_complete
    # resolves entity.employees.active.first for each KYC record.
    InvestorKyc.completed.where(entity_id: entity_id).includes(:documents, :investor, :entity)
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
    report = ctx[:support_agent_report]
    mark_step_running(report, :initialize_agent) if report
    investor_kyc = target
    # Initialize execution ctx with a single investor_kyc
    # Setup history, logging, or state tracking for this run
    Rails.logger.debug { "[KycOnboardingAgent] Initializing agent for InvestorKyc ID=#{investor_kyc.id}" }
    ctx[:investor_kyc] = investor_kyc
    ctx[:issues] = { field_issues: [], document_issues: [], aml_report: [] }
    mark_step_success(report, :initialize_agent, message: "Initialized for InvestorKyc #{investor_kyc.id}") if report
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
    report = ctx[:support_agent_report]
    mark_step_running(report, :check_field_completeness) if report

    if enabled?("validate_fields")

      Rails.logger.debug { "[KycOnboardingAgent] Starting field completeness check for InvestorKyc ID=#{investor_kyc.id}" }

      # Common invalid tokens used as placeholders that must be treated as invalid
      invalid_tokens = %w[N/A NA UNKNOWN UNK NONE TEST --].map(&:downcase)

      validate_required_attributes(ctx, investor_kyc, invalid_tokens)
      validate_custom_fields(ctx, investor_kyc, invalid_tokens)

      mark_step_success(report, :check_field_completeness, message: "Checked fields - #{ctx[:issues][:field_issues].count} issues") if report

      Rails.logger.debug { "[KycOnboardingAgent] Field completeness check completed. Issues found: #{ctx[:issues][:field_issues].count}" }
      ctx
    else
      Rails.logger.debug { "[KycOnboardingAgent] Field validation is disabled, skipping check." }
      mark_step_skipped(report, :check_field_completeness, message: "Disabled") if report
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
    invalid_count = 0
    required_attrs.each do |attr|
      value = investor_kyc.public_send(attr)
      next unless value.is_a?(String)

      str_val = value.strip
      next unless str_val.empty? || invalid_tokens.include?(str_val.downcase)

      Rails.logger.debug { "[KycOnboardingAgent] Invalid required field detected: #{attr}=#{value.inspect}" }
      ctx[:issues][:field_issues] << { type: :invalid_field_value, message: attr, value: value, severity: :blocking }
      invalid_count += 1
    end

    ctx[:issues][:field_issues] << { type: :info, message: "All required attributes are valid", severity: :success } if invalid_count.zero?

    true
  end

  # Validates custom form fields according to type-specific logic.
  # For select fields, ensures value belongs to defined options.
  # For text/other, ensures non-empty and not in invalid tokens.
  def validate_custom_fields(ctx, investor_kyc, invalid_tokens)
    invalid_count = 0

    investor_kyc.required_fields_for.each do |fcf|
      value = investor_kyc.json_fields[fcf.name]
      str_val = value.to_s.strip

      if fcf.field_type == "File"
        next # Skip file fields here, handled in document presence check
      elsif fcf.field_type == "Select"
        options = fcf.meta_data.split(",").map(&:strip).compact_blank
        unless options.include?(str_val) || str_val.empty?
          ctx[:issues][:field_issues] << { type: :invalid, message: fcf.name, value: value, severity: :blocking }
          Rails.logger.debug { "[KycOnboardingAgent] Invalid select field value for #{fcf.name}: #{value.inspect}" }
          invalid_count += 1
        end
      elsif str_val.empty? || invalid_tokens.include?(str_val.downcase)
        ctx[:issues][:field_issues] << { type: :invalid, message: fcf.name, value: value, severity: :blocking }
        Rails.logger.debug { "[KycOnboardingAgent] Invalid JSON field detected: #{fcf.name}=#{value.inspect}" }
        invalid_count += 1
      end
    end

    ctx[:issues][:field_issues] << { type: :info, message: "All required custom fields are valid", severity: :success } if invalid_count.zero?
  end

  # Verifies all required documents (from form fields and support_agent config)
  # are uploaded by the investor.
  def check_document_presence(ctx, investor_kyc:, support_agent:, **)
    report = ctx[:support_agent_report]
    mark_step_running(report, :check_document_presence) if report
    super(ctx, model: investor_kyc, support_agent: support_agent)
    mark_step_success(report, :check_document_presence, message: "Documents checked") if report
    true
  end

  # Uses LLM to validate each uploaded document against its label.
  # Records mismatched or unparsable responses as issues.
  # Returns true in all branches so Trailblazer continues to the next step.
  def check_document_validity(ctx, investor_kyc:, **)
    report = ctx[:support_agent_report]
    mark_step_running(report, :check_document_validity) if report

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

        begin
          raw = llm.ask(prompt, with: [doc.file.url])
          content = if raw.is_a?(RubyLLM::Message)
                      raw.content.is_a?(RubyLLM::Content) ? raw.content.text : raw.content
                    else
                      raw.to_s
                    end

          content = content.sub(/\A```(?:json)?/i, "").sub(/```$/, "").strip
          result = JSON.parse(content)
          if result["matches"]
            ctx[:issues][:document_issues] << { type: :info, name: doc.name, message: "Valid #{label}", severity: :success }
            Rails.logger.debug { "[KycOnboardingAgent] Document validated successfully: #{label}" }
          else
            ctx[:issues][:document_issues] << { type: :mismatched_document, name: doc.name, message: "Invalid #{label}", severity: :blocking, explanation: result["explanation"] }
            Rails.logger.debug { "[KycOnboardingAgent] Document mismatch detected: #{label}, explanation=#{result['explanation']}" }
          end
        rescue JSON::ParserError
          ctx[:issues][:document_issues] << { type: :llm_parse_error, name: doc.name, message: "Could not ascertain #{label}", severity: :warning, raw: raw }
          Rails.logger.warn("[KycOnboardingAgent] LLM parse error for document #{label}, raw=#{raw.inspect}")
        rescue Faraday::ResourceNotFound, Faraday::Error => e
          ctx[:issues][:document_issues] << { type: :document_unavailable, name: doc.name, message: "Document file not accessible (#{e.class})", severity: :warning }
          Rails.logger.warn("[KycOnboardingAgent] Document file unavailable for #{label}: #{e.message.lines.first.chomp}")
        rescue Errno::ENOENT => e
          # doc.file.url returns a web-relative path (/uploads/...) in local/test storage.
          # RubyLLM treats it as an absolute filesystem path and raises ENOENT when the
          # file doesn't exist there (the file lives at Rails.root/public/uploads/...).
          # Log a warning and skip validity checking rather than crashing the pipeline.
          ctx[:issues][:document_issues] << { type: :document_unavailable, name: doc.name, message: "Document file not accessible locally (#{e.class})", severity: :warning }
          Rails.logger.warn("[KycOnboardingAgent] Document file not found on filesystem for #{label}: #{e.message.lines.first.chomp}")
        end
      end

      Rails.logger.debug { "[KycOnboardingAgent] Document label consistency check finished. Issues found: #{ctx[:issues][:document_issues].count}" }
    else
      Rails.logger.debug { "[KycOnboardingAgent] Document validation is disabled, skipping check." }
      mark_step_skipped(report, :check_document_validity, message: "Disabled") if report
    end
    # Explicit true so Trailblazer does not route to the failure track.
    # Document issues are collected above; the step itself always succeeds.
    mark_step_success(report, :check_document_validity, message: "Document validity checked") if report
    true
  end

  # Delegates consistency verification between documents and fields
  # to the SupportAgent instance already configured.
  # Returns true in all branches so Trailblazer continues to the next step.
  def check_field_to_document_consistency(ctx, investor_kyc:, support_agent:, **)
    report = ctx[:support_agent_report]
    mark_step_running(report, :check_field_to_document_consistency) if report

    if enabled?("validate_documents")
      support_agent.check_field_to_document_consistency(ctx, investor_kyc)
      Rails.logger.debug { "[KycOnboardingAgent] Field-to-document consistency check finished. Issues found: #{ctx[:issues][:document_issues].count}" }
    else
      Rails.logger.debug { "[KycOnboardingAgent] Document validation is disabled, skipping field-to-document consistency check." }
      mark_step_skipped(report, :check_field_to_document_consistency, message: "Disabled") if report
    end
    # Explicit true so Trailblazer does not route to the failure track regardless
    # of what support_agent.check_field_to_document_consistency returns.
    mark_step_success(report, :check_field_to_document_consistency, message: "Consistency checked") if report
    true
  end

  # Generates per-investor/fund reports summarizing issues and state.
  # Stores report as persisted SupportAgentReport record.
  def generate_progress_reports(ctx, investor_kyc:, support_agent:, **)
    report = ctx[:support_agent_report]
    mark_step_running(report, :generate_progress_reports) if report
    super(ctx, model: investor_kyc, support_agent: support_agent)
    if report
      mark_step_success(report, :generate_progress_reports, message: "Report saved")
      finalize_report(report, status: "ready")
    end
    true
  end

  # Checks whether the KYC record is expired or approaching expiry.
  # Adds a blocking issue if expired, a warning if within configured thresholds.
  #
  # Configurable via json_fields:
  #   check_expiry        — "true"/"false" (default true)
  #   expiry_warning_days — comma-separated day thresholds, e.g. "60,30,15"
  def check_expiry_status(ctx, investor_kyc:, **)
    report = ctx[:support_agent_report]
    mark_step_running(report, :check_expiry_status) if report

    unless enabled?("check_expiry")
      Rails.logger.debug { "[KycOnboardingAgent] Expiry check disabled, skipping." }
      mark_step_skipped(report, :check_expiry_status, message: "Disabled") if report
      return true
    end

    expiry_date = investor_kyc.expiry_date

    if expiry_date.nil?
      ctx[:issues][:field_issues] << { type: :info, message: "No expiry date set", severity: :success }
      mark_step_success(report, :check_expiry_status, message: "No expiry date set") if report
      return true
    end

    # Use Time.zone.today so the date is evaluated in the Rails application timezone,
    # not the OS system timezone. Date.today can be off by a day near midnight
    # when the server timezone differs from the configured app timezone.
    days_remaining = (expiry_date - Time.zone.today).to_i
    warning_thresholds = @support_agent.json_fields["expiry_warning_days"]
                                       &.split(",")&.map(&:to_i) || [60, 30, 15]

    if investor_kyc.expired?
      ctx[:issues][:field_issues] << {
        type: :kyc_expired,
        message: "KYC expired on #{expiry_date}",
        severity: :blocking
      }
      Rails.logger.warn { "[KycOnboardingAgent] KYC expired for InvestorKyc ID=#{investor_kyc.id}" }
      mark_step_success(report, :check_expiry_status, message: "Expired on #{expiry_date}") if report
    elsif warning_thresholds.any? { |d| days_remaining <= d }
      ctx[:issues][:field_issues] << {
        type: :kyc_expiring_soon,
        message: "KYC expires in #{days_remaining} day(s) on #{expiry_date}",
        severity: :warning
      }
      Rails.logger.info { "[KycOnboardingAgent] KYC expiring soon for InvestorKyc ID=#{investor_kyc.id}: #{days_remaining} days remaining" }
      mark_step_success(report, :check_expiry_status, message: "Expires in #{days_remaining} days") if report
    else
      ctx[:issues][:field_issues] << {
        type: :info,
        message: "KYC valid until #{expiry_date} (#{days_remaining} days remaining)",
        severity: :success
      }
      mark_step_success(report, :check_expiry_status, message: "Valid until #{expiry_date}") if report
    end
    true
  end

  # Sends expiry alert emails when blocking or warning expiry issues are found.
  #
  # Configurable via json_fields:
  #   send_reminder — "true"/"false" (default true)
  def send_reminders(ctx, investor_kyc:, support_agent:, **)
    report = ctx[:support_agent_report]
    mark_step_running(report, :send_reminders) if report

    unless enabled?("send_reminder")
      Rails.logger.debug { "[KycOnboardingAgent] Reminder sending disabled, skipping." }
      mark_step_skipped(report, :send_reminders, message: "Disabled") if report
      return true
    end

    expiry_types = %i[kyc_expired kyc_expiring_soon]
    expiry_issues = ctx[:issues][:field_issues].select { |i| expiry_types.include?(i[:type]) }

    if expiry_issues.empty?
      Rails.logger.debug { "[KycOnboardingAgent] No expiry issues for InvestorKyc ID=#{investor_kyc.id} — skipping reminder." }
      mark_step_skipped(report, :send_reminders, message: "No expiry issues to send") if report
      return true
    end

    KycExpiryMailer.with(
      investor_kyc_id: investor_kyc.id,
      issues: expiry_issues,
      entity_id: support_agent.entity_id
    ).expiry_alert.deliver_later

    mark_step_success(report, :send_reminders, message: "Reminder queued") if report

    Rails.logger.info { "[KycOnboardingAgent] Expiry alert queued for InvestorKyc ID=#{investor_kyc.id}" }
    true
  end

  # Triggers AML workflow if KYC process is complete with no blocking issues.
  # Skips gracefully when AML is disabled, no active employee exists, or blocking issues remain.
  # Returns true in all branches so Trailblazer marks the operation as successful.
  def trigger_aml_if_complete(ctx, investor_kyc:, support_agent:, **)
    report = ctx[:support_agent_report]
    mark_step_running(report, :trigger_aml_if_complete) if report

    unless enabled?("trigger_aml")
      Rails.logger.debug { "[KycOnboardingAgent] AML triggering is disabled, skipping." }
      mark_step_skipped(report, :trigger_aml_if_complete, message: "Disabled") if report
      return true
    end

    Rails.logger.debug { "[KycOnboardingAgent] Checking AML trigger condition for InvestorKyc ID=#{investor_kyc.id} for #{support_agent.id}" }

    # Guard: entity must have at least one active employee to act as the AML requestor.
    # entity is eager-loaded via targets; employees.active is a filtered query.
    employee = investor_kyc.entity&.employees&.active&.first
    if employee.nil?
      Rails.logger.warn { "[KycOnboardingAgent] No active employee found for entity — skipping AML trigger for InvestorKyc ID=#{investor_kyc.id}" }
      report.json_fields["aml_report"] << { message: "Not triggered - no active entity employee found", type: "skipped" }
      report.save
      mark_step_skipped(report, :trigger_aml_if_complete, message: "No active employee") if report
      return true
    end

    if ctx[:issues][:field_issues].none? { |i| i[:severity] == :blocking } && ctx[:issues][:document_issues].none? { |i| i[:severity] == :blocking }
      Rails.logger.info { "[KycOnboardingAgent] KYC complete with no blocking issues, triggering AML check for InvestorKyc ID=#{investor_kyc.id}" }
      GenerateAmlReportJob.perform_later(investor_kyc.id, employee.id)
      # "aml_report" uses a string key to match generate_progress_reports, which stringifies
      # ctx[:issues] keys before merging into json_fields (ensuring DB/in-memory consistency).
      report.json_fields["aml_report"] << { message: "Triggered", triggered_at: Time.current, type: "completed" }
      report.save
      mark_step_success(report, :trigger_aml_if_complete, message: "AML triggered") if report
    else
      report.json_fields["aml_report"] << { message: "Not triggered - KYC incomplete or blocking issues present", type: "skipped" }
      report.save
      Rails.logger.info { "[KycOnboardingAgent] KYC not complete or has blocking issues, skipping AML trigger for InvestorKyc ID=#{investor_kyc.id}" }
      mark_step_skipped(report, :trigger_aml_if_complete, message: "Blocking issues present") if report
    end

    true
  end
end
