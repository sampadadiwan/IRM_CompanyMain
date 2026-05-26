class SupportAgentService < Trailblazer::Operation
  # Class-level step labels that can be overridden by subclasses
  STEP_LABELS = {}.freeze

  # Returns step definitions introspected from the Trailblazer operation
  def self.step_definitions
    nodes = Trailblazer::Activity::Introspect.Nodes(self)
    steps = nodes.values
                 .map(&:id)
                 .reject { |id| id.to_s.start_with?("Start.", "End.") }

    steps.map.with_index(1) do |step_id, index|
      {
        step: index,
        id: step_id.to_s,
        label: step_label(step_id),
        short_label: short_label(step_id)
      }
    end
  end

  def self.step_label(step_id)
    const_get(:STEP_LABELS)[step_id.to_sym] || step_id.to_s.humanize
  rescue NameError
    step_id.to_s.humanize
  end

  def self.short_label(step_id)
    step_label(step_id).truncate(12, omission: '')
  end

  def initialize_agent(ctx, **)
    @support_agent = SupportAgent.find(ctx[:support_agent_id])
    ctx[:support_agent]= @support_agent
    ctx[:llm] = LlmService.ruby_llm_chat(entity: @support_agent.entity, model: @support_agent.effective_model)
  end

  # Verifies all required documents (from form fields and support_agent config)
  # are uploaded by the investor.
  #
  # Returns true in all branches so Trailblazer continues to the next step.
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
    # Explicit true: Trailblazer treats any falsy step return as failure and
    # short-circuits the remaining pipeline. Missing issues are recorded above;
    # the step itself should always succeed so subsequent steps still run.
    true
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

    # Preserve existing metadata (triggered_by, triggered_by_user_id, run_at, etc.) by merging instead of replacing.
    # Stringify ctx[:issues] keys so json_fields stays consistent with string-keyed DB round-trips.
    # Without this, symbol keys (e.g. :aml_report) merged in-memory would differ from the string
    # keys ("aml_report") used by callers that read json_fields after a DB reload.
    has_blocking = ctx[:issues].values.flatten.any? { |issue| issue[:severity] == :blocking }
    report.json_fields = (report.json_fields || {}).merge(ctx[:issues].transform_keys(&:to_s)).merge(
      "final_status" => has_blocking ? "blocked" : "ready",
      "completed_at" => Time.current.iso8601
    )
    # MySQL doesn't auto-detect JSON field changes, must explicitly mark as changed
    report.json_fields_will_change!
    report.status = has_blocking ? SupportAgentReport.statuses[:failed] : SupportAgentReport.statuses[:completed]
    report.save

    ctx[:support_agent_report] = report
    Rails.logger.debug { "[#{self.class.name}] Report generated and saved (Report ID=#{report.id})" }
    report.valid?
  end

  def enabled?(field)
    %w[true 1 enabled yes].include? @support_agent.json_fields[field]&.downcase
  end

  # Initializes a SupportAgentReport with step definitions
  def initialize_report_with_steps(ctx, model:, support_agent:, user_id: nil, **)
    report = SupportAgentReport.find_or_initialize_by(owner: model, support_agent: support_agent)

    steps = self.class.step_definitions.map do |step_def|
      {
        "step" => step_def[:step],
        "id" => step_def[:id],
        "label" => step_def[:label],
        "short_label" => step_def[:short_label],
        "status" => "pending"
      }
    end

    report.json_fields = {
      "steps" => steps,
      "final_status" => "running",
      "triggered_by" => user_id.present? ? "manual" : "scheduled",
      "triggered_by_user_id" => user_id,
      "run_at" => Time.current.iso8601
    }
    report.status = :pending
    report.save!

    ctx[:support_agent_report] = report
    report
  end

  # Broadcasts a step update via Turbo Streams
  def broadcast_step(report, step_id, status:, message: nil, count: nil, failed_records: nil)
    step_data = report.json_fields["steps"]&.find { |s| s["id"] == step_id.to_s }
    return unless step_data

    step_data["started_at"] = Time.current.iso8601 if status.to_s == "running"
    step_data["status"] = status.to_s
    step_data["message"] = message if message
    step_data["count"] = count if count
    step_data["failed_records"] = failed_records if failed_records

    if status.to_s.in?(%w[success failed skipped])
      step_data["completed_at"] = Time.current.iso8601
      if step_data["started_at"].present?
        started = Time.zone.parse(step_data["started_at"])
        step_data["duration_ms"] = ((Time.current - started) * 1000).round
      end
    end

    report.save!

    Turbo::StreamsChannel.broadcast_replace_to(
      "support_agent_report_#{report.id}",
      target: "step_#{step_data['step']}",
      partial: "support_agents/step_circle",
      locals: { step: step_data }
    )

    Turbo::StreamsChannel.broadcast_replace_to(
      "support_agent_report_#{report.id}",
      target: "progress_bar_#{report.id}",
      partial: "support_agents/progress_bar",
      locals: { report: report }
    )
  end

  def mark_step_running(report, step_id)
    broadcast_step(report, step_id, status: :running)
  end

  def mark_step_success(report, step_id, message: nil, count: nil)
    broadcast_step(report, step_id, status: :success, message: message, count: count)
  end

  def mark_step_failed(report, step_id, message: nil, count: nil, failed_records: nil)
    broadcast_step(report, step_id, status: :failed, message: message, count: count, failed_records: failed_records)
  end

  def mark_step_skipped(report, step_id, message: nil)
    broadcast_step(report, step_id, status: :skipped, message: message)
  end

  def finalize_report(report, status:, failed_step: nil)
    report.json_fields["final_status"] = status.to_s
    report.json_fields["failed_step"] = failed_step if failed_step
    report.json_fields["completed_at"] = Time.current.iso8601

    if report.json_fields["run_at"].present?
      run_at = Time.zone.parse(report.json_fields["run_at"])
      report.json_fields["total_duration_ms"] = ((Time.current - run_at) * 1000).round
    end

    report.status = status.to_s == "ready" ? :completed : :failed
    report.save!

    Turbo::StreamsChannel.broadcast_replace_to(
      "support_agent_report_#{report.id}",
      target: "progress_panel_#{report.id}",
      partial: "support_agents/progress_panel",
      locals: { report: report, support_agent: report.support_agent, target: report.owner, collapsed: false }
    )
  end

  def cancelled?(report)
    report.reload
    report.json_fields["cancelled_at"].present?
  end
end
