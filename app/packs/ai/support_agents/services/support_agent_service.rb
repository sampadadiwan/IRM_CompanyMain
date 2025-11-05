class SupportAgentService < Trailblazer::Operation
  def initialize_agent(ctx, **)
    @support_agent = SupportAgent.find(ctx[:support_agent_id])
    ctx[:support_agent] = @support_agent
    model = ctx[:llm] || ENV["SUPPORT_AGENT_MODEL"] || "gemini-2.5-flash" # || "gpt-5"
    ctx[:llm] = RubyLLM.chat(model: model)
  end

  # Verifies all required documents (from form fields and support_agent config)
  # are uploaded by the investor.
  def check_document_presence(ctx, model:, support_agent:, **)
    if enabled?("validate_documents")

      if model.present?
        Rails.logger.debug { "[#{self.class.name}] Starting document presence check for InvestorKyc ID=#{model.id}" }
        # List of required documents from form and support agent json fields
        check_all_docs = ctx[:check_all_docs].present?
        required_docs = if check_all_docs
                          model.form_custom_fields.where(field_type: "File").map(&:label)
                        else
                          model.required_fields_for(field_type: "File").map(&:label)
                        end
        required_docs += support_agent.json_fields["required_docs"].to_s.split(",").map(&:strip)
        required_docs.uniq!

        Rails.logger.debug { "Required documents: #{required_docs.inspect}" }

        uploaded_docs = model.documents.pluck(:name).uniq

        required_docs.each do |name|
          unless uploaded_docs.include?(name)
            ctx[:issues][:document_issues] << { type: :missing, message: name, severity: :blocking }
            Rails.logger.debug { "[#{self.class.name}] Missing document detected: #{name}" }
          end
        end
        ctx[:issues][:document_issues] << { type: :info, message: "All required documents are present", severity: :success } if ctx[:issues][:document_issues].empty?
        Rails.logger.debug { "[#{self.class.name}] Document presence check completed. Issues found: #{ctx[:issues][:document_issues].count}" }
      else
        ctx[:issues][:document_issues] << { type: :missing, message: "No record found for document check", severity: :blocking }
        Rails.logger.warn { "[#{self.class.name}] No model provided for document presence check." }
      end
    else
      Rails.logger.debug { "[#{self.class.name}] Document validation is disabled, skipping check." }
    end
  end

  # Generates per-investor/fund reports summarizing issues and state.
  # Stores report as persisted SupportAgentReport record.
  def generate_progress_reports(ctx, model:, support_agent:, **)
    Rails.logger.debug { "[#{self.class.name}] Generating progress report for InvestorKyc ID=#{model.id} for #{support_agent.id}" }

    report = SupportAgentReport.find_or_initialize_by(owner: model, support_agent: support_agent)

    # WE need to cleanup issues where the message is nil or empty
    ctx[:issues].each_value do |issues|
      issues.reject! { |issue| issue[:message].blank? }
    end

    report.json_fields = ctx[:issues]
    report.status = ctx[:issues].values.flatten.any? { |issue| issue[:severity] == :blocking } ? SupportAgentReport.statuses[:failed] : SupportAgentReport.statuses[:completed]
    report.save

    ctx[:support_agent_report] = report
    Rails.logger.debug { "[self.class.name] Report generated and saved (Report ID=#{report.id})" }
    report.valid?
  end

  def enabled?(field)
    %w[true 1 enabled yes].include? @support_agent.json_fields[field]&.downcase
  end
end
