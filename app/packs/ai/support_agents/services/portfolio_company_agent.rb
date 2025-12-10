class PortfolioCompanyAgent < SupportAgentService
  step :initialize_agent
  # == Core Functions ==
  step :check_kpi_submission
  step :check_document_presence
  step :check_valuations
  step :generate_progress_reports

  def targets(entity_id)
    Investor.where(entity_id: entity_id, category: "Portfolio Company").includes(:kpi_reports, :valuations)
  end

  private

  # Initializes the agent with the portfolio_company under review.
  # Sets up the shared context including issue tracking hashes.
  #
  # @param ctx [Hash] Trailblazer execution context
  # @param target portfolio_company [Investor] record under verification
  def initialize_agent(ctx, target:, **)
    super
    portfolio_company = target
    ctx[:portfolio_company] = portfolio_company
    # Initialize execution ctx with a single portfolio_company
    # Setup history, logging, or state tracking for this run
    Rails.logger.debug { "[#{self.class.name}] Initializing agent for Investor ID=#{portfolio_company.id}" }
    ctx[:issues] = { kpi_issues: [], document_issues: [], valuation_issues: [] }
    # Only process if completed by investor and agent is enabled
    portfolio_company.category == "Portfolio Company" && @support_agent.enabled?
  end

  # Checks whether the portfolio company has submitted last quarter's KPIs.
  # Adds issues to ctx[:issues][:kpi_issues] if submission is missing, incomplete, or delayed.
  #
  # @param ctx [Hash] Trailblazer execution context
  def check_kpi_submission(ctx, portfolio_company:, **)
    due_period = @support_agent.json_fields["due_period"] || "Quarter"
    days_before_due_period_end = @support_agent.json_fields["days_before_due_period_end"]&.to_i || 15
    due_date = Date.end_of_period(due_period) - days_before_due_period_end.days
    prev_period = Date.previous_end_of_period(due_period, due_date)

    # Fetch last quarter KPIs for the portfolio_company
    # Validate submission presence, timeliness, and completeness
    # Append issues to ctx[:issues][:kpi_issues] if problems found
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
    ctx[:check_all_docs] = true
    super(ctx, model: @last_kpi_report, support_agent: support_agent)
  end

  # Validates valuations reported for the portfolio_company.
  # Adds issues to ctx[:issues][:valuation_issues] if there are missing valuations, stale entries, or anomalies.
  #
  # @param ctx [Hash] Trailblazer execution context
  def check_valuations(ctx, portfolio_company:, **)
    valuation_period = @support_agent.json_fields["valuation_period"] || "Quarter"
    days_before_valuation_period_end = @support_agent.json_fields["days_before_valuation_period_end"]&.to_i || 15
    valuation_due_date = Date.end_of_period(valuation_period) - days_before_valuation_period_end.days
    prev_valuation_period = Date.previous_end_of_period(valuation_period, valuation_due_date)

    # Retrieve reported valuations
    # Check for recency, accuracy, and consistency with standards
    # Append issues to ctx[:issues][:valuation_issues] if problems found

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
  def generate_progress_reports(ctx, portfolio_company:, support_agent:, **)
    super(ctx, model: portfolio_company, support_agent: support_agent)

    AgentChartJob.perform_later(ctx[:user_id], portfolio_company_id: portfolio_company.id)
    true
  end
end
