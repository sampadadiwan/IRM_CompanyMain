class PortfolioCompanyAgent < SupportAgentService
  DESCRIPTION = "Monitors portfolio companies for KPI submissions, document presence, and valuation accuracy.".freeze
  step :initialize_agent
  # == Core Functions ==
  step :check_kpi_submission
  step :send_kpi_reminder
  step :check_document_presence
  step :check_valuations
  step :generate_progress_reports

  def targets(entity_id)
    # Accept either an Investor instance (single target) or an entity_id (return relation)
    if entity_id.is_a?(Investor) || entity_id.is_a?(ActiveRecord::Base)
      [entity_id]
    else
      Investor.where(entity_id: entity_id, category: "Portfolio Company").includes(:kpi_reports, :valuations)
    end
  end

  # Batch processor for PortfolioCompanyAgent — shared by adhoc and scheduled runs.
  #
  # EXECUTION MODES:
  # - :adhoc_batch  — triggered manually from the portfolio agent run UI
  # - :scheduled    — triggered by AgentRunnerJob (cron); no per-company chat UI,
  #                   chart job runs silently, batch summary notification is suppressed
  #
  # Processes targets sequentially (one Trailblazer call per company), collects
  # successes/errors, enqueues a single AgentChartJob for all processed ids,
  # and emits a batch summary notification (skipped for :scheduled mode).
  #
  # @param support_agent_id [Integer]
  # @param targets [Array, ActiveRecord::Relation] Investor records to process
  # @param user_id [Integer, nil] nil for scheduled runs
  # @param entity_id [Integer]
  # @param execution_mode [Symbol] :adhoc_batch or :scheduled
  def self.process_batch(support_agent_id:, targets:, user_id:, entity_id:, with_steps: false, execution_mode: :adhoc_batch) # rubocop:disable Lint/UnusedMethodArgument
    support_agent = SupportAgent.find(support_agent_id)

    # Preload commonly used associations to avoid N+1 queries
    targets = targets.includes(:portfolio_kpi_reports, :documents, :valuations) if targets.respond_to?(:includes)

    successes = []
    errors = []

    # Batch mode always runs with_steps=false (no step-by-step UI for batch)
    # Sequential processing (no threading) per user requirement
    targets.to_a.each do |target|
      begin
        support_agent.agent.wtf?(support_agent_id: support_agent_id, target: target, user_id: user_id, entity_id: entity_id, batch_mode: true)
        successes << { id: target.id, name: target.try(:investor_name) || target.try(:name) || "ID=#{target.id}" }
      rescue StandardError => e
        Rails.logger.error { "PortfolioCompanyAgent.process_batch error for Target ID=#{target.id}: #{e.message}" }
        Rails.logger.error { e.backtrace.join("\n") }
        errors << { target_id: target.id, target_name: target.try(:investor_name) || target.try(:name) || "ID=#{target.id}", error: e.message }
      end
    end

    # Enqueue a single AgentChartJob for all processed portfolio companies
    if successes.any?
      processed_ids = successes.map { |s| s[:id] }
      AgentChartJob.perform_later(user_id, portfolio_company_ids: processed_ids.uniq, execution_mode: execution_mode)
    end

    # Send batch summary notification (skip for :scheduled mode, charts will notify separately)
    if execution_mode != :scheduled
      begin
        batch_target_type = targets.first.class.name if targets.any?
        SupportAgentJob.new.send(:send_batch_summary, support_agent, successes, errors, user_id, batch_target_type) if defined?(SupportAgentJob)
      rescue StandardError => e
        Rails.logger.error { "PortfolioCompanyAgent.process_batch: failed to send batch summary: #{e.message}" }
      end
    end

    { successes: successes, errors: errors }
  end

  private

  # Initializes the agent with the portfolio_company under review.
  # Sets up the shared context including issue tracking hashes.
  #
  # @param ctx [Hash] Trailblazer execution context
  # @param target portfolio_company [Investor] record under verification
  def initialize_agent(ctx, target: nil, **)
    super

    portfolio_company = target
    ctx[:portfolio_company] = portfolio_company
    Rails.logger.debug { "[#{self.class.name}] Initializing agent for Investor ID=#{portfolio_company.id}" }
    ctx[:issues] = { kpi_issues: [], document_issues: [], valuation_issues: [] }
    # Only process if this is a portfolio company and the agent is enabled
    portfolio_company.category == "Portfolio Company" && @support_agent.enabled?
  end

  # Checks whether the portfolio company has submitted last quarter's KPIs.
  # Adds issues to ctx[:issues][:kpi_issues] if submission is missing, incomplete, or delayed.
  #
  # @param ctx [Hash] Trailblazer execution context
  def check_kpi_submission(ctx, portfolio_company: nil, **)
    due_period = @support_agent.json_fields["due_period"] || "Quarter"
    days_before_due_period_end = @support_agent.json_fields["days_before_due_period_end"]&.to_i || 15
    due_date = Date.end_of_period(due_period) - days_before_due_period_end.days
    prev_period = Date.previous_end_of_period(due_period, due_date)

    kpi_report = portfolio_company.portfolio_kpi_reports.where(as_of: prev_period..due_date).order(as_of: :desc).last
    @last_kpi_report = kpi_report
    if kpi_report
      ctx[:issues][:kpi_issues] << {
        key: :kpi,
        type: :info,
        message: "Last #{due_period} KPIs submitted on #{kpi_report.as_of}",
        severity: :success
      }
      Rails.logger.debug { "[#{self.class.name}] Last quarter KPIs submitted for Investor ID=#{portfolio_company.id}" }
    else
      ctx[:issues][:kpi_issues] << {
        key: :kpi,
        type: :missing,
        message: "Last #{due_period} KPIs not submitted between #{prev_period} and #{due_date}",
        severity: :blocking
      }
      Rails.logger.warn { "[#{self.class.name}] Last quarter KPIs missing for Investor ID=#{portfolio_company.id}" }
    end
    true
  end

  # Sends a KPI reminder email to the portfolio company when KPIs are missing,
  # but only on configured day-offsets from the period start to avoid daily spam.
  #
  # Configurable via json_fields:
  #   send_kpi_reminder — "true"/"false" (default true)
  #   reminder_days     — comma-separated offsets from period start, e.g. "7,14,21"
  #   due_period        — reporting period, e.g. "Quarter" (shared with check_kpi_submission)
  def send_kpi_reminder(ctx, portfolio_company:, support_agent:, **)
    unless enabled?("send_kpi_reminder")
      Rails.logger.debug { "[#{self.class.name}] KPI reminder disabled, skipping." }
      return true
    end

    kpi_missing = ctx[:issues][:kpi_issues].any? { |i| i[:severity] == :blocking }
    unless kpi_missing
      ctx[:issues][:kpi_issues] << {
        key: :reminder, type: :info,
        message: "KPIs submitted — no reminder needed", severity: :success
      }
      return true
    end

    due_period    = support_agent.json_fields["due_period"] || "Quarter"
    reminder_days = support_agent.json_fields["reminder_days"]
                                 &.split(",")&.map(&:to_i) || [7, 14, 21]
    period_start  = case due_period.downcase
                    when "month"   then Date.today.beginning_of_month
                    when "year"    then Date.today.beginning_of_year
                    else                Date.today.beginning_of_quarter
                    end
    days_elapsed  = (Date.today - period_start).to_i

    unless reminder_days.include?(days_elapsed)
      ctx[:issues][:kpi_issues] << {
        key: :reminder, type: :info,
        message: "Reminder not due today (day #{days_elapsed}; fires on days #{reminder_days.join(', ')})",
        severity: :success
      }
      return true
    end

    # Avoid double-sending on the same calendar day
    last_report = SupportAgentReport
      .where(owner: portfolio_company, support_agent: support_agent)
      .order(created_at: :desc).first
    last_sent = last_report&.json_fields&.dig("last_kpi_reminder_sent_at")
    if last_sent && Date.parse(last_sent) >= Date.today
      ctx[:issues][:kpi_issues] << {
        key: :reminder, type: :info, message: "Reminder already sent today", severity: :success
      }
      return true
    end

    EntityMailer.with(
      entity_id: portfolio_company.entity_id,
      requesting_entity_id: support_agent.entity_id
    ).kpi_reminder.deliver_later

    ctx[:last_kpi_reminder_sent_at] = Date.today.iso8601
    ctx[:issues][:kpi_issues] << {
      key: :reminder, type: :info,
      message: "KPI reminder sent (day #{days_elapsed} of #{due_period})", severity: :success
    }
    Rails.logger.info { "[#{self.class.name}] KPI reminder sent for Investor ID=#{portfolio_company.id}" }
    true
  end

  # Verifies if mandatory documents are present for compliance and operational checks.
  # Adds issues to ctx[:issues][:document_issues] if any required documents are missing or invalid.
  def check_document_presence(ctx, support_agent:, **)
    ctx[:check_all_docs] = true
    super(ctx, model: @last_kpi_report, support_agent: support_agent)
  end

  # Validates valuations reported for the portfolio_company.
  # Adds issues to ctx[:issues][:valuation_issues] if there are missing valuations, stale entries, or anomalies.
  #
  # @param ctx [Hash] Trailblazer execution context
  def check_valuations(ctx, portfolio_company: nil, **)
    valuation_period = @support_agent.json_fields["valuation_period"] || "Quarter"
    days_before_valuation_period_end = @support_agent.json_fields["days_before_valuation_period_end"]&.to_i || 15
    valuation_due_date = Date.end_of_period(valuation_period) - days_before_valuation_period_end.days
    prev_valuation_period = Date.previous_end_of_period(valuation_period, valuation_due_date)

    valuation = portfolio_company.valuations.where(valuation_date: prev_valuation_period..valuation_due_date).order(valuation_date: :desc).last
    if valuation
      ctx[:issues][:valuation_issues] << {
        key: :valuation,
        type: :info,
        message: "Recent valuation reported on #{valuation.valuation_date}",
        severity: :success
      }
      Rails.logger.debug { "[#{self.class.name}] Recent valuations found for Investor ID=#{portfolio_company.id}" }
    else
      ctx[:issues][:valuation_issues] << {
        key: :valuation,
        type: :missing,
        message: "No valuations in the #{valuation_period} between #{prev_valuation_period} and #{valuation_due_date}",
        severity: :blocking
      }
      Rails.logger.warn { "[#{self.class.name}] Missing valuations for Investor ID=#{portfolio_company.id}" }
    end
    true
  end

  # Generates per-investor/fund reports summarizing issues and state.
  # Stores report as persisted SupportAgentReport record.
  #
  # Called for both single-company (with steps) and batch (adhoc/scheduled) runs.
  # Batch coordination (looping, chart job, notifications) is handled by process_batch.
  def generate_progress_reports(ctx, portfolio_company: nil, support_agent:, **)
    # Persist last reminder timestamp so the double-send guard works across runs
    if ctx[:last_kpi_reminder_sent_at]
      ctx[:issues]["last_kpi_reminder_sent_at"] = ctx[:last_kpi_reminder_sent_at]
    end
    super(ctx, model: portfolio_company, support_agent: support_agent)
    broadcast_portco_row(target: portfolio_company)
    # Only enqueue an individual chart job when NOT running inside process_batch.
    # process_batch enqueues a single bulk AgentChartJob for all companies at the end.
    # ctx[:batch_mode] is set to true by process_batch to suppress per-company jobs.
    AgentChartJob.perform_later(ctx[:user_id], portfolio_company_id: portfolio_company.id) unless ctx[:batch_mode]
    true
  end

  def broadcast_portco_row(target:)
    target.broadcast_row(row_template: "investors/portfolio_agent_run_row")
  end
end
