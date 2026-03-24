class PortfolioCompanyAgent < SupportAgentService
  DESCRIPTION = "Monitors portfolio companies for KPI submissions, document presence, and valuation accuracy.".freeze
  step :initialize_agent
  # == Core Functions ==
  step :check_kpi_submission
  step :check_document_presence
  step :check_valuations
  step :generate_progress_reports

  def targets(entity_id)
    Investor.where(entity_id: entity_id, category: "Portfolio Company").includes(:kpi_reports, :valuations)
  end

  # Class-level batch processor for PortfolioCompanyAgent.
  # This processes a collection of targets sequentially (with associations preloaded),
  # collects successes/errors, enqueues a single AgentChartJob for all processed ids,
  # and emits a single batch summary notification.
  #
  # Params:
  # - support_agent_id: Integer
  # - targets: Array or ActiveRecord::Relation of Investor records
  # - user_id: Integer
  # - entity_id: Integer
  # - with_steps: Boolean (optional) - if true, runs the with_steps path for each target
  def self.process_batch(support_agent_id:, targets:, user_id:, entity_id:, with_steps: false)
    support_agent = SupportAgent.find(support_agent_id)

    # Preload commonly used associations to avoid N+1 queries
    targets = targets.includes(:portfolio_kpi_reports, :documents, :valuations) if targets.respond_to?(:includes)

    successes = []
    errors = []
    if with_steps
      # Single operation invocation that handles multiple targets.
      # The agent's step methods will detect ctx[:portfolio_companies] and
      # perform per-company checks and reports sequentially (no threading).
      begin
        target_array = targets.to_a
        # Trailblazer operations expose a class-level `call` entrypoint.
        support_agent.agent.call(support_agent_id: support_agent_id, targets: target_array, user_id: user_id, entity_id: entity_id)
        successes = target_array.map { |t| { id: t.id, name: t.try(:investor_name) || t.try(:name) || "ID=#{t.id}" } }
      rescue StandardError => e
        Rails.logger.error { "PortfolioCompanyAgent.process_batch (with_steps) failed: #{e.message}" }
        Rails.logger.error { e.backtrace.join("\n") }
        errors << { error: e.message }
      end
    else
      # Non-step runs keep the previous behavior (sequential, no threads)
      targets.to_a.each do |target|
        begin
          support_agent.agent.wtf?(support_agent_id: support_agent_id, target: target, user_id: user_id, entity_id: entity_id)
          successes << { id: target.id, name: target.try(:investor_name) || target.try(:name) || "ID=#{target.id}" }
        rescue StandardError => e
          Rails.logger.error { "PortfolioCompanyAgent.process_batch error for Target ID=#{target.id}: #{e.message}" }
          Rails.logger.error { e.backtrace.join("\n") }
          errors << { target_id: target.id, target_name: target.try(:investor_name) || target.try(:name) || "ID=#{target.id}", error: e.message }
        end
      end
    end

    # Enqueue a single AgentChartJob for all processed portfolio companies
    if successes.any?
      processed_ids = successes.map { |s| s[:id] }
      AgentChartJob.perform_later(user_id, portfolio_company_ids: processed_ids.uniq)
    end

    # Reuse SupportAgentJob's helper to send a batch summary notification
    # It expects (support_agent, successes, errors, user_id, batch_target_type)
    begin
      batch_target_type = targets.first.class.name if targets.any?
      SupportAgentJob.new.send(:send_batch_summary, support_agent, successes, errors, user_id, batch_target_type) if defined?(SupportAgentJob)
    rescue StandardError => e
      Rails.logger.error { "PortfolioCompanyAgent.process_batch: failed to send batch summary: #{e.message}" }
    end

    { successes: successes, errors: errors }
  end

  private

  # Initializes the agent with the portfolio_company under review.
  # Sets up the shared context including issue tracking hashes.
  #
  # @param ctx [Hash] Trailblazer execution context
  # @param target portfolio_company [Investor] record under verification
  def initialize_agent(ctx, target: nil, targets: nil, **)
    super

    # Support either a single target (target:) or multiple targets (targets:)
    if targets.present?
      portfolio_companies = targets.is_a?(Array) ? targets : targets.to_a
      ctx[:portfolio_companies] = portfolio_companies
      ctx[:company_issues] = {}
      ctx[:last_kpi_report_by_id] = {}
      portfolio_companies.each do |pc|
        ctx[:company_issues][pc.id] = { kpi_issues: [], document_issues: [], valuation_issues: [] }
      end
      Rails.logger.debug { "[#{self.class.name}] Initializing agent for batch of #{portfolio_companies.size} companies" }
      # Ensure agent is enabled and all targets are portfolio companies
      return @support_agent.enabled? && portfolio_companies.all? { |c| c.category == "Portfolio Company" }
    else
      portfolio_company = target
      ctx[:portfolio_company] = portfolio_company
      # Initialize execution ctx with a single portfolio_company
      Rails.logger.debug { "[#{self.class.name}] Initializing agent for Investor ID=#{portfolio_company.id}" }
      ctx[:issues] = { kpi_issues: [], document_issues: [], valuation_issues: [] }
      # Only process if completed by investor and agent is enabled
      return portfolio_company.category == "Portfolio Company" && @support_agent.enabled?
    end
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

    # Batch path: iterate all portfolio_companies and record per-company issues
    if ctx[:portfolio_companies].present?
      ctx[:portfolio_companies].each do |pc|
        kpi_report = pc.portfolio_kpi_reports.where(as_of: prev_period..due_date).order(as_of: :desc).last
        ctx[:last_kpi_report_by_id][pc.id] = kpi_report
        issues = ctx[:company_issues][pc.id]

        if kpi_report
          issues[:kpi_issues] << {
            key: :kpi,
            type: :info,
            message: "Last #{due_period} KPIs submitted on #{kpi_report.as_of}",
            severity: :success
          }
          Rails.logger.debug { "[#{self.class.name}] Last quarter KPIs submitted for Investor ID=#{pc.id}" }
        else
          issues[:kpi_issues] << {
            key: :kpi,
            type: :missing,
            message: "Last #{due_period} KPIs not submitted between #{prev_period} and #{due_date}",
            severity: :blocking
          }
          Rails.logger.warn { "[#{self.class.name}] Last quarter KPIs missing for Investor ID=#{pc.id}" }
        end
      end
      return true
    end

    # Single company path (unchanged)
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

  # Verifies if mandatory documents are present for compliance and operational checks.
  # Adds issues to ctx[:issues][:document_issues] if any required documents are missing or invalid.
  def check_document_presence(ctx, support_agent:, **)
    # For document check, consider all documents, not only the mandatory required ones
    # If running in batch mode, iterate companies and run the shared
    # document presence check with a per-company issues hash.
    if ctx[:portfolio_companies].present?
      ctx[:portfolio_companies].each do |pc|
        ctx[:check_all_docs] = true
        # Use the per-company issues hash as the working ctx[:issues]
        ctx[:issues] = ctx[:company_issues][pc.id]
        # Provide the last kpi report for this portfolio company as the model
        last_kpi = ctx[:last_kpi_report_by_id][pc.id]
        super(ctx, model: last_kpi, support_agent: support_agent)
        # ensure the company_issues entry reflects any mutations from super
        ctx[:company_issues][pc.id] = ctx[:issues]
      end
      return true
    end

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

    if ctx[:portfolio_companies].present?
      ctx[:portfolio_companies].each do |pc|
        issues = ctx[:company_issues][pc.id]
        valuation = pc.valuations.where(valuation_date: prev_valuation_period..valuation_due_date).order(valuation_date: :desc).last
        if valuation
          issues[:valuation_issues] << {
            key: :valuation,
            type: :info,
            message: "Recent valuation reported on #{valuation.valuation_date}",
            severity: :success
          }
          Rails.logger.debug { "[#{self.class.name}] Recent valuations found for Investor ID=#{pc.id}" }
        else
          issues[:valuation_issues] << {
            key: :valuation,
            type: :missing,
            message: "No valuations in the #{valuation_period} between #{prev_valuation_period} and #{valuation_due_date}",
            severity: :blocking
          }
          Rails.logger.warn { "[#{self.class.name}] Missing valuations for Investor ID=#{pc.id}" }
        end
        ctx[:company_issues][pc.id] = issues
      end
      return true
    end

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
  def generate_progress_reports(ctx, portfolio_company: nil, support_agent:, **)
    # Single-company path (unchanged)
    if ctx[:portfolio_companies].blank?
      super(ctx, model: portfolio_company, support_agent: support_agent)
      AgentChartJob.perform_later(ctx[:user_id], portfolio_company_id: portfolio_company.id)
      return true
    end

    # Batch path: run per-company report generation sequentially.
    processed_ids = []
    ctx[:portfolio_companies].each do |pc|
      # Prepare a working ctx[:issues] for the company so SupportAgentService#generate_progress_reports
      # can merge and persist the right JSON structure.
      ctx[:issues] = ctx[:company_issues][pc.id]
      super(ctx, model: pc, support_agent: support_agent)
      processed_ids << pc.id
    end

    # Enqueue a single AgentChartJob for the entire batch
    AgentChartJob.perform_later(ctx[:user_id], portfolio_company_ids: processed_ids.uniq) if processed_ids.any?

    true
  end
end
